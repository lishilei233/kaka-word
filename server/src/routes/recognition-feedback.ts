import type { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../app.js";
import type { AccessService } from "../core/access/index.js";
import type { Logger } from "../utils/logger.js";
import { authenticateAccess, unauthorized } from "./access-auth.js";

const wordSchema = z.object({
  english: z.string().trim().min(1).max(60),
  chinese: z.string().trim().min(1).max(60),
});

const schema = z.object({
  original: wordSchema,
  selected: wordSchema,
  selection: z.enum(["first", "second", "third", "other"]),
});

export function registerRecognitionFeedbackRoute(
  app: Hono<AppEnv>,
  dependencies: { accessService: AccessService; logger: Logger },
): void {
  const { accessService, logger } = dependencies;

  app.post("/v1/recognition-feedback", async (c) => {
    const principal = await authenticateAccess(c, accessService);
    if (!principal) return unauthorized(c);

    const parsed = schema.safeParse(await c.req.json().catch(() => undefined));
    if (!parsed.success) return c.json({ error: "INVALID_RECOGNITION_FEEDBACK" }, 400);

    try {
      await accessService.recordRecognitionFeedback(parsed.data);
      return c.body(null, 204);
    } catch (error) {
      // Do not include a request ID or the submitted words in this privacy-sensitive log.
      logger.warn("recognition_feedback.record_failed", {
        message: error instanceof Error ? error.message : String(error),
      });
      return c.json({ error: "RECOGNITION_FEEDBACK_UNAVAILABLE" }, 503);
    }
  });
}
