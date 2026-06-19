#!/usr/bin/env bash
# Open firewalld for BGP and CUDN overlay on bastion.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../vars.env
source "${SCRIPT_DIR}/../../vars.env"

if ! systemctl is-active --quiet firewalld; then
  echo "firewalld is not running; nothing to do."
  exit 0
fi

echo "Opening firewalld for BGP and ${CUDN_SUBNET} on bastion..."
sudo firewall-cmd --permanent --add-port=179/tcp
sudo firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=${UNDERLAY_CIDR} port port=179 protocol=tcp accept"
sudo firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=${CUDN_SUBNET} accept"
sudo firewall-cmd --permanent --add-rich-rule="rule family=ipv4 destination address=${CUDN_SUBNET} accept"
sudo firewall-cmd --reload
sudo firewall-cmd --list-all
