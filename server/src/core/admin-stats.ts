import { Pool } from "pg";
import type { AccessEnvironment } from "./access/types.js";

export const adminStatsEnvironments = ["Production", "Sandbox", "Xcode", "LocalTesting"] as const;
export type AdminStatsEnvironment = (typeof adminStatsEnvironments)[number];

export type CountByName = { name: string; count: number };
export type DailyCount = { date: string; count: number };
export type MetricCount = { date: string; eventName: string; productId: string; outcome: string; count: number };
export type AdminStatsSnapshot = {
  generatedAt: string;
  days: number;
  environment: AdminStatsEnvironment;
  installations: { total: number; daily: DailyCount[]; freeUsage: CountByName[] };
  subscriptions: { states: CountByName[]; products: CountByName[]; transactions: CountByName[] };
  metrics: MetricCount[];
  quotaOperations: Array<{ subjectType: string; state: string; count: number }>;
  feedback: {
    selections: CountByName[];
    corrections: Array<{
      originalEnglish: string;
      originalChinese: string;
      correctedEnglish: string;
      correctedChinese: string;
      count: number;
    }>;
  };
};

export interface AdminStatsRepository {
  load(days: number, environment: AdminStatsEnvironment): Promise<AdminStatsSnapshot>;
}

type Numeric = string | number;
const rangeStart = `(clock_timestamp() AT TIME ZONE 'Asia/Shanghai')::date - ($1::int - 1)`;

export class PostgresAdminStatsRepository implements AdminStatsRepository {
  private readonly pool: Pool;

  constructor(databaseURL: string) {
    this.pool = new Pool({ connectionString: databaseURL });
  }

  async load(days: number, environment: AdminStatsEnvironment): Promise<AdminStatsSnapshot> {
    const client = await this.pool.connect();
    try {
      const [installationTotal, installationDaily, freeUsage, subscriptionStates, subscriptionProducts,
      transactions, metrics, quotaOperations, selections, corrections] = await Promise.all([
      client.query<{ count: Numeric }>(`SELECT COUNT(*) AS count FROM picture_word_installations`),
      client.query<{ date: string; count: Numeric }>(
        `SELECT (created_at AT TIME ZONE 'Asia/Shanghai')::date::text AS date, COUNT(*) AS count
         FROM picture_word_installations
         WHERE (created_at AT TIME ZONE 'Asia/Shanghai')::date >= ${rangeStart}
         GROUP BY 1 ORDER BY 1`, [days],
      ),
      client.query<{ name: Numeric; count: Numeric }>(
        `SELECT free_used AS name, COUNT(*) AS count
         FROM picture_word_installations GROUP BY free_used ORDER BY free_used`,
      ),
      client.query<{ name: string; count: Numeric }>(
        `SELECT state AS name, COUNT(DISTINCT original_transaction_id) AS count
         FROM picture_word_subscriptions WHERE environment = $1 GROUP BY state ORDER BY state`, [environment],
      ),
      client.query<{ name: string; count: Numeric }>(
        `SELECT product_id AS name, COUNT(DISTINCT original_transaction_id) AS count
         FROM picture_word_subscriptions WHERE environment = $1 GROUP BY product_id ORDER BY product_id`, [environment],
      ),
      client.query<{ name: string; count: Numeric }>(
        `SELECT product_id AS name, COUNT(*) AS count
         FROM picture_word_subscription_transactions
         WHERE environment = $2
           AND (purchase_at AT TIME ZONE 'Asia/Shanghai')::date >= ${rangeStart}
         GROUP BY product_id ORDER BY product_id`, [days, environment],
      ),
      client.query<{ metric_date: string; event_name: string; product_id: string; outcome: string; event_count: Numeric }>(
        `SELECT metric_date::text, event_name, product_id, outcome, event_count
         FROM picture_word_aggregate_metrics_daily
         WHERE metric_date >= ${rangeStart}
         ORDER BY metric_date, event_name, product_id, outcome`, [days],
      ),
      client.query<{ subject_type: string; state: string; count: Numeric }>(
        `SELECT subject_type, state, COUNT(*) AS count
         FROM picture_word_quota_operations
         WHERE (created_at AT TIME ZONE 'Asia/Shanghai')::date >= ${rangeStart}
         GROUP BY subject_type, state ORDER BY subject_type, state`, [days],
      ),
      client.query<{ name: string; count: Numeric }>(
        `SELECT selection AS name, SUM(confirmation_count) AS count
         FROM picture_word_recognition_confirmations_daily
         WHERE metric_date >= ${rangeStart}
         GROUP BY selection ORDER BY selection`, [days],
      ),
      client.query<{
        original_english: string; original_chinese: string; corrected_english: string;
        corrected_chinese: string; count: Numeric;
      }>(
        `SELECT original_english, original_chinese, corrected_english, corrected_chinese,
                SUM(correction_count) AS count
         FROM picture_word_recognition_corrections_daily
         WHERE metric_date >= ${rangeStart}
         GROUP BY original_english, original_chinese, corrected_english, corrected_chinese
         ORDER BY count DESC, original_english, corrected_english LIMIT 20`, [days],
      ),
    ]);

      return {
      generatedAt: new Date().toISOString(),
      days,
      environment,
      installations: {
        total: number(installationTotal.rows[0]?.count),
        daily: installationDaily.rows.map((row) => ({ date: row.date, count: number(row.count) })),
        freeUsage: freeUsage.rows.map((row) => ({ name: String(row.name), count: number(row.count) })),
      },
      subscriptions: {
        states: counts(subscriptionStates.rows),
        products: counts(subscriptionProducts.rows),
        transactions: counts(transactions.rows),
      },
      metrics: metrics.rows.map((row) => ({
        date: row.metric_date,
        eventName: row.event_name,
        productId: row.product_id,
        outcome: row.outcome,
        count: number(row.event_count),
      })),
      quotaOperations: quotaOperations.rows.map((row) => ({
        subjectType: row.subject_type, state: row.state, count: number(row.count),
      })),
      feedback: {
        selections: counts(selections.rows),
        corrections: corrections.rows.map((row) => ({
          originalEnglish: row.original_english,
          originalChinese: row.original_chinese,
          correctedEnglish: row.corrected_english,
          correctedChinese: row.corrected_chinese,
          count: number(row.count),
        })),
      },
      };
    } finally {
      client.release();
    }
  }
}

function counts(rows: Array<{ name: string; count: Numeric }>): CountByName[] {
  return rows.map((row) => ({ name: row.name, count: number(row.count) }));
}

function number(value: Numeric | undefined): number {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

export function isAdminStatsEnvironment(value: string): value is AccessEnvironment {
  return (adminStatsEnvironments as readonly string[]).includes(value);
}
