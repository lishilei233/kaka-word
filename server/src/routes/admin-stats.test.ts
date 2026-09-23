import assert from "node:assert/strict";
import test from "node:test";
import { Hono } from "hono";
import type { AppEnv } from "../app.js";
import type { AdminStatsEnvironment, AdminStatsRepository, AdminStatsSnapshot } from "../core/admin-stats.js";
import type { Logger } from "../utils/logger.js";
import { registerAdminStatsRoutes } from "./admin-stats.js";

const key = "admin-dashboard-test-key-with-32-characters";
const logger: Logger = { debug() {}, info() {}, warn() {}, error() {} };
const snapshot: AdminStatsSnapshot = {
  generatedAt: "2026-09-22T00:00:00.000Z",
  days: 30,
  environment: "Production",
  installations: { total: 2, daily: [], freeUsage: [] },
  subscriptions: { states: [], products: [], transactions: [] },
  metrics: [],
  quotaOperations: [],
  feedback: { selections: [], corrections: [] },
};

test("admin stats routes are unavailable without configuration", async () => {
  const app = appFor(undefined, undefined);
  assert.equal((await app.request("/admin/stats")).status, 404);
  assert.equal((await app.request("/admin/api/stats")).headers.get("cache-control"), "no-store");
});

test("admin stats routes challenge missing and incorrect credentials", async () => {
  const app = appFor(key, new FakeRepository());
  const missing = await app.request("/admin/stats");
  assert.equal(missing.status, 401);
  assert.match(missing.headers.get("www-authenticate") ?? "", /Basic/);
  assert.equal((await app.request("/admin/stats", { headers: auth("wrong-password") })).status, 401);
});

test("admin stats page and API accept correct credentials", async () => {
  const repository = new FakeRepository();
  const app = appFor(key, repository);
  const page = await app.request("/admin/stats", { headers: auth(key) });
  assert.equal(page.status, 200);
  const html = await page.text();
  assert.match(html, /数据手账/);
  assert.match(html, /新增安装/);

  const response = await app.request("/admin/api/stats?days=7&environment=Sandbox", { headers: auth(key) });
  assert.equal(response.status, 200);
  assert.deepEqual(repository.lastQuery, { days: 7, environment: "Sandbox" });
  assert.equal(response.headers.get("cache-control"), "no-store");
});

test("admin stats API defaults its query and rejects invalid values", async () => {
  const repository = new FakeRepository();
  const app = appFor(key, repository);
  assert.equal((await app.request("/admin/api/stats", { headers: auth(key) })).status, 200);
  assert.deepEqual(repository.lastQuery, { days: 30, environment: "Production" });
  assert.equal((await app.request("/admin/api/stats?days=1", { headers: auth(key) })).status, 200);
  assert.deepEqual(repository.lastQuery, { days: 1, environment: "Production" });
  assert.equal((await app.request("/admin/api/stats?days=14", { headers: auth(key) })).status, 400);
  assert.equal((await app.request("/admin/api/stats?environment=Staging", { headers: auth(key) })).status, 400);
});

function appFor(adminKey: string | undefined, repository: AdminStatsRepository | undefined) {
  const app = new Hono<AppEnv>();
  app.use("*", async (c, next) => { c.set("requestId", "test-request"); await next(); });
  registerAdminStatsRoutes(app, { key: adminKey, repository, logger });
  return app;
}

function auth(password: string): Record<string, string> {
  return { Authorization: `Basic ${Buffer.from(`admin:${password}`).toString("base64")}` };
}

class FakeRepository implements AdminStatsRepository {
  lastQuery?: { days: number; environment: AdminStatsEnvironment };

  async load(days: number, environment: AdminStatsEnvironment): Promise<AdminStatsSnapshot> {
    this.lastQuery = { days, environment };
    return { ...snapshot, days, environment };
  }
}
