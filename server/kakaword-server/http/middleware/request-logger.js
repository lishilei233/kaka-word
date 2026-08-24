import { errorFields } from "../../shared/logger.js";
export function requestLogger(logger, logLevel) {
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
