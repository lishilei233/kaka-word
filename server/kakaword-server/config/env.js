const DEFAULT_MAX_UPLOAD_BYTES = 5 * 1024 * 1024;
export function readServerConfig(environment = process.env) {
    return {
        port: Number(environment.PORT ?? 8787),
        maxUploadBytes: DEFAULT_MAX_UPLOAD_BYTES,
        logLevel: readLogLevel(environment.LOG_LEVEL),
        vision: readVisionConfig(environment),
    };
}
function readVisionConfig(environment) {
    const name = readProviderName(environment.VISION_PROVIDER);
    switch (name) {
        case "qwen":
            return {
                name,
                apiKey: environment.QWEN_API_KEY ?? "",
                apiHost: environment.QWEN_API_HOST ?? "",
                model: environment.QWEN_MODEL ?? "qwen3.7-plus",
            };
        case "volcengine":
            return {
                name,
                apiKey: environment.VOLCENGINE_API_KEY ?? "",
                endpoint: environment.VOLCENGINE_ENDPOINT ?? "https://ark.cn-beijing.volces.com/api/v3/chat/completions",
                model: environment.VOLCENGINE_MODEL ?? "",
            };
        case "gemini":
            return {
                name,
                apiKey: environment.GEMINI_API_KEY ?? "",
                model: environment.GEMINI_MODEL ?? "gemini-3.6-flash",
            };
        case "mock":
            return { name, model: "mock" };
    }
}
function readProviderName(value) {
    const name = value ?? "qwen";
    if (name === "qwen" || name === "volcengine" || name === "gemini" || name === "mock") {
        return name;
    }
    throw new Error("VISION_PROVIDER must be qwen, mock, volcengine, or gemini");
}
function readLogLevel(value) {
    if (value === "debug" || value === "info" || value === "warn" || value === "error") {
        return value;
    }
    return "info";
}
