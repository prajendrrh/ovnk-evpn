#!/usr/bin/env bash
# Sync EVPN control plane (FRR) into kernel dataplane (FDB + ARP on br100/vni100).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=frr-lib.sh
source "${SCRIPT_DIR}/frr-lib.sh"

frr_load_vars
frr_ensure_container

echo "Syncing EVPN dataplane on ${BRIDGE_DEV}/${VXLAN_DEV}..."

last_ip=""
while read -r mac vtep; do
  [[ -z "${mac}" || -z "${vtep}" ]] && continue
  echo "  FDB ${mac} -> ${vtep}"
  sudo bridge fdb replace "${mac}" dev "${VXLAN_DEV}" dst "${vtep}" self permanent
done < <(
  sudo podman exec "${CONTAINER_NAME}" vtysh -c "show evpn mac vni ${VNI}" \
    | awk '$2 == "remote" { print $1, $3 }'
)

routes=$(
  sudo podman exec "${CONTAINER_NAME}" vtysh -c "show bgp l2vpn evpn route type 2"
)

while read -r line; do
  [[ "${line}" != *"[32]:"* ]] && continue
  mac=$(sed -n 's/.*\[48\]:\[\([0-9a-f:]*\)\]:\[32\]:\[\([0-9.]*\)\].*/\1/p' <<< "${line}")
  ip=$(sed -n 's/.*\[48\]:\[\([0-9a-f:]*\)\]:\[32\]:\[\([0-9.]*\)\].*/\2/p' <<< "${line}")
  [[ -z "${mac}" || -z "${ip}" ]] && continue
  nh_line=$(grep -A1 "${line}" <<< "${routes}" | tail -1)
  vtep=$(awk '{print $1}' <<< "${nh_line}" | sed 's/^*>[a-z] //')
  [[ "${vtep}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
  echo "  ARP ${ip} -> ${mac}, FDB ${mac} -> ${vtep}"
  sudo bridge fdb replace "${mac}" dev "${VXLAN_DEV}" dst "${vtep}" self permanent
  sudo ip neigh replace "${ip}" lladdr "${mac}" dev "${BRIDGE_DEV}" nud reachable
  last_ip="${ip}"
done < <(grep '\[32\]:' <<< "${routes}")

echo
echo "Dataplane state:"
ip -br addr show dev "${BRIDGE_DEV}"
echo "--- FDB (${VXLAN_DEV}) ---"
bridge fdb show dev "${VXLAN_DEV}" | grep -v "00:00:00:00:00:00" || true
echo "--- ARP (${BRIDGE_DEV}) ---"
ip neigh show dev "${BRIDGE_DEV}" || true

if [[ -n "${last_ip}" ]]; then
  echo
  echo "Test ping to ${last_ip} (from ${BRIDGE_DEV}):"
  ping -I "${BRIDGE_DEV}" -c 2 -W 2 "${last_ip}" || true
fi
