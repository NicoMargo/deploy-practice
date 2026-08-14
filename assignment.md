# DevSecOps Homework — Differential Delivery Monorepo

**Role:** DevSecOps / Cloud Engineer (GCP)  
**Timebox:** **4 days** (quality over completeness; document trade-offs)  
**Language:** English (code + README)  
**Starter tooling:** **npm** workspaces (you may keep or justify a change)

---

## Context

You receive a small **TypeScript** codebase with:

- **3 HTTP services** (`orders`, `inventory`, `notifications`)
- **shared packages** used by more than one service (logger, HTTP client, types, secrets helper)

Your job is **not** to rewrite the product. Your job is to turn this into a **GitHub monorepo** with a delivery system that:

1. **tests** and **builds** correctly
2. **delivers** immutable artifacts
3. **deploys** to **GCP Cloud Run** against a local GCP emulator ([floci-gcp](https://floci.io/gcp/))
4. **deploys differentially** — only rebuild/redeploy what actually changed
5. runs **integration tests** against a deployed environment
6. applies sensible **DevSecOps** defaults — including a secure secrets story via **Secret Manager**

Treat this like production platform work: clear trade-offs, reproducible setup, and documentation that another engineer can follow.

### Runtime target: floci-gcp

You **must** use **[floci-gcp](https://floci.io/gcp/)** as the GCP control plane for this exercise (Cloud Run, Secret Manager, and any other GCP APIs you introduce).

- No real GCP project, billing account, or service-account JSON is required.
- Design pipelines and Terraform/gcloud usage so they talk to the emulator (endpoint overrides / `floci gcp env`), and document how the same shape would map to real GCP.
- CI should be able to start floci (Docker), seed/configure secrets, deploy, and run integration tests against it.
- **Container images live in GitHub Container Registry (GHCR).** floci-gcp does **not** emulate Artifact Registry, and its Cloud Run runs your container through the host Docker daemon — so images must be **pullable from a real registry**, not merely present in a local image cache. Push build artifacts to `ghcr.io/<owner>/<service>` and have floci Cloud Run pull them **by digest**. Public GHCR packages are free (no extra infra or cost). Document the real-GCP **Artifact Registry** equivalent — same push-by-digest shape, swap the registry host and auth.

### Secrets (required; design is yours)

The starter services **depend on Google Secret Manager** for sensitive configuration (API tokens / signing secrets). Hard-coding secrets in the repo or baking them into images is **not** acceptable.

**How** you make that secure and operable is intentionally open — we evaluate your decisions. Examples of choices you own (non-exhaustive):

- when/how secrets are created and versioned in floci
- how Cloud Run services obtain secret values (runtime fetch, env injection, volume mounts, etc.)
- IAM / identity model you would use on real GCP vs what floci allows locally
- secret naming, rotation story, and failure modes (missing secret, wrong version)
- how CI seeds secrets for integration tests without leaking them into logs

Document what you chose and why in `DESIGN.md`.

---

## What we give you

A starter folder containing an **npm workspaces** layout:

| Path | Purpose |
|------|---------|
| `services/orders` | Orders API (depends on shared packages; calls inventory) |
| `services/inventory` | Inventory API (depends on shared packages) |
| `services/notifications` | Notifications API (depends on shared packages) |
| `packages/*` | Shared TypeScript modules (logger, HTTP client, types, secrets) |
| `README.md` | How to run each service locally (minimal) |

Services are intentionally tiny. Assume they will grow; design the monorepo and pipelines accordingly.

---

## Assignment tasks

### 1. Monorepo layout & developer experience

- Keep (or thoughtfully evolve) the **npm workspaces** monorepo.
- Make it obvious how to:
  - install dependencies once
  - run unit tests for one service vs all
  - build one service vs all
- Add a root `README.md` that explains the layout and how the pipeline works.

### 2. Containerization

- Provide a **Dockerfile** (or equivalent) per service.
- Prefer patterns that keep images **small**, **reproducible**, and suitable for Cloud Run.
- Do **not** put secret values in images or Docker build args.
- Services must expose a health endpoint (already present).

### 3. CI: test → build → deliver (on every relevant change)

Implement **GitHub Actions** so that on pull requests / pushes you:

- detect **which services and shared packages changed**
- run **unit tests** for affected packages/services (and anything that depends on a changed shared package)
- **build** container images only for affected services
- push images to **GitHub Container Registry (GHCR)** (`ghcr.io/<owner>/<service>`) so floci-gcp Cloud Run can **pull** them at deploy time — floci has no Artifact Registry and its Cloud Run pulls from a registry rather than a local image cache, so a "build locally and hope floci runs it" path will not work; document the real-GCP **Artifact Registry** equivalent
- tag images immutably (commit SHA and/or content digest) and have Cloud Run / Terraform reference them **by digest** — not only `:latest`

### 4. Differential deployment (via floci-gcp Cloud Run)

Implement deployment so that:

- a change that only touches `services/orders` **does not** rebuild/redeploy `inventory` or `notifications`
- a change to a **shared package** rebuilds/redeploys **all services that depend on it**
- deployment target is **Cloud Run on floci-gcp**
- support at least two environments: **staging** and **production** (naming/isolation convention is yours — justify it)
- production promotion should be intentional (e.g. after staging succeeds, manual approval, or an explicit promotion workflow — pick one and justify it)

Document the exact local commands: starting the emulator, exporting env, seeding secrets, and deploying.

### 5. Infrastructure as Code

- Express Cloud Run (and any supporting resources you introduce, including secret wiring if applicable) with **Terraform**, aimed at floci-gcp endpoints where practical.
- Keep credentials and secret **values** out of git.
- For the real-GCP path, prefer **OIDC / Workload Identity Federation** over long-lived JSON keys; for floci, document the zero-auth local model and how you would swap providers/backends for real GCP.
- Document prerequisites: Docker, floci CLI (or `docker run floci/floci-gcp`), Terraform, etc.

> You do **not** need a full production VPC/Cloud SQL design. Prefer a minimal but credible Cloud Run + secrets footprint.

### 6. Integration tests in the pipeline

- After deploying to **staging** on floci-gcp, run **integration tests** that hit the deployed services over HTTP.
- At minimum:
  - health checks for each deployed service
  - one cross-service happy path (e.g. create an order that exercises orders → inventory, with auth secrets correctly available)
  - evidence that services fail safely when required secrets are missing (or an equivalent negative path you document)
- Fail the pipeline if integration tests fail.
- Keep tests hermetic enough to run in CI (start floci → seed secrets → deploy → test).

### 7. DevSecOps baseline (choose depth wisely)

Include a **small, coherent** security baseline in CI/CD. Examples (pick what you can justify; do not fake all of them):

- dependency and/or container image scanning
- pin GitHub Actions to commit SHAs
- least-privilege deploy identity (describe the real-GCP model even if floci is open locally)
- secrets only via Secret Manager (and/or GitHub Environments for *pipeline* secrets — not application secrets in the repo)
- SBOM generation and/or image signing (nice to have)

Explain what you implemented and what you deliberately deferred.

### 8. Operability & rollback

Document:

- how to see which Cloud Run revision is live (against floci)
- how to roll back a bad deploy for one service
- how staging vs production promotion works
- how secret rotation would work in your design
- known limitations of your differential deploy approach **and** of using an emulator vs real GCP

### 9. Local environment isolation & reproducible tooling

The full test/build/deploy loop must run on a clean machine **without relying on tooling installed in the developer's environment**. A reviewer should be able to clone the repo, have **Docker** (and a container runtime) available, and run the pipeline end-to-end — without first installing a specific Node version, npm, Terraform, the floci CLI, gcloud, or other host dependencies.

- Provide a **Docker-based way to run the test system** (and ideally build/deploy steps) so that the versions of Node, package managers, Terraform, floci, and any CLIs are **pinned inside containers**, not assumed on the host.
- The only host prerequisites should be Docker (plus a container runtime) and, optionally, a thin task runner (`make`, a shell script, `docker compose`, or equivalent). Document exactly what the host is expected to have.
- Running unit tests, integration tests, and the floci-backed deploy should be reproducible: **same commands, same pinned tool versions, same results** on any machine and in CI.
- The **same containerized entrypoints** used locally should be what CI invokes — avoid a separate, hand-maintained CI-only path that can drift from local.
- Document the trade-offs of your isolation approach (e.g. dev-container vs. compose vs. a "tools" image), and any escape hatches for developers who prefer running natively.

---

## Explicit non-goals

To keep scope fair, you do **not** need to:

- rewrite service business logic beyond wiring needed for secure config/deploy
- build a full Kubernetes platform
- implement a complete multi-region/HA architecture
- stand up Cloud SQL / VPC / Cloud Armor unless you want to show depth
- achieve perfect coverage or enterprise-grade policy-as-code
- provision a real GCP project or billing account

We care more about **sound pipeline design**, **secure secrets handling**, and **clear reasoning** than feature count.

---

## Deliverables

1. A **public or private GitHub repository** (share access with us) containing the monorepo + pipelines + Terraform + docs.
2. A root **README** covering: architecture diagram (simple is fine), how differential deploy works, how to run floci + secrets + deploy locally, and how CI uses floci.
3. A short **DESIGN.md** (1–2 pages) covering:
   - change-detection strategy (paths → affected services)
   - environment promotion model
   - **secrets design** (access pattern, seeding, IAM story, failure modes)
   - floci vs real GCP: what stays the same, what you would change
   - security choices and trade-offs
   - what you would do next with more time
4. Evidence the pipeline works: links to green workflow runs that start floci, seed secrets, deploy differentially, and pass integration tests.

---

## Evaluation criteria

| Area | What “good” looks like |
|------|------------------------|
| Monorepo & DX | Clear structure; shared packages handled correctly |
| Differential CI/CD | Correct rebuild/redeploy graph; no unnecessary deploys |
| floci-gcp usage | Reproducible emulator-based deploy + CI; clear real-GCP mapping |
| Secrets & security | Secret Manager used properly; no secret leakage; decisions justified |
| Delivery quality | Immutable artifacts; staging → prod with intent |
| IaC | Readable Terraform; environments not copy-pasted blindly |
| Integration testing | Automated checks against services deployed on floci |
| Local isolation & reproducibility | Test/build/deploy run via Docker with pinned tooling; no reliance on host-installed software; local and CI share the same entrypoints |
| Communication | README/DESIGN explain decisions and limits |

---

## How to submit

Reply with:

1. Repository URL (+ access if private)
2. Link to the most representative successful workflow run (floci + secrets + differential deploy + integration tests)
3. Your `DESIGN.md`

Optional: a 5–10 minute loom/video walkthrough of differential deploy + secrets behavior.
