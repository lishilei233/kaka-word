import assert from "node:assert/strict";
import test from "node:test";
import { readServerConfig } from "./config.js";

test("reads the production usage-limit defaults", () => {
  const config = readServerConfig({
    VISION_PROVIDER: "mock",
    DATABASE_URL: "postgres://localhost/picture_word",
    RATE_LIMIT_IP_HASH_SECRET: "a-secret-with-at-least-thirty-two-characters",
    TRUST_PROXY: "true",
    ACCESS_CONTROL_ENABLED: "false",
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

test("keeps access control disabled by default for the mock provider", () => {
  const config = readServerConfig({ VISION_PROVIDER: "mock", USAGE_LIMIT_ENABLED: "false" });
  assert.equal(config.access.enabled, false);
});

test("reads a strong dedicated video-studio credential", () => {
  const token = "video-studio-test-token-with-at-least-32-characters";
  const config = readServerConfig({
    VISION_PROVIDER: "mock", USAGE_LIMIT_ENABLED: "false", VIDEO_STUDIO_ACCESS_TOKEN: token,
  });
  assert.equal(config.videoStudioAccessToken, token);
  assert.throws(() => readServerConfig({
    VISION_PROVIDER: "mock", USAGE_LIMIT_ENABLED: "false", VIDEO_STUDIO_ACCESS_TOKEN: "too-short",
  }), /VIDEO_STUDIO_ACCESS_TOKEN/);
});

test("reads and validates the admin dashboard credential", () => {
  const key = "admin-dashboard-test-key-with-32-characters";
  const config = readServerConfig({
    VISION_PROVIDER: "mock", USAGE_LIMIT_ENABLED: "false", ADMIN_DASHBOARD_KEY: key,
  });
  assert.equal(config.adminDashboard?.key, key);
  assert.throws(() => readServerConfig({
    VISION_PROVIDER: "mock", USAGE_LIMIT_ENABLED: "false", ADMIN_DASHBOARD_KEY: "too-short",
  }), /ADMIN_DASHBOARD_KEY/);
});

test("reads a configurable non-negative member quota default", () => {
  const config = readServerConfig({
    VISION_PROVIDER: "mock",
    USAGE_LIMIT_ENABLED: "false",
    ACCESS_CONTROL_ENABLED: "false",
    MEMBER_QUOTA_DEFAULT: "0",
  });
  assert.equal(config.access.memberQuotaDefault, 0);
  assert.throws(() => readServerConfig({
    VISION_PROVIDER: "mock",
    USAGE_LIMIT_ENABLED: "false",
    ACCESS_CONTROL_ENABLED: "false",
    MEMBER_QUOTA_DEFAULT: "-1",
  }), /MEMBER_QUOTA_DEFAULT/);
});

test("allows unlimited member quota to be enabled with one environment variable", () => {
  const config = readServerConfig({
    VISION_PROVIDER: "mock",
    USAGE_LIMIT_ENABLED: "false",
    ACCESS_CONTROL_ENABLED: "false",
    MEMBER_QUOTA_UNLIMITED: "true",
  });
  assert.equal(config.access.memberQuotaUnlimited, true);
  assert.throws(() => readServerConfig({
    VISION_PROVIDER: "mock",
    USAGE_LIMIT_ENABLED: "false",
    ACCESS_CONTROL_ENABLED: "false",
    MEMBER_QUOTA_UNLIMITED: "yes",
  }), /MEMBER_QUOTA_UNLIMITED/);
});

test("requires Apple and DeviceCheck secrets when access control is enabled", () => {
  assert.throws(
    () => readServerConfig({
      VISION_PROVIDER: "mock",
      USAGE_LIMIT_ENABLED: "false",
      ACCESS_CONTROL_ENABLED: "true",
    }),
    /DATABASE_URL is required when access control is enabled/,
  );
});

test("requires database and HMAC secret when limits are enabled", () => {
  assert.throws(
    () => readServerConfig({ VISION_PROVIDER: "mock" }),
    /DATABASE_URL is required/,
  );
  assert.throws(
    () => readServerConfig({ VISION_PROVIDER: "mock", DATABASE_URL: "postgres://localhost/test" }),
    /RATE_LIMIT_IP_HASH_SECRET/,
  );
});

test("reads and validates app version rollout configuration", () => {
  const config = readServerConfig({
    VISION_PROVIDER: "mock",
    USAGE_LIMIT_ENABLED: "false",
    APP_STORE_URL: "https://apps.apple.com/app/id123456789",
    APP_MINIMUM_SUPPORTED_VERSION: "0.0.2",
    APP_LATEST_VERSION: "0.0.3",
    APP_VERSION_CONFIGURED_AT: "2026-09-13T00:00:00Z",
    APP_FORCE_UPGRADE_EFFECTIVE_AT: "2026-09-14T00:00:00Z",
    APP_RELEASE_NOTES_JSON: JSON.stringify({
      "0.0.3": { title: "更新说明", summary: "更稳定了", items: ["修复问题"] },
    }),
  });

  assert.equal(config.appVersion?.minimumSupportedVersion, "0.0.2");
  assert.equal(config.appVersion?.latestVersion, "0.0.3");
  assert.equal(config.appVersion?.releaseNotes["0.0.3"]?.items[0], "修复问题");

  assert.throws(() => readServerConfig({
    VISION_PROVIDER: "mock",
    USAGE_LIMIT_ENABLED: "false",
    APP_MINIMUM_SUPPORTED_VERSION: "0.0.4",
    APP_LATEST_VERSION: "0.0.3",
  }), /must not exceed/);
  assert.throws(() => readServerConfig({
    VISION_PROVIDER: "mock",
    USAGE_LIMIT_ENABLED: "false",
    APP_VERSION_CONFIGURED_AT: "2026-09-14T00:00:00Z",
    APP_FORCE_UPGRADE_EFFECTIVE_AT: "2026-09-13T00:00:00Z",
  }), /requires an earlier/);
});
