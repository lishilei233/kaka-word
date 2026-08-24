import assert from "node:assert/strict";
import test from "node:test";
import { readServerConfig } from "./config.js";
test("reads the production usage-limit defaults", () => {
    const config = readServerConfig({
        VISION_PROVIDER: "mock",
        DATABASE_URL: "postgres://localhost/picture_word",
        RATE_LIMIT_IP_HASH_SECRET: "a-secret-with-at-least-thirty-two-characters",
        TRUST_PROXY: "true",
    });
    assert.equal(config.usageLimits.enabled, true);
    assert.equal(config.usageLimits.perMinute, 10);
    assert.equal(config.usageLimits.dailyLimit, 500);
    assert.equal(config.usageLimits.dailyTimeZone, "Asia/Shanghai");
    assert.equal(config.usageLimits.trustProxy, true);
});
test("allows limits to be explicitly disabled for local mock development", () => {
    const config = readServerConfig({ VISION_PROVIDER: "mock", USAGE_LIMIT_ENABLED: "false" });
    assert.equal(config.usageLimits.enabled, false);
});
test("requires database and HMAC secret when limits are enabled", () => {
    assert.throws(() => readServerConfig({ VISION_PROVIDER: "mock" }), /DATABASE_URL is required/);
    assert.throws(() => readServerConfig({ VISION_PROVIDER: "mock", DATABASE_URL: "postgres://localhost/test" }), /RATE_LIMIT_IP_HASH_SECRET/);
});
