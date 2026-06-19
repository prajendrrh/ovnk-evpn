#!/usr/bin/env bash
# Moved to ocp/cluster/external-router/frr/
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/ocp/cluster/external-router/frr/setup-bastion.sh" "$@"
