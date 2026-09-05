import assert from "node:assert/strict";
import test from "node:test";
import { createApp } from "../app.js";
import type { ServerConfig } from "../config.js";
import { MockVisionProvider } from "../core/image-analysis/providers/mock.js";
import type { AnalyzeUsageLimiter } from "../core/usage-limits/index.js";
import type { Logger } from "../utils/logger.js";

const logger: Logger = { debug() {}, info() {}, warn() {}, error() {} };

test("membership config exposes the configured finite quota", async () => {
  const response = await appFor({ limit: 240, unlimited: false }).request("/v1/membership/config");

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "public, max-age=300, must-revalidate");
  assert.deepEqual(await response.json(), { quota: { limit: 240, unlimited: false } });
});

test("membership config exposes unlimited quota", async () => {
  const response = await appFor({ limit: 240, unlimited: true }).request("/v1/membership/config");
  assert.deepEqual(await response.json(), { quota: { limit: 240, unlimited: true } });
});

test("membership config uses production defaults", async () => {
  const response = await appFor().request("/v1/membership/config");
  assert.deepEqual(await response.json(), { quota: { limit: 100, unlimited: false } });
});

function appFor(quota?: { limit: number; unlimited: boolean }) {
  const config: ServerConfig = {
    port: 0,
    maxUploadBytes: 5 * 1024 * 1024,
    logLevel: "error",
    vision: { name: "mock", model: "mock" },
    usageLimits: {
      enabled: true,
      databaseURL: "postgres://unused",
      ipHashSecret: "test-secret-that-is-at-least-32-characters",
      perMinute: 10,
      dailyLimit: 500,
      dailyTimeZone: "Asia/Shanghai",
      trustProxy: true,
    },
    access: {
      enabled: false,
      databaseURL: "",
      tokenHashSecret: "",
      tokenTTLSeconds: 7_776_000,
      bundleId: "com.kakaword.app",
      appleRootCertificatePaths: [],
      appleOnlineChecks: false,
      monthlyProductId: "com.kakaword.app.membership.month",
      annualProductId: "com.kakaword.app.membership.annual",
      memberQuotaDefault: quota?.limit,
      memberQuotaUnlimited: quota?.unlimited,
      deviceCheck: { keyId: "", teamId: "", privateKey: "", environment: "development" },
    },
  };
  return createApp({
    config,
    provider: new MockVisionProvider(),
    usageLimiter: new NeverCalledLimiter(),
    logger,
  });
}

class NeverCalledLimiter implements AnalyzeUsageLimiter {
  async consumeMinute(): Promise<never> { throw new Error("not used"); }
  async consumeDaily(): Promise<never> { throw new Error("not used"); }
  async close(): Promise<void> {}
}
