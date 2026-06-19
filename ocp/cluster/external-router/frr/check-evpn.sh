#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=frr-lib.sh
source "${SCRIPT_DIR}/frr-lib.sh"

frr_load_vars
frr_ensure_bgp_configured

echo "=== BGP summary ==="
sudo podman exec frr vtysh -c "show bgp summary"

echo
echo "=== EVPN VNI ==="
sudo podman exec frr vtysh -c "show bgp l2vpn evpn vni"

echo
echo "=== EVPN type-2 routes ==="
sudo podman exec frr vtysh -c "show bgp l2vpn evpn route type 2"

echo
echo "=== EVPN MAC table (VNI ${VNI}) ==="
sudo podman exec frr vtysh -c "show evpn mac vni ${VNI}"

echo
echo "=== Kernel dataplane ==="
sudo "${SCRIPT_DIR}/sync-dataplane.sh"
