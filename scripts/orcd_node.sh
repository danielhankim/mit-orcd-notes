#!/usr/bin/env bash
# Usage: ./orcd_node.sh [CORES MEM_GB HOURS]   (all three, or none for defaults)
#   CORES   CPU cores        (-1 -> 1)
#   MEM_GB  memory in GB     (-1 -> 16)
#   HOURS   time limit hours (-1 -> 4)
#   e.g. ./orcd_node.sh -1 32 -1  -> 1 core, 32 GB, 4 hours
#
# Run this on your LOCAL machine (not on the cluster).
# It: 1) asks the scheduler for a node, 2) reads the node name,
#     3) rewrites HostName in the `orcd-compute` block of ~/.ssh/config.
# Then just connect to `orcd-compute` from VSCode or `ssh orcd-compute`.

set -euo pipefail

if (( $# != 0 && $# != 3 )); then
  echo "Pass all three arguments (CORES MEM_GB HOURS) or none for the defaults." >&2
  exit 1
fi
CORES="${1:--1}"
MEM_GB="${2:--1}"
HOURS="${3:--1}"
LOGIN_HOST="orcd-login"        # Host alias for the login node in ~/.ssh/config
COMPUTE_HOST="orcd-compute"    # Host alias to update
PARTITION="mit_normal"
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

# --no-shell: the allocation is granted and kept alive without holding a shell,
# so it survives after this ssh call returns. salloc blocks until granted.
NODE=$(ssh "$LOGIN_HOST" "
  jid=\$(salloc --no-shell -J vscode -p ${PARTITION} ${RES_FLAGS} 2>&1 \
        | tee /dev/stderr \
        | sed -n 's/.*Granted job allocation \([0-9]*\).*/\1/p')
  squeue -h -j \"\$jid\" -o %N
")

NODE="$(echo "$NODE" | tr -d '[:space:]')"
if [[ -z "$NODE" ]]; then
  echo "Could not determine the compute node." >&2
  exit 1
fi
echo ">> Allocated node: $NODE" >&2

# Update HostName inside the orcd-compute block only (portable: no sed -i)
cp "$CONFIG" "$CONFIG.bak"
awk -v host="$COMPUTE_HOST" -v node="$NODE" '
  tolower($1) == "host" { inblock = ($2 == host) }
  inblock && tolower($1) == "hostname" { print "  HostName " node; next }
  { print }
' "$CONFIG.bak" > "$CONFIG"

echo ">> Updated $CONFIG ($COMPUTE_HOST -> $NODE). Connect with: ssh $COMPUTE_HOST" >&2
echo ">> To release the node early: ssh $LOGIN_HOST scancel -n vscode" >&2
