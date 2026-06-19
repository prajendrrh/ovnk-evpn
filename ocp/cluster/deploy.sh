#!/usr/bin/env bash
set -euo pipefail

CLUSTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=vars.env
source "${CLUSTER_DIR}/vars.env"

echo "Applying EVPN/CUDN manifests on ${UNDERLAY_CIDR}..."
echo "  worker1 VTEP: ${WORKER1_IP}"
echo "  worker2 VTEP: ${WORKER2_IP}"
echo "  external FRR: ${BASTION_IP} (bastion)"
echo
echo "NMState is not used — nodes already have underlay IPs via DHCP."

oc apply -f "${CLUSTER_DIR}/1-vtep.yaml"
oc apply -f "${CLUSTER_DIR}/2-frr.yaml"
oc apply -f "${CLUSTER_DIR}/3-namespace.yaml"
oc apply -f "${CLUSTER_DIR}/4-CUDN.yaml"
oc apply -f "${CLUSTER_DIR}/5-ra.yaml"

echo
echo "OpenShift manifests applied."
echo
echo "Next, on bastion (${BASTION_IP}):"
echo "  cd ${CLUSTER_DIR}/external-router/frr"
echo "  ./setup-bastion.sh"
echo
echo "Verify OpenShift:"
echo "  oc get vtep,clusteruserdefinednetwork,routeadvertisements"
echo "  oc get frrconfiguration -n openshift-frr-k8s"
