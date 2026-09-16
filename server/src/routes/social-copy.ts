import { z } from "zod";
import type { Hono } from "hono";
import type { AppEnv } from "../app.js";
import { captionVariantsSchema, socialCopySchema, type VisionProvider } from "../core/image-analysis/types.js";
import type { Logger } from "../utils/logger.js";
import { authenticateVideoStudio, unauthorized } from "./access-auth.js";

const requestSchema = z.object({
  caption: z.string().trim().min(1).max(220),
  captionChinese: z.string().trim().max(220),
  words: z.array(z.object({ english: z.string().trim().min(1).max(60), chinese: z.string().max(60) })).min(1).max(10),
  highlightedWords: z.array(z.string().trim().min(1).max(60)).max(10).default([]),
});
const captionRequestSchema = requestSchema.pick({ caption: true, captionChinese: true, words: true });

export function registerSocialCopyRoute(app: Hono<AppEnv>, dependencies: {
  provider: VisionProvider;
  videoStudioAccessToken?: string;
  logger: Logger;
}): void {
  app.post("/v1/caption-variants", async (c) => {
    if (!authenticateVideoStudio(c.req.header("authorization"), dependencies.videoStudioAccessToken)) return unauthorized(c);
    if (!dependencies.provider.generateCaptionVariants) return c.json({ error: "UNAVAILABLE", message: "当前 AI 服务暂不支持多版本描述" }, 503);
    const parsed = captionRequestSchema.safeParse(await c.req.json().catch(() => undefined));
    if (!parsed.success) return c.json({ error: "INVALID_INPUT", message: "请先准备照片描述和单词" }, 400);
    try {
      return c.json(captionVariantsSchema.parse(await dependencies.provider.generateCaptionVariants({ ...parsed.data, signal: c.req.raw.signal })));
    } catch (error) {
      dependencies.logger.error("caption_variants.failed", { requestId: c.get("requestId"), error: error instanceof Error ? error.message : "Unknown error" });
      return c.json({ error: "CAPTION_VARIANTS_FAILED", message: "多版本照片描述生成失败，请稍后重试" }, 502);
    }
  });

  app.post("/v1/social-copy", async (c) => {
    if (!authenticateVideoStudio(c.req.header("authorization"), dependencies.videoStudioAccessToken)) return unauthorized(c);
    if (!dependencies.provider.generateSocialCopy) return c.json({ error: "UNAVAILABLE", message: "当前 AI 服务暂不支持发布文案" }, 503);
    const parsed = requestSchema.safeParse(await c.req.json().catch(() => undefined));
    if (!parsed.success) return c.json({ error: "INVALID_INPUT", message: "请先准备照片描述和单词" }, 400);
    try {
      return c.json(socialCopySchema.parse(await dependencies.provider.generateSocialCopy({ ...parsed.data, signal: c.req.raw.signal })));
    } catch (error) {
      dependencies.logger.error("social_copy.failed", { requestId: c.get("requestId"), error: error instanceof Error ? error.message : "Unknown error" });
      return c.json({ error: "SOCIAL_COPY_FAILED", message: "发布文案生成失败，请稍后重试" }, 502);
    }
  });
}
