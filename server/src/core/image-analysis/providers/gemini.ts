import { learningObjectPrompt, vocabularyPrompt } from "../prompts.js";
import type { AnalyzeResult, VisionInput, VocabularyDetails, VocabularyInput } from "../types.js";
import { HttpVisionProvider } from "./http-provider.js";

type GeminiConfig = { apiKey: string; model: string };

export class GeminiVisionProvider extends HttpVisionProvider {
  constructor(private readonly config: GeminiConfig) {
    super();
  }

  protected extractText(payload: any): string {
    const parts = payload?.candidates?.[0]?.content?.parts;
    if (!Array.isArray(parts)) throw new Error("Gemini response did not contain content parts");
    return parts.map((part) => part?.text ?? "").join("");
  }

  async analyze(input: VisionInput): Promise<AnalyzeResult> {
    if (!this.config.apiKey) throw new Error("GEMINI_API_KEY is required");
    const data = Buffer.from(input.image).toString("base64");
    const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${this.config.model}:generateContent`, {
      method: "POST",
      headers: { "x-goog-api-key": this.config.apiKey, "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [
          { inline_data: { mime_type: input.mimeType, data } },
          { text: learningObjectPrompt(input.maxObjects, input.captionStyle, input.masteredWords) },
        ] }],
        generationConfig: { temperature: 0.1, responseMimeType: "application/json" },
      }),
      signal: input.signal,
    });
    const result = await this.parseResponse(response);
    return {
      ...result,
      imageWidth: input.imageWidth,
      imageHeight: input.imageHeight,
      captionStyle: input.captionStyle,
    };
  }

  async resolveVocabulary(input: VocabularyInput): Promise<VocabularyDetails> {
    if (!this.config.apiKey) throw new Error("GEMINI_API_KEY is required");
    const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${this.config.model}:generateContent`, {
      method: "POST",
      headers: { "x-goog-api-key": this.config.apiKey, "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: vocabularyPrompt(input.term) }] }],
        generationConfig: { temperature: 0.1, responseMimeType: "application/json" },
      }),
      signal: input.signal,
    });
    return this.parseVocabularyResponse(response);
  }
}
