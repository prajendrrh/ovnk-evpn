#!/usr/bin/env bash
# End-to-end ping/dataplane diagnostics for bastion -> CUDN pod.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=frr-lib.sh
source "${SCRIPT_DIR}/frr-lib.sh"

POD_IP="${1:-}"

frr_load_vars
frr_ensure_container

echo "=== 1. BGP / EVPN control plane ==="
sudo podman exec frr vtysh -c "show bgp summary" | head -20
echo
sudo podman exec frr vtysh -c "show bgp l2vpn evpn vni"
echo
sudo podman exec frr vtysh -c "show evpn mac vni ${VNI}"

echo
echo "=== 2. Host interfaces ==="
ip -br addr show "${BRIDGE_DEV}"
ip -br addr show "${VXLAN_DEV}" 2>/dev/null || true
ip route show "${CUDN_SUBNET}" 2>/dev/null || true

echo
echo "=== 3. Sync dataplane ==="
sudo "${SCRIPT_DIR}/sync-dataplane.sh"

if [[ -z "${POD_IP}" ]]; then
  POD_IP=$(
    sudo podman exec frr vtysh -c "show bgp l2vpn evpn route type 2" \
      | sed -n 's/.*\[32\]:\[\([0-9.]*\)\].*/\1/p' | grep -v '^22\.100\.0\.1$' | head -1
  )
fi

if [[ -z "${POD_IP}" ]]; then
  echo
  echo "No remote pod IP found in EVPN routes."
  echo "Deploy a pod in evpn-test and re-run: $0 <pod-ip>"
  exit 1
fi

echo
echo "=== 4. Tests to pod ${POD_IP} ==="
echo "--- ARP ---"
arping -I "${BRIDGE_DEV}" -c 3 -W 2 "${POD_IP}" || true
echo "--- ping (-I ${BRIDGE_DEV}) ---"
ping -I "${BRIDGE_DEV}" -c 3 -W 2 "${POD_IP}" || true
echo "--- ping (-I ${CUDN_GATEWAY%%/*}) ---"
ping -I "${CUDN_GATEWAY%%/*}" -c 3 -W 2 "${POD_IP}" || true

echo
echo "=== 5. If still failing ==="
echo "On OpenShift:"
echo "  oc get pod -n evpn-test -o wide"
echo "  oc exec -n evpn-test <pod> -- ip addr"
echo "  oc exec -n evpn-test <pod> -- ping -c 2 ${CUDN_GATEWAY%%/*}"
echo
echo "On bastion (capture while pinging):"
echo "  tcpdump -i ${BRIDGE_DEV} -n host ${POD_IP}"
echo "  tcpdump -i ${VXLAN_DEV} -n host ${POD_IP}"
echo
echo "If pod cannot ping ${CUDN_GATEWAY%%/*}, OpenShift may not have bastion SVI in EVPN (return path)."
