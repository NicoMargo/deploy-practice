import test from "node:test";
import assert from "node:assert/strict";
import { safeEqual, MissingSecretError } from "./index";

test("safeEqual matches identical strings", () => {
  assert.equal(safeEqual("token-abc", "token-abc"), true);
});

test("safeEqual rejects different strings", () => {
  assert.equal(safeEqual("token-abc", "token-xyz"), false);
});

test("MissingSecretError includes secret id", () => {
  const err = new MissingSecretError("inventory-api-token");
  assert.match(err.message, /inventory-api-token/);
});
