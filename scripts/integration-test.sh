#!/usr/bin/env bash
# Runs the integration tests against an already-deployed environment.
# Node runs containerised and the tests use only built-ins, so nothing needs to
# be installed on the host and no dependency install step is required.
set -euo pipefail

# First argument: which environment to test. The script exits if it is missing.
ENVIRONMENT="${1:?usage: integration-test.sh <staging|prod>}"

# Absolute path to the repo root, so the script works from any folder.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Docker image used to run the tests.
NODE_IMAGE="node:20-alpine"

# File with the service URLs. deploy.sh writes it.
ENV_FILE="${REPO_ROOT}/.deploy-${ENVIRONMENT}.env"

# Fail early with a clear message if the environment was never deployed.
[ -f "$ENV_FILE" ] || {
  echo "missing ${ENV_FILE}: run scripts/deploy.sh ${ENVIRONMENT} first" >&2
  exit 1
}

set -a; source "$ENV_FILE"; set +a

# The env file holds localhost URLs, which are right for a human running curl on
# the host. Inside the container the host is host.docker.internal — and that also
# works on Docker Desktop, where --network host would not reach the Mac at all.
echo "running integration tests against ${ENVIRONMENT}"
docker run --rm \
  --add-host host.docker.internal:host-gateway \
  -e ORDERS_URL="${ORDERS_URL/localhost/host.docker.internal}" \
  -e INVENTORY_URL="${INVENTORY_URL/localhost/host.docker.internal}" \
  -e NOTIFICATIONS_URL="${NOTIFICATIONS_URL/localhost/host.docker.internal}" \
  -v "${REPO_ROOT}/tests:/tests:ro" \
  "$NODE_IMAGE" node --test /tests/integration/api.test.mjs
