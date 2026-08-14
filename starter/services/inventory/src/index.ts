import express from "express";
import { createLogger } from "@aceup/logger";
import { createSecretsClient, safeEqual } from "@aceup/secrets";
import type { ReserveRequest, ReserveResponse, StockItem } from "@aceup/types";

const log = createLogger("inventory");
const port = Number(process.env.PORT ?? 8081);
const secretId = process.env.INVENTORY_API_TOKEN_SECRET_ID ?? "inventory-api-token";

const stock = new Map<string, number>([
  ["SKU-TEE", 100],
  ["SKU-MUG", 50],
  ["SKU-HAT", 25],
]);

async function loadApiToken(): Promise<string> {
  const secrets = createSecretsClient();
  return secrets.accessSecret(secretId);
}

function unauthorized(res: express.Response): void {
  res.status(401).json({ error: "unauthorized" });
}

async function main(): Promise<void> {
  const apiToken = await loadApiToken();
  const app = express();
  app.use(express.json());

  app.get("/health", (_req, res) => {
    res.json({ status: "ok", service: "inventory" });
  });

  app.get("/stock/:sku", (req, res) => {
    const sku = req.params.sku;
    const quantity = stock.get(sku);
    if (quantity === undefined) {
      res.status(404).json({ error: "sku_not_found" });
      return;
    }
    const item: StockItem = { sku, quantity };
    res.json(item);
  });

  app.post("/reserve", (req, res) => {
    const auth = req.header("x-api-token") ?? "";
    if (!safeEqual(auth, apiToken)) {
      unauthorized(res);
      return;
    }

    const body = req.body as ReserveRequest;
    if (!body?.sku || !body?.quantity || !body?.orderId) {
      res.status(400).json({ error: "invalid_request" });
      return;
    }

    const available = stock.get(body.sku) ?? 0;
    if (available < body.quantity) {
      const response: ReserveResponse = {
        ok: false,
        sku: body.sku,
        reserved: 0,
        remaining: available,
      };
      res.status(409).json(response);
      return;
    }

    const remaining = available - body.quantity;
    stock.set(body.sku, remaining);
    log.info("reserved stock", { orderId: body.orderId, sku: body.sku, quantity: body.quantity });

    const response: ReserveResponse = {
      ok: true,
      sku: body.sku,
      reserved: body.quantity,
      remaining,
    };
    res.status(201).json(response);
  });

  app.listen(port, () => {
    log.info("inventory listening", { port, secretId });
  });
}

main().catch((err) => {
  log.error("failed to start inventory", { error: String(err) });
  process.exit(1);
});
