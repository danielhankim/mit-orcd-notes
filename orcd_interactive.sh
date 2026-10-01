#!/usr/bin/env bash
# Usage: ./orcd_interactive.sh [HOURS]
#   HOURS > 0   -> salloc -t HOURS:00:00
#   HOURS = -1  -> no time flag (default if omitted)
#
# Run on your LOCAL machine. It opens an interactive salloc shell on the
# cluster in this terminal (keep it open!). In the background it waits for the
# job to start, reads the node name, and updates HostName for `orcd-compute`
# in ~/.ssh/config. Exiting the shell ends the allocation.

set -uo pipefail

HOURS="${1:--1}"
LOGIN_HOST="orcd-login"
COMPUTE_HOST="orcd-compute"
PARTITION="mit_normal"
JOBNAME="vscode"
CONFIG="$HOME/.ssh/config"

if ! [[ "$HOURS" =~ ^-?[0-9]+$ ]]; then
  echo "Argument must be an integer (hours, or -1 for no limit)." >&2
  exit 1
fi

TIME_FLAG=""
(( HOURS > 0 )) && TIME_FLAG="-t ${HOURS}:00:00"

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
    node=$(ssh "${SSH_OPTS[@]}" -o BatchMode=yes "$LOGIN_HOST" \
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
ssh -t "${SSH_OPTS[@]}" "$LOGIN_HOST" "salloc -J $JOBNAME -p $PARTITION $TIME_FLAG"
