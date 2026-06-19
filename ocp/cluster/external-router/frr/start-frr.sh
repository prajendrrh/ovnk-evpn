#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME=frr
FRR_DIR="${FRR_DIR:-${HOME}/frr}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=../../vars.env
source "${CLUSTER_DIR}/vars.env"
FRR_IMAGE="${FRR_IMAGE:-quay.io/frrouting/frr:10.2.1}"

show_diagnostics() {
  echo
  echo "=== podman logs (${CONTAINER_NAME}) ==="
  sudo podman logs "${CONTAINER_NAME}" 2>&1 | tail -80 || true
  echo
  echo "=== processes ==="
  sudo podman exec "${CONTAINER_NAME}" ps aux 2>&1 || true
  echo
  echo "=== /var/log/frr ==="
  sudo podman exec "${CONTAINER_NAME}" sh -c 'ls -la /var/log/frr 2>/dev/null; tail -30 /var/log/frr/bgpd.log 2>/dev/null; tail -30 /var/log/frr/frr.log 2>/dev/null' || true
  echo
  echo "=== bgpd config check ==="
  sudo podman exec "${CONTAINER_NAME}" sh -c '/usr/lib/frr/bgpd --dryrun -f /etc/frr/frr.conf 2>&1' || true
}

prepare_config() {
  mkdir -p "${FRR_DIR}"
  cp -f "${SCRIPT_DIR}/daemons" "${SCRIPT_DIR}/vtysh.conf" "${FRR_DIR}/"
  envsubst '${BGP_ASN} ${BASTION_IP} ${WORKER1_IP} ${WORKER2_IP}' \
    < "${SCRIPT_DIR}/frr.conf.template" > "${FRR_DIR}/frr.conf"

  local frr_uid frr_gid vty_gid
  frr_uid=$(sudo podman run --rm --entrypoint id "${FRR_IMAGE}" -u frr)
  frr_gid=$(sudo podman run --rm --entrypoint id "${FRR_IMAGE}" -g frr)
  vty_gid=$(sudo podman run --rm --entrypoint getent "${FRR_IMAGE}" group frrvty | cut -d: -f3)

  sudo chown "${frr_uid}:${frr_gid}" "${FRR_DIR}/frr.conf" "${FRR_DIR}/daemons"
  sudo chown "${frr_uid}:${vty_gid}" "${FRR_DIR}/vtysh.conf"
  sudo chmod 640 "${FRR_DIR}/frr.conf" "${FRR_DIR}/daemons"
  sudo chmod 660 "${FRR_DIR}/vtysh.conf"
}

wait_for_bgpd() {
  local i
  for i in $(seq 1 30); do
    if sudo podman exec "${CONTAINER_NAME}" vtysh -c "show ip bgp summary" 2>&1 | grep -qv "bgpd is not running"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

prepare_config

if sudo podman ps -a --filter "name=${CONTAINER_NAME}" -q | grep -q .; then
  echo "Removing existing ${CONTAINER_NAME} container..."
  sudo podman rm -f "${CONTAINER_NAME}"
fi

echo "Starting FRR (${FRR_IMAGE}) on ${BASTION_IP}, peers ${WORKER1_IP} / ${WORKER2_IP}..."
echo "Config directory: ${FRR_DIR}"

sudo podman run -d --init \
  -v "${FRR_DIR}/frr.conf:/etc/frr/frr.conf:Z" \
  -v "${FRR_DIR}/daemons:/etc/frr/daemons:Z" \
  -v "${FRR_DIR}/vtysh.conf:/etc/frr/vtysh.conf:Z" \
  --net=host \
  --name "${CONTAINER_NAME}" \
  --privileged \
  "${FRR_IMAGE}"

if ! sudo podman ps --filter "name=${CONTAINER_NAME}" --format "{{.State}}" | grep -q "running"; then
  echo "FRR container is not running."
  show_diagnostics
  exit 1
fi

if ! wait_for_bgpd; then
  echo "bgpd did not start."
  show_diagnostics
  exit 1
fi

sudo podman exec "${CONTAINER_NAME}" vtysh -c "show ip bgp summary"
