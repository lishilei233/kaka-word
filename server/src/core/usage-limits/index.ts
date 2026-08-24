import type { UsageLimitConfig } from "../../config.js";
import type { Logger } from "../../utils/logger.js";
import { PostgresAnalyzeUsageLimiter } from "./postgres.js";
import { DisabledAnalyzeUsageLimiter, type AnalyzeUsageLimiter } from "./types.js";

export function createAnalyzeUsageLimiter(config: UsageLimitConfig, logger: Logger): AnalyzeUsageLimiter {
  if (!config.enabled) return new DisabledAnalyzeUsageLimiter();
  return new PostgresAnalyzeUsageLimiter({
    databaseURL: config.databaseURL,
    ipHashSecret: config.ipHashSecret,
    perMinute: config.perMinute,
    dailyLimit: config.dailyLimit,
    dailyTimeZone: config.dailyTimeZone,
  }, logger);
}

export { DisabledAnalyzeUsageLimiter } from "./types.js";
export type { AnalyzeUsageLimiter, UsageLimitDecision } from "./types.js";
