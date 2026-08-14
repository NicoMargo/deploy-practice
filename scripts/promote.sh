#!/usr/bin/env bash
# Promotes the images currently pinned for staging into the prod manifest.
#
# This does not deploy anything. It edits infra/envs/prod/terraform.tfvars so the
# change goes through a pull request, which is what makes promotion auditable:
# the repo records which version runs in prod, who promoted it and when, and a
# rollback is a revert of that commit.

# Stop on error, on unset variables, and on a failed command inside a pipe.
set -euo pipefail

# Absolute path to the repo root, so the script works from any folder.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The file we read the current staging images from.
STAGING="${REPO_ROOT}/infra/envs/staging/terraform.tfvars"

# Reads the value of a `<service>_image = "..."` line out of the staging file.
read_image() {
  sed -n "s/^[[:space:]]*$1_image[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$STAGING"
}

# Whatever staging runs right now. CI pins digests here (repo@sha256:...).
inventory=$(read_image inventory)
notifications=$(read_image notifications)
orders=$(read_image orders)

# Stop if any line was missing, so we never promote a half-filled manifest.
for service in inventory notifications orders; do
  # ${!service} reads the variable named by $service, so $inventory and so on.
  [ -n "${!service}" ] || { echo "could not read ${service}_image from staging" >&2; exit 1; }
done

echo "promoting staging images into prod:"
# Passes the three images as env vars; set-images.sh writes them into prod.tfvars.
INVENTORY_IMAGE="$inventory" \
NOTIFICATIONS_IMAGE="$notifications" \
ORDERS_IMAGE="$orders" \
  "${REPO_ROOT}/scripts/set-images.sh" prod

echo
echo "prod manifest updated. Commit it and open a pull request to promote."
# Shows what changed, so you can check it before committing.
git --no-pager diff --stat "${REPO_ROOT}/infra/envs/prod/terraform.tfvars"