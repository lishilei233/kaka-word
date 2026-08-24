import { extractJson } from "../response-json.js";
import { providerAnalyzeResultSchema, vocabularyDetailsSchema, } from "../types.js";
export class HttpVisionProvider {
    async parseResponse(response) {
        if (!response.ok) {
            const body = await response.text().catch(() => "");
            throw new Error(`Vision provider failed (${response.status}): ${body.slice(0, 240)}`);
        }
        const payload = await response.json();
        const text = this.extractText(payload);
        return providerAnalyzeResultSchema.parse(extractJson(text));
    }
    async parseVocabularyResponse(response) {
        if (!response.ok) {
            const body = await response.text().catch(() => "");
            throw new Error(`Vocabulary provider failed (${response.status}): ${body.slice(0, 240)}`);
        }
        const payload = await response.json();
        return vocabularyDetailsSchema.parse(extractJson(this.extractText(payload)));
    }
}
