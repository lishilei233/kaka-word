import { learningObjectPrompt, vocabularyPrompt } from "../prompts.js";
import { HttpVisionProvider } from "./http-provider.js";
export class VolcengineVisionProvider extends HttpVisionProvider {
    config;
    constructor(config) {
        super();
        this.config = config;
    }
    extractText(payload) {
        const content = payload?.choices?.[0]?.message?.content;
        if (typeof content === "string")
            return content;
        if (Array.isArray(content))
            return content.map((part) => part?.text ?? "").join("");
        throw new Error("Volcengine response did not contain message content");
    }
    async analyze(input) {
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
                            { type: "text", text: learningObjectPrompt(input.maxObjects, input.captionStyle) },
                        ],
                    }],
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
    async resolveVocabulary(input) {
        if (!this.config.apiKey || !this.config.model) {
            throw new Error("VOLCENGINE_API_KEY and VOLCENGINE_MODEL are required");
        }
        const response = await fetch(this.config.endpoint, {
            method: "POST",
            headers: { Authorization: `Bearer ${this.config.apiKey}`, "Content-Type": "application/json" },
            body: JSON.stringify({
                model: this.config.model,
                stream: false,
                temperature: 0.1,
                max_tokens: 400,
                messages: [{ role: "user", content: [{ type: "text", text: vocabularyPrompt(input.term) }] }],
            }),
            signal: input.signal,
        });
        return this.parseVocabularyResponse(response);
    }
}
