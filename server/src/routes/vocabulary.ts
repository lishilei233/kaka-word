import { getConnInfo } from "@hono/node-server/conninfo";
import { isIP } from "node:net";
import { z } from "zod";
import type { Context, Hono } from "hono";
import type { AccessService } from "../core/access/index.js";
import type { VisionProvider } from "../core/image-analysis/types.js";
import type { AnalyzeUsageLimiter, UsageLimitDecision } from "../core/usage-limits/index.js";
import { errorFields, type LogLevel, type Logger } from "../utils/logger.js";
import type { AppEnv } from "../app.js";
import { authenticateAccess, unauthorized } from "./access-auth.js";

type VocabularyRouteDependencies = {
  provider: VisionProvider;
  providerName: string;
  providerModel: string;
  usageLimiter: AnalyzeUsageLimiter;
  accessService: AccessService;
  trustProxy: boolean;
  logLevel: LogLevel;
  logger: Logger;
};

const requestSchema = z.object({
  term: z.string().trim().min(1).max(60),
});

export function registerVocabularyRoute(app: Hono<AppEnv>, dependencies: VocabularyRouteDependencies): void {
  const { provider, providerName, providerModel, usageLimiter, accessService, trustProxy, logLevel, logger } = dependencies;

  app.post("/v1/vocabulary/resolve", async (c) => {
    const requestId = c.get("requestId");
    const principal = await authenticateAccess(c, accessService);
    if (!principal) return unauthorized(c);
    try {
      const entitlement = await accessService.status(principal);
      if (!entitlement.vocabularyCorrectionEnabled) {
        return c.json({
          error: "MEMBERSHIP_REQUIRED",
          message: "AI 单词修改是会员功能",
          entitlement,
        }, 403);
      }
    } catch (error) {
      logger.error("access.status_failed", { requestId, ...errorFields(error, logLevel === "debug") });
      return c.json({ error: "ACCESS_UNAVAILABLE", message: "暂时无法读取会员状态" }, 503);
    }
    let minuteDecision: UsageLimitDecision;
    try {
      minuteDecision = await usageLimiter.consumeMinute(resolveClientIP(c, trustProxy));
    } catch (error) {
      logger.error("usage_limit.unavailable", { requestId, scope: "minute", ...errorFields(error, logLevel === "debug") });
      return c.json({ error: "USAGE_LIMIT_UNAVAILABLE", message: "识别服务暂时不可用，请稍后重试" }, 503);
    }
    if (!minuteDecision.allowed) {
      c.header("Retry-After", String(minuteDecision.retryAfterSeconds));
      return c.json({
        error: "RATE_LIMITED",
        message: `请求有点频繁，请在 ${minuteDecision.retryAfterSeconds} 秒后再试`,
        retryAfterSeconds: minuteDecision.retryAfterSeconds,
      }, 429);
    }

    const payload = await c.req.json().catch(() => undefined);
    const parsed = requestSchema.safeParse(payload);
    if (!parsed.success) {
      return c.json({ error: "INVALID_TERM", message: "请输入 1 到 60 个字符的中文或英文物体名称" }, 400);
    }

    let dailyDecision: UsageLimitDecision;
    try {
      dailyDecision = await usageLimiter.consumeDaily();
    } catch (error) {
      logger.error("usage_limit.unavailable", { requestId, scope: "daily", ...errorFields(error, logLevel === "debug") });
      return c.json({ error: "USAGE_LIMIT_UNAVAILABLE", message: "识别服务暂时不可用，请稍后重试" }, 503);
    }
    if (!dailyDecision.allowed) {
      c.header("Retry-After", String(dailyDecision.retryAfterSeconds));
      return c.json({
        error: "DAILY_LIMIT_REACHED",
        message: "今天的 AI 额度已用完，请明天再试",
        retryAfterSeconds: dailyDecision.retryAfterSeconds,
      }, 429);
    }

    try {
      const result = await provider.resolveVocabulary({
        term: parsed.data.term,
        language: "zh-CN",
        signal: c.req.raw.signal,
      });
      logger.info("vocabulary.request_completed", {
        requestId,
        provider: providerName,
        model: providerModel,
        inputLength: parsed.data.term.length,
      });
      await accessService.recordMetric({ eventName: "vocabulary_correction", outcome: "success" }).catch(() => undefined);
      return c.json(result);
    } catch (error) {
      await accessService.recordMetric({ eventName: "vocabulary_correction", outcome: "failure" }).catch(() => undefined);
      logger.error("vocabulary.failed", {
        requestId,
        provider: providerName,
        model: providerModel,
        ...errorFields(error, logLevel === "debug"),
      });
      return c.json({ error: "VOCABULARY_FAILED", message: "单词信息生成失败，请稍后重试" }, 502);
    }
  });
}

function resolveClientIP(c: Context<AppEnv>, trustProxy: boolean): string {
  let candidate = "";
  if (trustProxy) {
    candidate = c.req.header("x-forwarded-for")?.split(",", 1)[0]?.trim() ?? "";
  } else {
    try {
      candidate = getConnInfo(c).remote.address?.trim() ?? "";
    } catch {
      candidate = "";
    }
  }
  return isIP(candidate) === 0 ? "" : candidate;
}
