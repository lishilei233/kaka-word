import type { VisionProviderConfig, VisionProviderName } from "./core/image-analysis/providers/types.js";
import type { LogLevel } from "./utils/logger.js";

export type ServerConfig = {
  port: number;
  maxUploadBytes: number;
  logLevel: LogLevel;
  vision: VisionProviderConfig;
  usageLimits: UsageLimitConfig;
  access: AccessConfig;
};

export type AccessConfig = {
  enabled: boolean;
  databaseURL: string;
  tokenHashSecret: string;
  tokenTTLSeconds: number;
  bundleId: string;
  appAppleId?: number;
  appleRootCertificatePaths: string[];
  appleOnlineChecks: boolean;
  monthlyProductId: string;
  annualProductId: string;
  deviceCheck: DeviceCheckConfig;
};

export type DeviceCheckConfig = {
  keyId: string;
  teamId: string;
  privateKey: string;
  environment: "development" | "production";
};

export type UsageLimitConfig = {
  enabled: boolean;
  databaseURL: string;
  ipHashSecret: string;
  perMinute: number;
  dailyLimit: number;
  dailyTimeZone: string;
  trustProxy: boolean;
};

const DEFAULT_MAX_UPLOAD_BYTES = 5 * 1024 * 1024;

export function readServerConfig(environment: NodeJS.ProcessEnv = process.env): ServerConfig {
  const vision = readVisionConfig(environment);
  return {
    port: Number(environment.PORT ?? 8787),
    maxUploadBytes: DEFAULT_MAX_UPLOAD_BYTES,
    logLevel: readLogLevel(environment.LOG_LEVEL),
    vision,
    usageLimits: readUsageLimitConfig(environment),
    access: readAccessConfig(environment, vision.name !== "mock"),
  };
}

function readAccessConfig(environment: NodeJS.ProcessEnv, defaultEnabled: boolean): AccessConfig {
  const enabled = readBoolean(environment.ACCESS_CONTROL_ENABLED, defaultEnabled, "ACCESS_CONTROL_ENABLED");
  const appAppleId = readOptionalPositiveInteger(environment.APPLE_APP_ID, "APPLE_APP_ID");
  const config: AccessConfig = {
    enabled,
    databaseURL: environment.DATABASE_URL?.trim() ?? "",
    tokenHashSecret: environment.ACCESS_TOKEN_HASH_SECRET?.trim() ?? "",
    tokenTTLSeconds: readPositiveInteger(environment.ACCESS_TOKEN_TTL_SECONDS, 90 * 24 * 60 * 60, "ACCESS_TOKEN_TTL_SECONDS"),
    bundleId: environment.APPLE_BUNDLE_ID?.trim() || "com.kakaword.app",
    appAppleId,
    appleRootCertificatePaths: (environment.APPLE_ROOT_CERTIFICATE_PATHS ?? "")
      .split(",")
      .map((value) => value.trim())
      .filter(Boolean),
    appleOnlineChecks: readBoolean(environment.APPLE_JWS_ONLINE_CHECKS, true, "APPLE_JWS_ONLINE_CHECKS"),
    monthlyProductId: environment.APPLE_MONTHLY_PRODUCT_ID?.trim() || "com.kakaword.app.membership.monthly",
    annualProductId: environment.APPLE_ANNUAL_PRODUCT_ID?.trim() || "com.kakaword.app.membership.annual",
    deviceCheck: {
      keyId: environment.DEVICECHECK_KEY_ID?.trim() ?? "",
      teamId: environment.APPLE_TEAM_ID?.trim() ?? "",
      privateKey: normalizeMultilineSecret(environment.DEVICECHECK_PRIVATE_KEY ?? ""),
      environment: readDeviceCheckEnvironment(environment.DEVICECHECK_ENVIRONMENT),
    },
  };

  if (!enabled) return config;
  if (!config.databaseURL) throw new Error("DATABASE_URL is required when access control is enabled");
  if (config.tokenHashSecret.length < 32) {
    throw new Error("ACCESS_TOKEN_HASH_SECRET must contain at least 32 characters");
  }
  if (!config.appAppleId) throw new Error("APPLE_APP_ID is required when access control is enabled");
  if (config.appleRootCertificatePaths.length === 0) {
    throw new Error("APPLE_ROOT_CERTIFICATE_PATHS is required when access control is enabled");
  }
  if (!config.deviceCheck.keyId) throw new Error("DEVICECHECK_KEY_ID is required when access control is enabled");
  if (!config.deviceCheck.teamId) throw new Error("APPLE_TEAM_ID is required when access control is enabled");
  if (!config.deviceCheck.privateKey) {
    throw new Error("DEVICECHECK_PRIVATE_KEY is required when access control is enabled");
  }
  return config;
}

function readUsageLimitConfig(environment: NodeJS.ProcessEnv): UsageLimitConfig {
  const enabled = readBoolean(environment.USAGE_LIMIT_ENABLED, true, "USAGE_LIMIT_ENABLED");
  const config: UsageLimitConfig = {
    enabled,
    databaseURL: environment.DATABASE_URL?.trim() ?? "",
    ipHashSecret: environment.RATE_LIMIT_IP_HASH_SECRET?.trim() ?? "",
    perMinute: readPositiveInteger(environment.ANALYZE_RATE_LIMIT_PER_MINUTE, 10, "ANALYZE_RATE_LIMIT_PER_MINUTE"),
    dailyLimit: readPositiveInteger(environment.ANALYZE_DAILY_LIMIT, 500, "ANALYZE_DAILY_LIMIT"),
    dailyTimeZone: environment.ANALYZE_DAILY_TIME_ZONE?.trim() || "Asia/Shanghai",
    trustProxy: readBoolean(environment.TRUST_PROXY, false, "TRUST_PROXY"),
  };

  if (!enabled) return config;
  if (!config.databaseURL) throw new Error("DATABASE_URL is required when usage limits are enabled");
  if (config.ipHashSecret.length < 32) {
    throw new Error("RATE_LIMIT_IP_HASH_SECRET must contain at least 32 characters");
  }
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: config.dailyTimeZone }).format();
  } catch {
    throw new Error("ANALYZE_DAILY_TIME_ZONE must be a valid IANA time zone");
  }
  return config;
}

function readVisionConfig(environment: NodeJS.ProcessEnv): VisionProviderConfig {
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

function readProviderName(value: string | undefined): VisionProviderName {
  const name = value ?? "qwen";
  if (name === "qwen" || name === "volcengine" || name === "gemini" || name === "mock") {
    return name;
  }
  throw new Error("VISION_PROVIDER must be qwen, mock, volcengine, or gemini");
}

function readLogLevel(value: string | undefined): LogLevel {
  if (value === "debug" || value === "info" || value === "warn" || value === "error") {
    return value;
  }
  return "info";
}

function readPositiveInteger(value: string | undefined, fallback: number, name: string): number {
  const parsed = value == null || value === "" ? fallback : Number(value);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) throw new Error(`${name} must be a positive integer`);
  return parsed;
}

function readBoolean(value: string | undefined, fallback: boolean, name: string): boolean {
  if (value == null || value === "") return fallback;
  if (value === "true") return true;
  if (value === "false") return false;
  throw new Error(`${name} must be true or false`);
}

function readOptionalPositiveInteger(value: string | undefined, name: string): number | undefined {
  if (value == null || value.trim() === "") return undefined;
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) throw new Error(`${name} must be a positive integer`);
  return parsed;
}

function normalizeMultilineSecret(value: string): string {
  return value.trim().replaceAll("\\n", "\n");
}

function readDeviceCheckEnvironment(value: string | undefined): DeviceCheckConfig["environment"] {
  const normalized = value?.trim() || "production";
  if (normalized === "development" || normalized === "production") return normalized;
  throw new Error("DEVICECHECK_ENVIRONMENT must be development or production");
}
