import 'dotenv/config';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { Pool } from 'pg';
import { RecognitionAttemptStore } from './recognition-attempts.js';
import { PostgresAdminStatsRepository } from '../admin-stats.js';
import type { QuotaSnapshot, RecognitionAttemptInput } from './types.js';

const databaseURL = process.env.TEST_DATABASE_URL?.trim();
test('recognition details are atomic, idempotent, paginated and retained independently of daily summaries', {
  skip: !databaseURL && 'TEST_DATABASE_URL is not configured',
}, async t => {
  assert.ok(databaseURL);
  const schema = `pw_attempts_${process.pid}_${Date.now()}`;
  const admin = new Pool({ connectionString: databaseURL });
  await admin.query(`CREATE SCHEMA ${schema}`);
  t.after(async () => { await admin.query(`DROP SCHEMA ${schema} CASCADE`); await admin.end(); });
  const url = new URL(databaseURL); url.searchParams.set('options', `-c search_path=${schema}`);
  const pool = new Pool({ connectionString: url.toString() });
  const repository = new PostgresAdminStatsRepository(url.toString());
  t.after(async () => { await repository.close(); await pool.end(); });
  for (const migration of ['002_subscriptions', '003_subscription_transactions', '004_recognition_feedback', '005_installation_stats', '006_installation_environment', '007_recognition_attempts']) {
    await pool.query(await readFile(new URL(`../../../migrations/${migration}.sql`, import.meta.url), 'utf8'));
  }
  const installationId = randomUUID();
  await pool.query(`INSERT INTO picture_word_installations (id, installation_hash, store_environment) VALUES ($1, $2, 'Sandbox')`, [installationId, 'a'.repeat(64)]);
  const store = new RecognitionAttemptStore(pool);
  const quota: QuotaSnapshot = { tier: 'free', limit: 3, used: 0, reserved: 0, remaining: 3, periodStart: null, resetAt: null };
  const input: RecognitionAttemptInput = { installationId, operationId: randomUUID(), requestId: 'test', startedAt: new Date(), environment: 'Sandbox', appVersion: '1.2.0', appBuild: '35', quotaBefore: quota };
  assert.deepEqual((await Promise.all([store.begin(input), store.begin(input)])).sort(), [false, true]);
  await pool.query(`INSERT INTO picture_word_quota_operations (operation_id, installation_id, subject_type, subject_id, state, lease_expires_at) VALUES ($1, $2::uuid, 'free', $2::text, 'committed', clock_timestamp() + interval '10 minutes')`, [input.operationId, installationId]);
  const finished = { installationId, operationId: input.operationId, outcome: 'success' as const, reasonCode: null, stage: 'serialize_response', quotaAfter: { ...quota, used: 1, remaining: 2 } };
  await Promise.all([store.finish(finished), store.finish(finished)]);
  await store.finish({ ...finished, outcome: 'cancelled', reasonCode: 'CLIENT_DISCONNECTED' });
  const today = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Shanghai' });
  const shift = (day: string, count: number) => { const date = new Date(day + 'T00:00:00Z'); date.setUTCDate(date.getUTCDate() + count); return date.toISOString().slice(0, 10); };
  const query = { installationId, startDate: shift(today, -89), endDate: today, outcome: null, appVersion: null, cursor: null };
  const first = await repository.loadDeviceDetails(query);
  assert.ok(first);
  assert.equal(first.summary.recognitionAttempts, 1);
  assert.equal(first.summary.recognitionSuccesses, 1);
  assert.equal(first.attempts[0].outcome, 'success');
  assert.equal(first.attempts[0].quotaState, 'committed');
  assert.equal(first.attempts[0].quotaAfter?.used, 1);
  assert.equal(first.device.installationId, installationId);

  // Force counter insertion failure: neither the diagnostic row nor daily counter may survive.
  await pool.query(`CREATE FUNCTION reject_attempt_metric() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'simulated aggregate failure'; END $$`);
  await pool.query(`CREATE TRIGGER reject_metric BEFORE INSERT ON picture_word_installation_metrics_daily FOR EACH ROW EXECUTE FUNCTION reject_attempt_metric()`);
  const rejected = { ...input, operationId: randomUUID() };
  await assert.rejects(store.begin(rejected), /simulated aggregate failure/);
  assert.equal((await pool.query('SELECT 1 FROM picture_word_recognition_attempts WHERE operation_id=$1', [rejected.operationId])).rowCount, 0);
  await pool.query('DROP TRIGGER reject_metric ON picture_word_installation_metrics_daily');

  for (let i = 0; i < 52; i++) await store.begin({ ...input, operationId: randomUUID(), appVersion: null, appBuild: null });
  const page1 = await repository.loadDeviceDetails(query); assert.ok(page1?.nextCursor);
  assert.equal(page1.attempts.length, 50);
  const page2 = await repository.loadDeviceDetails({ ...query, cursor: JSON.parse(Buffer.from(page1.nextCursor, 'base64url').toString()) }); assert.ok(page2);
  assert.equal(page2.attempts.length, 3);
  assert.equal(page2.nextCursor, null);
  assert.equal(new Set([...page1.attempts, ...page2.attempts].map(x => x.operationId)).size, 53);
  const filtered = await repository.loadDeviceDetails({ ...query, outcome: 'success', appVersion: '35' });
  assert.equal(filtered?.attempts.length, 1);
  assert.equal(filtered?.summary.recognitionAttempts, 53); // Result filters do not distort success rates.

  const expired = { ...input, operationId: randomUUID(), startedAt: new Date(Date.now() - 11 * 60 * 1000) };
  await store.begin(expired);
  const unfinished = await repository.loadDeviceDetails({ ...query, outcome: 'unfinished' });
  assert.equal(unfinished?.attempts[0].operationId, expired.operationId);
  const old = { ...input, operationId: randomUUID(), startedAt: new Date(Date.now() - 91 * 86400000) };
  await store.begin(old); await store.maintain();
  assert.equal((await pool.query('SELECT 1 FROM picture_word_recognition_attempts WHERE operation_id=$1', [old.operationId])).rowCount, 0);
  assert.equal((await pool.query('SELECT outcome FROM picture_word_recognition_attempts WHERE operation_id=$1', [expired.operationId])).rows[0].outcome, 'unfinished');
  assert.ok((await pool.query(`SELECT 1 FROM picture_word_installation_metrics_daily WHERE metric_date < $1::date`, [query.startDate])).rowCount);

  // Exact Beijing start/end boundaries, plus incomplete after-snapshots and missing version metadata.
  const yesterday = shift(today, -1);
  await store.begin({ ...input, operationId: randomUUID(), startedAt: new Date(yesterday + 'T00:00:00+08:00'), appVersion: 'boundary' });
  await store.begin({ ...input, operationId: randomUUID(), startedAt: new Date(yesterday + 'T23:59:59.999+08:00'), appVersion: 'boundary' });
  await store.begin({ ...input, operationId: randomUUID(), startedAt: new Date(today + 'T00:00:00+08:00'), appVersion: 'boundary' });
  const boundary = await repository.loadDeviceDetails({ ...query, startDate: yesterday, endDate: yesterday, appVersion: 'boundary' });
  assert.equal(boundary?.attempts.length, 2);
  assert.equal((await repository.loadDeviceDetails({ ...query, installationId: randomUUID() })), null);
});
