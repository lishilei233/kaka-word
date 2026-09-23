import { Hono, type MiddlewareHandler } from "hono";
import { cors } from "hono/cors";
import type { ServerConfig } from "./config.js";
import { DisabledAccessService, type AccessService } from "./core/access/index.js";
import type { VisionProvider } from "./core/image-analysis/types.js";
import type { AnalyzeUsageLimiter } from "./core/usage-limits/index.js";
import { registerAccessRoutes } from "./routes/access.js";
import { registerAppVersionRoute } from "./routes/app-version.js";
import { registerAnalyzeRoute } from "./routes/analyze.js";
import { registerContentRoute } from "./routes/content.js";
import { registerMetricsRoute } from "./routes/metrics.js";
import { registerMembershipRoute } from "./routes/membership.js";
import { registerRecognitionFeedbackRoute } from "./routes/recognition-feedback.js";
import { registerStoreRoutes } from "./routes/store.js";
import { registerSocialCopyRoute } from "./routes/social-copy.js";
import { registerStudioSceneRoute } from './routes/studio-scene.js';
import { registerVocabularyRoute } from "./routes/vocabulary.js";
import { registerAdminStatsRoutes } from "./routes/admin-stats.js";
import type { AdminStatsRepository } from "./core/admin-stats.js";
import { errorFields, type LogLevel, type Logger } from "./utils/logger.js";

export type AppEnv = {
  Variables: {
    requestId: string;
  };
};

type AppDependencies = {
  config: ServerConfig;
  provider: VisionProvider;
  usageLimiter: AnalyzeUsageLimiter;
  accessService?: AccessService;
  logger: Logger;
  adminStatsRepository?: AdminStatsRepository;
};

export function createApp({ config, provider, usageLimiter, accessService = new DisabledAccessService(), logger, adminStatsRepository }: AppDependencies): Hono<AppEnv> {
  const app = new Hono<AppEnv>();

  app.use("*", cors({
    origin: "*",
    allowHeaders: ["Authorization", "Content-Type", "X-DeviceCheck-Token", "X-Operation-ID", "X-Request-ID"],
    exposeHeaders: ["X-Request-ID", "Retry-After"],
  }));
  app.use("*", requestLogger(logger, config.logLevel));

  app.get("/health", (c) => c.json({ ok: true, provider: config.vision.name }));
  registerAdminStatsRoutes(app, {
    key: config.adminDashboard?.key,
    repository: adminStatsRepository,
    logger,
  });
  if (config.appVersion) registerAppVersionRoute(app, config.appVersion);
  registerContentRoute(app, config.access);
  registerMembershipRoute(app, config.access);
  registerAccessRoutes(app, { accessService, logger });
  registerStoreRoutes(app, { accessService, logger });
  registerMetricsRoute(app, { accessService, logger });
  registerRecognitionFeedbackRoute(app, { accessService, logger });
  registerAnalyzeRoute(app, {
    provider,
    providerName: config.vision.name,
    providerModel: config.vision.model,
    maxUploadBytes: config.maxUploadBytes,
    usageLimiter,
    accessService,
    videoStudioAccessToken: config.videoStudioAccessToken,
    trustProxy: config.usageLimits.trustProxy,
    logLevel: config.logLevel,
    logger,
  });
  registerSocialCopyRoute(app, { provider, videoStudioAccessToken: config.videoStudioAccessToken, logger });
  registerStudioSceneRoute(app, { provider, videoStudioAccessToken: config.videoStudioAccessToken });
  registerVocabularyRoute(app, {
    provider,
    providerName: config.vision.name,
    providerModel: config.vision.model,
    usageLimiter,
    accessService,
    trustProxy: config.usageLimits.trustProxy,
    logLevel: config.logLevel,
    logger,
  });

  return app;
}

function requestLogger(logger: Logger, logLevel: LogLevel): MiddlewareHandler<AppEnv> {
  return async (c, next) => {
    const requestId = c.req.header("x-request-id")?.slice(0, 128) || crypto.randomUUID();
    const privacySensitive = c.req.path === "/v1/recognition-feedback";
    const startedAt = performance.now();
    c.set("requestId", requestId);
    if (!privacySensitive) c.header("x-request-id", requestId);

    try {
      await next();
    } catch (error) {
      logger.error("request.unhandled_error", {
        ...(privacySensitive ? {} : { requestId }),
        method: c.req.method,
        path: c.req.path,
        ...errorFields(error, logLevel === "debug"),
      });
      throw error;
    } finally {
      logger.info("request.completed", {
        ...(privacySensitive ? {} : { requestId }),
        method: c.req.method,
        path: c.req.path,
        status: c.res.status,
        durationMs: Math.round(performance.now() - startedAt),
      });
    }
  };
}
