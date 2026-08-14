import { randomUUID } from "node:crypto";
import express from "express";
import { createLogger } from "@aceup/logger";
import { createSecretsClient, safeEqual } from "@aceup/secrets";
import type { NotifyRequest, NotifyResponse } from "@aceup/types";

const log = createLogger("notifications");
const port = Number(process.env.PORT ?? 8082);
const secretId = process.env.NOTIFICATIONS_API_TOKEN_SECRET_ID ?? "notifications-api-token";

const sent: NotifyResponse[] = [];

async function loadApiToken(): Promise<string> {
  const secrets = createSecretsClient();
  return secrets.accessSecret(secretId);
}

async function main(): Promise<void> {
  const apiToken = await loadApiToken();
  const app = express();
  app.use(express.json());

  app.get("/health", (_req, res) => {
    res.json({ status: "ok", service: "notifications" });
  });

  app.get("/notifications", (_req, res) => {
    res.json({ items: sent });
  });

  app.post("/notify", (req, res) => {
    const auth = req.header("x-api-token") ?? "";
    if (!safeEqual(auth, apiToken)) {
      res.status(401).json({ error: "unauthorized" });
      return;
    }

    const body = req.body as NotifyRequest;
    if (!body?.orderId || !body?.customerEmail || !body?.message) {
      res.status(400).json({ error: "invalid_request" });
      return;
    }

    const response: NotifyResponse = {
      ok: true,
      notificationId: `ntf_${randomUUID()}`,
    };
    sent.push(response);
    log.info("notification queued", {
      notificationId: response.notificationId,
      orderId: body.orderId,
    });
    res.status(202).json(response);
  });

  app.listen(port, () => {
    log.info("notifications service listening", { port, secretId });
  });
}

main().catch((err) => {
  log.error("failed to start notifications", { error: String(err) });
  process.exit(1);
});
