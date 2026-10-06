import 'dotenv/config';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { Pool } from 'pg';
import { ActivityEventStore, type ActivityEvent } from './activity.js';
import { PostgresAdminStatsRepository } from '../admin-stats.js';
import { shiftActivityDate } from '../activity-stats.js';

const databaseURL = process.env.TEST_DATABASE_URL?.trim();
test('activity SQL is atomic, retry-safe, environment-aware and paginated without losing old-device activity', {
  skip: !databaseURL && 'TEST_DATABASE_URL is not configured',
}, async t => {
  assert.ok(databaseURL);
  const schema = `pw_activity_${process.pid}_${Date.now()}`;
  const admin = new Pool({ connectionString: databaseURL });
  await admin.query(`CREATE SCHEMA ${schema}`);
  t.after(async () => { await admin.query(`DROP SCHEMA ${schema} CASCADE`); await admin.end(); });
  const url = new URL(databaseURL); url.searchParams.set('options', `-c search_path=${schema}`);
  const pool = new Pool({ connectionString: url.toString() });
  const repository = new PostgresAdminStatsRepository(url.toString());
  t.after(async () => { await repository.close(); await pool.end(); });
  for (const migration of ['002_subscriptions', '003_subscription_transactions', '004_recognition_feedback',
    '005_installation_stats', '006_installation_environment', '007_recognition_attempts', '008_activity_events']) {
    await pool.query(await readFile(new URL(`../../../migrations/${migration}.sql`, import.meta.url), 'utf8'));
  }
  const installationId = randomUUID();
  await pool.query(`INSERT INTO picture_word_installations (id, installation_hash, store_environment, created_at)
    VALUES ($1, $2, 'Production', clock_timestamp() - interval '120 days')`, [installationId, 'b'.repeat(64)]);
  const store = new ActivityEventStore(pool);
  const today = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Shanghai' });
  const yesterday = shiftActivityDate(today, -1);
  const event = (eventName: ActivityEvent['eventName'], occurredAt = new Date().toISOString(), environment: ActivityEvent['environment'] = 'Sandbox'): ActivityEvent => ({
    eventId: randomUUID(), eventName, occurredAt, environment,
  });
  const oldDayVisit = event('app_foreground', `${yesterday}T23:59:59.999+08:00`);
  const newDayVisit = event('app_foreground', `${today}T00:00:00+08:00`);
  await Promise.all([store.record(installationId, [oldDayVisit, newDayVisit]), store.record(installationId, [oldDayVisit, newDayVisit])]);
  const overview = await repository.load(today, today, 'Sandbox');
  assert.equal(overview.activity.visitingDevices, 1);
  assert.equal(overview.activity.last7DayDevices, 1);
  assert.equal(overview.installations.devices[0].installationId, installationId); // Current device environment is Production.
  assert.equal(overview.activity.behaviors[0].count, 1);
  assert.equal(overview.installations.total, 0); // Registered before the selected date.
  const query = { installationId, startDate: yesterday, endDate: today, environment: 'Sandbox' as const, cursor: null };
  const detail = await repository.loadDeviceActivity(query);
  assert.equal(detail?.summary.activeDays, 2);
  assert.equal(detail?.events.length, 2);
  assert.equal((await repository.loadDeviceActivity({ ...query, startDate: today }))?.events.length, 1);
  assert.equal((await repository.loadDeviceActivity({ ...query, environment: 'Production' }))?.events.length, 0);

  await pool.query(`CREATE FUNCTION reject_activity() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'activity aggregate failure'; END $$`);
  await pool.query(`CREATE TRIGGER reject_activity BEFORE INSERT ON picture_word_activity_daily FOR EACH ROW EXECUTE FUNCTION reject_activity()`);
  const failed = event('history_view');
  await assert.rejects(store.record(installationId, [failed]), /activity aggregate failure/);
  assert.equal((await pool.query('SELECT 1 FROM picture_word_activity_events WHERE event_id = $1', [failed.eventId])).rowCount, 0);
  await pool.query('DROP TRIGGER reject_activity ON picture_word_activity_daily');

  await store.record(installationId, Array.from({ length: 52 }, () => event('word_play')));
  const page1 = await repository.loadDeviceActivity(query); assert.ok(page1?.nextCursor);
  const page2 = await repository.loadDeviceActivity({ ...query, cursor: JSON.parse(Buffer.from(page1.nextCursor, 'base64url').toString()) });
  assert.equal(page1.events.length, 50); assert.equal(page2?.events.length, 4);
  assert.equal(new Set([...page1.events, ...page2!.events].map(e => e.eventId)).size, 54);
  assert.equal(page1.summary.wordPlays, 52);

  await store.record(installationId, [event('history_view', `${shiftActivityDate(today, -90)}T23:59:59+08:00`),
    event('history_view', new Date(Date.now() + 86400000).toISOString())]);
  assert.equal((await repository.loadDeviceActivity(query))?.summary.historyViews, 0);
  // Seed an expired event and its already-aggregated day. Cleanup must leave summaries intact.
  const oldDate = shiftActivityDate(today, -91), oldId = randomUUID();
  await pool.query(`INSERT INTO picture_word_activity_events (event_id, installation_id, occurred_at, environment, event_name)
    VALUES ($1, $2, $3, 'Sandbox', 'app_open')`, [oldId, installationId, `${oldDate}T12:00:00+08:00`]);
  await pool.query(`INSERT INTO picture_word_activity_daily (installation_id, metric_date, environment, event_name, event_count, first_at, last_at)
    VALUES ($1, $2, 'Sandbox', 'app_open', 1, $3, $3)`, [installationId, oldDate, `${oldDate}T12:00:00+08:00`]);
  await store.maintain();
  assert.equal((await pool.query('SELECT 1 FROM picture_word_activity_events WHERE event_id = $1', [oldId])).rowCount, 0);
  assert.equal((await repository.load(oldDate, oldDate, 'Sandbox')).activity.behaviors[0].count, 1);
});
