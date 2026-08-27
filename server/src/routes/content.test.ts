import assert from "node:assert/strict";
import test from "node:test";
import { createApp } from "../app.js";
import type { ServerConfig } from "../config.js";
import { MockVisionProvider } from "../core/image-analysis/providers/mock.js";
import type { AnalyzeUsageLimiter } from "../core/usage-limits/index.js";
import type { Logger } from "../utils/logger.js";

const logger: Logger = { debug() {}, info() {}, warn() {}, error() {} };
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
    deviceCheck: { keyId: "", teamId: "", privateKey: "", environment: "development" },
  },
};

test("returns each supported content document without consuming usage limits", async () => {
  const limiter = new NeverCalledLimiter();
  const app = createApp({
    config,
    provider: new MockVisionProvider(),
    usageLimiter: limiter,
    logger,
  });

  for (const key of ["privacy", "terms", "about"]) {
    const response = await app.request(`/v1/content/${key}`);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("cache-control"), "public, max-age=300, must-revalidate");
    const body = await response.json();
    assert.equal(body.key, key);
    assert.equal(body.locale, "zh-CN");
    assert.equal(typeof body.title, "string");
    assert.equal(typeof body.code, "string");
    assert.equal(typeof body.version, "string");
    assert.equal(typeof body.updatedAt, "string");
    assert.equal(typeof body.summary, "string");
    assert.ok(Array.isArray(body.sections));
    for (const section of body.sections) {
      assert.equal(typeof section.heading, "string");
      assert.ok(Array.isArray(section.paragraphs));
      assert.ok(Array.isArray(section.bullets));
    }
  }

  assert.equal(limiter.calls, 0);
});

test("returns a stable error for an unknown content key", async () => {
  const app = createApp({
    config,
    provider: new MockVisionProvider(),
    usageLimiter: new NeverCalledLimiter(),
    logger,
  });
  const response = await app.request("/v1/content/unknown");

  assert.equal(response.status, 404);
  assert.deepEqual(await response.json(), {
    error: "CONTENT_NOT_FOUND",
    message: "内容不存在",
  });
});

class NeverCalledLimiter implements AnalyzeUsageLimiter {
  calls = 0;

  async consumeMinute(): Promise<never> {
    this.calls += 1;
    throw new Error("content route must not consume usage limits");
  }

  async consumeDaily(): Promise<never> {
    this.calls += 1;
    throw new Error("content route must not consume usage limits");
  }

  async close(): Promise<void> {}
}
