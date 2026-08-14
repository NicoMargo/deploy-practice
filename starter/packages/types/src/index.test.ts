import test from "node:test";
import assert from "node:assert/strict";
import type { Order } from "./index";

test("Order status union accepts accepted", () => {
  const order: Order = {
    id: "ord_1",
    sku: "SKU-1",
    quantity: 1,
    customerEmail: "a@b.com",
    status: "accepted",
  };
  assert.equal(order.status, "accepted");
});
