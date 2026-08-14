# AceUp DevOps homework

A small TypeScript monorepo with three services, and the delivery system around
it: tests and images only for what changed, deploys to Cloud Run on the
floci-gcp emulator, and integration tests against what was actually deployed.

The reasoning behind the decisions is in DESIGN.md.

## Running it

Developed on Ubuntu 24.04. The host needs Docker, `make`,
`git` and `curl`. Node, Terraform and floci all run in pinned containers, so you
do not have to install them.


**1. Clone the repo and go into it.**

```bash
git clone https://github.com/NicoMargo/Aceup-devops.git && cd Aceup-devops
```

**2. Run the unit tests** — this installs the dependencies on its own the first
time, so there is no separate install step.

```bash
make test
```

**3. Run the whole loop against staging** — it starts the emulator, seeds the
secrets, deploys the three services with Terraform, runs the integration tests
and checks that a service without its secret never becomes ready. Takes about
five minutes.

```bash
make verify ENV=staging
```

**4. Load the service URLs that the deploy wrote down**, so you can call them by
hand.

```bash
source .deploy-staging.env
```

**5. Ask `orders` if it is alive.**

```bash
curl -s "$ORDERS_URL/health"
```

**6. Read the stock of one product.**

```bash
curl -s "$INVENTORY_URL/stock/SKU-TEE"
```

**7. Place an order**, which makes `orders` call `inventory` to reserve the
stock and `notifications` to send the confirmation.

```bash
curl -s "$ORDERS_URL/orders" -H 'content-type: application/json' \
  -d '{"sku":"SKU-TEE","quantity":2,"customerEmail":"me@example.com"}'
```

**8. Read the stock again** — the number went down, so the two services really
talked to each other.

```bash
curl -s "$INVENTORY_URL/stock/SKU-TEE"
```

**9. Deploy the second environment**, a separate GCP project that shares no
secrets or services with staging.

```bash
make deploy ENV=prod
```

**10. Run the same tests against prod.**

```bash
make integration-test ENV=prod
```

**11. Optional: run the slow negative test**, which waits for Cloud Run to give
up on a revision whose secret is missing. Takes about four minutes.

```bash
./scripts/test-missing-secret.sh --full
```

**12. Stop the emulator and delete the generated files.**

```bash
make clean
```

`make help` lists every target. They are thin wrappers over the scripts in
`scripts/`, so you can run those directly too.

## What is here

```
starter/            the monorepo (npm workspaces)
  packages/         logger, types, secrets, http-client
  services/         orders, inventory, notifications
  scripts/          affected-packages.js — the dependency graph
infra/
  modules/          reusable Terraform: one service, and the platform
  envs/             staging and prod — variables only
scripts/            deploy, seed secrets, run tests
tests/integration/  tests that hit the deployed services over HTTP
```

## How it fits together

```
   PR or push to main
          |
   [ test ]  which packages changed? -> run only their tests + npm audit
          |
   [ build ] build images for affected services -> Trivy scan -> push to GHCR
          |
   [ deploy-staging ]
          |
          +-- start floci-gcp (Docker)
          +-- seed secrets into Secret Manager
          +-- terraform apply -> Cloud Run
          +-- integration tests over HTTP
          |
   on main only:
          |
   [ update-manifest ]  opens a PR recording the deployed digests
   [ deploy-prod ]      waits for a manual approval
```

The three services talk to each other:

```
   orders  --HTTP-->  inventory      (reserve stock, with an API token)
      |
      +---- HTTP -->  notifications  (send the confirmation)

   all three read their tokens from Secret Manager at startup
```

## Differential builds and deploys

`starter/scripts/affected-packages.js` reads every `package.json` in the
monorepo and builds the dependency graph. CI gives it the list of changed files
and it answers which packages and services are affected.

| You change | What is rebuilt |
|---|---|
| `services/orders/**` | orders |
| `packages/http-client/**` | orders (it is the only package that uses it) |
| `packages/logger/**` | all three services |
| lockfile, CI, root config | everything |

The last row is on purpose. If the file that decides what to build has changed,
we do not trust that decision.

`infra/envs/<env>/terraform.tfvars` pins each service's image by digest and is
the record of what runs in that environment. A deploy overrides only the services
it just rebuilt; everything else deploys what the file says, so rollback is a git
revert plus a redeploy.

After a merge to `main` deploys staging, the pipeline opens a pull request that
writes the digests it deployed back into the staging tfvars — it never pushes to
`main`. Promoting to prod is the same move by hand, with `scripts/promote.sh`.
A change to a manifest rebuilds nothing. Merging one redeploys prod, which
always deploys what its own manifest pins; staging is redeployed by the next
pipeline run, or by hand with `make deploy ENV=staging`.

## Opening up `make verify`

Step 3 above is one target that chains four others. You can run them apart:

```bash
make floci-up                     # start the emulator
make deploy ENV=staging           # seed secrets + terraform apply, prints the URLs
make integration-test ENV=staging
make test-secrets                 # services must not start without their secrets
make floci-down                   # stop the emulator
```

The scripts use only `curl`, `sed`, `grep` and `base64` beyond Docker and
`make`. If you have the floci CLI installed, `floci gcp start` replaces
`make floci-up`.

### Working on the code

```bash
make install    # npm ci
make test       # unit tests for every workspace
make build      # compile everything
```

These run npm inside a `node:20-alpine` container, so the Node version is the
same for everyone and for CI. To work on one workspace only:

```bash
cd starter
npm test -w @aceup/orders-service
```

## How CI uses floci

floci is not a server somewhere. Every workflow run starts a fresh one inside
the GitHub Actions VM, deploys into it, tests it, and the VM is destroyed when
the job ends. Nothing is left over, and nothing from a previous run can affect
the next one.

That also means you cannot open the deployed services from your browser after a
CI run — the only thing that comes out is the log. That is why the integration
tests run inside the same VM.

CI runs the same `make` targets you run locally — `make floci-up`,
`make deploy ENV=staging`, `make integration-test ENV=staging`.

## Security checks in the pipeline

- GitHub Actions pinned to commit SHAs, not tags. Same for the tool images the
  pipeline runs: Terraform, Trivy and floci are pinned by version or digest.
- `npm audit --audit-level=high` fails the run.
- Trivy scans each image **before** it is pushed. Fixable HIGH and CRITICAL fail
  the build. Exceptions live in `.trivyignore` with a reason and an expiry date.
- Images are tagged with the commit SHA but **deployed by digest**. The tag makes
  the registry readable; the digest is a hash of the content, so it cannot be
  repointed at something else.
- Only the build job can write packages; everything else is read only.
- Staging and prod have different API tokens, stored as GitHub Environment
  secrets. A leaked staging token is useless against prod.
- No secret value is in the repo, in an image, or in a build argument. Tokens
  arrive as environment variables at runtime, and the seeding script never logs
  a value.

## Operations

```bash
# what is deployed, and which revision is serving (swap the project for prod)
curl -s "http://localhost:4588/v2/projects/floci-staging/locations/us-central1/services"

# roll back one service: put its previous image back in the tfvars and redeploy
git revert <commit>            # or edit infra/envs/staging/terraform.tfvars
make deploy ENV=staging
```

Rollback is per service, because each service has its own image line in the
tfvars.

**Promoting to prod:**

```bash
./scripts/promote.sh    # copies the staging images into the prod tfvars
git checkout -b promote/$(date +%F)
git commit -am "Promote staging images to prod"
```

Open a pull request with that change. Merging it to `main` runs the prod deploy,
which waits for an approval in the `production` GitHub Environment before it
starts. The prod job deploys what the tfvars says — it never picks the image
itself, so the file is always the record of what runs in prod.

**Secret rotation:** add a new version of the secret, then deploy a new
revision. Services read the secret once at startup, so a running container keeps
the old value until it is replaced. Traffic only moves to the new revision once
it is healthy, so a wrong secret value means the deploy fails and the old
revision keeps serving.