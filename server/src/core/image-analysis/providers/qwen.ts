import { z } from "zod";
import { qwenLearningObjectPrompt, vocabularyPrompt } from "../prompts.js";
import { extractJson } from "../response-json.js";
import { ObjectArrayStreamParser, readSSEData } from "../streaming-json.js";
import {
  analyzeResultSchema,
  vocabularyDetailsSchema,
  type AnalyzeResult,
  type VisionInput,
  type VisionProvider,
  type VocabularyDetails,
  type VocabularyInput,
} from "../types.js";

type QwenConfig = { apiKey: string; apiHost: string; model: string };

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
    exampleChinese: z.string().min(1).max(180).optional(),
    candidates: z.array(z.object({
      english: z.string().min(1).max(60),
      chinese: z.string().min(1).max(60),
      ipa: z.string().max(80).default(""),
      example: z.string().min(1).max(180),
      exampleChinese: z.string().min(1).max(180).optional(),
    })).min(2).max(3).optional(),
    confirmationStatus: z.enum(["confirmed", "needsConfirmation", "userConfirmed"]).default("confirmed"),
  })).max(10),
  caption: z.string().min(1).max(220),
  captionChinese: z.string().min(1).max(220),
});

export class QwenVisionProvider implements VisionProvider {
  constructor(private readonly config: QwenConfig) {}

  async analyze(input: VisionInput): Promise<AnalyzeResult> {
    return this.request(input, false);
  }

  async analyzeStream(
    input: VisionInput,
    onObject: (object: AnalyzeResult["objects"][number]) => Promise<void> | void,
  ): Promise<AnalyzeResult> {
    return this.request(input, true, onObject);
  }

  private async request(
    input: VisionInput,
    stream: boolean,
    onObject?: (object: AnalyzeResult["objects"][number]) => Promise<void> | void,
  ): Promise<AnalyzeResult> {
    if (!this.config.apiKey) throw new Error("QWEN_API_KEY is required");

    const data = Buffer.from(input.image).toString("base64");
    const response = await fetch(qwenEndpoint(this.config.apiHost), {
      method: "POST",
      headers: { Authorization: `Bearer ${this.config.apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: this.config.model,
        stream,
        enable_thinking: false,
        response_format: { type: "json_object" },
        messages: [{
          role: "user",
          content: [
            { type: "text", text: qwenLearningObjectPrompt(input.maxObjects, input.captionStyle, input.masteredWords) },
            { type: "image_url", image_url: { url: `data:${input.mimeType};base64,${data}` } },
          ],
        }],
      }),
      signal: input.signal,
    });

    if (!response.ok) {
      const body = await response.text().catch(() => "");
      throw new Error(`Qwen failed (${response.status}): ${body.slice(0, 240)}`);
    }

    if (!stream) {
      const payload = await response.json() as any;
      const content = payload?.choices?.[0]?.message?.content;
      if (typeof content !== "string") throw new Error("Qwen response did not contain message content");
      return this.parseResult(content, input);
    }

    if (!response.body) throw new Error("Qwen streaming response did not contain a body");
    const objectParser = new ObjectArrayStreamParser();
    let content = "";
    let objectIndex = 0;

    for await (const data of readSSEData(response.body)) {
      if (data === "[DONE]") break;
      const payload = JSON.parse(data) as any;
      const fragment = payload?.choices?.[0]?.delta?.content;
      if (typeof fragment !== "string" || !fragment) continue;
      content += fragment;

      for (const rawObject of objectParser.push(fragment)) {
        const parsedObject = qwenResultSchema.shape.objects.element.parse(rawObject);
        const object = normalizeObject(parsedObject, objectIndex);
        objectIndex += 1;
        await onObject?.(object);
      }
    }

    return this.parseResult(content, input);
  }

  private parseResult(content: string, input: VisionInput): AnalyzeResult {
    const parsed = qwenResultSchema.parse(extractJson(content));

    return analyzeResultSchema.parse({
      imageWidth: input.imageWidth,
      imageHeight: input.imageHeight,
      objects: parsed.objects.map(normalizeObject),
      caption: parsed.caption,
      captionChinese: parsed.captionChinese,
      captionStyle: input.captionStyle,
    });
  }

  async resolveVocabulary(input: VocabularyInput): Promise<VocabularyDetails> {
    if (!this.config.apiKey) throw new Error("QWEN_API_KEY is required");
    const response = await fetch(qwenEndpoint(this.config.apiHost), {
      method: "POST",
      headers: { Authorization: `Bearer ${this.config.apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: this.config.model,
        stream: false,
        enable_thinking: false,
        response_format: { type: "json_object" },
        messages: [{ role: "user", content: vocabularyPrompt(input.term) }],
      }),
      signal: input.signal,
    });
    if (!response.ok) {
      const body = await response.text().catch(() => "");
      throw new Error(`Qwen failed (${response.status}): ${body.slice(0, 240)}`);
    }
    const payload = await response.json() as any;
    const content = payload?.choices?.[0]?.message?.content;
    if (typeof content !== "string") throw new Error("Qwen response did not contain message content");
    return vocabularyDetailsSchema.parse(extractJson(content));
  }
}

type QwenObject = z.infer<typeof qwenResultSchema>["objects"][number];

function normalizeObject(object: QwenObject, index: number): AnalyzeResult["objects"][number] {
  const [rawX1, rawY1, rawX2, rawY2] = object.bbox;
  const left = normalizeCoordinate(Math.min(rawX1, rawX2));
  const top = normalizeCoordinate(Math.min(rawY1, rawY2));
  const right = normalizeCoordinate(Math.max(rawX1, rawX2));
  const bottom = normalizeCoordinate(Math.max(rawY1, rawY2));
  return analyzeResultSchema.shape.objects.element.parse({
    ...object,
    id: object.id || `obj_${String(index + 1).padStart(2, "0")}`,
    box: { x: left, y: top, width: right - left, height: bottom - top },
    anchor: object.anchor
      ? { x: normalizeCoordinate(object.anchor[0]), y: normalizeCoordinate(object.anchor[1]) }
      : { x: (left + right) / 2, y: (top + bottom) / 2 },
  });
}

function qwenEndpoint(apiHost: string): string {
  const rawHost = apiHost.trim().replace(/\/+$/, "");
  if (!rawHost) throw new Error("QWEN_API_HOST is required");
  const host = /^https?:\/\//i.test(rawHost) ? rawHost : `https://${rawHost}`;
  if (host.endsWith("/chat/completions")) return host;
  if (host.endsWith("/compatible-mode/v1")) return `${host}/chat/completions`;
  return `${host}/compatible-mode/v1/chat/completions`;
}

function normalizeCoordinate(value: number): number {
  return Math.max(0, Math.min(1, value / 999));
}
