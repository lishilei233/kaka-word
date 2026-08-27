import "dotenv/config";
import { serve } from "@hono/node-server";
import { createApp } from "./app.js";
import { readServerConfig } from "./config.js";
import { createAccessService } from "./core/access/index.js";
import { createVisionProvider } from "./core/image-analysis/providers/index.js";
import { createAnalyzeUsageLimiter } from "./core/usage-limits/index.js";
import { createLogger } from "./utils/logger.js";

const config = readServerConfig();
const logger = createLogger(config.logLevel);
const provider = createVisionProvider(config.vision);
const usageLimiter = createAnalyzeUsageLimiter(config.usageLimits, logger);
const accessService = await createAccessService(config.access, logger);
const app = createApp({ config, provider, usageLimiter, accessService, logger });

// Bind IPv4 explicitly so a real device on the local network can reach the
// development server via its LAN address (for example, 192.168.x.x).
serve({
  fetch: app.fetch,
  port: config.port,
  hostname: process.env.SERVER_HOSTNAME?.trim() || "0.0.0.0",
}, (info) => {
  logger.info("server.started", {
    port: info.port,
    provider: config.vision.name,
    model: config.vision.model,
    logLevel: config.logLevel,
    usageLimitsEnabled: config.usageLimits.enabled,
    analyzeRateLimitPerMinute: config.usageLimits.perMinute,
    analyzeDailyLimit: config.usageLimits.dailyLimit,
    accessControlEnabled: config.access.enabled,
  });
});
