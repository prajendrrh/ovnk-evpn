#!/usr/bin/env bash
# Sync EVPN control plane (FRR) into kernel dataplane (FDB + ARP on br100/vni100).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=frr-lib.sh
source "${SCRIPT_DIR}/frr-lib.sh"

frr_load_vars
frr_ensure_container

echo "Syncing EVPN dataplane on ${BRIDGE_DEV}/${VXLAN_DEV}..."

# Ensure bridge + routes exist
sudo "${SCRIPT_DIR}/vxlan.sh" >/dev/null

# FRR/zebra installs extern_learn FDB on the bridge — that traps remote MACs
# locally and prevents VXLAN encap. Remove those before programming vni100.
cleanup_bridge_fdb() {
  local mac=$1
  while sudo bridge fdb show dev "${BRIDGE_DEV}" | grep -q "${mac}"; do
    echo "  DEL bad FDB on ${BRIDGE_DEV}: ${mac}"
    sudo bridge fdb delete "${mac}" dev "${BRIDGE_DEV}" master 2>/dev/null || break
  done
}

sync_mac() {
  local mac=$1 vtep=$2
  cleanup_bridge_fdb "${mac}"
  echo "  FDB ${mac} -> ${vtep} via ${VXLAN_DEV}"
  sudo bridge fdb replace "${mac}" dev "${VXLAN_DEV}" dst "${vtep}" self static
}

sync_neigh() {
  local ip=$1 mac=$2
  # Replace zebra NOARP/extern_learn entries with a normal reachable neighbor
  sudo ip neigh del "${ip}" dev "${BRIDGE_DEV}" 2>/dev/null || true
  echo "  ARP ${ip} -> ${mac}"
  sudo ip neigh replace "${ip}" lladdr "${mac}" dev "${BRIDGE_DEV}" nud reachable
}

# Remote VTEP head-end replication entries (helps BUM/ARP)
for vtep in "${WORKER1_IP}" "${WORKER2_IP}"; do
  echo "  VTEP FDB * -> ${vtep}"
  sudo bridge fdb replace 00:00:00:00:00:00 dev "${VXLAN_DEV}" dst "${vtep}" self static 2>/dev/null || \
    sudo bridge fdb append 00:00:00:00:00:00 dev "${VXLAN_DEV}" dst "${vtep}" self static
done

# Remote MACs from EVPN MAC table
while read -r mac vtep; do
  [[ -z "${mac}" || -z "${vtep}" ]] && continue
  sync_mac "${mac}" "${vtep}"
done < <(
  sudo podman exec "${CONTAINER_NAME}" vtysh -c "show evpn mac vni ${VNI}" \
    | awk '$2 == "remote" { print $1, $3 }'
)

# MAC+IP from type-2 routes (robust parser)
last_ip=""
entries=$(
  sudo podman exec "${CONTAINER_NAME}" vtysh -c "show bgp l2vpn evpn route type 2" | \
  awk '
    /\[2\]:.*\[32\]:/ {
      if (match($0, /\[48\]:\[([0-9a-f:]+)\]:\[32\]:\[([0-9.]+)\]/, m)) {
        mac = m[1]
        ip = m[2]
        pending = 1
      }
      next
    }
    pending && $1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {
      print ip, mac, $1
      pending = 0
    }
  '
)

while read -r ip mac vtep; do
  [[ -z "${ip}" || -z "${mac}" || -z "${vtep}" ]] && continue
  echo "  MAC/IP ${ip} ${mac} -> ${vtep}"
  sync_mac "${mac}" "${vtep}"
  sync_neigh "${ip}" "${mac}"
  last_ip="${ip}"
done <<< "${entries}"

echo
echo "Dataplane state:"
ip -br addr show dev "${BRIDGE_DEV}"
echo "--- route ---"
ip route show "${CUDN_SUBNET}" || true
echo "--- FDB (${BRIDGE_DEV}) - should NOT list remote MACs ---"
bridge fdb show dev "${BRIDGE_DEV}" | grep -v "22.100.0.1" || echo "(none)"
echo "--- FDB (${VXLAN_DEV}) - remote MACs with dst VTEP ---"
bridge fdb show dev "${VXLAN_DEV}" || true
echo "--- ARP (${BRIDGE_DEV}) ---"
ip neigh show dev "${BRIDGE_DEV}" || true

if [[ -n "${last_ip}" ]]; then
  echo
  echo "Test from ${BRIDGE_DEV} to ${last_ip}:"
  ping -I "${BRIDGE_DEV}" -c 2 -W 2 "${last_ip}" || true
fi
