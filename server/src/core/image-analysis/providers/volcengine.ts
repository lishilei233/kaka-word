import { learningObjectPrompt } from "../prompts.js";
import type { AnalyzeResult, VisionInput } from "../types.js";
import { HttpVisionProvider } from "./http-provider.js";

type VolcengineConfig = { apiKey: string; endpoint: string; model: string };

export class VolcengineVisionProvider extends HttpVisionProvider {
  constructor(private readonly config: VolcengineConfig) {
    super();
  }

  protected extractText(payload: any): string {
    const content = payload?.choices?.[0]?.message?.content;
    if (typeof content === "string") return content;
    if (Array.isArray(content)) return content.map((part) => part?.text ?? "").join("");
    throw new Error("Volcengine response did not contain message content");
  }

  async analyze(input: VisionInput): Promise<AnalyzeResult> {
    if (!this.config.apiKey || !this.config.model) {
      throw new Error("VOLCENGINE_API_KEY and VOLCENGINE_MODEL are required");
    }
    const data = Buffer.from(input.image).toString("base64");
    const response = await fetch(this.config.endpoint, {
      method: "POST",
      headers: { Authorization: `Bearer ${this.config.apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: this.config.model,
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
