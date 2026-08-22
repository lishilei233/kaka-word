import { Hono, type MiddlewareHandler } from "hono";
import { cors } from "hono/cors";
import type { ServerConfig } from "./config.js";
import type { VisionProvider } from "./core/image-analysis/types.js";
import { registerAnalyzeRoute } from "./routes/analyze.js";
import { errorFields, type LogLevel, type Logger } from "./utils/logger.js";

export type AppEnv = {
  Variables: {
    requestId: string;
  };
};

type AppDependencies = {
  config: ServerConfig;
  provider: VisionProvider;
  logger: Logger;
};

export function createApp({ config, provider, logger }: AppDependencies): Hono<AppEnv> {
  const app = new Hono<AppEnv>();

  app.use("*", cors({
    origin: "*",
    allowHeaders: ["Content-Type", "X-Request-ID"],
    exposeHeaders: ["X-Request-ID"],
  }));
  app.use("*", requestLogger(logger, config.logLevel));

  app.get("/health", (c) => c.json({ ok: true, provider: config.vision.name }));
  registerAnalyzeRoute(app, {
    provider,
    providerName: config.vision.name,
    providerModel: config.vision.model,
    maxUploadBytes: config.maxUploadBytes,
    logLevel: config.logLevel,
    logger,
  });

  return app;
}

function requestLogger(logger: Logger, logLevel: LogLevel): MiddlewareHandler<AppEnv> {
  return async (c, next) => {
    const requestId = c.req.header("x-request-id")?.slice(0, 128) || crypto.randomUUID();
    const startedAt = performance.now();
    c.set("requestId", requestId);
    c.header("x-request-id", requestId);

    try {
      await next();
    } catch (error) {
      logger.error("request.unhandled_error", {
        requestId,
        method: c.req.method,
        path: c.req.path,
        ...errorFields(error, logLevel === "debug"),
      });
      throw error;
    } finally {
      logger.info("request.completed", {
        requestId,
        method: c.req.method,
        path: c.req.path,
        status: c.res.status,
        durationMs: Math.round(performance.now() - startedAt),
      });
    }
  };
}
