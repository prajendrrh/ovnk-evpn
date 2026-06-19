#!/usr/bin/env bash
# One-shot fix for bastion -> pod forwarding (22.100.0.3 / worker1).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=frr-lib.sh
source "${SCRIPT_DIR}/frr-lib.sh"

frr_load_vars

POD_IP="${1:-22.100.0.3}"
POD_MAC="${2:-0a:58:16:64:00:03}"
REMOTE_VTEP="${3:-${WORKER1_IP}}"

sudo "${SCRIPT_DIR}/vxlan.sh" >/dev/null

echo "Fixing forward path: ${POD_IP} ${POD_MAC} via ${REMOTE_VTEP}"

while bridge fdb show dev "${BRIDGE_DEV}" 2>/dev/null | grep -q "^${POD_MAC}.*extern_learn"; do
  echo "  DEL extern_learn ${POD_MAC} on ${BRIDGE_DEV}"
  sudo bridge fdb delete "${POD_MAC}" dev "${BRIDGE_DEV}" master 2>/dev/null || break
done

sudo bridge fdb replace "${POD_MAC}" dev "${VXLAN_DEV}" dst "${REMOTE_VTEP}" self static
sudo ip neigh del "${POD_IP}" dev "${BRIDGE_DEV}" 2>/dev/null || true
sudo ip neigh replace "${POD_IP}" lladdr "${POD_MAC}" dev "${BRIDGE_DEV}" nud reachable

echo
bridge fdb show dev "${BRIDGE_DEV}" | grep "${POD_MAC}" || echo "OK: ${POD_MAC} not on ${BRIDGE_DEV}"
bridge fdb show dev "${VXLAN_DEV}" | grep "${POD_MAC}"
ip neigh show dev "${BRIDGE_DEV}" | grep "${POD_IP}"

echo
ping -I "${BRIDGE_DEV}" -c 3 -W 2 "${POD_IP}"
