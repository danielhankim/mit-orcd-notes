#!/usr/bin/env bash
# Usage: ./orcd_node.sh [HOURS]
#   HOURS > 0   -> request that many hours (salloc -t HOURS:00:00)
#   HOURS = -1  -> no time flag (partition default)   [default if omitted]
#
# Run this on your LOCAL machine (not on the cluster).
# It: 1) asks the scheduler for a node, 2) reads the node name,
#     3) rewrites HostName in the `orcd-compute` block of ~/.ssh/config.
# Then just connect to `orcd-compute` from VSCode or `ssh orcd-compute`.

set -euo pipefail

HOURS="${1:--1}"
LOGIN_HOST="orcd-login"        # Host alias for the login node in ~/.ssh/config
COMPUTE_HOST="orcd-compute"    # Host alias to update
PARTITION="mit_normal"
CONFIG="$HOME/.ssh/config"

if ! [[ "$HOURS" =~ ^-?[0-9]+$ ]]; then
  echo "Argument must be an integer (hours, or -1 for no limit)." >&2
  exit 1
fi

TIME_FLAG=""
if (( HOURS > 0 )); then
  TIME_FLAG="-t ${HOURS}:00:00"
fi

echo ">> Requesting allocation on ${PARTITION} (${TIME_FLAG:-no time flag})..." >&2

# --no-shell: the allocation is granted and kept alive without holding a shell,
# so it survives after this ssh call returns. salloc blocks until granted.
NODE=$(ssh "$LOGIN_HOST" "
  jid=\$(salloc --no-shell -J vscode -p ${PARTITION} ${TIME_FLAG} 2>&1 \
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
