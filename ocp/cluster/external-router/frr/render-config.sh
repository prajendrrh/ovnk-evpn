#!/usr/bin/env bash
# Regenerate frr.conf from vars.env + frr.conf.template
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=../../vars.env
source "${CLUSTER_DIR}/vars.env"

envsubst '${BGP_ASN} ${BASTION_IP} ${WORKER1_IP} ${WORKER2_IP}' \
  < "${SCRIPT_DIR}/frr.conf.template" > "${SCRIPT_DIR}/frr.conf"

echo "Wrote ${SCRIPT_DIR}/frr.conf"
echo "  bastion:  ${BASTION_IP}"
echo "  worker1:  ${WORKER1_IP}"
echo "  worker2:  ${WORKER2_IP}"
echo "  ASN:      ${BGP_ASN}"
