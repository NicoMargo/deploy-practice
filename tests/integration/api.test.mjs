import test from "node:test";
import assert from "node:assert/strict";

const ORDERS_URL = process.env.ORDERS_URL;
const INVENTORY_URL = process.env.INVENTORY_URL;
const NOTIFICATIONS_URL = process.env.NOTIFICATIONS_URL;

for (const [name, value] of Object.entries({ ORDERS_URL, INVENTORY_URL, NOTIFICATIONS_URL })) {
  if (!value) {
    throw new Error(`${name} is not set — run scripts/deploy.sh first`);
  }
}

async function getJson(url) {
  const res = await fetch(url);
  assert.equal(res.status, 200, `GET ${url} returned ${res.status}`);
  return res.json();
}

async function postJson(url, body, headers = {}) {
  return fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

test("every deployed service reports healthy", async () => {
  for (const [service, url] of Object.entries({
    orders: ORDERS_URL,
    inventory: INVENTORY_URL,
    notifications: NOTIFICATIONS_URL,
  })) {
    const body = await getJson(`${url}/health`);
    assert.deepEqual(body, { status: "ok", service });
  }
});

test("creating an order reserves stock and queues a notification", async () => {
  const sku = "SKU-TEE";
  const quantity = 2;

  const stockBefore = await getJson(`${INVENTORY_URL}/stock/${sku}`);
  const notificationsBefore = await getJson(`${NOTIFICATIONS_URL}/notifications`);

  const res = await postJson(`${ORDERS_URL}/orders`, {
    sku,
    quantity,
    customerEmail: "integration@example.com",
  });

  assert.equal(res.status, 201);
  const order = await res.json();
  assert.equal(order.status, "accepted");
  assert.match(order.id, /^ord_/);

  // The order is only meaningful if it actually moved state in the other two
  // services — asserting a 201 alone would pass even if they were mocked away.
  const stockAfter = await getJson(`${INVENTORY_URL}/stock/${sku}`);
  assert.equal(stockAfter.quantity, stockBefore.quantity - quantity);

  const notificationsAfter = await getJson(`${NOTIFICATIONS_URL}/notifications`);
  assert.equal(notificationsAfter.items.length, notificationsBefore.items.length + 1);
});

test("an order larger than available stock is rejected without side effects", async () => {
  const sku = "SKU-HAT";
  const stockBefore = await getJson(`${INVENTORY_URL}/stock/${sku}`);

  const res = await postJson(`${ORDERS_URL}/orders`, {
    sku,
    quantity: stockBefore.quantity + 1,
    customerEmail: "integration@example.com",
  });

  // inventory signals insufficient stock with HTTP 409, and the shared
  // http-client throws on any non-2xx before the body is inspected. That makes
  // orders' `if (!reservation.ok)` branch unreachable, so the rejection
  // surfaces through its generic upstream-failure handler instead of as a
  // status:"rejected" order. Asserting the real behaviour rather than the
  // intended one keeps this test honest; the discrepancy is documented in
  // DESIGN.md as a starter-code finding.
  assert.equal(res.status, 409);
  const body = await res.json();
  assert.equal(body.error, "upstream_failure");

  // The important guarantee still holds: a rejected order consumes no stock.
  const stockAfter = await getJson(`${INVENTORY_URL}/stock/${sku}`);
  assert.equal(stockAfter.quantity, stockBefore.quantity);
});

test("inventory rejects a reservation carrying an invalid API token", async () => {
  const res = await postJson(
    `${INVENTORY_URL}/reserve`,
    { sku: "SKU-TEE", quantity: 1, orderId: "integration-probe" },
    { "x-api-token": "not-the-real-token" },
  );
  assert.equal(res.status, 401);
});

test("notifications rejects a notify carrying an invalid API token", async () => {
  const res = await postJson(
    `${NOTIFICATIONS_URL}/notify`,
    { orderId: "integration-probe", customerEmail: "x@example.com", message: "probe" },
    { "x-api-token": "not-the-real-token" },
  );
  assert.equal(res.status, 401);
});
