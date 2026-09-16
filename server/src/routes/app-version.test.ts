import assert from "node:assert/strict";
import test from "node:test";
import { Hono } from "hono";
import type { AppEnv } from "../app.js";
import type { AppVersionConfig } from "../config.js";
import { registerAppVersionRoute } from "./app-version.js";

const config: AppVersionConfig = {
  minimumSupportedVersion: "0.0.3",
  latestVersion: "0.0.3",
  configuredAt: "2026-09-13T00:00:00Z",
  forceUpgradeEffectiveAt: "2026-09-14T00:00:00Z",
  appStoreURL: "https://apps.apple.com/app/id123456789",
  updateTitle: "需要更新咔咔单词",
  updateMessage: "旧版本存在影响使用的问题，请更新后继续。",
  releaseNotes: {
    "0.0.3": {
      title: "0.0.3 更新说明",
      summary: "本次更新修复了一个重要问题。",
      items: ["修复重大稳定性问题"],
    },
  },
};

test("returns the configured app version policy without caching", async () => {
  const app = new Hono<AppEnv>();
  registerAppVersionRoute(app, config);

  const response = await app.request("/v1/app-version");

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.deepEqual(await response.json(), config);
});
