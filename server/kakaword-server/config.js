const DEFAULT_MAX_UPLOAD_BYTES = 5 * 1024 * 1024;
export function readServerConfig(environment = process.env) {
    return {
        port: Number(environment.PORT ?? 8787),
        maxUploadBytes: DEFAULT_MAX_UPLOAD_BYTES,
        logLevel: readLogLevel(environment.LOG_LEVEL),
        vision: readVisionConfig(environment),
        usageLimits: readUsageLimitConfig(environment),
    };
}
function readUsageLimitConfig(environment) {
    const enabled = readBoolean(environment.USAGE_LIMIT_ENABLED, true, "USAGE_LIMIT_ENABLED");
    const config = {
        enabled,
        databaseURL: environment.DATABASE_URL?.trim() ?? "",
        ipHashSecret: environment.RATE_LIMIT_IP_HASH_SECRET?.trim() ?? "",
        perMinute: readPositiveInteger(environment.ANALYZE_RATE_LIMIT_PER_MINUTE, 10, "ANALYZE_RATE_LIMIT_PER_MINUTE"),
        dailyLimit: readPositiveInteger(environment.ANALYZE_DAILY_LIMIT, 500, "ANALYZE_DAILY_LIMIT"),
        dailyTimeZone: environment.ANALYZE_DAILY_TIME_ZONE?.trim() || "Asia/Shanghai",
        trustProxy: readBoolean(environment.TRUST_PROXY, false, "TRUST_PROXY"),
    };
    if (!enabled)
        return config;
    if (!config.databaseURL)
        throw new Error("DATABASE_URL is required when usage limits are enabled");
    if (config.ipHashSecret.length < 32) {
        throw new Error("RATE_LIMIT_IP_HASH_SECRET must contain at least 32 characters");
    }
    try {
        new Intl.DateTimeFormat("en-US", { timeZone: config.dailyTimeZone }).format();
    }
    catch {
        throw new Error("ANALYZE_DAILY_TIME_ZONE must be a valid IANA time zone");
    }
    return config;
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
function readPositiveInteger(value, fallback, name) {
    const parsed = value == null || value === "" ? fallback : Number(value);
    if (!Number.isSafeInteger(parsed) || parsed <= 0)
        throw new Error(`${name} must be a positive integer`);
    return parsed;
}
function readBoolean(value, fallback, name) {
    if (value == null || value === "")
        return fallback;
    if (value === "true")
        return true;
    if (value === "false")
        return false;
    throw new Error(`${name} must be true or false`);
}
