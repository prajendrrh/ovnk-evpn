#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME=frr
FRR_DIR="${FRR_DIR:-${HOME}/frr}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=../../vars.env
source "${CLUSTER_DIR}/vars.env"

mkdir -p "${FRR_DIR}"
envsubst '${BGP_ASN} ${BASTION_IP} ${WORKER1_IP} ${WORKER2_IP}' \
  < "${SCRIPT_DIR}/frr.conf.template" > "${FRR_DIR}/frr.conf"

if sudo podman ps --filter "name=${CONTAINER_NAME}" --format "{{.State}}" | grep -q "running"; then
  echo "Stopping existing ${CONTAINER_NAME} container..."
  sudo podman stop "${CONTAINER_NAME}"
fi

echo "Starting FRR on ${BASTION_IP}, peers ${WORKER1_IP} / ${WORKER2_IP}..."
sudo podman run -d --rm \
  -v "${FRR_DIR}:/etc/frr:Z" \
  --net=host \
  --name "${CONTAINER_NAME}" \
  --privileged \
  quay.io/frrouting/frr:master

sleep 3
sudo podman exec "${CONTAINER_NAME}" vtysh -c "show ip bgp summary"
