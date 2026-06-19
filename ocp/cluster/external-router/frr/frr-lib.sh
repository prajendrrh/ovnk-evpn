#!/usr/bin/env bash
# Shared helpers for bastion FRR scripts.
set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-frr}"
FRR_DIR="${FRR_DIR:-${HOME}/frr}"

frr_lib_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

frr_cluster_dir() {
  cd "$(frr_lib_dir)/../.." && pwd
}

frr_load_vars() {
  # shellcheck source=../../vars.env
  source "$(frr_cluster_dir)/vars.env"
  FRR_IMAGE="${FRR_IMAGE:-quay.io/frrouting/frr:10.2.1}"
}

frr_ensure_container() {
  if ! sudo podman ps --filter "name=${CONTAINER_NAME}" --format "{{.State}}" | grep -q "running"; then
    echo "FRR container '${CONTAINER_NAME}' is not running. Run ./start-frr.sh first."
    exit 1
  fi
}

frr_bgp_loaded() {
  local out
  out=$(sudo podman exec "${CONTAINER_NAME}" vtysh -c "show bgp summary" 2>&1)
  ! echo "${out}" | grep -qE "bgpd is not running|BGP instance not found|% Unknown"
}

frr_load_bgp_config() {
  frr_load_vars

  echo "Applying BGP/EVPN configuration to running daemons..."
  sudo podman exec -i "${CONTAINER_NAME}" vtysh <<EOF
configure terminal
frr defaults traditional
log stdout debugging
interface ${VXLAN_DEV}
 evpn vni ${VNI}
exit
!
router bgp ${BGP_ASN}
 bgp router-id ${BASTION_IP}
 no bgp default ipv4-unicast
 neighbor ${WORKER1_IP} remote-as ${BGP_ASN}
 neighbor ${WORKER2_IP} remote-as ${BGP_ASN}
 neighbor ${WORKER1_IP} allowas-in origin
 neighbor ${WORKER2_IP} allowas-in origin
 address-family ipv4 unicast
  neighbor ${WORKER1_IP} activate
  neighbor ${WORKER1_IP} next-hop-self
  neighbor ${WORKER2_IP} activate
  neighbor ${WORKER2_IP} next-hop-self
  redistribute static
  redistribute connected
 exit-address-family
 address-family l2vpn evpn
  neighbor ${WORKER1_IP} activate
  neighbor ${WORKER2_IP} activate
  advertise-all-vni
  advertise-svi-ip
 exit-address-family
end
EOF
}

frr_ensure_bgp_configured() {
  frr_ensure_container
  if frr_bgp_loaded; then
    return 0
  fi
  frr_load_bgp_config
  if ! frr_bgp_loaded; then
    echo "BGP configuration is still not loaded."
    sudo podman exec "${CONTAINER_NAME}" vtysh -c "show bgp summary" 2>&1 || true
    exit 1
  fi
}
