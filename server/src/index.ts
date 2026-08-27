import "dotenv/config";
import { serve } from "@hono/node-server";
import { createApp } from "./app.js";
import { readServerConfig } from "./config.js";
import { createVisionProvider } from "./core/image-analysis/providers/index.js";
import { createAnalyzeUsageLimiter } from "./core/usage-limits/index.js";
import { createLogger } from "./utils/logger.js";

const config = readServerConfig();
const logger = createLogger(config.logLevel);
const provider = createVisionProvider(config.vision);
const usageLimiter = createAnalyzeUsageLimiter(config.usageLimits, logger);
const app = createApp({ config, provider, usageLimiter, logger });

serve({ fetch: app.fetch, port: config.port }, (info) => {
  logger.info("server.started", {
    port: info.port,
    provider: config.vision.name,
    model: config.vision.model,
    logLevel: config.logLevel,
    usageLimitsEnabled: config.usageLimits.enabled,
    analyzeRateLimitPerMinute: config.usageLimits.perMinute,
    analyzeDailyLimit: config.usageLimits.dailyLimit,
  });
});
