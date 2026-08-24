import { Hono } from "hono";
import { cors } from "hono/cors";
import { registerAnalyzeRoute } from "./routes/analyze.js";
import { registerVocabularyRoute } from "./routes/vocabulary.js";
import { errorFields } from "./utils/logger.js";
export function createApp({ config, provider, usageLimiter, logger }) {
    const app = new Hono();
    app.use("*", cors({
        origin: "*",
        allowHeaders: ["Content-Type", "X-Request-ID"],
        exposeHeaders: ["X-Request-ID", "Retry-After"],
    }));
    app.use("*", requestLogger(logger, config.logLevel));
    app.get("/health", (c) => c.json({ ok: true, provider: config.vision.name }));
    registerAnalyzeRoute(app, {
        provider,
        providerName: config.vision.name,
        providerModel: config.vision.model,
        maxUploadBytes: config.maxUploadBytes,
        usageLimiter,
        trustProxy: config.usageLimits.trustProxy,
        logLevel: config.logLevel,
        logger,
    });
    registerVocabularyRoute(app, {
        provider,
        providerName: config.vision.name,
        providerModel: config.vision.model,
        usageLimiter,
        trustProxy: config.usageLimits.trustProxy,
        logLevel: config.logLevel,
        logger,
    });
    return app;
}
function requestLogger(logger, logLevel) {
    return async (c, next) => {
        const requestId = c.req.header("x-request-id")?.slice(0, 128) || crypto.randomUUID();
        const startedAt = performance.now();
        c.set("requestId", requestId);
        c.header("x-request-id", requestId);
        try {
            await next();
        }
        catch (error) {
            logger.error("request.unhandled_error", {
                requestId,
                method: c.req.method,
                path: c.req.path,
                ...errorFields(error, logLevel === "debug"),
            });
            throw error;
        }
        finally {
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
