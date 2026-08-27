import type { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../app.js";
import type { AccessService } from "../core/access/index.js";
import type { Logger } from "../utils/logger.js";
import { authenticateAccess, unauthorized } from "./access-auth.js";

const allowedEvents = ["paywall_exposure", "plan_selection", "purchase_result", "restore_result"] as const;
const schema = z.object({
  eventName: z.enum(allowedEvents),
  productId: z.string().trim().max(128).optional(),
  outcome: z.string().trim().max(64).optional(),
});

export function registerMetricsRoute(
  app: Hono<AppEnv>,
  dependencies: { accessService: AccessService; logger: Logger },
): void {
  const { accessService, logger } = dependencies;
  app.post("/v1/metrics", async (c) => {
    const principal = await authenticateAccess(c, accessService);
    if (!principal) return unauthorized(c);
    const parsed = schema.safeParse(await c.req.json().catch(() => undefined));
    if (!parsed.success) return c.json({ error: "INVALID_METRIC" }, 400);
    try {
      await accessService.recordMetric(parsed.data);
      return c.body(null, 204);
    } catch (error) {
      logger.warn("metrics.record_failed", {
        requestId: c.get("requestId"),
        message: error instanceof Error ? error.message : String(error),
      });
      return c.json({ error: "METRICS_UNAVAILABLE" }, 503);
    }
  });
}
