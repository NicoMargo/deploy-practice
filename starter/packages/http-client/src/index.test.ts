import test from "node:test";
import assert from "node:assert/strict";
import { HttpError } from "./index";

test("HttpError carries status", () => {
  const err = new HttpError("nope", 401, "unauthorized");
  assert.equal(err.status, 401);
  assert.equal(err.body, "unauthorized");
});
