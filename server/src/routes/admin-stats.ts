import type { DeviceActivityQuery } from '../core/activity-stats.js';
import { activityMarkup, activityScript, activityDetailScript } from './admin-activity-ui.js';
import { deviceDetailsStyles, deviceDetailsMarkup, deviceDetailsScript } from "./admin-device-details-ui.js";
import { recognitionOutcomes, type RecognitionOutcome } from "../core/access/types.js";
import type { DeviceDetailQuery } from "../core/admin-device-details.js";
import { createHash, timingSafeEqual } from "node:crypto";
import type { Hono } from "hono";
import type { AppEnv } from "../app.js";
import {
  isAdminStatsEnvironment,
  type AdminStatsEnvironment,
  type AdminStatsRepository,
} from "../core/admin-stats.js";
import type { Logger } from "../utils/logger.js";

type Dependencies = { key?: string; repository?: AdminStatsRepository; logger: Logger };
const allowedDays = new Set([1, 7, 30, 90]);
const datePattern = /^\d{4}-\d{2}-\d{2}$/;

export function registerAdminStatsRoutes(app: Hono<AppEnv>, dependencies: Dependencies): void {
  app.use("/admin/*", async (c, next) => {
    c.header("Cache-Control", "no-store");
    if (!dependencies.key || !dependencies.repository) return c.json({ error: "NOT_FOUND" }, 404);
    if (!isAuthorized(c.req.header("authorization"), dependencies.key)) {
      c.header("WWW-Authenticate", 'Basic realm="Picture Word Stats", charset="UTF-8"');
      return c.json({ error: "UNAUTHORIZED" }, 401);
    }
    await next();
  });

  app.get("/admin/stats", (c) => c.html(adminStatsPage));

  app.get('/admin/api/stats/devices/:installationId/activity', async c => {
    const installationId = c.req.param('installationId');
    const startDate = c.req.query('startDate') ?? addDays(todayInShanghai(), -89);
    const endDate = c.req.query('endDate') ?? todayInShanghai();
    const environment = c.req.query('environment') ?? 'All';
    let cursor: DeviceActivityQuery['cursor'] = null;
    try {
      const encoded = c.req.query('cursor');
      if (encoded) {
        if (encoded.length > 512 || !/^[A-Za-z0-9_-]+$/.test(encoded)) throw new Error('Invalid cursor');
        const value = JSON.parse(Buffer.from(encoded, 'base64url').toString());
        if (typeof value.occurredAt !== 'string' || !Number.isFinite(Date.parse(value.occurredAt)) || !isUUID(value.eventId)) throw new Error('Invalid cursor');
        cursor = { occurredAt: new Date(value.occurredAt).toISOString(), eventId: value.eventId };
      }
    } catch { return c.json({ error: 'INVALID_STATS_QUERY' }, 400); }
    if (!isUUID(installationId) || !isValidDate(startDate) || !isValidDate(endDate) || startDate > endDate
      || endDate > todayInShanghai() || !isAdminStatsEnvironment(environment)) return c.json({ error: 'INVALID_STATS_QUERY' }, 400);
    try {
      const data = await dependencies.repository!.loadDeviceActivity({ installationId, startDate, endDate, environment, cursor });
      return data ? c.json(data) : c.json({ error: 'DEVICE_NOT_FOUND' }, 404);
    } catch (error) {
      dependencies.logger.error('admin_stats.activity_load_failed', { requestId: c.get('requestId'), message: error instanceof Error ? error.message : String(error) });
      return c.json({ error: 'STATS_UNAVAILABLE' }, 503);
    }
  });

  app.get('/admin/api/stats/devices/:installationId', async c => {
    const installationId = c.req.param('installationId');
    const oldest = addDays(todayInShanghai(), -89);
    const startDate = c.req.query('startDate') ?? oldest;
    const endDate = c.req.query('endDate') ?? todayInShanghai();
    const outcome = c.req.query('outcome') || null;
    const appVersion = c.req.query('appVersion')?.trim() || null;
    const environment = c.req.query('environment') ?? 'All';
    let cursor: DeviceDetailQuery['cursor'] = null;
    try {
      const encoded = c.req.query('cursor');
      if (encoded) {
        if (encoded.length > 512 || !/^[A-Za-z0-9_-]+$/.test(encoded)) throw new Error('Invalid cursor');
        const value = JSON.parse(Buffer.from(encoded, 'base64url').toString());
        if (typeof value.startedAt !== 'string' || !Number.isFinite(Date.parse(value.startedAt)) || !isUUID(value.operationId)) throw new Error('Invalid cursor');
        cursor = { startedAt: new Date(value.startedAt).toISOString(), operationId: value.operationId };
      }
    } catch { return c.json({ error: 'INVALID_STATS_QUERY' }, 400); }
    if (!isUUID(installationId) || !isAdminStatsEnvironment(environment) || !isValidDate(startDate) || !isValidDate(endDate) || startDate > endDate
      || startDate < oldest || endDate > todayInShanghai()
      || (outcome !== null && !recognitionOutcomes.includes(outcome as RecognitionOutcome))
      || (appVersion !== null && (appVersion.length > 64 || /[\x00-\x1f]/.test(appVersion)))) {
      return c.json({ error: 'INVALID_STATS_QUERY' }, 400);
    }
    try {
      const data = await dependencies.repository!.loadDeviceDetails({ installationId, startDate, endDate,
        outcome: outcome as RecognitionOutcome | null, appVersion, cursor, environment });
      return data ? c.json(data) : c.json({ error: 'DEVICE_NOT_FOUND' }, 404);
    } catch (error) {
      dependencies.logger.error('admin_stats.device_load_failed', { requestId: c.get('requestId'),
        message: error instanceof Error ? error.message : String(error) });
      return c.json({ error: 'STATS_UNAVAILABLE' }, 503);
    }
  });

  app.get("/admin/api/stats", async (c) => {
    const requestedStartDate = c.req.query("startDate");
    const requestedEndDate = c.req.query("endDate");
    const daysValue = c.req.query("days");
    const allTimeValue = c.req.query("allTime");
    const environment = c.req.query("environment") ?? "Production";
    let startDate: string | null;
    let endDate: string | null;
    if (allTimeValue !== undefined) {
      if (allTimeValue !== "true" || requestedStartDate !== undefined || requestedEndDate !== undefined || daysValue !== undefined) {
        return c.json({ error: "INVALID_STATS_QUERY" }, 400);
      }
      startDate = null;
      endDate = null;
    } else if (requestedStartDate !== undefined || requestedEndDate !== undefined) {
      if (!requestedStartDate || !requestedEndDate || daysValue !== undefined
        || !isValidDate(requestedStartDate) || !isValidDate(requestedEndDate)
        || requestedStartDate > requestedEndDate) {
        return c.json({ error: "INVALID_STATS_QUERY" }, 400);
      }
      startDate = requestedStartDate;
      endDate = requestedEndDate;
    } else {
      const days = daysValue === undefined ? 30 : Number(daysValue);
      if (!allowedDays.has(days)) return c.json({ error: "INVALID_STATS_QUERY" }, 400);
      endDate = todayInShanghai();
      startDate = addDays(endDate, -(days - 1));
    }
    if (!isAdminStatsEnvironment(environment)) {
      return c.json({ error: "INVALID_STATS_QUERY" }, 400);
    }
    try {
      return c.json(await dependencies.repository!.load(startDate, endDate, environment as AdminStatsEnvironment));
    } catch (error) {
      dependencies.logger.error("admin_stats.load_failed", {
        requestId: c.get("requestId"),
        message: error instanceof Error ? error.message : String(error),
      });
      return c.json({ error: "STATS_UNAVAILABLE" }, 503);
    }
  });
}

function isUUID(value: unknown): value is string {
  return typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}

function isValidDate(value: string): boolean {
  if (!datePattern.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return Number.isFinite(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
}

function todayInShanghai(): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Shanghai", year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(new Date());
  const get = (type: string) => parts.find((part) => part.type === type)!.value;
  return `${get("year")}-${get("month")}-${get("day")}`;
}

function addDays(value: string, days: number): string {
  const date = new Date(`${value}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

function isAuthorized(header: string | undefined, expectedKey: string): boolean {
  if (!header?.startsWith("Basic ")) return false;
  let decoded = "";
  try {
    decoded = Buffer.from(header.slice(6), "base64").toString("utf8");
  } catch {
    return false;
  }
  const separator = decoded.indexOf(":");
  if (separator < 0 || decoded.slice(0, separator) !== "admin") return false;
  return safeEqual(decoded.slice(separator + 1), expectedKey);
}

function safeEqual(actual: string, expected: string): boolean {
  const actualHash = createHash("sha256").update(actual).digest();
  const expectedHash = createHash("sha256").update(expected).digest();
  return timingSafeEqual(actualHash, expectedHash);
}

const adminStatsPage = String.raw`<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Picture Word · 数据手账</title>
  <style>
    :root { --paper:#f7f0df; --light:#fffaf0; --deep:#e9ddc4; --ink:#252a2b; --muted:#6f7068; --sun:#f6c94c; --coral:#ef715f; --mint:#65b99b; --sky:#84b9d7; --line:rgba(37,42,43,.12); --shadow:0 14px 32px rgba(70,55,34,.10); }
    * { box-sizing:border-box; }
    body { margin:0; color:var(--ink); font-family:"Avenir Next","PingFang SC","Hiragino Sans GB",sans-serif; background-color:var(--paper); background-image:linear-gradient(var(--line) 1px,transparent 1px),radial-gradient(rgba(37,42,43,.10) .8px,transparent .8px); background-size:100% 32px,18px 18px; }
    body::before { content:""; position:fixed; inset:0 auto 0 54px; width:2px; background:rgba(239,113,95,.22); pointer-events:none; }
    main { width:min(1440px,calc(100% - 36px)); margin:0 auto; padding:36px 0 72px; }
    header { display:grid; grid-template-columns:1fr; gap:24px; align-items:end; margin:0 10px 34px 42px; }
    .eyebrow,.tag,.section-kicker { font-family:"SFMono-Regular",Menlo,monospace; letter-spacing:.16em; text-transform:uppercase; font-size:11px; font-weight:800; }
    h1 { margin:8px 0 6px; font-family:Georgia,"Songti SC",serif; font-size:clamp(36px,6vw,72px); line-height:.95; letter-spacing:-.04em; }
    .subtitle { max-width:630px; color:var(--muted); font-weight:600; }
    .filters { display:flex; flex-wrap:wrap; gap:10px; padding:12px; background:rgba(255,250,240,.84); border:1px solid var(--line); border-radius:18px; box-shadow:var(--shadow); }
    select,input,button { border:0; background:var(--deep); color:var(--ink); border-radius:999px; padding:11px 14px; font:700 13px inherit; cursor:pointer; }
    button { background:var(--ink); color:var(--light); min-width:78px; }
    .notice { margin:0 10px 28px 42px; padding:16px 20px; background:var(--sun); border:1px solid rgba(37,42,43,.18); border-radius:14px 24px 18px 12px; font-weight:700; transform:rotate(-.25deg); box-shadow:4px 6px 0 rgba(37,42,43,.08); }
    .section { margin:34px 0 0 42px; }
    .section-head { display:flex; justify-content:space-between; align-items:end; gap:16px; margin:0 8px 14px; }
    h2 { margin:5px 0 0; font-family:Georgia,"Songti SC",serif; font-size:28px; }
    .section-note { color:var(--muted); font-size:13px; font-weight:600; text-align:right; }
    .device-panel { padding-top:18px; }
    .cards { display:grid; grid-template-columns:repeat(auto-fit,minmax(150px,1fr)); gap:14px; }
    .card,.panel { background:rgba(255,250,240,.93); border:1px solid var(--line); box-shadow:var(--shadow); }
    .card { min-height:132px; padding:18px; border-radius:22px 18px 28px 16px; position:relative; overflow:visible; }
    .card:nth-child(2n) { transform:rotate(.3deg); }.card:nth-child(3n) { transform:rotate(-.25deg); }
    .card::after { content:""; position:absolute; right:-20px; bottom:-28px; width:72px; height:72px; border-radius:50%; background:var(--accent,var(--sky)); opacity:.22; }
    .card-label { color:var(--muted); font-size:13px; font-weight:750; }
    .card-value { margin-top:14px; font-family:Georgia,serif; font-size:36px; font-weight:800; font-variant-numeric:tabular-nums; }
    .card-foot { margin-top:5px; color:var(--muted); font-size:11px; font-weight:700; }
    .grid { display:grid; grid-template-columns:repeat(12,1fr); gap:16px; }
    .panel { border-radius:24px; padding:22px; min-height:250px; overflow:visible; position:relative; }
    .card:has(.tip[open]),.panel:has(.tip[open]) { z-index:30; }
    .span-12 { grid-column:span 12; }.span-8 { grid-column:span 8; }.span-7 { grid-column:span 7; }.span-6 { grid-column:span 6; }.span-5 { grid-column:span 5; }.span-4 { grid-column:span 4; }
    .panel h3 { margin:0; font-size:16px; }.muted { color:var(--muted); }
    .panel-title { display:flex; align-items:center; justify-content:space-between; gap:12px; margin-bottom:18px; }
    .tip { position:relative; z-index:5; }
    .tip summary { display:grid; place-items:center; width:26px; height:26px; border:1px solid rgba(37,42,43,.2); border-radius:50%; background:var(--deep); color:var(--ink); cursor:pointer; font:800 13px Georgia,serif; list-style:none; user-select:none; }
    .tip summary::-webkit-details-marker { display:none; }
    .tip summary:hover,.tip[open] summary { background:var(--sun); transform:rotate(-5deg); }
    .tip-pop { position:absolute; top:34px; right:0; width:min(340px,calc(100vw - 56px)); padding:17px 18px; background:var(--ink); color:var(--light); border-radius:16px 10px 18px 14px; box-shadow:0 18px 50px rgba(20,20,18,.28); font-size:12px; line-height:1.55; font-weight:550; }
    .tip-pop::before { content:""; position:absolute; right:8px; top:-7px; width:15px; height:15px; background:var(--ink); transform:rotate(45deg); }
    .tip-pop p { margin:0 0 8px; }.tip-pop p:last-child { margin:0; }.tip-pop b { color:var(--sun); }
    .card .tip { position:absolute; top:14px; right:14px; }.card .tip-pop { right:-4px; }
    .bars { display:grid; gap:12px; }.bar-row { display:grid; grid-template-columns:minmax(90px,1.2fr) 4fr 52px; gap:10px; align-items:center; font-size:12px; font-weight:700; }
    .track { height:14px; background:var(--deep); border-radius:999px; overflow:hidden; }.fill { height:100%; min-width:2px; border-radius:inherit; background:var(--accent,var(--mint)); transition:width .5s ease; }
    svg { width:100%; height:190px; overflow:visible; }.line { fill:none; stroke:var(--coral); stroke-width:4; stroke-linecap:round; stroke-linejoin:round; }.area { fill:rgba(239,113,95,.12); }
    .legend { display:flex; gap:14px; flex-wrap:wrap; color:var(--muted); font-size:11px; font-weight:700; margin-top:10px; }
    .table-wrap { width:100%; overflow-x:auto; }
    table { width:100%; border-collapse:collapse; font-size:13px; } th { text-align:left; color:var(--ink); font-size:14px; font-weight:850; letter-spacing:.02em; white-space:nowrap; } th,td { padding:10px 8px; border-bottom:1px dashed var(--line); } td:not(:first-child),th:not(:first-child) { text-align:right; font-variant-numeric:tabular-nums; white-space:nowrap; }
    .device-table { min-width:1080px; }
    .filter-heading { vertical-align:top; }
    .heading-content { display:flex; align-items:center; justify-content:space-between; gap:8px; }
    .filter-toggle { display:inline-grid; place-items:center; width:25px; height:25px; flex:0 0 25px; padding:0; min-width:0; border:1px solid var(--line); border-radius:8px; background:var(--light); color:var(--muted); font-size:14px; line-height:1; }
    .filter-toggle:hover,.filter-toggle[aria-pressed="true"] { background:var(--sun); color:var(--ink); }
    .filter-toggle.is-active { border-color:var(--coral); color:var(--coral); box-shadow:inset 0 0 0 1px var(--coral); }
    .filter-row td { padding:8px; background:rgba(246,201,76,.12); vertical-align:top; }
    .column-filter { min-width:130px; max-width:180px; padding:10px; border:1px solid var(--line); border-radius:12px; background:var(--light); box-shadow:0 8px 20px rgba(70,55,34,.10); text-align:left; white-space:normal; }
    .column-filter label { display:block; margin:0 0 5px; color:var(--muted); font-size:10px; font-weight:750; }
    .column-filter input,.column-filter select { width:100%; min-width:0; margin:0 0 8px; padding:8px 9px; border:1px solid var(--line); border-radius:9px; background:#fffdf7; color:var(--ink); font:600 12px "Avenir Next","PingFang SC","Hiragino Sans GB",sans-serif; }
    .filter-pair { display:grid; grid-template-columns:1fr 1fr; gap:7px 6px; }
    .filter-field { display:block; min-width:0; margin:0; color:var(--muted); font-size:10px; font-weight:750; }
    .filter-field input,.filter-field select { display:block; margin-top:5px; }
    .filter-actions { display:flex; gap:6px; margin-top:4px; }
    .filter-actions button { min-width:0; flex:1; padding:8px 9px; border-radius:9px; font-size:11px; }
    .filter-actions .clear-column { background:var(--deep); color:var(--ink); }
    .device-table-status { display:flex; align-items:center; justify-content:space-between; gap:12px; margin:0 0 10px; color:var(--muted); font-size:12px; font-weight:700; }
    .clear-filters { min-width:0; padding:7px 11px; border:1px solid var(--line); background:var(--light); color:var(--ink); font-size:11px; }
    .clear-filters:disabled { opacity:.48; cursor:default; }
    .filtered-empty { min-height:120px; }
    tfoot { font-weight:800; background:rgba(246,201,76,.18); }
    .empty,.error { display:grid; place-items:center; min-height:150px; color:var(--muted); font-weight:700; }.error { color:var(--coral); }
    .loading .panel,.loading .card { opacity:.48; }
    footer { margin:36px 8px 0 50px; color:var(--muted); font-size:11px; font-family:Menlo,monospace; }
    @media(max-width:1000px){.cards{grid-template-columns:repeat(3,1fr)}.span-8,.span-7,.span-6,.span-5,.span-4{grid-column:span 12}header{grid-template-columns:1fr}.filters{justify-self:start}}
    @media(max-width:600px){main{width:calc(100% - 20px)}body::before{left:20px}.section,.notice{margin-left:22px}.cards{grid-template-columns:repeat(2,1fr)}header{margin-left:22px}.card-value{font-size:30px}.section-head{align-items:start;flex-direction:column}.section-note{text-align:left}}
    @media(prefers-reduced-motion:reduce){*{transition:none!important;scroll-behavior:auto!important}}
    #activityDaily { max-height:420px; overflow:auto; }
    #activityDaily thead { position:sticky; top:0; background:var(--light); z-index:1; }
    ${deviceDetailsStyles}
    .device-table { min-width:1100px; }
  </style>
</head>
<body>
<main id="app" class="loading">
  <header><div><div class="eyebrow">Picture Word · Operations Notebook</div><h1>数据手账</h1><div class="subtitle">查看访问、学习与功能使用趋势，打开设备详情查看行为记录和识别结果。</div></div></header>
  <div class="notice">按安装标识统计设备，不等于真实人数。时间范围按行为发生日期筛选，包含回来的老设备；未上报的旧版行为不补造。设备环境和会员类型为当前快照；日期均为北京时间。</div>
  ${activityMarkup}
  <div class="section-note" id="generated" style="margin:18px 8px 0 50px">正在读取数据…</div>
  <section class="section"><div class="section-head"><div><div class="section-kicker">Device detail</div><h2>设备活跃统计</h2></div><div class="section-note">包含所选期间有行为或新注册的设备；会员类型为当前快照</div></div><div class="panel device-panel"><div class="table-wrap" id="devices"></div></div></section>
  <section class="section"><div class="section-head"><div><div class="section-kicker">Conversion trail</div><h2>付费路径</h2></div><div class="section-note">漏斗为全环境事件；产品订阅与交易受环境筛选</div></div><div class="grid"><div class="panel span-7"><div class="panel-title"><h3>事件漏斗</h3><span data-tip="funnel"></span></div><div id="funnel"></div></div><div class="panel span-5"><div class="panel-title"><h3>套餐选择</h3><span data-tip="plans"></span></div><div id="plans"></div></div><div class="panel span-6"><div class="panel-title"><h3>购买结果</h3><span data-tip="purchase"></span></div><div id="purchase"></div></div><div class="panel span-6"><div class="panel-title"><h3>恢复购买</h3><span data-tip="restore"></span></div><div id="restore"></div></div></div></section>
  <section class="section"><div class="section-head"><div><div class="section-kicker">Recognition quality</div><h2>纠正词</h2></div></div><div class="grid"><div class="panel span-12"><div class="panel-title"><h3>常见纠正 · Top 20</h3><span data-tip="corrections"></span></div><div id="corrections"></div></div></div></section>
  <footer id="footer"></footer>
</main>
${deviceDetailsMarkup}
<script>
const $=id=>document.getElementById(id), fmt=n=>new Intl.NumberFormat('zh-CN').format(n||0), pct=(a,b)=>b?((a/b)*100).toFixed(1)+'%':'—';
const sum=(xs,fn=x=>x.count)=>xs.reduce((n,x)=>n+fn(x),0);
const metrics=(data,name)=>data.metrics.filter(x=>x.eventName===name);
const total=(data,name,outcome)=>sum(metrics(data,name).filter(x=>outcome===undefined||x.outcome===outcome));
const shortProduct=s=>s.includes('annual')?'年付':s.includes('month')?'月付':s||'未标记';
const labels={success:'成功',empty:'空结果',failure:'失败',cancelled:'取消',awaiting_sync:'等待同步',failed:'失败',not_found:'未找到',active:'活跃',grace:'宽限期',expired:'已过期',revoked:'已撤销',committed:'已扣除',released:'已释放',free:'免费',subscription:'会员',first:'第一候选',second:'第二候选',third:'第三候选',other:'其他'};
const tips={
installations:['安装设备','成功调用过 bootstrap 的不同安装标识总数。','对安装表记录计数；同一 installationId 只记录一次。','不是 App Store 下载量或真实人数；多设备、模拟器和标识重置会影响结果。'],
newInstallations:['新增安装','所选时间范围内首次成功注册的安装标识数量。','按北京时间筛选 installations.created_at 后计数。','表示首次完成服务端注册，不等于 App Store 下载；同一人的多台设备会分别计数。'],
activeSubscriptions:['活跃订阅','当前仍提供会员权益的订阅链数量。','按所选环境统计 state=active 的不同 originalTransactionId。','是当前快照而非所选时间段新增；切换 Production/Sandbox 会改变结果。'],
attempts:['识别尝试','已通过鉴权和额度检查并开始识别的请求次数。','汇总 recognition_attempt 事件。','按事件次数而非用户去重，且当前事件没有 Production/Sandbox 环境字段。'],
successRate:['识别成功率','识别成功事件占识别尝试事件的比例。','recognition_result=success ÷ recognition_attempt。','取消、失败和空结果都会降低比例；事件写入失败也可能造成轻微偏差。'],
quotaExhausted:['免费额度耗尽','免费设备因三次终身额度用完而被拒绝的次数。','汇总 quota_exhausted 且 outcome=free 的事件。','同一设备反复尝试会重复计数，因此不是耗尽额度的设备数。'],
changeRate:['用户改选率','反馈中没有接受第一候选的比例。','第二、第三、其他选择次数 ÷ 全部确认反馈。','仅统计主动提交反馈的样本，不能代表所有识别结果。'],
trend:['每日识别结果','所选时间范围内每天产生的识别结果事件。','按北京时间对 recognition_result 的所有 outcome 求和。','事件不带环境字段；今天按 Asia/Shanghai 自然日计算。'],
results:['结果构成','成功、空结果、失败和取消在识别结果中的次数分布。','按 recognition_result 的 outcome 分组汇总。','是请求事件数，不是设备数；部分取消发生时可能没有产品信息。'],
freeUsage:['免费额度使用分布','当前安装标识分别使用了 0、1、2、3 次免费额度的数量。','按 installations.free_used 的当前值分组。','这是当前全量快照，不受时间和订阅环境筛选影响，也不等于真实用户数。'],
quota:['额度操作','识别额度预占最终扣除或释放的次数。','按 quota_operations 的 subject_type 与 state 分组。','成功完成通常 committed；失败、取消、空结果或超时通常 released。'],
subscriptionStates:['订阅状态','所选环境下订阅链当前处于活跃、宽限、过期或撤销的数量。','按 originalTransactionId 去重后，依据 subscriptions.state 分组。','当前状态快照不受时间筛选影响；测试环境续订频率与生产不同。'],
funnel:['付费事件漏斗','付费墙曝光、套餐选择、购买成功的事件次数路径。','分别汇总 paywall_exposure、plan_selection 与 purchase_result=success。','不是同一批用户的严格漏斗，不能当作独立用户转化率，且事件没有环境字段。'],
plans:['套餐选择','用户点击月付或年付方案的事件次数。','按 plan_selection 的 productId 分组。','一次用户可多次选择；表示偏好信号，不代表最终成交。'],
purchase:['购买结果','发起购买后的成功、取消、失败及等待同步次数。','按 purchase_result 的 outcome 分组。','客户端事件没有环境字段；等待同步不代表最终购买失败。'],
restore:['恢复购买','用户执行恢复购买后的结果分布。','按 restore_result 的 outcome 分组。','同一用户可重复恢复；失败可能来自网络或商店状态，并非一定没有订阅。'],
selections:['候选选择','用户最终确认第一、第二、第三或自定义候选的次数。','汇总 recognition_confirmations_daily，并按 selection 分组。','只有提交确认反馈的识别会进入统计，样本可能较小。'],
corrections:['常见纠正','模型原始词被用户改成其他词的高频组合。','在所选日期内汇总 corrections_daily，按次数排序取前 20。','包含用户输入词语，仅限管理员查看；低频结果不代表问题不重要。']};
function bars(rows,color){if(!rows.length)return '<div class="empty">暂无数据</div>';const max=Math.max(...rows.map(x=>x.count),1);return '<div class="bars">'+rows.map(x=>'<div class="bar-row"><span>'+escapeHtml(labels[x.name]||x.name)+'</span><div class="track"><div class="fill" style="width:'+Math.max(2,x.count/max*100)+'%;--accent:'+(color||'var(--mint)')+'"></div></div><strong>'+fmt(x.count)+'</strong></div>').join('')+'</div>'}
function aggregate(rows,key){const m=new Map();rows.forEach(x=>m.set(key(x),(m.get(key(x))||0)+x.count));return [...m].map(([name,count])=>({name,count})).sort((a,b)=>b.count-a.count)}
function dateKey(date){const parts=new Intl.DateTimeFormat('en-US',{timeZone:'Asia/Shanghai',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(date);const get=t=>parts.find(x=>x.type===t).value;return get('year')+'-'+get('month')+'-'+get('day')}
function lineChart(rows,days){const map=new Map(rows.map(x=>[x.date,x.count]));const dates=[];const now=new Date();for(let i=days-1;i>=0;i--){const d=new Date(now);d.setDate(d.getDate()-i);dates.push(dateKey(d))}const values=dates.map(d=>map.get(d)||0),max=Math.max(...values,1),w=800,h=170,p=12;const points=values.map((v,i)=>(p+i*(w-2*p)/Math.max(values.length-1,1))+','+(h-p-v/max*(h-2*p))).join(' ');const area=p+','+(h-p)+' '+points+' '+(w-p)+','+(h-p);return '<svg viewBox="0 0 '+w+' '+h+'" role="img" aria-label="每日识别趋势"><polygon class="area" points="'+area+'"></polygon><polyline class="line" points="'+points+'"></polyline></svg><div class="legend"><span>'+dates[0]+'</span><span>峰值 '+fmt(max)+'</span><span>'+dates[dates.length-1]+'</span></div>'}
function tipControl(t){return '<details class="tip"><summary aria-label="查看指标说明">i</summary><div class="tip-pop"><p><b>是什么：</b>'+escapeHtml(t[0])+'</p><p><b>表示什么：</b>'+escapeHtml(t[1])+'</p><p><b>如何统计：</b>'+escapeHtml(t[2])+'</p><p><b>注意：</b>'+escapeHtml(t[3])+'</p></div></details>'}
function card(label,value,foot,color,tip){return '<article class="card" style="--accent:'+color+'">'+tipControl(tip)+'<div class="card-label">'+label+'</div><div class="card-value">'+value+'</div><div class="card-foot">'+foot+'</div></article>'}
function escapeHtml(v){return String(v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
function shiftDate(value,days){const date=new Date(value+'T00:00:00.000Z');date.setUTCDate(date.getUTCDate()+days);return date.toISOString().slice(0,10)}
function rangeForDays(days){const endDate=dateKey(new Date());return {preset:String(days),startDate:shiftDate(endDate,-(days-1)),endDate}}
let dateRange={...rangeForDays(30)};
let pendingDateRange={...dateRange};
let currentStatsEnvironment='All';
let deviceTableError='';
async function load(){const app=$('app');app.classList.add('loading');try{const params=new URLSearchParams({environment:$('activityEnvironment').value||'All'});if(dateRange.preset==='all')params.set('allTime','true');else{if(!dateRange.startDate||!dateRange.endDate||dateRange.startDate>dateRange.endDate)throw new Error('请选择有效的统计日期范围');params.set('startDate',dateRange.startDate);params.set('endDate',dateRange.endDate)}const res=await fetch('/admin/api/stats?'+params.toString());if(!res.ok)throw new Error('HTTP '+res.status);render(await res.json());}catch(e){deviceTableError='统计数据暂时无法读取，请检查日期范围或稍后重试。';$('generated').textContent='统计数据暂时无法读取：'+e.message;currentDeviceRows=[];renderDeviceTable();}finally{app.classList.remove('loading')}}
const deviceFilterColumns=[
{key:'deviceId',title:'设备',fields:[['query','搜索设备编号','search']]},
{key:'registrationDate',title:'注册时间（北京时间）',fields:[]},
{key:'environment',title:'环境',fields:[['value','运行环境','select']]},
{key:'membershipType',title:'会员类型',fields:[['value','会员类型','select']]}

];
let currentDeviceRows=[];
let openDeviceFilter=null;
const emptyDeviceFilter=column=>Object.fromEntries(column.fields.map(([field])=>[field,'']));
let deviceFilters=Object.fromEntries(deviceFilterColumns.map(column=>[column.key,emptyDeviceFilter(column)]));
function activeDeviceFilter(key){if(key==='registrationDate')return false;return Object.values(deviceFilters[key]||{}).some(value=>value!==''&&value!=null)}
function anyDeviceFilter(){return deviceFilterColumns.some(column=>activeDeviceFilter(column.key))}
function deviceMatchesFilters(device){
return deviceFilterColumns.every(column=>{
const filter=deviceFilters[column.key]||{};
if(column.key==='deviceId'&&filter.query&&!device.deviceId.toLowerCase().includes(filter.query.trim().toLowerCase()))return false;
if(column.key==='environment'&&filter.value&&device.environment!==filter.value)return false;
if(column.key==='membershipType'&&filter.value&&device.membershipType!==filter.value)return false;
return true;
});
}
function withinRange(value,min,max){return (min===''||value>=Number(min))&&(max===''||value<=Number(max))}
function filterControl(column){
const state=deviceFilters[column.key]||{};
const input=(field,label,type)=>'<label class="filter-field">'+label+'<input data-filter-field="'+field+'" type="'+(type==='percent'?'number':type)+'"'+(type==='number'||type==='percent'?' min="0" step="'+(type==='percent'?'0.1':'1')+'"':'')+(type==='percent'?' max="100"':'')+' value="'+escapeHtml(state[field]||'')+'" placeholder="不限"></label>';
let controls='';
if(column.key==='registrationDate'){
const option=(value,label)=>'<option value="'+value+'"'+(pendingDateRange.preset===value?' selected':'')+'>'+label+'</option>';
controls='<label class="filter-field">快捷范围<select data-date-preset>'+option('custom','自定义')+option('1','今天')+option('7','最近 7 天')+option('30','最近 30 天')+option('90','最近 90 天')+option('all','不限时间')+'</select></label><div class="filter-pair"><label class="filter-field">开始日期<input data-date-start type="date" value="'+escapeHtml(pendingDateRange.startDate||'')+'"'+(pendingDateRange.preset==='all'?' disabled':'')+'></label><label class="filter-field">结束日期<input data-date-end type="date" value="'+escapeHtml(pendingDateRange.endDate||'')+'"'+(pendingDateRange.preset==='all'?' disabled':'')+'></label></div>';
}else if(column.key==='environment'){
controls='<label class="filter-field">运行环境<select data-filter-field="value"><option value="">全部环境</option><option value="Production"'+(state.value==='Production'?' selected':'')+'>正式环境</option><option value="Sandbox"'+(state.value==='Sandbox'?' selected':'')+'>沙盒环境</option><option value="Xcode"'+(state.value==='Xcode'?' selected':'')+'>Xcode</option><option value="LocalTesting"'+(state.value==='LocalTesting'?' selected':'')+'>本地测试</option><option value="Unknown"'+(state.value==='Unknown'?' selected':'')+'>未知</option></select></label>';
}else if(column.key==='membershipType'){
controls='<label class="filter-field">会员类型<select data-filter-field="value"><option value="">全部类型</option><option value="free"'+(state.value==='free'?' selected':'')+'>免费版</option><option value="monthly"'+(state.value==='monthly'?' selected':'')+'>月会员</option><option value="annual"'+(state.value==='annual'?' selected':'')+'>年会员</option></select></label>';
}else if(column.key==='deviceId')controls=input('query','设备编号包含','search');
else if(column.key==='freeQuota')controls='<div class="filter-pair">'+input('usedMin','已用最少','number')+input('usedMax','已用最多','number')+input('remainingMin','剩余最少','number')+input('remainingMax','剩余最多','number')+'</div>';
else if(column.key==='successRate'||column.key==='changeRate')controls='<div class="filter-pair">'+input('min','最低 %','percent')+input('max','最高 %','percent')+'</div>';
else controls='<div class="filter-pair">'+input('min','最少','number')+input('max','最多','number')+'</div>';
return '<div class="column-filter" data-filter-panel="'+column.key+'">'+controls+'<div class="filter-actions"><button type="button" data-filter-action="apply" data-filter-key="'+column.key+'">应用</button><button type="button" class="clear-column" data-filter-action="clear-column" data-filter-key="'+column.key+'">清除此列</button></div></div>';
}
function renderDeviceTable(){
const root=$('devices');
const devices=currentDeviceRows.filter(deviceMatchesFilters);
const membershipCounts=devices.reduce((counts,device)=>{if(device.membershipType in counts)counts[device.membershipType]++;return counts},{free:0,monthly:0,annual:0});
const header=column=>column.key==='registrationDate'?'<th scope="col">注册时间（北京时间）</th>':'<th class="filter-heading"><div class="heading-content"><span>'+column.title+'</span><button type="button" class="filter-toggle'+(activeDeviceFilter(column.key)?' is-active':'')+'" data-filter-toggle="'+column.key+'" aria-label="筛选：'+column.title+'" aria-pressed="'+(openDeviceFilter===column.key)+'">'+(activeDeviceFilter(column.key)?'⌕':'▽')+'</button></div></th>';
const envLabels={Production:'正式环境',Sandbox:'沙盒环境',Xcode:'Xcode',LocalTesting:'本地测试',Unknown:'未知'};
const cell=device=>'<tr><td>设备 '+escapeHtml(device.deviceId)+'</td><td>'+escapeHtml(device.registrationDate||'—')+'</td><td>'+escapeHtml(envLabels[device.environment]||device.environment||'未知')+'</td><td>'+({free:'免费版',monthly:'月会员',annual:'年会员'}[device.membershipType]||'会员')+'</td>'+activityDeviceCells(device.activity)+'<td><button type="button" class="clear-filters" data-device-details="'+escapeHtml(device.installationId)+'" aria-label="查看设备 '+escapeHtml(device.deviceId)+' 的活跃和识别详情">查看详情</button></td></tr>';
const activityHeader='<th>最近活跃</th><th>活跃天数</th><th>打开次数</th><th>学习次数</th>';
const filterRow=openDeviceFilter?'<tr class="filter-row">'+deviceFilterColumns.map(column=>'<td>'+(openDeviceFilter===column.key?filterControl(column):'')+'</td>').join('')+'<td colspan="5"></td></tr>':'';
const emptyMessage=deviceTableError|| (currentDeviceRows.length?'没有设备符合这些筛选条件。':'所选时间范围内没有活跃或新增设备。');
const body=devices.length?devices.map(cell).join(''):'<tr><td class="empty filtered-empty" colspan="9">'+emptyMessage+(anyDeviceFilter()?'<button type="button" class="clear-filters" data-filter-action="clear-all">清除筛选</button>':'')+'</td></tr>';
const membershipTotal='<div>免费会员：'+fmt(membershipCounts.free)+'<br>月会员：'+fmt(membershipCounts.monthly)+'<br>年会员：'+fmt(membershipCounts.annual)+'</div>';
const total='<tfoot><tr><td>总计（'+fmt(devices.length)+' 台）</td><td>—</td><td>—</td><td>'+membershipTotal+'</td><td colspan="5">—</td></tr></tfoot>';
root.innerHTML='<div class="device-table-status"><span>当前显示 '+fmt(devices.length)+' / '+fmt(currentDeviceRows.length)+' 台设备</span><div><button type="button" class="clear-filters" data-filter-action="clear-all"'+(anyDeviceFilter()?'':' disabled')+'>清除全部筛选</button> <button type="button" data-filter-action="refresh">刷新数据</button></div></div><table class="device-table"><thead><tr>'+deviceFilterColumns.map(header).join('')+activityHeader+'<th scope="col">详情</th></tr>'+filterRow+'</thead><tbody>'+body+'</tbody>'+total+'</table>';
}
function handleDeviceFilterChange(event){
const target=event.target;
if(target.dataset.datePreset!==undefined){
const preset=target.value;
pendingDateRange=preset==='all'?{preset,startDate:'',endDate:''}:preset==='custom'?{...pendingDateRange,preset}:rangeForDays(Number(preset));
renderDeviceTable();
return;
}
if(target.dataset.dateStart!==undefined||target.dataset.dateEnd!==undefined){
pendingDateRange={...pendingDateRange,preset:'custom',startDate:target.dataset.dateStart!==undefined?target.value:pendingDateRange.startDate,endDate:target.dataset.dateEnd!==undefined?target.value:pendingDateRange.endDate};
const preset=$('devices').querySelector('[data-date-preset]');if(preset)preset.value='custom';
}
}
function handleDeviceFilterClick(event){
const target=event.target.closest('[data-filter-toggle],[data-filter-action],[data-device-details]');
if(!target)return;
if(target.dataset.deviceDetails)return openDeviceDetails(target.dataset.deviceDetails);
const action=target.dataset.filterAction;
if(target.dataset.filterToggle){const key=target.dataset.filterToggle;openDeviceFilter=openDeviceFilter===key?null:key;if(openDeviceFilter==='registrationDate')pendingDateRange={...dateRange};renderDeviceTable();return}
const key=target.dataset.filterKey;
if(action==='refresh')return load();
if(action==='apply'&&key==='registrationDate'){
if(pendingDateRange.preset!=='all'&&(!pendingDateRange.startDate||!pendingDateRange.endDate||pendingDateRange.startDate>pendingDateRange.endDate)){$('generated').textContent='请选择有效的统计日期范围';return}
dateRange={...pendingDateRange};openDeviceFilter=null;return load();
}
if(action==='apply'&&key){const panel=$('devices').querySelector('[data-filter-panel="'+key+'"]');const state={};panel.querySelectorAll('[data-filter-field]').forEach(field=>{state[field.dataset.filterField]=field.value.trim()});deviceFilters[key]=state;openDeviceFilter=null;renderDeviceTable();return}
if(action==='clear-column'&&key==='registrationDate'){dateRange={preset:'all',startDate:'',endDate:''};pendingDateRange={...dateRange};openDeviceFilter=null;return load()}
if(action==='clear-column'&&key){deviceFilters[key]=emptyDeviceFilter(deviceFilterColumns.find(column=>column.key===key));openDeviceFilter=null;renderDeviceTable();return}
if(action==='clear-all'){deviceFilters=Object.fromEntries(deviceFilterColumns.map(column=>[column.key,emptyDeviceFilter(column)]));dateRange={preset:'all',startDate:'',endDate:''};pendingDateRange={...dateRange};openDeviceFilter=null;renderDeviceTable();return load()}
}
$('devices').addEventListener('click',handleDeviceFilterClick);
function render(data){
currentStatsEnvironment=data.environment;
renderActivity(data.activity);
deviceTableError='';
currentDeviceRows=data.installations.devices;openDeviceFilter=null;renderDeviceTable();
const paywall=total(data,'paywall_exposure'),selected=total(data,'plan_selection'),bought=total(data,'purchase_result','success');$('funnel').innerHTML=bars([{name:'付费墙曝光',count:paywall},{name:'套餐选择',count:selected},{name:'购买成功',count:bought}],'var(--coral)')+'<div class="legend"><span>选择率 '+pct(selected,paywall)+'</span><span>事件转化率 '+pct(bought,paywall)+'</span></div>';
$('plans').innerHTML=bars(aggregate(metrics(data,'plan_selection'),x=>shortProduct(x.productId)),'var(--sun)');$('purchase').innerHTML=bars(aggregate(metrics(data,'purchase_result'),x=>labels[x.outcome]||x.outcome||'未知'),'var(--coral)');$('restore').innerHTML=bars(aggregate(metrics(data,'restore_result'),x=>labels[x.outcome]||x.outcome||'未知'),'var(--sky)');
$('corrections').innerHTML=data.feedback.corrections.length?'<table><thead><tr><th>模型原词</th><th>用户修正</th><th>次数</th></tr></thead><tbody>'+data.feedback.corrections.map(x=>'<tr><td>'+escapeHtml(x.originalEnglish)+' · '+escapeHtml(x.originalChinese)+'</td><td>'+escapeHtml(x.correctedEnglish)+' · '+escapeHtml(x.correctedChinese)+'</td><td>'+fmt(x.count)+'</td></tr>').join('')+'</tbody></table>':'<div class="empty">暂无纠正反馈</div>';
$('generated').textContent='生成于 '+new Date(data.generatedAt).toLocaleString('zh-CN')+' · '+({All:'全部环境',Production:'正式环境',Sandbox:'沙盒环境',Xcode:'Xcode',LocalTesting:'本地测试'}[data.environment]||data.environment);$('footer').textContent='范围：'+(data.startDate&&data.endDate?data.startDate+' 至 '+data.endDate:'不限时间')+' · 时区：Asia/Shanghai · 订阅环境：'+data.environment+' · 页面不缓存';}
document.querySelectorAll('[data-tip]').forEach(el=>{el.innerHTML=tipControl(tips[el.dataset.tip])});
${activityScript}
${deviceDetailsScript}
${activityDetailScript}
$('devices').addEventListener('change',handleDeviceFilterChange);renderDeviceTable();load();
</script>
</body></html>`;
