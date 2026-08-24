import "dotenv/config";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { Pool } from "pg";
import { PostgresAnalyzeUsageLimiter } from "./postgres.js";
const testDatabaseURL = process.env.TEST_DATABASE_URL?.trim();
const logger = {
    debug() { },
    info() { },
    warn() { },
    error() { },
};
test("PostgreSQL limits are atomic, persistent, and clean stale buckets", {
    skip: !testDatabaseURL && "TEST_DATABASE_URL is not configured",
}, async (t) => {
    assert.ok(testDatabaseURL);
    const schema = `picture_word_test_${process.pid}_${Date.now()}`;
    const adminPool = new Pool({ connectionString: testDatabaseURL });
    await adminPool.query(`CREATE SCHEMA ${schema}`);
    t.after(async () => {
        await adminPool.query(`DROP SCHEMA IF EXISTS ${schema} CASCADE`);
        await adminPool.end();
    });
    const isolatedURL = new URL(testDatabaseURL);
    isolatedURL.searchParams.set("options", `-c search_path=${schema}`);
    const migration = await readFile(new URL("../../../migrations/001_usage_limits.sql", import.meta.url), "utf8");
    const setupPool = new Pool({ connectionString: isolatedURL.toString() });
    await setupPool.query(migration);
    await setupPool.query(migration);
    await setupPool.query(`INSERT INTO picture_word_rate_limit_buckets (scope, subject_hash, tokens, updated_at)
     VALUES ('stale', repeat('0', 64), 0, CURRENT_TIMESTAMP - INTERVAL '25 hours')`);
    const limiter = new PostgresAnalyzeUsageLimiter({
        databaseURL: isolatedURL.toString(),
        ipHashSecret: "integration-secret-with-at-least-32-characters",
        perMinute: 10,
        dailyLimit: 5,
        dailyTimeZone: "Asia/Shanghai",
    }, logger);
    t.after(async () => {
        await limiter.close();
        await setupPool.end();
    });
    const minuteDecisions = await Promise.all(Array.from({ length: 11 }, () => limiter.consumeMinute("203.0.113.20")));
    assert.equal(minuteDecisions.filter((decision) => decision.allowed).length, 10);
    const minuteRejection = minuteDecisions.find((decision) => !decision.allowed);
    assert.ok(minuteRejection && minuteRejection.retryAfterSeconds >= 1);
    const storedBuckets = await setupPool.query("SELECT subject_hash FROM picture_word_rate_limit_buckets WHERE scope = 'analyze-minute'");
    assert.equal(storedBuckets.rows.length, 1);
    assert.equal(storedBuckets.rows[0]?.subject_hash.length, 64);
    assert.notEqual(storedBuckets.rows[0]?.subject_hash, "203.0.113.20");
    const staleBuckets = await setupPool.query("SELECT COUNT(*)::integer AS count FROM picture_word_rate_limit_buckets WHERE scope = 'stale'");
    assert.equal(staleBuckets.rows[0]?.count, 0);
    const dailyDecisions = await Promise.all(Array.from({ length: 6 }, () => limiter.consumeDaily()));
    assert.equal(dailyDecisions.filter((decision) => decision.allowed).length, 5);
    const dailyRejection = dailyDecisions.find((decision) => !decision.allowed);
    assert.ok(dailyRejection && dailyRejection.retryAfterSeconds > 0);
    assert.ok(dailyRejection.retryAfterSeconds <= 24 * 60 * 60);
    await setupPool.query(`DELETE FROM picture_word_daily_usage
     WHERE usage_date = (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Shanghai')::date`);
    await setupPool.query(`INSERT INTO picture_word_daily_usage (scope, usage_date, request_count, updated_at)
     VALUES (
       'analyze-global',
       (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Shanghai')::date - 1,
       5,
       CURRENT_TIMESTAMP
     )`);
    assert.equal((await limiter.consumeDaily()).allowed, true);
});
