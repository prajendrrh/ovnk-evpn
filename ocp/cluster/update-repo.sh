#!/usr/bin/env bash
# Discard generated local frr.conf and pull latest repo changes.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

cd "${REPO_ROOT}"
git checkout -- ocp/cluster/external-router/frr/frr.conf 2>/dev/null || true
git pull

echo "Updated to $(git rev-parse --short HEAD)"
