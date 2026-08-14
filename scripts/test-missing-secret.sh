#!/usr/bin/env bash
# Proves the services fail closed when a required secret is missing.
#
# Runs inventory against an empty project and checks it refuses to serve:
#   default   the container exits non-zero (~5s)
#   --full    also checks a Cloud Run revision never becomes ready (~4 min)
#
# Services load secrets in main() before app.listen(), so a missing secret is
# not a graceful HTTP error: the process never serves traffic at all.

set -euo pipefail

# Off by default; `--full` as the first argument turns on the slow Cloud Run check.
FULL=0
[ "${1:-}" = "--full" ] && FULL=1

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENDPOINT="${FLOCI_ENDPOINT:-http://localhost:4588}"
TFVARS="${REPO_ROOT}/infra/envs/staging/terraform.tfvars"
EMPTY_PROJECT="floci-no-secrets-here"   # a project with no secrets in it

# Test the same image staging runs.
IMAGE=$(sed -n 's/^[[:space:]]*inventory_image[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$TFVARS")
[ -n "$IMAGE" ] || { echo "could not resolve the inventory image from ${TFVARS}" >&2; exit 1; }

echo "==> container-level: inventory must refuse to start without its secret"

# --stop-timeout rather than the `timeout`
# set +e because a non-zero exit is the expected result here.
set +e
output=$(docker run --rm --stop-timeout 60 \
  --add-host host.docker.internal:host-gateway \
  -e GCP_PROJECT_ID="$EMPTY_PROJECT" \
  -e SECRET_MANAGER_EMULATOR_HOST=host.docker.internal:4588 \
  "$IMAGE" 2>&1)
exit_code=$?
set -e

if [ "$exit_code" -eq 0 ]; then
  echo "FAIL: the container started even though the secret is absent" >&2
  exit 1
fi

# Non-zero is not enough: check it died for the right reason.
if ! grep -q "failed to start inventory" <<<"$output"; then
  echo "FAIL: exited non-zero but not for the expected reason:" >&2
  echo "$output" >&2
  exit 1
fi
echo "    ok — exited ${exit_code} with 'failed to start inventory'"

if [ "$FULL" -eq 0 ]; then
  echo
  echo "skipping the Cloud Run readiness check (run with --full to include it)"
  exit 0
fi

echo "==> cloud run level: a revision must never become ready (~4 min)"
SERVICE="probe-missing-secret"
BASE="${ENDPOINT}/v2/projects/${EMPTY_PROJECT}/locations/us-central1/services"

# Delete the probe service on any exit, including a failure.
cleanup() { curl -sS -o /dev/null -X DELETE "${BASE}/${SERVICE}" || true; }
trap cleanup EXIT

# Deploy the same image as a Cloud Run service, still with no secrets.
curl -sS -o /dev/null -X POST "${BASE}?serviceId=${SERVICE}" \
  -H 'content-type: application/json' \
  -d "{\"template\":{\"containers\":[{\"image\":\"${IMAGE}\",\"ports\":[{\"containerPort\":8081}],\"env\":[{\"name\":\"GCP_PROJECT_ID\",\"value\":\"${EMPTY_PROJECT}\"},{\"name\":\"SECRET_MANAGER_EMULATOR_HOST\",\"value\":\"host.docker.internal:4588\"}]}]}}"

# Poll for up to 10 minutes. CONDITION_PENDING means floci is still starting the
# container, so wait for a terminal state, not just for the field to appear.
state=""
for _ in $(seq 1 60); do
  sleep 10
  # terminalCondition comes first in the response, so the first CONDITION_* match
  # is its state. grep keeps jq off the list of host requirements.
  state=$(curl -sS "${BASE}/${SERVICE}" | grep -o 'CONDITION_[A-Z]*' | head -1)
  case "$state" in
    CONDITION_FAILED | CONDITION_SUCCEEDED) break ;;
  esac
  echo "    revision still settling (state='${state:-unknown}')..."
done

# FAILED is the pass condition here: the revision was supposed to never be ready.
case "$state" in
  CONDITION_FAILED)
    echo "    ok — revision never became ready, as expected"
    ;;
  CONDITION_SUCCEEDED)
    echo "FAIL: the revision became ready without its secret" >&2
    exit 1
    ;;
  *)
    echo "FAIL: revision did not settle within the polling window (state='${state}')" >&2
    exit 1
    ;;
esac