import { loadActivityOverview, loadDeviceActivity, type ActivityOverview, type ActivityDeviceSummary, type DeviceActivityQuery, type DeviceActivity } from './activity-stats.js';
import { Pool } from "pg";
import { loadDeviceDetails, type DeviceDetailQuery, type DeviceDetails } from "./admin-device-details.js";
export const adminStatsEnvironments = ["All", "Production", "Sandbox", "Xcode", "LocalTesting", "Unknown"] as const;
export type AdminStatsEnvironment = (typeof adminStatsEnvironments)[number];
export type CountByName = { name: string; count: number };
export type DailyCount = { date: string; count: number };
export type MetricCount = { date: string; eventName: string; productId: string; outcome: string; count: number };
export type AdminStatsDevice = {
  installationId: string;
  deviceId: string;
  registrationDate: string;
  environment: string;
  membershipType: string;
  recognitionAttempts: number;
  recognitionSuccesses: number;
  confirmationCount: number;
  reselectionCount: number;
  freeUsed: number;
  activity?: ActivityDeviceSummary;
};
export type AdminStatsSnapshot = {
  activity: ActivityOverview;
  generatedAt: string;
  startDate: string | null;
  endDate: string | null;
  environment: AdminStatsEnvironment;
  installations: { total: number; daily: DailyCount[]; freeUsage: CountByName[]; devices: AdminStatsDevice[] };
  subscriptions: { states: CountByName[]; products: CountByName[]; transactions: CountByName[] };
  metrics: MetricCount[];
  quotaOperations: Array<{ subjectType: string; state: string; count: number }>;
  feedback: { selections: CountByName[]; corrections: Array<{ originalEnglish: string; originalChinese: string; correctedEnglish: string; correctedChinese: string; count: number }> };
};
export interface AdminStatsRepository {
  loadDeviceActivity(query: DeviceActivityQuery): Promise<DeviceActivity | null>;
  loadDeviceDetails(query: DeviceDetailQuery): Promise<DeviceDetails | null>;
  load(startDate: string | null, endDate: string | null, environment: AdminStatsEnvironment): Promise<AdminStatsSnapshot>;
}
type Numeric = string | number;
const filter = "($1::date IS NULL OR %s >= $1::date) AND ($2::date IS NULL OR %s <= $2::date)";

export class PostgresAdminStatsRepository implements AdminStatsRepository {
  private readonly pool: Pool;
  constructor(databaseURL: string) { this.pool = new Pool({ connectionString: databaseURL }); }

  async loadDeviceActivity(query: DeviceActivityQuery): Promise<DeviceActivity | null> { return loadDeviceActivity(this.pool, query); }
  async loadDeviceDetails(query: DeviceDetailQuery): Promise<DeviceDetails | null> { return loadDeviceDetails(this.pool, query); }
  async close(): Promise<void> { await this.pool.end(); }

  async load(startDate: string | null, endDate: string | null, environment: AdminStatsEnvironment): Promise<AdminStatsSnapshot> {
    const client = await this.pool.connect();
    try {
      const params = [startDate, endDate, environment];
      const activity = await loadActivityOverview(client, startDate, endDate, environment);
      const activityByDevice = new Map(activity.devices.map(device => [device.installationId, device]));
      const installationTotal = await client.query<{ count: Numeric }>(
        `SELECT COUNT(*) AS count FROM picture_word_installations WHERE ${filter.replaceAll("%s", "(created_at AT TIME ZONE 'Asia/Shanghai')::date")}`, params.slice(0, 2));
      const installationDaily = await client.query<{ date: string; count: Numeric }>(
        `SELECT (created_at AT TIME ZONE 'Asia/Shanghai')::date::text AS date, COUNT(*) AS count FROM picture_word_installations WHERE ${filter.replaceAll("%s", "(created_at AT TIME ZONE 'Asia/Shanghai')::date")} GROUP BY 1 ORDER BY 1`, params.slice(0, 2));
      const freeUsage = await client.query<{ name: Numeric; count: Numeric }>(
        `SELECT free_used AS name, COUNT(*) AS count FROM picture_word_installations WHERE ${filter.replaceAll("%s", "(created_at AT TIME ZONE 'Asia/Shanghai')::date")} GROUP BY free_used ORDER BY free_used`, params.slice(0, 2));
      const devices = await client.query<{
        installation_id: string; device_id: string; registration_date: string; store_environment: string; membership_type: string; recognition_attempt_count: Numeric;
        recognition_success_count: Numeric; confirmation_count: Numeric; reselection_count: Numeric; free_used: number;
      }>(
        `SELECT i.id::text AS installation_id, right(i.id::text, 6) AS device_id,
                to_char(i.created_at AT TIME ZONE 'Asia/Shanghai', 'YYYY-MM-DD HH24:MI') AS registration_date,
                COALESCE(i.store_environment, 'Unknown') AS store_environment,
                COALESCE(member.product_id, 'free') AS membership_type,
                COALESCE(SUM(m.recognition_attempt_count), 0) AS recognition_attempt_count,
                COALESCE(SUM(m.recognition_success_count), 0) AS recognition_success_count,
                COALESCE(SUM(m.confirmation_count), 0) AS confirmation_count,
                COALESCE(SUM(m.reselection_count), 0) AS reselection_count, i.free_used
         FROM picture_word_installations i
         LEFT JOIN picture_word_installation_metrics_daily m ON m.installation_id = i.id
           AND ${filter.replaceAll("%s", "m.metric_date")}
           AND ($3 = 'All' OR m.environment = $3)
         LEFT JOIN LATERAL (
           SELECT s.product_id FROM picture_word_access_tokens t JOIN picture_word_subscriptions s
             ON s.environment = t.subscription_environment AND s.original_transaction_id = t.original_transaction_id
           WHERE t.installation_id = i.id AND t.expires_at > clock_timestamp()
             AND (i.store_environment IS NULL OR s.environment = i.store_environment)
             AND ((s.state = 'active' AND s.expires_at > clock_timestamp()) OR (s.state = 'grace' AND s.grace_expires_at > clock_timestamp()))
           ORDER BY t.last_used_at DESC LIMIT 1
         ) member ON TRUE
         WHERE ((${filter.replaceAll("%s", "(i.created_at AT TIME ZONE 'Asia/Shanghai')::date")}
             AND ($3 = 'All' OR COALESCE(i.store_environment, 'Unknown') = $3))
           OR EXISTS (SELECT 1 FROM picture_word_activity_daily ad WHERE ad.installation_id = i.id
             AND ${filter.replaceAll("%s", "ad.metric_date")} AND ($3 = 'All' OR ad.environment = $3))
           OR EXISTS (SELECT 1 FROM picture_word_installation_metrics_daily rd WHERE rd.installation_id = i.id
             AND ${filter.replaceAll("%s", "rd.metric_date")} AND ($3 = 'All' OR rd.environment = $3)))
         GROUP BY i.id, i.created_at, i.free_used, i.store_environment, member.product_id ORDER BY i.created_at DESC, i.id`, params);
      const subscriptionStates = await client.query<{ name: string; count: Numeric }>(
        `SELECT state AS name, COUNT(DISTINCT original_transaction_id) AS count FROM picture_word_subscriptions WHERE ($1 = 'All' OR environment = $1) GROUP BY state ORDER BY state`, [environment]);
      const subscriptionProducts = await client.query<{ name: string; count: Numeric }>(
        `SELECT product_id AS name, COUNT(DISTINCT original_transaction_id) AS count FROM picture_word_subscriptions WHERE ($1 = 'All' OR environment = $1) GROUP BY product_id ORDER BY product_id`, [environment]);
      const transactions = await client.query<{ name: string; count: Numeric }>(
        `SELECT product_id AS name, COUNT(*) AS count FROM picture_word_subscription_transactions WHERE ($3 = 'All' OR environment = $3)
         AND ${filter.replaceAll("%s", "(purchase_at AT TIME ZONE 'Asia/Shanghai')::date")} GROUP BY product_id ORDER BY product_id`, params);
      const metrics = await client.query<{ metric_date: string; event_name: string; product_id: string; outcome: string; event_count: Numeric }>(
        `SELECT metric_date::text, event_name, product_id, outcome, event_count FROM picture_word_aggregate_metrics_daily WHERE ${filter.replaceAll("%s", "metric_date")} ORDER BY metric_date, event_name, product_id, outcome`, params.slice(0, 2));
      const quotaOperations = await client.query<{ subject_type: string; state: string; count: Numeric }>(
        `SELECT subject_type, state, COUNT(*) AS count FROM picture_word_quota_operations WHERE ${filter.replaceAll("%s", "(created_at AT TIME ZONE 'Asia/Shanghai')::date")} GROUP BY subject_type, state ORDER BY subject_type, state`, params.slice(0, 2));
      const selections = await client.query<{ name: string; count: Numeric }>(
        `SELECT selection AS name, SUM(confirmation_count) AS count FROM picture_word_recognition_confirmations_daily WHERE ${filter.replaceAll("%s", "metric_date")} GROUP BY selection ORDER BY selection`, params.slice(0, 2));
      const corrections = await client.query<{ original_english: string; original_chinese: string; corrected_english: string; corrected_chinese: string; count: Numeric }>(
        `SELECT original_english, original_chinese, corrected_english, corrected_chinese, SUM(correction_count) AS count FROM picture_word_recognition_corrections_daily WHERE ${filter.replaceAll("%s", "metric_date")} GROUP BY original_english, original_chinese, corrected_english, corrected_chinese ORDER BY count DESC, original_english, corrected_english LIMIT 20`, params.slice(0, 2));
      return {
        activity,
        generatedAt: new Date().toISOString(), startDate, endDate, environment,
        installations: {
          total: number(installationTotal.rows[0]?.count),
          daily: installationDaily.rows.map((row) => ({ date: row.date, count: number(row.count) })),
          freeUsage: freeUsage.rows.map((row) => ({ name: String(row.name), count: number(row.count) })),
          devices: devices.rows.map((row) => ({
            activity: activityByDevice.get(row.installation_id),
            installationId: row.installation_id, deviceId: row.device_id, registrationDate: row.registration_date, environment: row.store_environment,
            membershipType: row.membership_type === "free" ? "free" : row.membership_type.endsWith("annual") ? "annual" : "monthly",
            recognitionAttempts: number(row.recognition_attempt_count), recognitionSuccesses: number(row.recognition_success_count),
            confirmationCount: number(row.confirmation_count), reselectionCount: number(row.reselection_count), freeUsed: row.free_used,
          })),
        },
        subscriptions: { states: counts(subscriptionStates.rows), products: counts(subscriptionProducts.rows), transactions: counts(transactions.rows) },
        metrics: metrics.rows.map((row) => ({ date: row.metric_date, eventName: row.event_name, productId: row.product_id, outcome: row.outcome, count: number(row.event_count) })),
        quotaOperations: quotaOperations.rows.map((row) => ({ subjectType: row.subject_type, state: row.state, count: number(row.count) })),
        feedback: {
          selections: counts(selections.rows),
          corrections: corrections.rows.map((row) => ({ originalEnglish: row.original_english, originalChinese: row.original_chinese, correctedEnglish: row.corrected_english, correctedChinese: row.corrected_chinese, count: number(row.count) })),
        },
      };
    } finally { client.release(); }
  }
}
function counts(rows: Array<{ name: string; count: Numeric }>): CountByName[] { return rows.map((row) => ({ name: row.name, count: number(row.count) })); }
function number(value: Numeric | undefined): number { const parsed = Number(value ?? 0); return Number.isFinite(parsed) ? parsed : 0; }
export function isAdminStatsEnvironment(value: string): value is AdminStatsEnvironment { return (adminStatsEnvironments as readonly string[]).includes(value); }
