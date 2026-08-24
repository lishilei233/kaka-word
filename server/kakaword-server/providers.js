import { z } from "zod";
import { analyzeResultSchema } from "./types.js";
import { extractJson, learningObjectPrompt, qwenLearningObjectPrompt } from "./prompt.js";
const env = (name, fallback = "") => process.env[name] ?? fallback;
class MockVisionProvider {
    async analyze(input) {
        return {
            imageWidth: input.imageWidth,
            imageHeight: input.imageHeight,
            objects: [
                {
                    id: "obj_01",
                    english: "mug",
                    chinese: "杯子",
                    ipa: "/mʌɡ/",
                    confidence: 0.96,
                    box: { x: 0.58, y: 0.43, width: 0.22, height: 0.28 },
                    anchor: { x: 0.69, y: 0.57 },
                    example: "This is a mug.",
                },
                {
                    id: "obj_02",
                    english: "book",
                    chinese: "书",
                    ipa: "/bʊk/",
                    confidence: 0.93,
                    box: { x: 0.12, y: 0.57, width: 0.30, height: 0.20 },
                    anchor: { x: 0.27, y: 0.67 },
                    example: "I am reading a book.",
                },
                {
                    id: "obj_03",
                    english: "plant",
                    chinese: "植物",
                    ipa: "/plænt/",
                    confidence: 0.91,
                    box: { x: 0.08, y: 0.12, width: 0.22, height: 0.34 },
                    anchor: { x: 0.19, y: 0.29 },
                    example: "The plant is green.",
                },
            ],
        };
    }
}
const qwenResultSchema = z.object({
    objects: z.array(z.object({
        id: z.string().min(1).max(40),
        english: z.string().min(1).max(60),
        chinese: z.string().min(1).max(60),
        ipa: z.string().max(80).default(""),
        confidence: z.number().min(0).max(1).default(0.8),
        bbox: z.tuple([z.number(), z.number(), z.number(), z.number()]),
        anchor: z.tuple([z.number(), z.number()]).optional(),
        example: z.string().min(1).max(180),
    })).max(8),
});
class QwenVisionProvider {
    async analyze(input) {
        const key = env("QWEN_API_KEY");
        if (!key)
            throw new Error("QWEN_API_KEY is required");
        const data = Buffer.from(input.image).toString("base64");
        const response = await fetch(qwenEndpoint(), {
            method: "POST",
            headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
            body: JSON.stringify({
                model: env("QWEN_MODEL", "qwen3.7-plus"),
                stream: false,
                enable_thinking: false,
                response_format: { type: "json_object" },
                messages: [{
                        role: "user",
                        content: [
                            { type: "text", text: qwenLearningObjectPrompt(input.maxObjects) },
                            { type: "image_url", image_url: { url: `data:${input.mimeType};base64,${data}` } },
                        ],
                    }],
            }),
        });
        if (!response.ok) {
            const body = await response.text().catch(() => "");
            throw new Error(`Qwen failed (${response.status}): ${body.slice(0, 240)}`);
        }
        const payload = await response.json();
        const content = payload?.choices?.[0]?.message?.content;
        if (typeof content !== "string")
            throw new Error("Qwen response did not contain message content");
        const parsed = qwenResultSchema.parse(extractJson(content));
        return analyzeResultSchema.parse({
            imageWidth: input.imageWidth,
            imageHeight: input.imageHeight,
            objects: parsed.objects.map((object, index) => {
                const [rawX1, rawY1, rawX2, rawY2] = object.bbox;
                const left = normalizeQwenCoordinate(Math.min(rawX1, rawX2));
                const top = normalizeQwenCoordinate(Math.min(rawY1, rawY2));
                const right = normalizeQwenCoordinate(Math.max(rawX1, rawX2));
                const bottom = normalizeQwenCoordinate(Math.max(rawY1, rawY2));
                return {
                    ...object,
                    id: object.id || `obj_${String(index + 1).padStart(2, "0")}`,
                    box: { x: left, y: top, width: right - left, height: bottom - top },
                    anchor: object.anchor
                        ? { x: normalizeQwenCoordinate(object.anchor[0]), y: normalizeQwenCoordinate(object.anchor[1]) }
                        : { x: (left + right) / 2, y: (top + bottom) / 2 },
                };
            }),
        });
    }
}
function qwenEndpoint() {
    const rawHost = env("QWEN_API_HOST").trim().replace(/\/+$/, "");
    if (!rawHost)
        throw new Error("QWEN_API_HOST is required");
    const host = /^https?:\/\//i.test(rawHost) ? rawHost : `https://${rawHost}`;
    if (host.endsWith("/chat/completions"))
        return host;
    if (host.endsWith("/compatible-mode/v1"))
        return `${host}/chat/completions`;
    return `${host}/compatible-mode/v1/chat/completions`;
}
function normalizeQwenCoordinate(value) {
    return Math.max(0, Math.min(1, value / 999));
}
class HttpVisionProvider {
    async parseResponse(response) {
        if (!response.ok) {
            const body = await response.text().catch(() => "");
            throw new Error(`Vision provider failed (${response.status}): ${body.slice(0, 240)}`);
        }
        const payload = await response.json();
        const text = this.extractText(payload);
        return analyzeResultSchema.parse(extractJson(text));
    }
}
class VolcengineVisionProvider extends HttpVisionProvider {
    extractText(payload) {
        const content = payload?.choices?.[0]?.message?.content;
        if (typeof content === "string")
            return content;
        if (Array.isArray(content))
            return content.map((part) => part?.text ?? "").join("");
        throw new Error("Volcengine response did not contain message content");
    }
    async analyze(input) {
        const key = env("VOLCENGINE_API_KEY");
        const model = env("VOLCENGINE_MODEL");
        if (!key || !model)
            throw new Error("VOLCENGINE_API_KEY and VOLCENGINE_MODEL are required");
        const data = Buffer.from(input.image).toString("base64");
        const response = await fetch(env("VOLCENGINE_ENDPOINT", "https://ark.cn-beijing.volces.com/api/v3/chat/completions"), {
            method: "POST",
            headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
            body: JSON.stringify({
                model,
                stream: false,
                temperature: 0.1,
                max_tokens: 1600,
                messages: [{
                        role: "user",
                        content: [
                            { type: "image_url", image_url: { url: `data:${input.mimeType};base64,${data}` } },
                            { type: "text", text: learningObjectPrompt(input.maxObjects) },
                        ],
                    }],
            }),
        });
        const result = await this.parseResponse(response);
        return { ...result, imageWidth: input.imageWidth, imageHeight: input.imageHeight };
    }
}
class GeminiVisionProvider extends HttpVisionProvider {
    extractText(payload) {
        const parts = payload?.candidates?.[0]?.content?.parts;
        if (!Array.isArray(parts))
            throw new Error("Gemini response did not contain content parts");
        return parts.map((part) => part?.text ?? "").join("");
    }
    async analyze(input) {
        const key = env("GEMINI_API_KEY");
        const model = env("GEMINI_MODEL", "gemini-3.6-flash");
        if (!key)
            throw new Error("GEMINI_API_KEY is required");
        const data = Buffer.from(input.image).toString("base64");
        const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
            method: "POST",
            headers: { "x-goog-api-key": key, "Content-Type": "application/json" },
            body: JSON.stringify({
                contents: [{ parts: [
                            { inline_data: { mime_type: input.mimeType, data } },
                            { text: learningObjectPrompt(input.maxObjects) },
                        ] }],
                generationConfig: { temperature: 0.1, responseMimeType: "application/json" },
            }),
        });
        const result = await this.parseResponse(response);
        return { ...result, imageWidth: input.imageWidth, imageHeight: input.imageHeight };
    }
}
export function createVisionProvider() {
    switch (env("VISION_PROVIDER", "qwen")) {
        case "qwen": return new QwenVisionProvider();
        case "volcengine": return new VolcengineVisionProvider();
        case "gemini": return new GeminiVisionProvider();
        case "mock": return new MockVisionProvider();
        default: throw new Error("VISION_PROVIDER must be qwen, mock, volcengine, or gemini");
    }
}
