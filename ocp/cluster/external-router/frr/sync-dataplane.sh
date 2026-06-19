#!/usr/bin/env bash
# Sync EVPN control plane (FRR) into kernel dataplane (FDB + ARP on br100/vni100).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=frr-lib.sh
source "${SCRIPT_DIR}/frr-lib.sh"

frr_vtysh() {
  sudo podman exec "${CONTAINER_NAME}" vtysh -c "$1"
}

frr_load_vars
frr_ensure_container

echo "Syncing EVPN dataplane on ${BRIDGE_DEV}/${VXLAN_DEV}..."

sudo "${SCRIPT_DIR}/vxlan.sh" >/dev/null

LOCAL_MAC=$(
  bridge fdb show dev "${BRIDGE_DEV}" 2>/dev/null \
    | awk '/permanent/ && $1 !~ /^(33:33|01:00:5e)/ { print $1; exit }'
)

cleanup_extern_learn_fdb() {
  local mac
  for mac in $(bridge fdb show dev "${BRIDGE_DEV}" 2>/dev/null | awk '/extern_learn/ {print $1}' | sort -u); do
    [[ -z "${mac}" || "${mac}" == "${LOCAL_MAC}" ]] && continue
    while bridge fdb show dev "${BRIDGE_DEV}" 2>/dev/null | grep -q "^${mac}.*extern_learn"; do
      echo "  DEL extern_learn on ${BRIDGE_DEV}: ${mac}"
      sudo bridge fdb delete "${mac}" dev "${BRIDGE_DEV}" master 2>/dev/null || break
    done
  done
}

sync_mac() {
  local mac=$1 vtep=$2
  cleanup_extern_learn_fdb
  echo "  FDB ${mac} -> ${vtep} via ${VXLAN_DEV}"
  sudo bridge fdb replace "${mac}" dev "${VXLAN_DEV}" dst "${vtep}" self static
}

sync_neigh() {
  local ip=$1 mac=$2
  sudo ip neigh del "${ip}" dev "${BRIDGE_DEV}" 2>/dev/null || true
  echo "  ARP ${ip} -> ${mac}"
  sudo ip neigh replace "${ip}" lladdr "${mac}" dev "${BRIDGE_DEV}" nud reachable
}

parse_evpn_macs() {
  frr_vtysh "show evpn mac vni ${VNI}" | awk '$2 == "remote" { print $1, $3 }'
}

parse_type2_macip() {
  local routes line mac ip vtep nh
  routes=$(frr_vtysh "show bgp l2vpn evpn route type 2")
  while IFS= read -r line; do
    [[ "${line}" != *"[32]:"* ]] && continue
    mac=$(sed -n 's/.*\[48\]:\[\([0-9a-f:]*\)\].*/\1/p' <<< "${line}")
    ip=$(sed -n 's/.*\[32\]:\[\([0-9.]*\)\].*/\1/p' <<< "${line}")
    [[ -z "${mac}" || -z "${ip}" || "${ip}" == "${CUDN_GATEWAY%%/*}" ]] && continue
    nh=$(grep -A1 "${line}" <<< "${routes}" | tail -1)
    vtep=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' <<< "${nh}" | head -1)
    [[ -n "${vtep}" ]] && echo "${ip} ${mac} ${vtep}"
  done <<< "${routes}"
}

# VTEP flood entries
for vtep in "${WORKER1_IP}" "${WORKER2_IP}"; do
  echo "  VTEP FDB * -> ${vtep}"
  sudo bridge fdb replace 00:00:00:00:00:00 dev "${VXLAN_DEV}" dst "${vtep}" self static 2>/dev/null || \
    sudo bridge fdb append 00:00:00:00:00:00 dev "${VXLAN_DEV}" dst "${vtep}" self static
done

echo "--- EVPN remote MACs ---"
mac_count=0
while read -r mac vtep; do
  [[ -z "${mac}" || -z "${vtep}" ]] && continue
  sync_mac "${mac}" "${vtep}"
  mac_count=$((mac_count + 1))
done < <(parse_evpn_macs)

if [[ "${mac_count}" -eq 0 ]]; then
  echo "  (no remote MACs from 'show evpn mac vni ${VNI}')"
  frr_vtysh "show evpn mac vni ${VNI}" | head -8
fi

echo "--- EVPN type-2 MAC/IP ---"
last_ip=""
ip_count=0
while read -r ip mac vtep; do
  [[ -z "${ip}" || -z "${mac}" || -z "${vtep}" ]] && continue
  echo "  MAC/IP ${ip} ${mac} -> ${vtep}"
  sync_mac "${mac}" "${vtep}"
  sync_neigh "${ip}" "${mac}"
  last_ip="${ip}"
  ip_count=$((ip_count + 1))
done < <(parse_type2_macip)

if [[ "${ip_count}" -eq 0 ]]; then
  echo "  (no remote MAC/IP from type-2 routes)"
  frr_vtysh "show bgp l2vpn evpn route type 2" | grep '\[32\]:' | head -5 || true
fi

# Zebra may re-add bad entries immediately — clean twice
cleanup_extern_learn_fdb
if [[ -n "${last_ip}" ]]; then
  mac=$(ip neigh show dev "${BRIDGE_DEV}" | awk "/^${last_ip} / {print \$3}")
  [[ -n "${mac}" ]] && sync_neigh "${last_ip}" "${mac}"
fi

echo
echo "Dataplane state:"
ip -br addr show dev "${BRIDGE_DEV}"
echo "--- FDB (${BRIDGE_DEV}) remote check ---"
bridge fdb show dev "${BRIDGE_DEV}" | grep extern_learn || echo "OK: no extern_learn on ${BRIDGE_DEV}"
echo "--- FDB (${VXLAN_DEV}) ---"
bridge fdb show dev "${VXLAN_DEV}" | grep -E '0a:58|dst 192.168' || bridge fdb show dev "${VXLAN_DEV}"
echo "--- ARP (${BRIDGE_DEV}) ---"
ip neigh show dev "${BRIDGE_DEV}" | grep 22.100 || ip neigh show dev "${BRIDGE_DEV}"

if [[ -n "${last_ip}" ]]; then
  echo
  echo "Test: ping -I ${BRIDGE_DEV} ${last_ip}"
  ping -I "${BRIDGE_DEV}" -c 2 -W 2 "${last_ip}" || true
fi
