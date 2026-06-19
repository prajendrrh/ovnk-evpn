#!/usr/bin/env bash
# EVPN VXLAN on bastion. Does not modify the primary NIC IP.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../vars.env
source "${SCRIPT_DIR}/../../vars.env"

VTEP_LOCAL="${VTEP_LOCAL:-${BASTION_IP}}"
SVI_IP="${CUDN_GATEWAY}"
SVI_IP_ADDR="${SVI_IP%%/*}"
SVI_PREFIX="${SVI_IP##*/}"

ip link show "${BRIDGE_DEV}" >/dev/null 2>&1 || ip link add "${BRIDGE_DEV}" type bridge
ip link set "${BRIDGE_DEV}" up

if ! ip link show "${VXLAN_DEV}" >/dev/null 2>&1; then
  ip link add "${VXLAN_DEV}" type vxlan id "${VNI}" dstport 4789 local "${VTEP_LOCAL}" nolearning
fi
ip link set "${VXLAN_DEV}" master "${BRIDGE_DEV}"
ip link set "${VXLAN_DEV}" up

# Ensure SVI uses /16 (remove stale /24 from earlier runs)
while read -r old_prefix; do
  [[ -z "${old_prefix}" ]] && continue
  if [[ "${old_prefix}" != "${SVI_IP}" ]]; then
    ip addr del "${old_prefix}" dev "${BRIDGE_DEV}" 2>/dev/null || true
  fi
done < <(ip -4 -o addr show dev "${BRIDGE_DEV}" | awk '{print $4}')

if ! ip -4 addr show dev "${BRIDGE_DEV}" | grep -q "${SVI_IP_ADDR}/${SVI_PREFIX}"; then
  ip addr add "${SVI_IP}" dev "${BRIDGE_DEV}"
fi

# L2 domain route for the CUDN subnet
ip route replace "${CUDN_SUBNET}" dev "${BRIDGE_DEV}" scope link proto static

# Lab: disable neigh_suppress so ARP/neighbor resolution works with manual FDB sync
ip link set "${VXLAN_DEV}" type bridge_slave neigh_suppress off 2>/dev/null || true

# Avoid dropping asymmetric EVPN return traffic
sysctl -w "net.ipv4.conf.${BRIDGE_DEV}.rp_filter=0" >/dev/null
sysctl -w "net.ipv4.conf.${VXLAN_DEV}.rp_filter=0" >/dev/null
sysctl -w "net.ipv4.conf.all.forwarding=1" >/dev/null

echo "VXLAN ready: local ${VTEP_LOCAL}, VNI ${VNI}, SVI ${SVI_IP} on ${BRIDGE_DEV}"
ip -br addr show "${BRIDGE_DEV}"
ip route show dev "${BRIDGE_DEV}"
ip -d link show "${VXLAN_DEV}"
