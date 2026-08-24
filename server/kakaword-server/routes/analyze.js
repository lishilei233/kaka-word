import { getConnInfo } from "@hono/node-server/conninfo";
import { isIP } from "node:net";
import { streamSSE } from "hono/streaming";
import { requestedCaptionStyleSchema, } from "../core/image-analysis/types.js";
import { getImageDimensions } from "../utils/image-dimensions.js";
import { errorFields } from "../utils/logger.js";
export function registerAnalyzeRoute(app, dependencies) {
    const { provider, providerName, providerModel, maxUploadBytes, usageLimiter, trustProxy, logLevel, logger, } = dependencies;
    app.post("/v1/analyze", async (c) => {
        const requestId = c.get("requestId");
        const analyzeStartedAt = performance.now();
        let stage = "validate_request";
        try {
            stage = "minute_limit";
            let minuteDecision;
            try {
                minuteDecision = await usageLimiter.consumeMinute(resolveClientIP(c, trustProxy));
            }
            catch (error) {
                logger.error("usage_limit.unavailable", {
                    requestId,
                    scope: "minute",
                    ...errorFields(error, logLevel === "debug"),
                });
                return c.json({
                    error: "USAGE_LIMIT_UNAVAILABLE",
                    message: "识别服务暂时不可用，请稍后重试",
                }, 503);
            }
            if (!minuteDecision.allowed) {
                logger.warn("usage_limit.rejected", {
                    requestId,
                    scope: "minute",
                    retryAfterSeconds: minuteDecision.retryAfterSeconds,
                });
                c.header("Retry-After", String(minuteDecision.retryAfterSeconds));
                return c.json({
                    error: "RATE_LIMITED",
                    message: `识别有点频繁，请在 ${minuteDecision.retryAfterSeconds} 秒后再试`,
                    retryAfterSeconds: minuteDecision.retryAfterSeconds,
                }, 429);
            }
            stage = "validate_request";
            const contentLength = Number(c.req.header("content-length") ?? 0);
            if (contentLength > maxUploadBytes + 64_000) {
                logger.warn("analyze.rejected", { requestId, reason: "IMAGE_TOO_LARGE", contentLength });
                return c.json({ error: "IMAGE_TOO_LARGE" }, 413);
            }
            const body = await c.req.parseBody();
            const image = body.image;
            const requestedMaxObjects = Number(body.maxObjects);
            const requestedCaptionStyle = requestedCaptionStyleSchema.safeParse(body.captionStyle).success
                ? requestedCaptionStyleSchema.parse(body.captionStyle)
                : "serious";
            const captionStyle = requestedCaptionStyle === "random"
                ? (Math.random() < 0.5 ? "serious" : "funny")
                : requestedCaptionStyle;
            const maxObjects = Number.isInteger(requestedMaxObjects)
                ? Math.min(Math.max(requestedMaxObjects, 3), 8)
                : 8;
            if (!(image instanceof File)) {
                logger.warn("analyze.rejected", { requestId, reason: "IMAGE_REQUIRED" });
                return c.json({ error: "IMAGE_REQUIRED" }, 400);
            }
            if (!image.type.startsWith("image/")) {
                logger.warn("analyze.rejected", { requestId, reason: "UNSUPPORTED_IMAGE_TYPE", mimeType: image.type });
                return c.json({ error: "UNSUPPORTED_IMAGE_TYPE" }, 415);
            }
            if (image.size > maxUploadBytes) {
                logger.warn("analyze.rejected", { requestId, reason: "IMAGE_TOO_LARGE", imageBytes: image.size });
                return c.json({ error: "IMAGE_TOO_LARGE" }, 413);
            }
            const bytes = new Uint8Array(await image.arrayBuffer());
            stage = "validate_image";
            const dimensions = getImageDimensions(bytes);
            if (!dimensions) {
                logger.warn("analyze.rejected", { requestId, reason: "INVALID_IMAGE", imageBytes: image.size, mimeType: image.type });
                return c.json({ error: "INVALID_IMAGE" }, 400);
            }
            logger.info("analyze.image_received", {
                requestId,
                imageBytes: image.size,
                mimeType: image.type,
                imageWidth: dimensions.width,
                imageHeight: dimensions.height,
            });
            stage = "daily_limit";
            let dailyDecision;
            try {
                dailyDecision = await usageLimiter.consumeDaily();
            }
            catch (error) {
                logger.error("usage_limit.unavailable", {
                    requestId,
                    scope: "daily",
                    ...errorFields(error, logLevel === "debug"),
                });
                return c.json({
                    error: "USAGE_LIMIT_UNAVAILABLE",
                    message: "识别服务暂时不可用，请稍后重试",
                }, 503);
            }
            if (!dailyDecision.allowed) {
                logger.warn("usage_limit.rejected", {
                    requestId,
                    scope: "daily",
                    retryAfterSeconds: dailyDecision.retryAfterSeconds,
                });
                c.header("Retry-After", String(dailyDecision.retryAfterSeconds));
                return c.json({
                    error: "DAILY_LIMIT_REACHED",
                    message: "今天的识别额度已用完，请明天再试",
                    retryAfterSeconds: dailyDecision.retryAfterSeconds,
                }, 429);
            }
            const providerStartedAt = performance.now();
            stage = "vision_provider";
            logger.info("vision.request_started", {
                requestId,
                provider: providerName,
                model: providerModel,
                maxObjects,
                captionStyle,
            });
            const abortController = new AbortController();
            const input = {
                image: bytes,
                mimeType: image.type === "image/heic" ? "image/jpeg" : image.type,
                imageWidth: dimensions.width,
                imageHeight: dimensions.height,
                language: "zh-CN",
                maxObjects,
                captionStyle,
                signal: abortController.signal,
            };
            c.header("Cache-Control", "no-cache");
            c.header("Content-Encoding", "Identity");
            c.header("X-Accel-Buffering", "no");
            return streamSSE(c, async (stream) => {
                let streamedObjectCount = 0;
                stream.onAbort(() => abortController.abort());
                await stream.writeSSE({
                    event: "started",
                    data: JSON.stringify({ imageWidth: dimensions.width, imageHeight: dimensions.height }),
                });
                try {
                    const sendObject = async (object) => {
                        streamedObjectCount += 1;
                        if (streamedObjectCount === 1) {
                            logger.info("vision.first_object", {
                                requestId,
                                provider: providerName,
                                model: providerModel,
                                durationMs: Math.round(performance.now() - providerStartedAt),
                            });
                        }
                        await stream.writeSSE({ event: "object", data: JSON.stringify(object) });
                    };
                    const result = provider.analyzeStream
                        ? await provider.analyzeStream(input, sendObject)
                        : await provider.analyze(input);
                    if (!provider.analyzeStream) {
                        for (const object of result.objects)
                            await sendObject(object);
                    }
                    stage = "serialize_response";
                    await stream.writeSSE({ event: "complete", data: JSON.stringify(result) });
                    logger.info("vision.request_completed", {
                        requestId,
                        provider: providerName,
                        model: providerModel,
                        objectCount: result.objects.length,
                        durationMs: Math.round(performance.now() - providerStartedAt),
                    });
                }
                catch (error) {
                    if (abortController.signal.aborted) {
                        logger.info("vision.request_cancelled", {
                            requestId,
                            provider: providerName,
                            model: providerModel,
                            streamedObjectCount,
                            durationMs: Math.round(performance.now() - providerStartedAt),
                        });
                        return;
                    }
                    logger.error("analyze.failed", {
                        requestId,
                        provider: providerName,
                        model: providerModel,
                        stage,
                        streamedObjectCount,
                        durationMs: Math.round(performance.now() - analyzeStartedAt),
                        ...errorFields(error, logLevel === "debug"),
                    });
                    await stream.writeSSE({
                        event: "error",
                        data: JSON.stringify({ error: "ANALYZE_FAILED", message: "AI 识别暂时失败，请稍后重试" }),
                    });
                }
            });
        }
        catch (error) {
            logger.error("analyze.failed", {
                requestId,
                provider: providerName,
                model: providerModel,
                stage,
                durationMs: Math.round(performance.now() - analyzeStartedAt),
                ...errorFields(error, logLevel === "debug"),
            });
            return c.json({ error: "ANALYZE_FAILED", message: error instanceof Error ? error.message : "Unknown error" }, 502);
        }
    });
}
function resolveClientIP(c, trustProxy) {
    let candidate = "";
    if (trustProxy) {
        candidate = c.req.header("x-forwarded-for")?.split(",", 1)[0]?.trim() ?? "";
    }
    else {
        try {
            candidate = getConnInfo(c).remote.address?.trim() ?? "";
        }
        catch {
            candidate = "";
        }
    }
    return isIP(candidate) === 0 ? "" : candidate;
}
