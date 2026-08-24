import { extractJson } from "../response-json.js";
import {
  providerAnalyzeResultSchema,
  vocabularyDetailsSchema,
  type AnalyzeResult,
  type VisionInput,
  type VisionProvider,
  type VocabularyDetails,
  type VocabularyInput,
} from "../types.js";

export abstract class HttpVisionProvider implements VisionProvider {
  protected async parseResponse(response: Response): Promise<Omit<AnalyzeResult, "captionStyle">> {
    if (!response.ok) {
      const body = await response.text().catch(() => "");
      throw new Error(`Vision provider failed (${response.status}): ${body.slice(0, 240)}`);
    }
    const payload = await response.json() as unknown;
    const text = this.extractText(payload);
    return providerAnalyzeResultSchema.parse(extractJson(text));
  }

  protected async parseVocabularyResponse(response: Response): Promise<VocabularyDetails> {
    if (!response.ok) {
      const body = await response.text().catch(() => "");
      throw new Error(`Vocabulary provider failed (${response.status}): ${body.slice(0, 240)}`);
    }
    const payload = await response.json() as unknown;
    return vocabularyDetailsSchema.parse(extractJson(this.extractText(payload)));
  }

  protected abstract extractText(payload: unknown): string;
  abstract analyze(input: VisionInput): Promise<AnalyzeResult>;
  abstract resolveVocabulary(input: VocabularyInput): Promise<VocabularyDetails>;
}
