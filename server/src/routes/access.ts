import type { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../app.js";
import type { AccessService } from "../core/access/index.js";
import type { Logger } from "../utils/logger.js";
import { authenticateAccess, unauthorized } from "./access-auth.js";

const bootstrapSchema = z.object({
  installationId: z.string().uuid(),
  deviceToken: z.string().trim().min(16).max(16_384),
});

export function registerAccessRoutes(
  app: Hono<AppEnv>,
  dependencies: { accessService: AccessService; logger: Logger },
): void {
  const { accessService, logger } = dependencies;

  app.post("/v1/access/bootstrap", async (c) => {
    const payload = await c.req.json().catch(() => undefined);
    const parsed = bootstrapSchema.safeParse(payload);
    if (!parsed.success) {
      return c.json({ error: "INVALID_ACCESS_REQUEST", message: "设备验证信息无效" }, 400);
    }
    try {
      return c.json(await accessService.bootstrap(parsed.data));
    } catch (error) {
      logger.error("access.bootstrap_failed", {
        requestId: c.get("requestId"),
        message: error instanceof Error ? error.message : String(error),
      });
      return c.json({
        error: "DEVICE_VERIFICATION_UNAVAILABLE",
        message: "暂时无法验证设备，请稍后重试",
      }, 503);
    }
  });

  app.get("/v1/access/status", async (c) => {
    const principal = await authenticateAccess(c, accessService);
    if (!principal) return unauthorized(c);
    try {
      return c.json({ entitlement: await accessService.status(principal) });
    } catch (error) {
      logger.error("access.status_failed", {
        requestId: c.get("requestId"),
        message: error instanceof Error ? error.message : String(error),
      });
      return c.json({ error: "ACCESS_UNAVAILABLE", message: "暂时无法读取会员状态" }, 503);
    }
  });
}
