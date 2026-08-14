project     = "floci-staging"
name_prefix = "staging-"

# This file is the manifest of what is deployed to this environment. A pipeline
# run overrides only the services it rebuilt; everything else stays on the image
# pinned here. Rollback is therefore a git revert, and promotion to prod is a
# copy of these values into the prod tfvars.

inventory_image     = "ghcr.io/nicomargo/inventory@sha256:fd7014d34af2b02b468cf61be54d1ee551a477723aec88c80b3bf63a4ffdd861"
notifications_image = "ghcr.io/nicomargo/notifications@sha256:d4e49ab459f990148e0ade7cbfcc0eab8d7713d5fd7466059ec94a6151b91d5f"
orders_image        = "ghcr.io/nicomargo/orders@sha256:de53d401ae6db0dd734daf68a1b418d9f7cfc8cbf619a7b2cd53c55520f63508"