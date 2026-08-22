export type VisionProviderName = "qwen" | "volcengine" | "gemini" | "mock";

export type VisionProviderConfig =
  | { name: "qwen"; apiKey: string; apiHost: string; model: string }
  | { name: "volcengine"; apiKey: string; endpoint: string; model: string }
  | { name: "gemini"; apiKey: string; model: string }
  | { name: "mock"; model: "mock" };
