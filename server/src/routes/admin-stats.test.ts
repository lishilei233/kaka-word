import assert from "node:assert/strict";
import { createContext, runInContext } from "node:vm";
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
  startDate: "2026-09-01",
  endDate: "2026-09-30",
  environment: "Production",
  installations: { total: 2, daily: [], freeUsage: [], devices: [] },
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
  assert.match(html, /<section class="section">[\s\S]*?id="devices"/);
  assert.match(html, /快捷范围<select data-date-preset/);
  assert.match(html, /title:'环境'/);
  assert.doesNotMatch(html.match(/<header>[\s\S]*?<\/header>/)?.[0] ?? "", /class="filters"/);
  assert.doesNotMatch(html, /区间新增安装/);
  assert.match(html, /type="date"/);
  assert.match(html, /recognitionSuccesses/);
  assert.match(html, /注册时间（北京时间）/);
  assert.match(html, /option\('all','不限时间'\)/);
  assert.match(html, /font-size:14px; font-weight:850/);
  assert.match(html, /pct\(successes,attempts\)/);
  assert.match(html, /pct\(reselected,confirmations\)/);
  assert.match(html, /总计/);
  assert.doesNotMatch(html, /id="trend"|id="freeUsage"|id="selections"/);
  assert.match(html, /id="funnel"/);
  assert.match(html, /id="corrections"/);

  const response = await app.request(
    "/admin/api/stats?startDate=2026-09-01&endDate=2026-09-22&environment=Sandbox",
    { headers: auth(key) },
  );
  assert.equal(response.status, 200);
  assert.deepEqual(repository.lastQuery, {
    startDate: "2026-09-01", endDate: "2026-09-22", environment: "Sandbox",
  });
  assert.equal(response.headers.get("cache-control"), "no-store");
});

test("admin stats API keeps shortcut day ranges and defaults to the last 30 days", async () => {
  const repository = new FakeRepository();
  const app = appFor(key, repository);
  assert.equal((await app.request("/admin/api/stats", { headers: auth(key) })).status, 200);
  assert.equal(repository.lastQuery?.environment, "Production");
  assert.equal(repository.lastQuery?.startDate, shiftDate(repository.lastQuery!.endDate!, -29));

  assert.equal((await app.request("/admin/api/stats?days=7&environment=Sandbox", { headers: auth(key) })).status, 200);
  assert.equal(repository.lastQuery?.startDate, shiftDate(repository.lastQuery!.endDate!, -6));
  assert.equal(repository.lastQuery?.environment, "Sandbox");

  assert.equal((await app.request("/admin/api/stats?days=1", { headers: auth(key) })).status, 200);
  assert.equal(repository.lastQuery?.startDate, repository.lastQuery?.endDate);
});

test("admin stats API supports all-time and all-environment queries", async () => {
  const repository = new FakeRepository();
  const app = appFor(key, repository);
  assert.equal((await app.request("/admin/api/stats?allTime=true&environment=All", { headers: auth(key) })).status, 200);
  assert.deepEqual(repository.lastQuery, { startDate: null, endDate: null, environment: "All" });
});

test("device header filters combine by column, recalculate totals, and clear cleanly", async () => {
  const app = appFor(key, new FakeRepository());
  const html = await (await app.request("/admin/stats", { headers: auth(key) })).text();
  const script = html.match(/<script>\s*([\s\S]*?)\s*<\/script>/)?.[1];
  assert.ok(script);
  const elements = new Map<string, TestElement>();
  const requestedURLs: string[] = [];
  const element = (id: string) => {
    if (!elements.has(id)) elements.set(id, new TestElement());
    return elements.get(id)!;
  };
  const context = createContext({
    document: { getElementById: element, querySelectorAll: () => [] },
    fetch: async (url: string) => { requestedURLs.push(url); return { ok: true, json: async () => ({ ...snapshot, installations: { ...snapshot.installations, devices: [] } }) }; },
    URLSearchParams,
    Intl,
    Date,
    console,
  });
  runInContext(script, context);
  await new Promise(resolve => setImmediate(resolve));
  assert.match(element("devices").innerHTML, /<table class="device-table">[\s\S]*注册时间（北京时间）[\s\S]*环境/);
  assert.match(element("devices").innerHTML, /所选注册日期范围内没有新增设备/);
  requestedURLs.length = 0;
  const devices = [
    { deviceId: "a1", registrationDate: "2026-09-01 10:00", environment: "Production", membershipType: "free", recognitionAttempts: 10, recognitionSuccesses: 8, confirmationCount: 4, reselectionCount: 1, freeUsed: 2 },
    { deviceId: "b2", registrationDate: "2026-09-15 12:30", environment: "Unknown", membershipType: "monthly", recognitionAttempts: 0, recognitionSuccesses: 0, confirmationCount: 0, reselectionCount: 0, freeUsed: 0 },
    { deviceId: "c3", registrationDate: "2026-09-30 23:59", environment: "Sandbox", membershipType: "annual", recognitionAttempts: 5, recognitionSuccesses: 5, confirmationCount: 2, reselectionCount: 2, freeUsed: 3 },
  ];
  runInContext(`currentDeviceRows=${JSON.stringify(devices)}; renderDeviceTable()`, context);
  const run = (code: string) => runInContext(code, context);
  run("openDeviceFilter='registrationDate'; pendingDateRange={...dateRange}; renderDeviceTable()");
  run("handleDeviceFilterChange({target:{dataset:{datePreset:'7'},value:'7'}})");
  run("handleDeviceFilterChange({target:{dataset:{dateStart:''},value:'2026-09-08'}})");
  run("handleDeviceFilterChange({target:{dataset:{dateEnd:''},value:'2026-09-14'}})");
  context.dateApplyButton = { dataset: { filterAction: "apply", filterKey: "registrationDate" }, closest() { return this; } };
  await run("handleDeviceFilterClick({target:dateApplyButton})");
  assert.match(requestedURLs.at(-1) ?? "", /environment=All&startDate=2026-09-08&endDate=2026-09-14/);
  run(`currentDeviceRows=${JSON.stringify(devices)}; renderDeviceTable()`);
  const root = element("devices") as TestElement;
  run("openDeviceFilter='recognitionAttempts'; renderDeviceTable()");
  root.panel = { querySelectorAll: () => root.fields };
  root.fields = [{ dataset: { filterField: "min" }, value: "6" }, { dataset: { filterField: "max" }, value: "" }];
  context.applyButton = { dataset: { filterAction: "apply", filterKey: "recognitionAttempts" }, closest() { return this; } };
  run("handleDeviceFilterClick({target:applyButton})");
  assert.match(root.innerHTML, /总计（1 台）/);
  run("deviceFilters=Object.fromEntries(deviceFilterColumns.map(column=>[column.key,emptyDeviceFilter(column)]))");

  for (const [keyName, filters, expected] of [
    ["deviceId", { query: "B2" }, [false, true, false]],
    ["environment", { value: "Sandbox" }, [false, false, true]],
    ["membershipType", { value: "annual" }, [false, false, true]],
    ["recognitionAttempts", { min: "6", max: "10" }, [true, false, false]],
    ["recognitionSuccesses", { min: "5", max: "8" }, [true, false, true]],
    ["successRate", { min: "99", max: "100" }, [false, false, true]],
    ["freeQuota", { usedMin: "3", usedMax: "3", remainingMin: "0", remainingMax: "0" }, [false, false, true]],
    ["changeRate", { min: "25", max: "25" }, [true, false, false]],
  ] as const) {
    run(`deviceFilters=Object.fromEntries(deviceFilterColumns.map(column=>[column.key,emptyDeviceFilter(column)])); deviceFilters[${JSON.stringify(keyName)}]=Object.assign(emptyDeviceFilter(deviceFilterColumns.find(column=>column.key===${JSON.stringify(keyName)})),${JSON.stringify(filters)})`);
    assert.deepEqual(JSON.parse(run("JSON.stringify(currentDeviceRows.map(deviceMatchesFilters))")), expected, keyName);
  }

  run("deviceFilters=Object.fromEntries(deviceFilterColumns.map(column=>[column.key,emptyDeviceFilter(column)])); deviceFilters.membershipType.value='free'; renderDeviceTable()");
  const table = element("devices").innerHTML;
  assert.match(table, /总计（1 台）/);
  assert.match(table, /免费会员：1<br>月会员：0<br>年会员：0/);
  assert.match(table, /80\.0%/);
  assert.match(table, /25\.0%/);
  assert.match(table, /当前显示 1 \/ 3 台设备/);

  run("deviceFilters=Object.fromEntries(deviceFilterColumns.map(column=>[column.key,emptyDeviceFilter(column)])); deviceFilters.successRate.min='0'; renderDeviceTable()");
  assert.deepEqual(JSON.parse(run("JSON.stringify(currentDeviceRows.map(deviceMatchesFilters))")), [true, false, true]);
  run("deviceFilters.successRate.min='101'; renderDeviceTable()");
  assert.match(element("devices").innerHTML, /没有设备符合这些筛选条件/);
  const clearButton = { dataset: { filterAction: "clear-all" }, closest() { return this; } };
  context.clearButton = clearButton;
  run("handleDeviceFilterClick({target:clearButton})");
  assert.match(element("devices").innerHTML, /总计（3 台）/);
});

test("admin stats API rejects invalid dates, reversed ranges, mixed range parameters, and environments", async () => {
  const app = appFor(key, new FakeRepository());
  const invalidURLs = [
    "/admin/api/stats?startDate=2026-09-01",
    "/admin/api/stats?startDate=2026-02-30&endDate=2026-03-01",
    "/admin/api/stats?startDate=2026-09-02&endDate=2026-09-01",
    "/admin/api/stats?startDate=2026-09-01&endDate=2026-09-22&days=7",
    "/admin/api/stats?days=14",
    "/admin/api/stats?environment=Staging",
    "/admin/api/stats?allTime=true&days=7",
  ];
  for (const url of invalidURLs) {
    assert.equal((await app.request(url, { headers: auth(key) })).status, 400, url);
  }
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
  lastQuery?: { startDate: string | null; endDate: string | null; environment: AdminStatsEnvironment };

  async load(startDate: string | null, endDate: string | null, environment: AdminStatsEnvironment): Promise<AdminStatsSnapshot> {
    this.lastQuery = { startDate, endDate, environment };
    return { ...snapshot, startDate, endDate, environment };
  }
}

class TestElement {
  innerHTML = "";
  value = "";
  listeners = new Map<string, (event: any) => void>();
  panel: { querySelectorAll: () => Array<{ dataset: { filterField: string }; value: string }> } | null = null;
  fields: Array<{ dataset: { filterField: string }; value: string }> = [];
  classList = { add() {}, remove() {} };
  addEventListener(name: string, listener: (event: any) => void) { this.listeners.set(name, listener); }
  querySelector() { return this.panel; }
  querySelectorAll() { return []; }
}

function shiftDate(value: string, days: number): string {
  const date = new Date(`${value}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}
