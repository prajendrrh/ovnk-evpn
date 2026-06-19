#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../vars.env
source "${SCRIPT_DIR}/../../vars.env"

sudo podman exec frr vtysh -c "show ip bgp summary"
sudo podman exec frr vtysh -c "show bgp l2vpn evpn vni"
sudo podman exec frr vtysh -c "show bgp l2vpn evpn route type 2"
sudo podman exec frr vtysh -c "show evpn mac vni ${VNI}"
