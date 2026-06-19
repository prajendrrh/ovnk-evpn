#!/usr/bin/env bash
# EVPN VXLAN on bastion. Does not modify the primary NIC IP.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../vars.env
source "${SCRIPT_DIR}/../../vars.env"

VTEP_LOCAL="${VTEP_LOCAL:-${BASTION_IP}}"
SVI_IP="${CUDN_GATEWAY}"

ip link show br100 >/dev/null 2>&1 || ip link add br100 type bridge
ip link set br100 up

ip link show vni100 >/dev/null 2>&1 || \
  ip link add vni100 type vxlan id "${VNI}" dstport 4789 local "${VTEP_LOCAL}" nolearning
ip link set vni100 master br100
ip link set vni100 up

ip -4 addr show dev br100 | grep -q "${CUDN_GATEWAY%%/*}/" || ip addr add "${SVI_IP}" dev br100

ip link set vni100 type bridge_slave neigh_suppress on 2>/dev/null || true

echo "VXLAN ready: local ${VTEP_LOCAL}, VNI ${VNI}, SVI ${SVI_IP} on br100"
ip -br addr show br100
ip -d link show vni100
