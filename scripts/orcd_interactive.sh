#!/usr/bin/env bash
# Usage: ./orcd_interactive.sh [CORES MEM_GB HOURS]   (all three, or none for defaults)
#   CORES   CPU cores        (-1 -> 1)
#   MEM_GB  memory in GB     (-1 -> 16)
#   HOURS   time limit hours (-1 -> 4)
#   e.g. ./orcd_interactive.sh -1 32 -1  -> 1 core, 32 GB, 4 hours
#
# Run on your LOCAL machine. It opens an interactive salloc shell on the
# cluster in this terminal (keep it open!). In the background it waits for the
# job to start, reads the node name, and updates HostName for `orcd-compute`
# in ~/.ssh/config. Exiting the shell ends the allocation.

set -uo pipefail

if (( $# != 0 && $# != 3 )); then
  echo "Pass all three arguments (CORES MEM_GB HOURS) or none for the defaults." >&2
  exit 1
fi
CORES="${1:--1}"
MEM_GB="${2:--1}"
HOURS="${3:--1}"
LOGIN_HOST="orcd-login"
COMPUTE_HOST="orcd-compute"
PARTITION="mit_normal"
# Unique per run, so the watcher never matches an older still-running job.
JOBNAME="vscode-$(date +%Y%m%d-%H%M%S)-$$"
CONFIG="$HOME/.ssh/config"

for v in "$CORES" "$MEM_GB" "$HOURS"; do
  if ! [[ "$v" =~ ^(-1|[1-9][0-9]*)$ ]]; then
    echo "Arguments must be positive integers, or -1 for the default." >&2
    exit 1
  fi
done
(( CORES  == -1 )) && CORES=1
(( MEM_GB == -1 )) && MEM_GB=16
(( HOURS  == -1 )) && HOURS=4
RES_FLAGS="-c ${CORES} --mem=${MEM_GB}G -t ${HOURS}:00:00"
echo ">> Requesting ${CORES} core(s), ${MEM_GB} GB memory, ${HOURS} hour(s) on ${PARTITION}..." >&2

# Same multiplexing settings as the ORCD docs, so the watcher can reuse the
# authenticated connection (no second password / Duo prompt).
SSH_OPTS=(-o ControlMaster=auto -o "ControlPath=$HOME/.ssh/%r@%h:%p" -o ControlPersist=300s)

update_config() {
  local node="$1"
  cp "$CONFIG" "$CONFIG.bak"
  awk -v host="$COMPUTE_HOST" -v node="$node" '
    tolower($1) == "host" { inblock = ($2 == host) }
    inblock && tolower($1) == "hostname" { print "  HostName " node; next }
    { print }
  ' "$CONFIG.bak" > "$CONFIG"
}

watcher() {
  # Wait until the interactive connection is up and authenticated
  until ssh "${SSH_OPTS[@]}" -O check "$LOGIN_HOST" 2>/dev/null; do sleep 2; done
  # Wait until the job is RUNNING and has a node
  local node=""
  while [[ -z "$node" ]]; do
    sleep 3
    node=$(ssh -n "${SSH_OPTS[@]}" -o BatchMode=yes "$LOGIN_HOST" \
           "squeue --me -h -n $JOBNAME -t R -o %N" 2>/dev/null | head -n1 | tr -d '[:space:]')
  done
  update_config "$node"
  printf '\r\n>> [orcd] Node %s ready; %s updated. Connect to "%s".\r\n' \
         "$node" "$CONFIG" "$COMPUTE_HOST" >&2
}

watcher &
WATCHER_PID=$!
trap 'kill $WATCHER_PID 2>/dev/null' EXIT

# Foreground: your interactive allocation (this is your manual step i)
ssh -t "${SSH_OPTS[@]}" "$LOGIN_HOST" "salloc -J $JOBNAME -p $PARTITION $RES_FLAGS"
