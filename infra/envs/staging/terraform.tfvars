project     = "floci-staging"
name_prefix = "staging-"

# This file is the manifest of what is deployed to this environment. A pipeline
# run overrides only the services it rebuilt; everything else stays on the image
# pinned here. Rollback is therefore a git revert, and promotion to prod is a
# copy of these values into the prod tfvars.

inventory_image     = "ghcr.io/nicomargo/practice/inventory@sha256:73f939dfe8c4d22ddec559b5414e8336caaef3a177f6f6a07f5d9234faebe1a6"
notifications_image = "ghcr.io/nicomargo/practice/notifications@sha256:e6e60f55741f0498f5679a609bb5b33faf3456167615e376759fd6fcd9fea5f2"
orders_image        = "ghcr.io/nicomargo/practice/orders@sha256:568cf47e9d6f22f00d5b3ff7626d679d6ba360121031bbe3731e7f6042a02731"