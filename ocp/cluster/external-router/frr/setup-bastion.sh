#!/usr/bin/env bash
# Run on bastion (${BASTION_IP}) with podman and envsubst installed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=../../vars.env
source "${CLUSTER_DIR}/vars.env"

echo "Bastion EVPN setup (${BASTION_IP})"
echo "  worker1: ${WORKER1_IP}"
echo "  worker2: ${WORKER2_IP}"
echo "  VNI: ${VNI}, CUDN gateway: ${CUDN_GATEWAY}"
echo

echo "=== 1/4 VXLAN bridge ==="
sudo "${SCRIPT_DIR}/vxlan.sh"

echo
echo "=== 2/4 Firewall (if firewalld active) ==="
sudo "${SCRIPT_DIR}/setup-firewall.sh" || true

echo
echo "=== 3/4 FRR container ==="
"${SCRIPT_DIR}/start-frr.sh"

echo
echo "=== 4/4 EVPN dataplane (FDB/ARP) ==="
sudo "${SCRIPT_DIR}/sync-dataplane.sh"

echo
echo "Verify EVPN:"
echo "  ${SCRIPT_DIR}/check-evpn.sh"
