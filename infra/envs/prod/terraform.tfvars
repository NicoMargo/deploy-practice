project     = "floci-prod"
name_prefix = "prod-"

# This file is the manifest of what is deployed to this environment. A pipeline
# run overrides only the services it rebuilt; everything else stays on the image
# pinned here. Rollback is therefore a git revert, and promotion from staging is
# a copy of the staging tfvars values into this file.

inventory_image     = "ghcr.io/nicomargo/inventory@sha256:86cd267daccc3bdf84402abcd08306669bef6262df810a56f5c339b08c749d81"
notifications_image = "ghcr.io/nicomargo/notifications@sha256:ba503dbb2e9fec5ee17b1b0c013b13e5e57796e0fd229246826fa78e3fa57b1c"
orders_image        = "ghcr.io/nicomargo/orders@sha256:77868aa8cbd23ccdc75338bf3c6f2f14498ebe560a6a3512b58944959c272c43"
