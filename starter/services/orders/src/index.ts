import { randomUUID } from "node:crypto";
import express from "express";
import { fetchJson, HttpError } from "@aceup/http-client";
import { createLogger } from "@aceup/logger";
import { createSecretsClient } from "@aceup/secrets";
import type { CreateOrderRequest, Order, ReserveResponse } from "@aceup/types";

const log = createLogger("orders");
const port = Number(process.env.PORT ?? 8080);
const inventoryBaseUrl = process.env.INVENTORY_BASE_URL ?? "http://127.0.0.1:8081";
const notificationsBaseUrl = process.env.NOTIFICATIONS_BASE_URL ?? "http://127.0.0.1:8082";
const inventoryTokenSecretId =
  process.env.INVENTORY_API_TOKEN_SECRET_ID ?? "inventory-api-token";
const notificationsTokenSecretId =
  process.env.NOTIFICATIONS_API_TOKEN_SECRET_ID ?? "notifications-api-token";

const orders = new Map<string, Order>();

async function loadTokens(): Promise<{ inventoryToken: string; notificationsToken: string }> {
  const secrets = createSecretsClient();
  const [inventoryToken, notificationsToken] = await Promise.all([
    secrets.accessSecret(inventoryTokenSecretId),
    secrets.accessSecret(notificationsTokenSecretId),
  ]);
  return { inventoryToken, notificationsToken };
}

async function main(): Promise<void> {
  const { inventoryToken, notificationsToken } = await loadTokens();
  const app = express();
  app.use(express.json());

  app.get("/health", (_req, res) => {
    res.json({ status: "ok", service: "orders" });
  });

  app.get("/orders/:id", (req, res) => {
    const order = orders.get(req.params.id);
    if (!order) {
      res.status(404).json({ error: "not_found" });
      return;
    }
    res.json(order);
  });

  app.post("/orders", async (req, res) => {
    const body = req.body as CreateOrderRequest;
    if (!body?.sku || !body?.quantity || !body?.customerEmail) {
      res.status(400).json({ error: "invalid_request" });
      return;
    }

    const orderId = `ord_${randomUUID()}`;

    try {
      const reservation = await fetchJson<ReserveResponse>(`${inventoryBaseUrl}/reserve`, {
        method: "POST",
        headers: { "x-api-token": inventoryToken },
        body: { sku: body.sku, quantity: body.quantity, orderId },
      });

      if (!reservation.ok) {
        const rejected: Order = {
          id: orderId,
          sku: body.sku,
          quantity: body.quantity,
          customerEmail: body.customerEmail,
          status: "rejected",
        };
        orders.set(orderId, rejected);
        res.status(409).json(rejected);
        return;
      }

      const accepted: Order = {
        id: orderId,
        sku: body.sku,
        quantity: body.quantity,
        customerEmail: body.customerEmail,
        status: "accepted",
      };
      orders.set(orderId, accepted);

      await fetchJson(`${notificationsBaseUrl}/notify`, {
        method: "POST",
        headers: { "x-api-token": notificationsToken },
        body: {
          orderId,
          customerEmail: body.customerEmail,
          message: `Order ${orderId} accepted for ${body.sku}`,
        },
      });

      log.info("order accepted", { orderId, sku: body.sku });
      res.status(201).json(accepted);
    } catch (err) {
      const status = err instanceof HttpError ? err.status : 502;
      log.error("order failed", { orderId, error: String(err) });
      res.status(status).json({ error: "upstream_failure", orderId });
    }
  });

  app.listen(port, () => {
    log.info("orders listening", {
      port,
      inventoryBaseUrl,
      notificationsBaseUrl,
    });
  });
}

main().catch((err) => {
  log.error("failed to start orders", { error: String(err) });
  process.exit(1);
});
