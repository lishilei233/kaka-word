import type { Hono } from 'hono';
import { z } from 'zod';
import type { AppEnv } from '../app.js';
import type { AccessService } from '../core/access/index.js';
import { accessEnvironments } from '../core/access/types.js';
import { activityEventNames } from '../core/access/activity.js';
import type { Logger } from '../utils/logger.js';
import { authenticateAccess, unauthorized } from './access-auth.js';

const eventSchema = z.object({
  eventId: z.string().uuid(), occurredAt: z.string().datetime({ offset: true }),
  eventName: z.enum(activityEventNames), environment: z.enum([...accessEnvironments, 'Unknown'] as ['Sandbox', 'Production', 'Xcode', 'LocalTesting', 'Unknown']),
  outcome: z.enum(['found', 'revealed']).optional(), sessionId: z.string().uuid().optional(),
  appVersion: z.string().max(64).optional(), appBuild: z.string().max(64).optional(),
}).strict().superRefine((event, ctx) => {
  if ((event.eventName === 'listening_answer') !== (event.outcome !== undefined)) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, message: 'Answer outcome is required only for listening answers' });
  }
  if (['listening_start', 'listening_answer', 'listening_complete'].includes(event.eventName) && !event.sessionId) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, message: 'Listening round ID is required' });
  }
});
const schema = z.object({ events: z.array(eventSchema).min(1).max(100) }).strict();

export function registerActivityRoute(app: Hono<AppEnv>, { accessService, logger }: { accessService: AccessService; logger: Logger }): void {
  app.post('/v1/activity/events', async c => {
    const principal = await authenticateAccess(c, accessService);
    if (!principal) return unauthorized(c);
    const raw = await c.req.text();
    if (Buffer.byteLength(raw) > 100_000) return c.json({ error: 'ACTIVITY_BATCH_TOO_LARGE' }, 413);
    let body: unknown;
    try { body = JSON.parse(raw); } catch { return c.json({ error: 'INVALID_ACTIVITY' }, 400); }
    const parsed = schema.safeParse(body);
    if (!parsed.success) return c.json({ error: 'INVALID_ACTIVITY' }, 400);
    try {
      await accessService.recordActivityEvents(principal.installationId, parsed.data.events);
      // Expired or future-clock events are acknowledged but excluded from statistics.
      return c.json({ acknowledgedEventIds: parsed.data.events.map(event => event.eventId) });
    } catch (error) {
      logger.warn('activity.record_failed', { requestId: c.get('requestId'), message: error instanceof Error ? error.message : String(error) });
      return c.json({ error: 'ACTIVITY_UNAVAILABLE' }, 503);
    }
  });
}
