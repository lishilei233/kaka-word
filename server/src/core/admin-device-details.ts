import type { Pool } from 'pg';
import type { AdminStatsEnvironment, AdminStatsDevice } from './admin-stats.js';
import type { QuotaSnapshot, RecognitionOutcome } from './access/types.js';

export type DeviceDetailQuery = {
  environment?: AdminStatsEnvironment;
  installationId: string; startDate: string; endDate: string;
  outcome: RecognitionOutcome | null; appVersion: string | null;
  cursor: { startedAt: string; operationId: string } | null;
};
export type RecognitionAttemptDetail = {
  operationId: string; requestId: string; startedAt: string; finishedAt: string | null;
  environment: string; outcome: RecognitionOutcome; reasonCode: string | null; stage: string | null;
  durationMs: number | null; appVersion: string | null; appBuild: string | null;
  quotaBefore: QuotaSnapshot; quotaAfter: QuotaSnapshot | null;
  quotaState: 'not_reserved' | 'reserved' | 'committed' | 'released';
};
export type DeviceDetails = {
  device: AdminStatsDevice; startDate: string; endDate: string; recordingStartedAt: string;
  summary: { recognitionAttempts: number; recognitionSuccesses: number; confirmationCount: number; reselectionCount: number };
  attempts: RecognitionAttemptDetail[]; nextCursor: string | null;
};

export async function loadDeviceDetails(pool: Pool, query: DeviceDetailQuery): Promise<DeviceDetails | null> {
  const client = await pool.connect();
  try {
    const installation = await client.query<{
      id: string; registration_date: string; environment: string; free_used: number; product_id: string | null;
    }>(
      `SELECT i.id::text, to_char(i.created_at AT TIME ZONE 'Asia/Shanghai', 'YYYY-MM-DD HH24:MI') AS registration_date,
        COALESCE(i.store_environment, 'Unknown') AS environment, i.free_used, member.product_id
       FROM picture_word_installations i LEFT JOIN LATERAL (
         SELECT s.product_id FROM picture_word_access_tokens t JOIN picture_word_subscriptions s
           ON s.environment = t.subscription_environment AND s.original_transaction_id = t.original_transaction_id
         WHERE t.installation_id = i.id AND t.expires_at > clock_timestamp()
           AND (i.store_environment IS NULL OR s.environment = i.store_environment)
           AND ((s.state = 'active' AND s.expires_at > clock_timestamp()) OR (s.state = 'grace' AND s.grace_expires_at > clock_timestamp()))
         ORDER BY t.last_used_at DESC LIMIT 1
       ) member ON TRUE WHERE i.id = $1`, [query.installationId],
    );
    const row = installation.rows[0];
    if (!row) return null;
    const totals = await client.query<{
      attempts: string; successes: string; confirmations: string; reselections: string;
    }>(
      `SELECT COALESCE(SUM(recognition_attempt_count), 0)::text AS attempts,
        COALESCE(SUM(recognition_success_count), 0)::text AS successes,
        COALESCE(SUM(confirmation_count), 0)::text AS confirmations,
        COALESCE(SUM(reselection_count), 0)::text AS reselections
       FROM picture_word_installation_metrics_daily WHERE installation_id = $1
         AND metric_date BETWEEN $2::date AND $3::date AND ($4 = 'All' OR environment = $4)`, [query.installationId, query.startDate, query.endDate, query.environment ?? 'All'],
    );
    const metadata = await client.query<{ recorded_at: Date }>(
      `SELECT recorded_at FROM picture_word_stats_metadata WHERE name = 'recognition_attempts_started'`,
    );
    const attempts = await client.query<Omit<RecognitionAttemptDetail, 'startedAt' | 'finishedAt'> & { startedAt: Date; finishedAt: Date | null }>(
      `WITH rows AS (
        SELECT a.*, CASE WHEN a.outcome = 'processing' AND a.started_at <= clock_timestamp() - interval '10 minutes'
          THEN 'unfinished' ELSE a.outcome END AS effective_outcome,
          CASE WHEN o.state = 'reserved' AND o.lease_expires_at <= clock_timestamp() THEN 'released'
               ELSE COALESCE(o.state, 'not_reserved') END AS quota_state
        FROM picture_word_recognition_attempts a LEFT JOIN picture_word_quota_operations o ON o.operation_id = a.operation_id
        WHERE a.installation_id = $1 AND ($8 = 'All' OR a.environment = $8)
          AND a.started_at >= ($2::date::timestamp AT TIME ZONE 'Asia/Shanghai')
          AND a.started_at < (($3::date + 1)::timestamp AT TIME ZONE 'Asia/Shanghai')
          AND a.started_at >= (((clock_timestamp() AT TIME ZONE 'Asia/Shanghai')::date - 89)::timestamp AT TIME ZONE 'Asia/Shanghai')
      ) SELECT operation_id::text AS "operationId", request_id AS "requestId", started_at AS "startedAt",
        CASE WHEN effective_outcome = 'unfinished' THEN COALESCE(finished_at, started_at + interval '10 minutes') ELSE finished_at END AS "finishedAt",
        environment, effective_outcome AS outcome,
        CASE WHEN effective_outcome = 'unfinished' THEN COALESCE(reason_code, 'ATTEMPT_TIMEOUT') ELSE reason_code END AS "reasonCode",
        stage, CASE WHEN effective_outcome = 'unfinished' THEN COALESCE(duration_ms, 600000) ELSE duration_ms END AS "durationMs",
        app_version AS "appVersion", app_build AS "appBuild", quota_before AS "quotaBefore", quota_after AS "quotaAfter", quota_state AS "quotaState"
      FROM rows WHERE ($4::text IS NULL OR effective_outcome = $4)
        AND ($5::text IS NULL OR position(lower($5) in lower(concat(app_version, ' (', app_build, ')'))) > 0)
        AND ($6::timestamptz IS NULL OR (started_at, operation_id) < ($6::timestamptz, $7::uuid))
      ORDER BY started_at DESC, operation_id DESC LIMIT 51`,
      [query.installationId, query.startDate, query.endDate, query.outcome, query.appVersion,
        query.cursor?.startedAt ?? null, query.cursor?.operationId ?? null, query.environment ?? 'All'],
    );
    const summary = {
      recognitionAttempts: Number(totals.rows[0].attempts), recognitionSuccesses: Number(totals.rows[0].successes),
      confirmationCount: Number(totals.rows[0].confirmations), reselectionCount: Number(totals.rows[0].reselections),
    };
    const page = attempts.rows.slice(0, 50).map(item => ({ ...item,
      startedAt: item.startedAt.toISOString(), finishedAt: item.finishedAt?.toISOString() ?? null,
    }));
    const last = page.at(-1);
    return {
      device: { installationId: row.id, deviceId: row.id.slice(-6), registrationDate: row.registration_date,
        environment: row.environment, membershipType: !row.product_id ? 'free' : row.product_id.endsWith('annual') ? 'annual' : 'monthly',
        freeUsed: row.free_used, ...summary },
      startDate: query.startDate, endDate: query.endDate, recordingStartedAt: metadata.rows[0].recorded_at.toISOString(), summary,
      attempts: page,
      nextCursor: attempts.rows.length > 50 && last
        ? Buffer.from(JSON.stringify({ startedAt: last.startedAt, operationId: last.operationId })).toString('base64url') : null,
    };
  } finally { client.release(); }
}
