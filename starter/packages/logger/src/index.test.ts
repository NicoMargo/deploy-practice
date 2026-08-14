import test from "node:test";
import assert from "node:assert/strict";
import { createLogger } from "./index";

test("createLogger returns leveled methods", () => {
  const log = createLogger("test");
  assert.equal(typeof log.info, "function");
  assert.equal(typeof log.error, "function");
});
