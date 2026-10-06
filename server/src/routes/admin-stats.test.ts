import { summarizeActivity } from '../core/activity-stats.js';
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
  activity: summarizeActivity([], '2026-09-01', '2026-09-30', 'Production', null),
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
  assert.match(html, /pct\(s.recognitionSuccesses,s.recognitionAttempts\)/);
  assert.match(html, /pct\(s.reselectionCount,s.confirmationCount\)/);
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
  assert.match(element("devices").innerHTML, /所选时间范围内没有活跃或新增设备/);
  requestedURLs.length = 0;
  const devices = [
    { installationId: "11111111-1111-4111-8111-111111111111", deviceId: "a1", registrationDate: "2026-09-01 10:00", environment: "Production", membershipType: "free", recognitionAttempts: 10, recognitionSuccesses: 8, confirmationCount: 4, reselectionCount: 1, freeUsed: 2 },
    { installationId: "22222222-2222-4222-8222-222222222222", deviceId: "b2", registrationDate: "2026-09-15 12:30", environment: "Unknown", membershipType: "monthly", recognitionAttempts: 0, recognitionSuccesses: 0, confirmationCount: 0, reselectionCount: 0, freeUsed: 0 },
    { installationId: "33333333-3333-4333-8333-333333333333", deviceId: "c3", registrationDate: "2026-09-30 23:59", environment: "Sandbox", membershipType: "annual", recognitionAttempts: 5, recognitionSuccesses: 5, confirmationCount: 2, reselectionCount: 2, freeUsed: 3 },
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
  for (const [keyName, filters, expected] of [
    ["deviceId", { query: "B2" }, [false, true, false]],
    ["environment", { value: "Sandbox" }, [false, false, true]],
    ["membershipType", { value: "annual" }, [false, false, true]],
  ] as const) {
    run(`deviceFilters=Object.fromEntries(deviceFilterColumns.map(column=>[column.key,emptyDeviceFilter(column)])); deviceFilters[${JSON.stringify(keyName)}]=Object.assign(emptyDeviceFilter(deviceFilterColumns.find(column=>column.key===${JSON.stringify(keyName)})),${JSON.stringify(filters)})`);
    assert.deepEqual(JSON.parse(run("JSON.stringify(currentDeviceRows.map(deviceMatchesFilters))")), expected, keyName);
  }

  run("deviceFilters=Object.fromEntries(deviceFilterColumns.map(column=>[column.key,emptyDeviceFilter(column)])); deviceFilters.membershipType.value='free'; renderDeviceTable()");
  const table = element("devices").innerHTML;
  assert.match(table, /总计（1 台）/);
  assert.match(table, /免费会员：1<br>月会员：0<br>年会员：0/);
  assert.match(table, /查看详情/);
  assert.doesNotMatch(table, /识别尝试|成功识别|免费额度|用户改选率/);
  assert.match(table, /当前显示 1 \/ 3 台设备/);

  run("deviceFilters=Object.fromEntries(deviceFilterColumns.map(column=>[column.key,emptyDeviceFilter(column)])); deviceFilters.deviceId.query='missing'; renderDeviceTable()");
  assert.match(element("devices").innerHTML, /没有设备符合这些筛选条件/);
  assert.match(element("devices").innerHTML, /总计（0 台）/);
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
  activityData: import('../core/activity-stats.js').DeviceActivity | null = null;
  lastActivityQuery?: import('../core/activity-stats.js').DeviceActivityQuery;
  async loadDeviceActivity(query: import('../core/activity-stats.js').DeviceActivityQuery) { this.lastActivityQuery = query; return this.activityData; }
  detailData: import('../core/admin-device-details.js').DeviceDetails | null = null;
  lastDetailQuery?: import('../core/admin-device-details.js').DeviceDetailQuery;
  async loadDeviceDetails(query: import('../core/admin-device-details.js').DeviceDetailQuery): Promise<import('../core/admin-device-details.js').DeviceDetails | null> { this.lastDetailQuery = query; return this.detailData; }
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
  hidden = false;
  disabled = false;
  textContent = "";
  open = false;
  setAttribute() {}
  showModal() { this.open = true; }
  close() { this.open = false; this.listeners.get("close")?.({}); }
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

const detailDeviceId = '11111111-1111-4111-8111-111111111111';
function detailFixture(): import('../core/admin-device-details.js').DeviceDetails {
  return {
    device: { installationId: detailDeviceId, deviceId: '111111', registrationDate: '2026-10-01 12:00', environment: 'Sandbox', membershipType: 'free', freeUsed: 1, recognitionAttempts: 3, recognitionSuccesses: 1, confirmationCount: 4, reselectionCount: 1 },
    summary: { recognitionAttempts: 3, recognitionSuccesses: 1, confirmationCount: 4, reselectionCount: 1 },
    startDate: '2026-09-01', endDate: '2026-10-01', recordingStartedAt: '2026-10-01T04:00:00.000Z',
    attempts: [{ operationId: detailDeviceId, requestId: 'request<escaped>', startedAt: '2026-10-01T05:00:00.000Z', finishedAt: '2026-10-01T05:00:02.000Z', environment: 'Sandbox', outcome: 'success', reasonCode: null, stage: 'serialize_response', durationMs: 2000, appVersion: '1.2.0', appBuild: '35', quotaBefore: { tier: 'free', limit: 3, used: 0, reserved: 0, remaining: 3, periodStart: null, resetAt: null }, quotaAfter: { tier: 'free', limit: 3, used: 1, reserved: 0, remaining: 2, periodStart: null, resetAt: null }, quotaState: 'committed' }], nextCursor: null,
  };
}

test('device detail API enforces admin authentication, date retention, filters, cursors and missing devices', async () => {
  const repo = new FakeRepository();
  const app = appFor(key, repo), endpoint = '/admin/api/stats/devices/' + detailDeviceId;
  assert.equal((await app.request(endpoint)).status, 401);
  assert.equal((await app.request(endpoint, { headers: auth(key) })).status, 404);
  assert.ok(repo.lastDetailQuery);
  assert.equal(repo.lastDetailQuery.startDate, shiftDate(repo.lastDetailQuery.endDate, -89));
  repo.detailData = detailFixture();
  const cursor = Buffer.from(JSON.stringify({ startedAt: '2026-10-01T05:00:00.000Z', operationId: detailDeviceId })).toString('base64url');
  assert.equal((await app.request(endpoint + '?outcome=success&appVersion=1.2.0&cursor=' + cursor, { headers: auth(key) })).status, 200);
  assert.equal(repo.lastDetailQuery.outcome, 'success');
  assert.equal(repo.lastDetailQuery.appVersion, '1.2.0');
  assert.equal(repo.lastDetailQuery.cursor?.operationId, detailDeviceId);
  for (const suffix of ['?startDate=2000-01-01', '?startDate=2026-02-30', '?endDate=2999-01-01', '?outcome=wrong', '?cursor=invalid', '?appVersion=' + 'x'.repeat(65)]) {
    assert.equal((await app.request(endpoint + suffix, { headers: auth(key) })).status, 400, suffix);
  }
  assert.equal((await app.request('/admin/api/stats/devices/111111', { headers: auth(key) })).status, 400);
});

test('device drawer shows weighted summaries, quota snapshots, version and preserves headers on errors', async () => {
  const html = await (await appFor(key, new FakeRepository()).request('/admin/stats', { headers: auth(key) })).text();
  const script = html.match(/<script>\s*([\s\S]*?)\s*<\/script>/)![1];
  const elements = new Map<string, TestElement>();
  const element = (id: string) => { if (!elements.has(id)) elements.set(id, new TestElement()); return elements.get(id)!; };
  const urls: string[] = [];
  const context = createContext({ document: { getElementById: element, querySelectorAll: () => [] }, URLSearchParams, Intl, Date, console,
    fetch: async (url: string) => { urls.push(url); return { ok: true, json: async () => url.includes('/devices/') ? detailFixture() : snapshot }; } });
  runInContext(script, context); await new Promise(resolve => setImmediate(resolve));
  await runInContext('openDeviceDetails("' + detailDeviceId + '")', context);
  assert.equal(element('deviceDetails').open, true);
  assert.match(urls.at(-1)!, new RegExp('/devices/' + detailDeviceId));
  assert.equal(element('detailPreset').value, '90');
  assert.match(element('detailSummary').innerHTML, /33\.3%/);
  assert.match(element('detailSummary').innerHTML, /25\.0%/);
  assert.match(element('detailAttempts').innerHTML, /是 · 已扣除/);
  assert.match(element('detailAttempts').innerHTML, /剩余 3[\s\S]*剩余 2/);
  assert.match(element('detailAttempts').innerHTML, /1\.2\.0/);
  assert.match(element('detailAttempts').innerHTML, /request&lt;escaped&gt;/);
  context.fetch = async () => ({ ok: false, status: 503 });
  await runInContext('loadDeviceDetailsPage()', context);
  assert.match(element('detailStatus').textContent, /HTTP 503/);
  assert.match(element('detailAttempts').innerHTML, /<thead>/);
  assert.equal(element('detailRetry').hidden, false);
  element('deviceDetails').close();
  assert.equal(runInContext('detailDeviceId', context), null);
});


test('device activity API validates identity, dates, environment and independent pagination', async () => {
  const repository = new FakeRepository(), app = appFor(key, repository);
  const endpoint = '/admin/api/stats/devices/' + detailDeviceId + '/activity';
  assert.equal((await app.request(endpoint)).status, 401);
  assert.equal((await app.request(endpoint, { headers: auth(key) })).status, 404);
  assert.equal(repository.lastActivityQuery?.environment, 'All');
  repository.activityData = { summary: { installationId: detailDeviceId, clientActivityCovered: true,
    activeDays: 1, learningDays: 1, lastActiveAt: '2026-10-01T00:00:00Z', opens: 1, recognitionAttempts: 0,
    recognitionSuccesses: 0, listeningEnters: 1, listeningStarts: 1, listeningAnswers: 3, listeningFound: 2,
    listeningRevealed: 1, listeningCompletions: 1, historyViews: 0, wordPlays: 0 }, recordingStartedAt: null,
    daily: [], events: [], nextCursor: null };
  const cursor = Buffer.from(JSON.stringify({ occurredAt: '2026-10-01T00:00:00Z', eventId: detailDeviceId })).toString('base64url');
  assert.equal((await app.request(endpoint + '?startDate=2026-10-01&endDate=2026-10-01&environment=Unknown&cursor=' + cursor, { headers: auth(key) })).status, 200);
  assert.equal(repository.lastActivityQuery?.environment, 'Unknown');
  assert.equal(repository.lastActivityQuery?.cursor?.eventId, detailDeviceId);
  for (const suffix of ['?startDate=2026-02-30', '?startDate=2026-10-02&endDate=2026-10-01', '?environment=Other', '?cursor=invalid', '?endDate=2999-01-01']) {
    assert.equal((await app.request(endpoint + suffix, { headers: auth(key) })).status, 400);
  }
  // Old daily summaries remain queryable even after detail retention expires.
  assert.equal((await app.request(endpoint + '?startDate=2020-01-01&endDate=2020-01-02', { headers: auth(key) })).status, 200);
});

test('activity dashboard distinguishes historical coverage and calculates weighted recognition success', async () => {
  const app = appFor(key, new FakeRepository());
  const html = await (await app.request('/admin/stats', { headers: auth(key) })).text();
  const script = html.match(/<script>\s*([\s\S]*?)\s*<\/script>/)?.[1];
  assert.ok(script);
  const elements = new Map<string, TestElement>();
  const element = (id: string) => { if (!elements.has(id)) elements.set(id, new TestElement()); return elements.get(id)!; };
  const context = createContext({ document: { getElementById: element, querySelectorAll: () => [] },
    Intl, Date, URLSearchParams, fetch: async () => ({ ok: true, json: async () => snapshot }) });
  runInContext(script, context);
  const activity = summarizeActivity([
    { installationId: detailDeviceId, date: '2026-10-01', eventName: 'recognition_attempt', environment: 'Production', outcome: '', count: 4, firstAt: '2026-10-01T00:00:00Z', lastAt: '2026-10-01T00:00:00Z' },
    { installationId: detailDeviceId, date: '2026-10-01', eventName: 'recognition_success', environment: 'Production', outcome: '', count: 3, firstAt: '2026-10-01T00:00:00Z', lastAt: '2026-10-01T00:00:00Z' },
  ], '2026-09-30', '2026-10-01', 'Production', '2026-10-01T00:00:00Z');
  context.activity = activity;
  runInContext('renderActivity(activity)', context);
  assert.match(element('activityCards').innerHTML, /75.0%/);
  assert.match(element('activityDaily').innerHTML, /未覆盖/);
  assert.match(element('activityBehaviors').innerHTML, /识别尝试/);
  context.deviceActivity = activity.devices[0];
  assert.match(runInContext('activityDeviceCells(deviceActivity)', context), /仅识别日期/);
});
