import type { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../app.js";
import type { AccessService } from "../core/access/index.js";
import type { Logger } from "../utils/logger.js";
import { authenticateAccess, unauthorized } from "./access-auth.js";

const syncSchema = z.object({
  signedTransaction: z.string().trim().min(32).max(200_000),
  signedRenewalInfo: z.string().trim().min(32).max(200_000).optional(),
});
const notificationSchema = z.object({
  signedPayload: z.string().trim().min(32).max(500_000),
});

export function registerStoreRoutes(
  app: Hono<AppEnv>,
  dependencies: { accessService: AccessService; logger: Logger },
): void {
  const { accessService, logger } = dependencies;

  app.post("/v1/store/sync", async (c) => {
    const principal = await authenticateAccess(c, accessService);
    if (!principal) return unauthorized(c);
    const parsed = syncSchema.safeParse(await c.req.json().catch(() => undefined));
    if (!parsed.success) {
      return c.json({ error: "INVALID_TRANSACTION", message: "购买凭证无效" }, 400);
    }
    try {
      const entitlement = await accessService.syncSubscription(
        principal,
        parsed.data.signedTransaction,
        parsed.data.signedRenewalInfo,
      );
      return c.json({ entitlement });
    } catch (error) {
      logger.warn("store.sync_rejected", {
        requestId: c.get("requestId"),
        message: error instanceof Error ? error.message : String(error),
      });
      return c.json({ error: "TRANSACTION_VERIFICATION_FAILED", message: "无法验证这笔购买，请尝试恢复购买" }, 400);
    }
  });

  app.post("/v1/store/notifications", async (c) => {
    const parsed = notificationSchema.safeParse(await c.req.json().catch(() => undefined));
    if (!parsed.success) return c.json({ error: "INVALID_NOTIFICATION" }, 400);
    try {
      await accessService.processStoreNotification(parsed.data.signedPayload);
      return c.json({ ok: true });
    } catch (error) {
      logger.error("store.notification_failed", {
        requestId: c.get("requestId"),
        message: error instanceof Error ? error.message : String(error),
      });
      return c.json({ error: "NOTIFICATION_VERIFICATION_FAILED" }, 400);
    }
  });
}
