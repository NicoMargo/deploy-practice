#!/usr/bin/env bash
# Seeds the application secrets into a floci-gcp project via the Secret Manager
# REST API. Values come from the environment so CI can inject them from GitHub
# Secrets; the defaults are throwaway local-development tokens.

# Stop on error, on unset variables, and on a failed command inside a pipe.
set -euo pipefail

# Which project to seed. Exits with the usage text if not given.
PROJECT="${1:?usage: seed-secrets.sh <project-id>}"

# Where the emulator listens. Override with FLOCI_ENDPOINT if needed.
ENDPOINT="${FLOCI_ENDPOINT:-http://localhost:4588}"

# Real values come from CI; these defaults are for local development only.
INVENTORY_TOKEN="${INVENTORY_API_TOKEN:-dev-inventory-token}"
NOTIFICATIONS_TOKEN="${NOTIFICATIONS_API_TOKEN:-dev-notifications-token}"

# Creates a secret and adds a version with the given value.
seed() {
  local id="$1" value="$2" encoded

  # Creating an existing secret returns an error we can safely ignore, which is
  # what makes re-running the pipeline on the same environment.
  # || true keeps set -e from stopping the script on that error.
  curl -sS -o /dev/null -X POST \
    "${ENDPOINT}/v1/projects/${PROJECT}/secrets?secretId=${id}" \
    -H 'content-type: application/json' \
    -d '{"replication":{"automatic":{}}}' || true

  # The REST API takes the payload as base64, since fields become
  # base64 in JSON. 
  encoded=$(printf '%s' "$value" | base64 | tr -d '\n')

  # Adds the value as a new version of the secret.
  curl -sS -o /dev/null -X POST \
    "${ENDPOINT}/v1/projects/${PROJECT}/secrets/${id}:addVersion" \
    -H 'content-type: application/json' \
    -d "{\"payload\":{\"data\":\"${encoded}\"}}"

  # Log the secret id only, never the value.
  echo "  seeded ${id}"
}

echo "seeding secrets into project ${PROJECT}"
# The ids here must match what the services ask Secret Manager for.
seed inventory-api-token "$INVENTORY_TOKEN"
seed notifications-api-token "$NOTIFICATIONS_TOKEN"