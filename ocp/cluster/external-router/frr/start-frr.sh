#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME=frr
FRR_DIR="${FRR_DIR:-${HOME}/frr}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=../../vars.env
source "${CLUSTER_DIR}/vars.env"

mkdir -p "${FRR_DIR}"
cp -f "${SCRIPT_DIR}/daemons" "${SCRIPT_DIR}/vtysh.conf" "${FRR_DIR}/"
envsubst '${BGP_ASN} ${BASTION_IP} ${WORKER1_IP} ${WORKER2_IP}' \
  < "${SCRIPT_DIR}/frr.conf.template" > "${FRR_DIR}/frr.conf"
touch "${FRR_DIR}/zebra.conf"
chmod 644 "${FRR_DIR}/"*

if sudo podman ps -a --filter "name=${CONTAINER_NAME}" -q | grep -q .; then
  echo "Removing existing ${CONTAINER_NAME} container..."
  sudo podman rm -f "${CONTAINER_NAME}"
fi

echo "Starting FRR on ${BASTION_IP}, peers ${WORKER1_IP} / ${WORKER2_IP}..."
echo "Config directory: ${FRR_DIR}"
sudo podman run -d \
  -v "${FRR_DIR}:/etc/frr:Z" \
  --net=host \
  --name "${CONTAINER_NAME}" \
  --privileged \
  quay.io/frrouting/frr:master

for _ in $(seq 1 10); do
  if sudo podman ps --filter "name=${CONTAINER_NAME}" --format "{{.State}}" | grep -q "running"; then
    break
  fi
  sleep 1
done

if ! sudo podman ps --filter "name=${CONTAINER_NAME}" --format "{{.State}}" | grep -q "running"; then
  echo "FRR container failed to stay running. Logs:"
  sudo podman logs "${CONTAINER_NAME}" || true
  exit 1
fi

sudo podman exec "${CONTAINER_NAME}" vtysh -c "show ip bgp summary"
