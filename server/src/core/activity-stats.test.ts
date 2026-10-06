import assert from 'node:assert/strict';
import test from 'node:test';
import { summarizeActivity, type ActivityDailyRow } from './activity-stats.js';
const row = (installationId: string, date: string, eventName: string, count = 1, environment = 'Production', outcome = ''): ActivityDailyRow => ({
  installationId, date, eventName, count, environment, outcome, firstAt: `${date}T00:00:00Z`, lastAt: `${date}T01:00:00Z`,
});

test('activity deduplicates days, devices and environments across windows while retaining behavior counts', () => {
  const rows = [row('a', '2026-10-01', 'app_foreground', 4), row('a', '2026-10-02', 'app_foreground'),
    row('a', '2026-10-02', 'app_foreground', 2, 'Sandbox'), row('a', '2026-10-02', 'word_play', 3),
    row('a', '2026-10-02', 'listening_answer', 2, 'Production', 'revealed'), row('b', '2026-10-02', 'app_foreground'),
    row('b', '2026-10-02', 'history_view', 5), row('c', '2026-10-02', 'recognition_success'),
    row('d', '2026-09-28', 'app_foreground'), row('e', '2026-09-01', 'app_foreground')];
  const stats = summarizeActivity(rows, '2026-10-01', '2026-10-02', 'All', null);
  assert.equal(stats.visitingDevices, 2); assert.equal(stats.learningDevices, 2);
  assert.equal(stats.participatingVisitors, 1); assert.equal(stats.last7DayDevices, 3); assert.equal(stats.last30DayDevices, 3);
  assert.equal(stats.daily.find(d => d.date === '2026-10-02')?.visitingDevices, 2);
  const a = stats.devices.find(d => d.installationId === 'a')!;
  assert.equal(a.activeDays, 2); assert.equal(a.learningDays, 1); assert.equal(a.listeningRevealed, 2);
  assert.equal(a.wordPlays, 3); assert.equal(a.clientActivityCovered, true);
  assert.equal(stats.devices.find(d => d.installationId === 'c')?.clientActivityCovered, false);
  assert.equal(stats.devices.find(d => d.installationId === 'b')?.learningDays, 0);
});

test('activity filters by historical environment, not a device current environment', () => {
  const rows = [row('a', '2026-10-02', 'app_foreground', 1, 'Sandbox'), row('a', '2026-10-02', 'word_play', 2),
    row('b', '2026-10-02', 'app_foreground', 1, 'Unknown')];
  const production = summarizeActivity(rows, '2026-10-02', '2026-10-02', 'Production', null);
  assert.equal(production.visitingDevices, 0); assert.equal(production.learningDevices, 1);
  assert.equal(production.participatingVisitors, 0);
  assert.equal(summarizeActivity(rows, null, null, 'Unknown', null, '2026-10-02').visitingDevices, 1);
});
