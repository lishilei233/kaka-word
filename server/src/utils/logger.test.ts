import assert from "node:assert/strict";
import test from "node:test";
import { errorFields } from "./logger.js";

test("errorFields includes Node fetch cause details", () => {
  const cause = Object.assign(new Error("connect timed out"), {
    code: "UND_ERR_CONNECT_TIMEOUT",
    errno: -60,
    syscall: "connect",
    address: "203.0.113.1",
    port: 443,
  });
  const error = new TypeError("fetch failed", { cause });

  assert.deepEqual(errorFields(error), {
    errorType: "TypeError",
    errorMessage: "fetch failed",
    causeType: "Error",
    causeMessage: "connect timed out",
    causeCode: "UND_ERR_CONNECT_TIMEOUT",
    causeErrno: -60,
    causeSyscall: "connect",
    causeAddress: "203.0.113.1",
    causePort: 443,
  });
});

test("errorFields redacts secrets from the cause and includes its stack only in debug mode", () => {
  const cause = new Error("Bearer token-value sk-secret-value");
  const error = new TypeError("fetch failed", { cause });
  const fields = errorFields(error, true);

  assert.equal(fields.causeMessage, "Bearer [REDACTED] sk-[REDACTED]");
  assert.equal(typeof fields.causeStack, "string");
  assert.doesNotMatch(String(fields.causeStack), /token-value|secret-value/);
});
