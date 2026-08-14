> **Note added by me — the original starter README is unchanged below.**
>
> Two things in it no longer apply:
>
> - It says to export `SECRETMANAGER_EMULATOR_HOST`. `floci gcp env` exports
>   `SECRET_MANAGER_EMULATOR_HOST`, with the underscore. see DESIGN.md in the repo root.
> - The `gcloud secrets create ...` examples are replaced by
>   `scripts/seed-secrets.sh`, which uses the REST API and needs no gcloud.
>
> To run the whole system, use the README in the repo root, not this file.

---

# AceUp DevOps homework — starter services

Tiny TypeScript monorepo starter for the differential-delivery homework.

## Layout

```
packages/
  types/          shared request/response types
  logger/         JSON stdout logger
  http-client/    tiny fetch JSON helper
  secrets/        Google Secret Manager accessor (floci-compatible)
services/
  inventory/      stock + reserve API (requires inventory-api-token)
  orders/         creates orders; calls inventory + notifications
  notifications/  accepts notify calls (requires notifications-api-token)
```

## Prerequisites

- Node.js 20+
- npm 10+
- [floci-gcp](https://floci.io/gcp/) running if you want services to boot for real

## Install & build

```bash
npm install
npm run build
npm test
```

## Secrets the apps expect

Services **refuse to start** without Secret Manager values:

| Secret ID | Used by |
|-----------|---------|
| `inventory-api-token` | `inventory` (auth for `/reserve`); `orders` (caller token) |
| `notifications-api-token` | `notifications` (auth for `/notify`); `orders` (caller token) |

Default project id: `floci-local` (`GCP_PROJECT_ID`).

With floci running:

```bash
floci gcp start
eval $(floci gcp env)

# Example seeding (exact approach is part of the homework):
# gcloud secrets create inventory-api-token --replication-policy=automatic
# echo -n 'dev-inventory-token' | gcloud secrets versions add inventory-api-token --data-file=-
# gcloud secrets create notifications-api-token --replication-policy=automatic
# echo -n 'dev-notifications-token' | gcloud secrets versions add notifications-api-token --data-file=-
```

Set emulator host if not using `floci gcp env`:

```bash
export SECRETMANAGER_EMULATOR_HOST=localhost:4588
export GCP_PROJECT_ID=floci-local
```

## Run locally (after secrets exist)

```bash
# terminal 1
npm run dev -w @aceup/inventory-service

# terminal 2
npm run dev -w @aceup/notifications-service

# terminal 3
INVENTORY_BASE_URL=http://127.0.0.1:8081 \
NOTIFICATIONS_BASE_URL=http://127.0.0.1:8082 \
npm run dev -w @aceup/orders-service
```

Happy path:

```bash
curl -s http://127.0.0.1:8080/orders \
  -H 'content-type: application/json' \
  -d '{"sku":"SKU-TEE","quantity":1,"customerEmail":"candidate@example.com"}'
```

## Notes for candidates

- No Dockerfiles, CI, Terraform, or deploy wiring are included on purpose.
- How you wire Secret Manager into Cloud Run on floci (and what you would do on real GCP) is a scored design decision — see the assignment.
