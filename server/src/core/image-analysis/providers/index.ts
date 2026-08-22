import type { VisionProvider } from "../types.js";
import { GeminiVisionProvider } from "./gemini.js";
import { MockVisionProvider } from "./mock.js";
import { QwenVisionProvider } from "./qwen.js";
import type { VisionProviderConfig } from "./types.js";
import { VolcengineVisionProvider } from "./volcengine.js";

export function createVisionProvider(config: VisionProviderConfig): VisionProvider {
  switch (config.name) {
    case "qwen": return new QwenVisionProvider(config);
    case "volcengine": return new VolcengineVisionProvider(config);
    case "gemini": return new GeminiVisionProvider(config);
    case "mock": return new MockVisionProvider();
  }
}
