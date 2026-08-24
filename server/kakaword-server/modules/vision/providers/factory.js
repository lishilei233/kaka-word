import { GeminiVisionProvider } from "./gemini.js";
import { MockVisionProvider } from "./mock.js";
import { QwenVisionProvider } from "./qwen.js";
import { VolcengineVisionProvider } from "./volcengine.js";
export function createVisionProvider(config) {
    switch (config.name) {
        case "qwen": return new QwenVisionProvider(config);
        case "volcengine": return new VolcengineVisionProvider(config);
        case "gemini": return new GeminiVisionProvider(config);
        case "mock": return new MockVisionProvider();
    }
}
