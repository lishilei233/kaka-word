import { getImageDimensions } from "../../shared/image-dimensions.js";
import { errorFields } from "../../shared/logger.js";
export function registerAnalyzeRoute(app, dependencies) {
    const { provider, providerName, providerModel, maxUploadBytes, logLevel, logger } = dependencies;
    app.post("/v1/analyze", async (c) => {
        const requestId = c.get("requestId");
        const analyzeStartedAt = performance.now();
        let stage = "validate_request";
        try {
            const contentLength = Number(c.req.header("content-length") ?? 0);
            if (contentLength > maxUploadBytes + 64_000) {
                logger.warn("analyze.rejected", { requestId, reason: "IMAGE_TOO_LARGE", contentLength });
                return c.json({ error: "IMAGE_TOO_LARGE" }, 413);
            }
            const body = await c.req.parseBody();
            const image = body.image;
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
            const providerStartedAt = performance.now();
            stage = "vision_provider";
            logger.info("vision.request_started", {
                requestId,
                provider: providerName,
                model: providerModel,
                maxObjects: 8,
            });
            const result = await provider.analyze({
                image: bytes,
                mimeType: image.type === "image/heic" ? "image/jpeg" : image.type,
                imageWidth: dimensions.width,
                imageHeight: dimensions.height,
                language: "zh-CN",
                maxObjects: 8,
            });
            stage = "serialize_response";
            logger.info("vision.request_completed", {
                requestId,
                provider: providerName,
                model: providerModel,
                objectCount: result.objects.length,
                durationMs: Math.round(performance.now() - providerStartedAt),
            });
            return c.json(result);
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
