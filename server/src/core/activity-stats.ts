import type { Pool, PoolClient } from 'pg';
import type { AdminStatsEnvironment } from './admin-stats.js';

export type ActivityDailyRow = {
  installationId: string; date: string; environment: string; eventName: string; outcome: string;
  count: number; firstAt: string; lastAt: string;
};
export type ActivityDeviceSummary = {
  installationId: string; clientActivityCovered: boolean; activeDays: number; learningDays: number; lastActiveAt: string | null;
  opens: number; recognitionAttempts: number; recognitionSuccesses: number; listeningEnters: number;
  listeningStarts: number; listeningAnswers: number; listeningFound: number; listeningRevealed: number;
  listeningCompletions: number; historyViews: number; wordPlays: number;
};
export type ActivityOverview = {
  recordingStartedAt: string | null; startDate: string | null; endDate: string | null; environment: string;
  visitingDevices: number; learningDevices: number; participatingVisitors: number;
  last7DayDevices: number; last30DayDevices: number; windowEndDate: string;
  daily: Array<{ date: string; visitingDevices: number; learningDevices: number; opens: number }>;
  behaviors: Array<{ eventName: string; count: number; devices: number }>;
  devices: ActivityDeviceSummary[];
};
const learningEvents = new Set(['recognition_success', 'word_play', 'listening_answer']);
// A single source for recognition counts: never accept recognition events from the client.
export const activityDailySQL = `
  SELECT installation_id::text AS "installationId", metric_date::text AS date, environment,
    event_name AS "eventName", outcome, event_count::text AS count, first_at AS "firstAt", last_at AS "lastAt"
  FROM picture_word_activity_daily
  UNION ALL
  SELECT m.installation_id::text, m.metric_date::text, m.environment, x.name, '', x.count::text,
    COALESCE(a.first_at, m.metric_date::timestamp AT TIME ZONE 'Asia/Shanghai'),
    COALESCE(a.last_at, m.metric_date::timestamp AT TIME ZONE 'Asia/Shanghai')
  FROM picture_word_installation_metrics_daily m
  CROSS JOIN LATERAL (VALUES ('recognition_attempt', m.recognition_attempt_count),
    ('recognition_success', m.recognition_success_count)) x(name, count)
  LEFT JOIN LATERAL (
    SELECT MIN(started_at) AS first_at, MAX(started_at) AS last_at FROM picture_word_recognition_attempts
    WHERE installation_id = m.installation_id AND environment = m.environment
      AND started_at >= (m.metric_date::timestamp AT TIME ZONE 'Asia/Shanghai')
      AND started_at < ((m.metric_date + 1)::timestamp AT TIME ZONE 'Asia/Shanghai')
      AND (x.name = 'recognition_attempt' OR outcome = 'success')
  ) a ON TRUE WHERE x.count > 0`;

const lastKnownActivitySQL = `
  SELECT installation_id, environment, last_at FROM picture_word_activity_daily
  UNION ALL SELECT installation_id, environment, started_at FROM picture_word_recognition_attempts
  UNION ALL SELECT installation_id, environment, metric_date::timestamp AT TIME ZONE 'Asia/Shanghai'
    FROM picture_word_installation_metrics_daily WHERE recognition_attempt_count > 0`;

export function shiftActivityDate(value: string, days: number): string {
  const date = new Date(`${value}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}
function today(): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Shanghai', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
}
export function summarizeActivity(rows: ActivityDailyRow[], startDate: string | null, endDate: string | null,
  environment: AdminStatsEnvironment | 'Unknown', recordingStartedAt: string | null, windowEndDate = endDate ?? today()): ActivityOverview {
  const filtered = rows.filter(row => environment === 'All' || row.environment === environment);
  const inRange = filtered.filter(row => (!startDate || row.date >= startDate) && (!endDate || row.date <= endDate));
  const visitors = new Set<string>(), learners = new Set<string>();
  const days = new Map<string, { visitors: Set<string>; learners: Set<string>; opens: number }>();
  const behavior = new Map<string, { count: number; devices: Set<string> }>();
  const devices = new Map<string, { summary: ActivityDeviceSummary; active: Set<string>; learning: Set<string> }>();
  for (const row of inRange) {
    if (row.count <= 0) continue;
    const day = days.get(row.date) ?? { visitors: new Set<string>(), learners: new Set<string>(), opens: 0 };
    days.set(row.date, day);
    const metric = behavior.get(row.eventName) ?? { count: 0, devices: new Set<string>() };
    metric.count += row.count; metric.devices.add(row.installationId); behavior.set(row.eventName, metric);
    const item = devices.get(row.installationId) ?? { summary: emptyActivityDevice(row.installationId), active: new Set<string>(), learning: new Set<string>() };
    devices.set(row.installationId, item);
    item.active.add(row.date);
    if (!row.eventName.startsWith('recognition_')) item.summary.clientActivityCovered = true;
    if (!item.summary.lastActiveAt || row.lastAt > item.summary.lastActiveAt) item.summary.lastActiveAt = row.lastAt;
    if (row.eventName === 'app_foreground') { visitors.add(row.installationId); day.visitors.add(row.installationId); }
    if (learningEvents.has(row.eventName)) { learners.add(row.installationId); day.learners.add(row.installationId); item.learning.add(row.date); }
    const mapping: Record<string, keyof ActivityDeviceSummary> = {
      app_open: 'opens', recognition_attempt: 'recognitionAttempts', recognition_success: 'recognitionSuccesses',
      listening_enter: 'listeningEnters', listening_start: 'listeningStarts', listening_answer: 'listeningAnswers',
      listening_complete: 'listeningCompletions', history_view: 'historyViews', word_play: 'wordPlays',
    };
    const field = mapping[row.eventName];
    if (field) (item.summary[field] as number) += row.count;
    if (row.eventName === 'app_open') day.opens += row.count;
    if (row.eventName === 'listening_answer' && row.outcome === 'found') item.summary.listeningFound += row.count;
    if (row.eventName === 'listening_answer' && row.outcome === 'revealed') item.summary.listeningRevealed += row.count;
  }
  const windowDevices = (length: number) => new Set(filtered.filter(row => row.eventName === 'app_foreground'
    && row.date >= shiftActivityDate(windowEndDate, -(length - 1)) && row.date <= windowEndDate && row.count > 0).map(row => row.installationId)).size;
  return {
    recordingStartedAt, startDate, endDate, environment, windowEndDate,
    visitingDevices: visitors.size, learningDevices: learners.size,
    participatingVisitors: [...visitors].filter(id => learners.has(id)).length,
    last7DayDevices: windowDevices(7), last30DayDevices: windowDevices(30),
    daily: [...days].sort(([a], [b]) => a.localeCompare(b)).map(([date, day]) => ({ date, visitingDevices: day.visitors.size, learningDevices: day.learners.size, opens: day.opens })),
    behaviors: [...behavior].map(([eventName, value]) => ({ eventName, count: value.count, devices: value.devices.size })),
    devices: [...devices.values()].map(item => ({ ...item.summary, activeDays: item.active.size, learningDays: item.learning.size })),
  };
}
export function emptyActivityDevice(installationId: string): ActivityDeviceSummary {
  return { installationId, clientActivityCovered: false, activeDays: 0, learningDays: 0, lastActiveAt: null, opens: 0, recognitionAttempts: 0,
    recognitionSuccesses: 0, listeningEnters: 0, listeningStarts: 0, listeningAnswers: 0, listeningFound: 0,
    listeningRevealed: 0, listeningCompletions: 0, historyViews: 0, wordPlays: 0 };
}
async function recordingStart(client: PoolClient): Promise<string | null> {
  const result = await client.query<{ recorded_at: Date }>(`SELECT recorded_at FROM picture_word_stats_metadata WHERE name = 'activity_events_started'`);
  return result.rows[0]?.recorded_at.toISOString() ?? null;
}
function normalizeRows(rows: Array<Omit<ActivityDailyRow, 'count' | 'firstAt' | 'lastAt'> & { count: string; firstAt: Date; lastAt: Date }>): ActivityDailyRow[] {
  return rows.map(row => ({ ...row, count: Number(row.count), firstAt: row.firstAt.toISOString(), lastAt: row.lastAt.toISOString() }));
}
export async function loadActivityOverview(client: PoolClient, startDate: string | null, endDate: string | null, environment: AdminStatsEnvironment): Promise<ActivityOverview> {
  const anchor = endDate ?? today(), windowStart = shiftActivityDate(anchor, -29);
  const earliest = startDate ? (startDate < windowStart ? startDate : windowStart) : null;
  const result = await client.query(`WITH activity AS (${activityDailySQL}) SELECT * FROM activity
    WHERE ($1::date IS NULL OR date::date >= $1::date) AND ($2::date IS NULL OR date::date <= $2::date)
      AND ($3 = 'All' OR environment = $3)`, [earliest, endDate, environment]);
  const overview = summarizeActivity(normalizeRows(result.rows), startDate, endDate, environment, await recordingStart(client), anchor);
  const latest = await client.query<{ installation_id: string; last_at: Date }>(`SELECT installation_id::text, MAX(last_at) AS last_at
    FROM (${lastKnownActivitySQL}) known WHERE ($1 = 'All' OR environment = $1) GROUP BY installation_id`, [environment]);
  const lastByDevice = new Map(latest.rows.map(row => [row.installation_id, row.last_at.toISOString()]));
  for (const device of overview.devices) device.lastActiveAt = lastByDevice.get(device.installationId) ?? device.lastActiveAt;
  return overview;
}
export type DeviceActivityQuery = {
  installationId: string; startDate: string; endDate: string; environment: AdminStatsEnvironment;
  cursor: { occurredAt: string; eventId: string } | null;
};
export type DeviceActivity = {
  summary: ActivityDeviceSummary; recordingStartedAt: string | null; daily: ActivityDailyRow[];
  events: Array<{ eventId: string; occurredAt: string; eventName: string; environment: string; outcome: string; sessionId: string | null; appVersion: string | null; appBuild: string | null }>;
  nextCursor: string | null;
};
export async function loadDeviceActivity(pool: Pool, query: DeviceActivityQuery): Promise<DeviceActivity | null> {
  const client = await pool.connect();
  try {
    const found = await client.query('SELECT 1 FROM picture_word_installations WHERE id = $1', [query.installationId]);
    if (!found.rowCount) return null;
    const params = [query.installationId, query.startDate, query.endDate, query.environment];
    const result = await client.query(`WITH activity AS (${activityDailySQL}) SELECT * FROM activity
      WHERE "installationId" = $1 AND date::date BETWEEN $2::date AND $3::date AND ($4 = 'All' OR environment = $4)
      ORDER BY date DESC, "eventName", outcome`, params);
    const daily = normalizeRows(result.rows);
    const events = await client.query(`SELECT event_id::text AS "eventId", occurred_at AS "occurredAt", event_name AS "eventName",
      environment, outcome, session_id::text AS "sessionId", app_version AS "appVersion", app_build AS "appBuild"
      FROM picture_word_activity_events WHERE installation_id = $1
      AND occurred_at >= (((clock_timestamp() AT TIME ZONE 'Asia/Shanghai')::date - 89)::timestamp AT TIME ZONE 'Asia/Shanghai')
      AND occurred_at >= ($2::date::timestamp AT TIME ZONE 'Asia/Shanghai')
      AND occurred_at < (($3::date + 1)::timestamp AT TIME ZONE 'Asia/Shanghai')
      AND ($4 = 'All' OR environment = $4)
      AND ($5::timestamptz IS NULL OR (occurred_at, event_id) < ($5::timestamptz, $6::uuid))
      ORDER BY occurred_at DESC, event_id DESC LIMIT 51`, [...params, query.cursor?.occurredAt ?? null, query.cursor?.eventId ?? null]);
    const page = events.rows.slice(0, 50).map(row => ({ ...row, occurredAt: row.occurredAt.toISOString() }));
    const last = page.at(-1);
    const overview = summarizeActivity(daily, query.startDate, query.endDate, query.environment, await recordingStart(client));
    // Last active is an all-time value, separate from the selected period's counts.
    const latest = await client.query<{ last_at: Date | null }>(`SELECT MAX(last_at) AS last_at FROM (${lastKnownActivitySQL}) known
      WHERE installation_id = $1 AND ($2 = 'All' OR environment = $2)`, [query.installationId, query.environment]);
    const summary = overview.devices[0] ?? emptyActivityDevice(query.installationId);
    summary.lastActiveAt = latest.rows[0]?.last_at?.toISOString() ?? summary.lastActiveAt;
    return { summary, recordingStartedAt: overview.recordingStartedAt, daily, events: page,
      nextCursor: events.rows.length > 50 && last ? Buffer.from(JSON.stringify({ occurredAt: last.occurredAt, eventId: last.eventId })).toString('base64url') : null };
  } finally { client.release(); }
}
