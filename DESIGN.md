# Design notes

Decisions I made, why, and what I left out.

## What happens when you push

1. **You open or update a pull request.** CI starts.
2. **`test`** diffs your branch against its base, feeds the changed files to
   `affected-packages.js`, and runs the unit tests only for the packages that come
   back. It also runs `npm audit`, which fails on high or critical.
3. **`build`** runs only if something is affected. For each affected service it
   builds the image, scans it with Trivy, and pushes it to GHCR **in that order**,
   so an image that fails the scan never reaches the registry. Then it reads back
   the digest of what it pushed.
4. **`deploy-staging`** starts a fresh floci emulator inside the runner, seeds the
   secrets from the environment's GitHub secrets, and applies Terraform in two
   phases. Services this run rebuilt get the new digest; the rest get what
   `infra/envs/staging/terraform.tfvars` pins. Then it runs the integration tests
   against the deployed services and checks they fail closed without a secret.
5. **If anything above fails, the pull request cannot be merged.** The branch
   rule requires one check, `ci-ok`, which passes only if every job above passed
   or was skipped. It has to be that job and not the three themselves: `build`
   and `deploy-staging` are skipped when nothing is affected, and a skipped
   required check leaves a pull request pending for ever.
6. **You merge to `main`.** The same three jobs run again. Two more follow:
   `update-manifest` opens a pull request writing the digests it deployed into the
   staging tfvars, and `deploy-prod` waits until someone approves the `production`
   environment, then deploys exactly what the prod tfvars pins.
7. **Promoting is a separate change.** `scripts/promote.sh` copies the staging
   digests into the prod tfvars, and that edit goes through its own pull request.

## Change detection

I did not want a hardcoded map like "if `services/orders/**` changed, deploy
orders". `starter/scripts/affected-packages.js` builds the graph from the repo instead: it
reads every `package.json` under `packages/*` and `services/*`, builds a reverse
dependency graph, maps each changed file to the workspace that owns it, and walks
the graph to find everything that depends on the changed packages. CI runs
`git diff` (PR base, or previous commit on `main`) and feeds it the file list.

The case that matters is `packages/http-client`: only `orders` imports it, so a
change there must not rebuild `inventory` or `notifications`. Changing
`packages/logger` does rebuild all three.

If a changed file belongs to no workspace (lockfile, root config, CI workflow,
scripts), the script returns "everything affected". That is on purpose: if the
logic that decides what to build has itself changed, I do not want to trust it to
scope the build.

## Environments and promotion

Two environments, each in its own GCP project (`floci-staging`, `floci-prod`).
Separate projects because on real GCP that is the strongest isolation boundary:
IAM, quotas and billing are all per project. floci does not put the project in
its container names, so I also add a `staging-` / `prod-` prefix, that part is
only a workaround so port discovery can tell the environments.

Terraform is a `cloud-run-service` module, a `platform` module that wires the
three services together, and one thin root per environment. No resource is
defined twice; the two `envs/*/main.tf` files are identical but contain only
variable declarations and a module call. All the difference is in
`terraform.tfvars`. I considered Terraform workspaces to remove even that
boilerplate, but workspaces share one state backend and I prefer a separate state
file per environment.

`terraform.tfvars` pins each service's image by digest and is the record of what
runs in that environment. A deploy overrides only the services it just rebuilt;
everything else deploys what the file says. So rollback is a git revert plus a
redeploy.

Keeping that record true needs the pipeline to write back. After a merge to
`main` deploys staging, `update-manifest` puts the digests it deployed into the
staging tfvars — through a pull request, not a push to `main`. A direct push would
have needed either a bypass on the branch protection or a long-lived credential,
and this project's argument is that it uses neither. The cost is that the manifest
is behind until that pull request is merged.

A manifest change rebuilds nothing: `affected-packages.js` ignores `infra/envs/`.
Without that, merging the bot's pull request would rebuild every service, get new
digests, and open another one.

That has a consequence I had to handle. With nothing affected, `build` and
`deploy-staging` are skipped, and a job whose `needs` were skipped is skipped
too — so a promotion, which only edits the prod manifest, would never have
reached prod. `deploy-prod` therefore uses `!cancelled()` plus explicit checks on
each `needs.*.result`, which lets a skipped job through but still stops on a
failed one.

Promotion is a commit, not a pipeline trigger. `scripts/promote.sh` copies the
image values from the staging tfvars into the prod one; that change goes through
a pull request, and merging it to `main` runs the prod deploy. The prod job
deploys exactly what its tfvars pins — it never overrides the image with the
commit SHA, or the file would stop being the record of what runs.

There are two checkpoints: the review of the promotion PR, and a GitHub
Environment (`production`) with required reviewers that holds the job until
someone approves it. I chose manual approval over promoting automatically after
staging because the integration tests here are small, so I do not have enough
confidence to skip a human. The cost is one click.

## Secrets

**Access pattern.** Services fetch tokens from Secret Manager at startup with the
SDK. I kept this instead of Cloud Run's native secret injection because the
starter is already written around an SDK call, and changing it would mean changing
the application, not only the deployment. 

**Making it work with floci.** The shipped `createSecretsClient()` builds the
client with no arguments, and that client reads no environment variable to decide
where to connect, so it always tried to reach real Google Cloud. The
`EMULATOR_HOST` convention that works for Firestore or Pub/Sub does not exist for
this client. (The starter README also mentions
`SECRETMANAGER_EMULATOR_HOST` while floci exports `SECRET_MANAGER_EMULATOR_HOST`)

My fix builds the client conditionally: with `SECRET_MANAGER_EMULATOR_HOST` set it
connects to that host and port over an insecure channel (floci), without it, the default
client and Application Default Credentials (GCP). The same compiled code runs against
floci and real GCP. 

**Seeding.** `scripts/seed-secrets.sh` uses the Secret Manager REST API with
`curl`, so it needs no Node. Values come from environment variables, so CI injects
them from GitHub Secrets; defaults are throwaway dev tokens. It logs secret ids,
never values, and ignores "already exists", so re-running is safe.

**Failure mode.** All three services load secrets in `main()` before
`app.listen()`. A missing secret is therefore not a 500, the process exits and
never serves traffic. On Cloud Run that is a revision that never becomes ready. I
saw it for real: floci waited four minutes and reported
`Cloud Run runtime did not become ready before timeout`.

`scripts/test-missing-secret.sh` asserts the container exits non-zero with the
expected log line, and with `--full` also asserts the Cloud Run revision ends in
`CONDITION_FAILED`. CI runs the fast check every time; four minutes per PR for the
slow one is not worth it.

**Rotation.** Services read the secret once at startup and keep the value in
  memory, so adding a new version does not change anything for containers that are
  already running. Rotating means: add the version, then deploy a new revision so
  the containers start again and pick it up.

**IAM on real GCP** (design only, floci has no auth). One service account per
  service, not the shared default. Access is granted per secret, and it follows who
  calls whom: `inventory` and `notifications` each read only their own token, which
  they use to check incoming requests, while `orders` reads both, because it is the
  caller and has to authenticate against them

## floci vs real GCP

What I learned: floci emulates Cloud Run **v2** and Secret Manager over **REST**
as well as gRPC, so the Terraform Google provider works against it with
`cloud_run_v2_custom_endpoint` and `secret_manager_custom_endpoint`. Its state is
in memory, so a restart deletes everything, where each run starts a
fresh emulator. It launches Cloud Run containers through the host Docker daemon,
so it needs `/var/run/docker.sock` mounted.

**The service discovery gap.** floci gives each service a
`*.run.localhost.floci.io` URL and even runs an embedded DNS server for that
domain, but it does not configure its own containers to use that DNS. I checked:
the container's `/etc/hosts` only has `host.docker.internal` and itself. So
`orders` cannot reach `inventory` by URL. It uses the port floci publishes on the
host instead, and because that port is random, `scripts/deploy.sh` runs in two
phases: deploy the services with no dependencies, discover their ports, then
deploy `orders` pointing at them. On real GCP the URL is public DNS, so `orders`
would use `module.inventory.uri` and one apply would be enough.

Matching a container by name is a guess, so after discovering a port the script
calls `/health` and checks the service name.

| Area | floci | Real GCP |
|---|---|---|
| Auth | dummy token, zero auth | Workload Identity Federation |
| Provider | custom endpoints | remove them |
| State | local file, disposable | GCS backend with locking |
| Environments | recreated per CI run | long lived |
| Secrets | seeded every run | created once, rotated separately |
| Discovery | published ports, two phases | Cloud Run URL, one apply |

## Security choices

In place: no secret value in the repo, an image or a build argument; the seeding
script never prints values; CI uses the automatic `GITHUB_TOKEN` for GHCR instead
of a personal token I would have to store and rotate; images run as non-root,
build from a lockfile with `npm ci`, and ship only compiled output and production
dependencies; `main` is protected with a required PR and a required check; the
deploy job depends on tests and build, so a red test never reaches a deploy.

**Images are tagged with the commit SHA, but every deploy references the digest**
  CI captures it after the push, and `terraform.tfvars` pins it for anything CI did
  not rebuild.

**Actions pinned to commit SHAs**, not tags. A tag like `@v4` can be moved by
whoever owns the action, which would change what runs in my pipeline without any
change on my side. The version is kept in a comment so the file stays readable.

**Dependency scanning** with `npm audit --audit-level=high` on every run. Failing
on high and critical, not on moderate: a gate that fires on everything gets
bypassed and then protects nothing. The repo currently has 5 moderate findings,
visible in the log, not blocking.

**Image scanning** with Trivy, between build and push, so an image that fails the
policy never reaches the registry. Threshold is fixable HIGH and CRITICAL —
`--ignore-unfixed`, because a vulnerability with no fix available would block the
pipeline forever and the gate would end up disabled.

The first scan found 20 fixable HIGH/CRITICAL. None of them were in the
application dependencies, which were clean. 18 came from the npm CLI's own
bundled packages (tar, minimatch, glob, sigstore) and 2 from Alpine's openssl.
npm is only needed to install dependencies, never at runtime, so the runtime
stage now deletes npm and yarn in the same `RUN` as the install, a separate
layer would leave the files in the image. That removed all 18.

The 2 openssl ones are fixed in Alpine 3.5.7-r0, but `node:20-alpine` has not
been rebuilt with it. `apk upgrade` at build time would fix them, but it would
also make two builds of the same commit produce different images, so I kept
reproducibility instead. The CVE is in `.trivyignore` with the reason and an
expiry date. That is one reviewed exception.

Left out on purpose:

- **Signing the base image choice.** The base image is pinned by tag
  (`node:20-alpine`), not by digest, so it can move. Pinning by digest would be
  stricter, but then security patches never arrive until someone updates the
  digest by hand. With the scan gate in place I preferred the tag.

## Things I found in the starter

- **`http-client` throws on any non-2xx**, so in `orders` the
  `if (!reservation.ok)` branch is unreachable: `inventory` returns 409 for "not
  enough stock" and the client throws before the body is read. The caller gets
  `{"error": "upstream_failure"}` instead of a `rejected` order, and the order is
  never stored. From outside, "out of stock" looks like "the other service is
  down". I did not change it, it is application logic, but my integration test
  asserts the real behaviour with a comment explaining why.

- **Test scripts relied on shell glob expansion.** `node --test src/**/*.test.ts`
  worked locally and failed in CI: npm runs scripts with `sh`, which does not
  expand `**`. Quoting moved the problem to Node, whose glob support depends on
  the version (my machine has Node 24, CI pins Node 20). `$(find src -name
  '*.test.ts')` depends on neither.

- **Committed `dist/` folders**, ignored by `.gitignore`. I built the repo from
  scratch so they never entered my history, and `.dockerignore` excludes them so
  containers always compile from source.

## Next steps

1. Real GCP identity: WIF, per-service runtime accounts, per-secret IAM bindings.
2. Service-to-service authentication, which needs the application change
   described above.
3. Watch the `.trivyignore` expiry and drop the entry once a patched
   `node:20-alpine` is published.

## Known limitations

- Differential deploy does not help when a shared package or root config changes:
  everything rebuilds. Correct, but the benefit disappears exactly when the change
  is large.
- The graph only understands npm dependencies. If a service started reading a
  shared file that is not a dependency, the graph would miss it.
- Host tools: Docker, `make`, and `curl`, `sed`, `grep`, `base64`. Node,
  Terraform and floci all run in pinned containers, and `make` is only a thin
  wrapper over the scripts, but those utilities are still assumed to exist. I
  found this out by testing on a clean machine: `make` was missing on Ubuntu and
  `jq` was missing on Kali, so I dropped `jq` from the scripts and parse those
  two small JSON responses with `grep` instead. CI still uses `jq`, since the
  GitHub runners ship it and the parsing there is less trivial.

## Cost

floci is free, so there is no real bill here, but this is how I would think
about it on GCP. Cloud Run charges per request and scales down to zero, so
services with little traffic cost almost nothing while nobody is using them. The
setting I would not skip is a maximum number of instances: without it, a bug
that retries in a loop can start many containers and turn into a large bill. The
other thing that grows without anyone looking is stored images, because every
commit pushes new ones, so the old ones should be deleted. And since each
environment is its own project, I would put a budget alert on each one.
