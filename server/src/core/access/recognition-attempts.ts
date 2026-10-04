import type { Pool } from 'pg';
import type { RecognitionAttemptInput, RecognitionAttemptResult } from './types.js';

// Store no images, model output, raw provider errors, tokens, or IP addresses.
export class RecognitionAttemptStore {
  constructor(private readonly pool: Pool) {}

  async begin(input: RecognitionAttemptInput): Promise<boolean> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const inserted = await client.query(
        `INSERT INTO picture_word_recognition_attempts
         (operation_id, installation_id, request_id, started_at, environment, app_version, app_build, quota_before)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8) ON CONFLICT (operation_id) DO NOTHING RETURNING operation_id`,
        [input.operationId, input.installationId, input.requestId, input.startedAt,
          input.environment ?? 'Unknown', input.appVersion, input.appBuild, JSON.stringify(input.quotaBefore)],
      );
      if (inserted.rowCount) {
        await client.query(
          `INSERT INTO picture_word_installation_metrics_daily
           (installation_id, metric_date, environment, recognition_attempt_count)
           VALUES ($1, ($2::timestamptz AT TIME ZONE 'Asia/Shanghai')::date, $3, 1)
           ON CONFLICT (installation_id, metric_date, environment) DO UPDATE
           SET recognition_attempt_count = picture_word_installation_metrics_daily.recognition_attempt_count + 1,
               updated_at = clock_timestamp()`,
          [input.installationId, input.startedAt, input.environment ?? 'Unknown'],
        );
      }
      await client.query('COMMIT');
      return Boolean(inserted.rowCount);
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally { client.release(); }
  }

  async finish(result: RecognitionAttemptResult): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const updated = await client.query<{ started_at: Date; environment: string }>(
        `UPDATE picture_word_recognition_attempts
         SET outcome = $3, reason_code = $4, stage = $5, quota_after = $6,
             finished_at = clock_timestamp(),
             duration_ms = LEAST(2147483647, GREATEST(0, EXTRACT(EPOCH FROM (clock_timestamp() - started_at)) * 1000))::integer
         WHERE operation_id = $1 AND installation_id = $2 AND outcome IN ('processing', 'unfinished')
         RETURNING started_at, environment`,
        [result.operationId, result.installationId, result.outcome, result.reasonCode, result.stage,
          result.quotaAfter ? JSON.stringify(result.quotaAfter) : null],
      );
      const row = updated.rows[0];
      if (row && result.outcome === 'success') {
        await client.query(
          `INSERT INTO picture_word_installation_metrics_daily
           (installation_id, metric_date, environment, recognition_success_count)
           VALUES ($1, ($2::timestamptz AT TIME ZONE 'Asia/Shanghai')::date, $3, 1)
           ON CONFLICT (installation_id, metric_date, environment) DO UPDATE
           SET recognition_success_count = picture_word_installation_metrics_daily.recognition_success_count + 1,
               updated_at = clock_timestamp()`,
          [result.installationId, row.started_at, row.environment],
        );
      }
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally { client.release(); }
  }

  async maintain(): Promise<void> {
    await this.pool.query(
      `UPDATE picture_word_recognition_attempts SET outcome = 'unfinished', reason_code = 'ATTEMPT_TIMEOUT',
         finished_at = started_at + interval '10 minutes', duration_ms = 600000
       WHERE outcome = 'processing' AND started_at <= clock_timestamp() - interval '10 minutes'`,
    );
    // Bound each transaction so expiry cannot hold locks for the whole history.
    let deleted: number;
    do {
      const result = await this.pool.query(
        `DELETE FROM picture_word_recognition_attempts WHERE operation_id IN
         (SELECT operation_id FROM picture_word_recognition_attempts
          WHERE started_at < ((clock_timestamp() AT TIME ZONE 'Asia/Shanghai')::date - 89)::timestamp AT TIME ZONE 'Asia/Shanghai'
          ORDER BY started_at LIMIT 10000)`,
      );
      deleted = result.rowCount ?? 0;
    } while (deleted === 10000);
  }
}
