import type { Pool } from 'pg';
import type { AccessEnvironment } from './types.js';

export const activityEventNames = ['app_foreground', 'app_open', 'listening_enter', 'listening_start',
  'listening_answer', 'listening_complete', 'history_view', 'word_play'] as const;
export type ActivityEventName = typeof activityEventNames[number];
export type ActivityEvent = {
  eventId: string; occurredAt: string; eventName: ActivityEventName;
  environment: AccessEnvironment | 'Unknown'; outcome?: 'found' | 'revealed';
  sessionId?: string; appVersion?: string; appBuild?: string;
};

export class ActivityEventStore {
  constructor(private readonly pool: Pool) {}

  async record(installationId: string, events: ActivityEvent[]): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      // Only newly inserted IDs contribute to summaries, including concurrent retries.
      await client.query(
        `WITH inserted AS (
          INSERT INTO picture_word_activity_events
            (event_id, installation_id, occurred_at, environment, event_name, outcome, session_id, app_version, app_build)
          SELECT x."eventId"::uuid, $1::uuid, x."occurredAt"::timestamptz, x.environment, x."eventName",
            COALESCE(x.outcome, ''), x."sessionId"::uuid, x."appVersion", x."appBuild"
          FROM jsonb_to_recordset($2::jsonb) AS x("eventId" text, "occurredAt" text, environment text,
            "eventName" text, outcome text, "sessionId" text, "appVersion" text, "appBuild" text)
          WHERE x."occurredAt"::timestamptz <= clock_timestamp() + interval '5 minutes'
            AND x."occurredAt"::timestamptz >=
              (((clock_timestamp() AT TIME ZONE 'Asia/Shanghai')::date - 89)::timestamp AT TIME ZONE 'Asia/Shanghai')
          ON CONFLICT (event_id) DO NOTHING
          RETURNING *
        )
        INSERT INTO picture_word_activity_daily
          (installation_id, metric_date, environment, event_name, outcome, event_count, first_at, last_at)
        SELECT installation_id, (occurred_at AT TIME ZONE 'Asia/Shanghai')::date,
          environment, event_name, outcome, COUNT(*), MIN(occurred_at), MAX(occurred_at)
        FROM inserted GROUP BY 1, 2, 3, 4, 5
        ON CONFLICT (installation_id, metric_date, environment, event_name, outcome) DO UPDATE
        SET event_count = picture_word_activity_daily.event_count + EXCLUDED.event_count,
          first_at = LEAST(picture_word_activity_daily.first_at, EXCLUDED.first_at),
          last_at = GREATEST(picture_word_activity_daily.last_at, EXCLUDED.last_at)`,
        [installationId, JSON.stringify(events)],
      );
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally { client.release(); }
  }

  async maintain(): Promise<void> {
    let deleted: number;
    do {
      const result = await this.pool.query(`DELETE FROM picture_word_activity_events WHERE event_id IN
        (SELECT event_id FROM picture_word_activity_events WHERE occurred_at <
          (((clock_timestamp() AT TIME ZONE 'Asia/Shanghai')::date - 89)::timestamp AT TIME ZONE 'Asia/Shanghai')
         ORDER BY occurred_at LIMIT 10000)`);
      deleted = result.rowCount ?? 0;
    } while (deleted === 10000);
  }
}
