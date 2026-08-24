import { createHmac } from "node:crypto";
import { isIP } from "node:net";
import { Pool } from "pg";
import { errorFields, type Logger } from "../../utils/logger.js";
import type { AnalyzeUsageLimiter, UsageLimitDecision } from "./types.js";

type PostgresUsageLimiterConfig = {
  databaseURL: string;
  ipHashSecret: string;
  perMinute: number;
  dailyLimit: number;
  dailyTimeZone: string;
};

type TokenBucketRow = {
  remaining: number;
};

type RetryRow = {
  retry_after_seconds: number;
};

type DailyUsageRow = {
  request_count: number | null;
  retry_after_seconds: number;
};

const MINUTE_SCOPE = "analyze-minute";
const DAILY_SCOPE = "analyze-global";
const CLEANUP_INTERVAL_MS = 60 * 60 * 1_000;

export class PostgresAnalyzeUsageLimiter implements AnalyzeUsageLimiter {
  private readonly pool: Pool;
  private nextCleanupAt = 0;

  constructor(
    private readonly config: PostgresUsageLimiterConfig,
    private readonly logger: Logger,
  ) {
    this.pool = new Pool({ connectionString: config.databaseURL });
  }

  async consumeMinute(clientIP: string): Promise<UsageLimitDecision> {
    if (isIP(clientIP) === 0) throw new Error("Client IP is unavailable or invalid");

    const subjectHash = createHmac("sha256", this.config.ipHashSecret)
      .update(clientIP)
      .digest("hex");
    const result = await this.pool.query<TokenBucketRow>(
      `
        INSERT INTO picture_word_rate_limit_buckets (scope, subject_hash, tokens, updated_at)
        VALUES ($1, $2, $3::double precision - 1, clock_timestamp())
        ON CONFLICT (scope, subject_hash) DO UPDATE
        SET
          tokens = LEAST(
            $3::double precision,
            picture_word_rate_limit_buckets.tokens
              + GREATEST(
                  0,
                  EXTRACT(EPOCH FROM (clock_timestamp() - picture_word_rate_limit_buckets.updated_at))
                ) * $3::double precision / 60
          ) - 1,
          updated_at = clock_timestamp()
        WHERE LEAST(
          $3::double precision,
          picture_word_rate_limit_buckets.tokens
            + GREATEST(
                0,
                EXTRACT(EPOCH FROM (clock_timestamp() - picture_word_rate_limit_buckets.updated_at))
              ) * $3::double precision / 60
        ) >= 1
        RETURNING FLOOR(tokens)::integer AS remaining
      `,
      [MINUTE_SCOPE, subjectHash, this.config.perMinute],
    );

    await this.cleanupStaleBucketsIfNeeded();

    const row = result.rows[0];
    if (row) return { allowed: true, remaining: row.remaining };

    const retry = await this.pool.query<RetryRow>(
      `
        SELECT GREATEST(
          1,
          CEIL(
            GREATEST(
              0,
              1 - LEAST(
                $3::double precision,
                tokens
                  + GREATEST(0, EXTRACT(EPOCH FROM (clock_timestamp() - updated_at)))
                    * $3::double precision / 60
              )
            ) * 60 / $3::double precision
          )
        )::integer AS retry_after_seconds
        FROM picture_word_rate_limit_buckets
        WHERE scope = $1 AND subject_hash = $2
      `,
      [MINUTE_SCOPE, subjectHash, this.config.perMinute],
    );
    return { allowed: false, retryAfterSeconds: retry.rows[0]?.retry_after_seconds ?? 6 };
  }

  async consumeDaily(): Promise<UsageLimitDecision> {
    const result = await this.pool.query<DailyUsageRow>(
      `
        WITH current_day AS (
          SELECT (CURRENT_TIMESTAMP AT TIME ZONE $1::text)::date AS usage_date
        ), consumed AS (
          INSERT INTO picture_word_daily_usage (scope, usage_date, request_count, updated_at)
          SELECT $2, usage_date, 1, clock_timestamp()
          FROM current_day
          ON CONFLICT (scope, usage_date) DO UPDATE
          SET
            request_count = picture_word_daily_usage.request_count + 1,
            updated_at = clock_timestamp()
          WHERE picture_word_daily_usage.request_count < $3
          RETURNING request_count
        )
        SELECT
          consumed.request_count,
          GREATEST(
            1,
            CEIL(EXTRACT(EPOCH FROM (
              ((current_day.usage_date + 1)::timestamp AT TIME ZONE $1::text)
                - CURRENT_TIMESTAMP
            )))
          )::integer AS retry_after_seconds
        FROM current_day
        LEFT JOIN consumed ON TRUE
      `,
      [this.config.dailyTimeZone, DAILY_SCOPE, this.config.dailyLimit],
    );

    const row = result.rows[0];
    if (row?.request_count != null) {
      return { allowed: true, remaining: Math.max(0, this.config.dailyLimit - row.request_count) };
    }
    return { allowed: false, retryAfterSeconds: row?.retry_after_seconds ?? 60 };
  }

  async close(): Promise<void> {
    await this.pool.end();
  }

  private async cleanupStaleBucketsIfNeeded(): Promise<void> {
    const now = Date.now();
    if (now < this.nextCleanupAt) return;
    this.nextCleanupAt = now + CLEANUP_INTERVAL_MS;

    try {
      const result = await this.pool.query(
        "DELETE FROM picture_word_rate_limit_buckets WHERE updated_at < CURRENT_TIMESTAMP - INTERVAL '24 hours'",
      );
      if ((result.rowCount ?? 0) > 0) {
        this.logger.info("usage_limit.buckets_cleaned", { deletedCount: result.rowCount });
      }
    } catch (error) {
      this.logger.warn("usage_limit.cleanup_failed", {
        ...errorFields(error),
      });
    }
  }
}
