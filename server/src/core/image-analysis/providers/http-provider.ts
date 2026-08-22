import { extractJson } from "../response-json.js";
import { analyzeResultSchema, type AnalyzeResult, type VisionInput, type VisionProvider } from "../types.js";

export abstract class HttpVisionProvider implements VisionProvider {
  protected async parseResponse(response: Response): Promise<AnalyzeResult> {
    if (!response.ok) {
      const body = await response.text().catch(() => "");
      throw new Error(`Vision provider failed (${response.status}): ${body.slice(0, 240)}`);
    }
    const payload = await response.json() as unknown;
    const text = this.extractText(payload);
    return analyzeResultSchema.parse(extractJson(text));
  }

  protected abstract extractText(payload: unknown): string;
  abstract analyze(input: VisionInput): Promise<AnalyzeResult>;
}
