#!/usr/bin/env bash
# Writes INVENTORY_IMAGE, NOTIFICATIONS_IMAGE and ORDERS_IMAGE into one
# environment's terraform.tfvars.
#
# A variable that is not set leaves its line alone, so a run that rebuilt one
# service only touches that service.

# Stop on error, on unset variables, and on a failed command inside a pipe.
set -euo pipefail

# Which environment file to edit. Exits with the usage text if not given.
ENVIRONMENT="${1:?usage: set-images.sh <staging|prod>}"

# Absolute path to the repo root, so the script works from any folder.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The file we rewrite.
TFVARS="${REPO_ROOT}/infra/envs/${ENVIRONMENT}/terraform.tfvars"

# No tfvars file means this environment does not exist.
[ -f "$TFVARS" ] || { echo "unknown environment: ${ENVIRONMENT}" >&2; exit 1; }

for service in inventory notifications orders; do
  # inventory -> INVENTORY_IMAGE
  var="$(echo "$service" | tr '[:lower:]' '[:upper:]')_IMAGE"
  # Reads that variable, empty string if it is not set.
  image="${!var:-}"
  # Nothing passed for this service, so leave its line as it is.
  [ -n "$image" ] || continue

  # Replaces the `<service>_image = "..."` line with the new image, keeping the
  # indentation. Writes to a temp file because sed cannot edit in place safely
  # on both GNU and BSD. Separator is | because image refs contain slashes.
  sed "s|^\([[:space:]]*${service}_image[[:space:]]*=[[:space:]]*\).*|\1\"${image}\"|" \
    "$TFVARS" > "${TFVARS}.tmp"

  # Temp file becomes the real one.
  mv "${TFVARS}.tmp" "$TFVARS"

  echo "  ${service} -> ${image}"
done