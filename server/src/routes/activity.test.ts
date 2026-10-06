import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import test from 'node:test';
import { Hono } from 'hono';
import type { AppEnv } from '../app.js';
import { DisabledAccessService } from '../core/access/disabled.js';
import type { ActivityEvent } from '../core/access/activity.js';
import { registerActivityRoute } from './activity.js';

class AccessSpy extends DisabledAccessService {
  received: ActivityEvent[] = [];
  installationId: string | null = null;
  fails = false;
  authenticated = true;
  override async authenticate() {
    return this.authenticated ? { accessTokenHash: 'hash', installationId: '11111111-1111-4111-8111-111111111111',
      subscriptionEnvironment: null, originalTransactionId: null, storeEnvironment: null } : null;
  }
  override async recordActivityEvents(installationId: string, events: ActivityEvent[]) {
    if (this.fails) throw new Error('unavailable');
    this.installationId = installationId; this.received = events;
  }
}
function setup() {
  const access = new AccessSpy(); const app = new Hono<AppEnv>();
  registerActivityRoute(app, { accessService: access, logger: { debug() {}, info() {}, warn() {}, error() {} } });
  return { access, post: (body: unknown) => app.request('/v1/activity/events', { method: 'POST',
    headers: { authorization: 'Bearer test', 'content-type': 'application/json' }, body: JSON.stringify(body) }) };
}
const event = (overrides: Record<string, unknown> = {}) => ({ eventId: randomUUID(), occurredAt: '2026-10-05T23:59:59+08:00',
  eventName: 'history_view', environment: 'Sandbox', appVersion: '0.7.0', ...overrides });

test('activity batches preserve occurrence time/environment and use authenticated installation', async () => {
  const { access, post } = setup(); const events = [event(), event({ eventName: 'listening_answer', outcome: 'revealed', sessionId: randomUUID() })];
  const response = await post({ events });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { acknowledgedEventIds: events.map(e => e.eventId) });
  assert.deepEqual(access.received, events);
  assert.equal(access.installationId, '11111111-1111-4111-8111-111111111111');
});

test('activity rejects client recognition, content payloads, malformed dates and invalid listening outcomes', async () => {
  const { post, access } = setup();
  for (const invalid of [event({ eventName: 'recognition_success' }), event({ image: 'private-image' }),
    event({ occurredAt: 'bad' }), event({ installationId: randomUUID() }), event({ environment: 'other' }),
    event({ eventName: 'listening_answer', sessionId: randomUUID() }), event({ eventName: 'listening_answer', outcome: 'found' }),
    event({ outcome: 'found' }), event({ eventName: 'listening_start' })]) {
    assert.equal((await post({ events: [invalid] })).status, 400);
  }
  assert.equal((await post({ events: [] })).status, 400);
  assert.equal((await post({ events: Array.from({ length: 101 }, () => event()) })).status, 400);
  assert.equal(access.received.length, 0);
});

test('activity never acknowledges failed or unauthenticated uploads', async () => {
  const { access, post } = setup(); access.authenticated = false;
  assert.equal((await post({ events: [event()] })).status, 401);
  access.authenticated = true; access.fails = true;
  const response = await post({ events: [event()] });
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { error: 'ACTIVITY_UNAVAILABLE' });
});
