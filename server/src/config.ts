import type { VisionProviderConfig, VisionProviderName } from "./core/image-analysis/providers/types.js";
import type { LogLevel } from "./utils/logger.js";

export type ServerConfig = {
  port: number;
  maxUploadBytes: number;
  logLevel: LogLevel;
  vision: VisionProviderConfig;
  usageLimits: UsageLimitConfig;
  access: AccessConfig;
  videoStudioAccessToken?: string;
  appVersion?: AppVersionConfig;
  adminDashboard?: AdminDashboardConfig;
};

export type AdminDashboardConfig = {
  key?: string;
  databaseURL: string;
};

export type AppVersionConfig = {
  minimumSupportedVersion: string;
  latestVersion: string;
  forceUpgradeEffectiveAt?: string;
  configuredAt?: string;
  appStoreURL: string;
  updateTitle: string;
  updateMessage: string;
  releaseNotes: Record<string, AppReleaseNotes>;
};

export type AppReleaseNotes = {
  title: string;
  summary: string;
  items: string[];
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
  memberQuotaDefault?: number;
  memberQuotaUnlimited?: boolean;
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
  const access = readAccessConfig(environment, vision.name !== "mock");
  const videoStudioAccessToken = environment.VIDEO_STUDIO_ACCESS_TOKEN?.trim() || undefined;
  if (videoStudioAccessToken && videoStudioAccessToken.length < 32) {
    throw new Error("VIDEO_STUDIO_ACCESS_TOKEN must contain at least 32 characters");
  }
  const adminDashboardKey = environment.ADMIN_DASHBOARD_KEY?.trim() || undefined;
  if (adminDashboardKey && adminDashboardKey.length < 32) {
    throw new Error("ADMIN_DASHBOARD_KEY must contain at least 32 characters");
  }
  return {
    port: Number(environment.PORT ?? 8787),
    maxUploadBytes: DEFAULT_MAX_UPLOAD_BYTES,
    logLevel: readLogLevel(environment.LOG_LEVEL),
    vision,
    usageLimits: readUsageLimitConfig(environment),
    access,
    videoStudioAccessToken,
    appVersion: readAppVersionConfig(environment, access.appAppleId, access.enabled),
    adminDashboard: {
      key: adminDashboardKey,
      databaseURL: environment.DATABASE_URL?.trim() ?? "",
    },
  };
}

function readAppVersionConfig(environment: NodeJS.ProcessEnv, appAppleId: number | undefined, requireStoreURL: boolean): AppVersionConfig {
  const minimumSupportedVersion = environment.APP_MINIMUM_SUPPORTED_VERSION?.trim() || "0.1.0";
  const latestVersion = environment.APP_LATEST_VERSION?.trim() || "0.1.5";
  assertAppVersion(minimumSupportedVersion, "APP_MINIMUM_SUPPORTED_VERSION");
  assertAppVersion(latestVersion, "APP_LATEST_VERSION");
  if (compareAppVersions(minimumSupportedVersion, latestVersion) > 0) {
    throw new Error("APP_MINIMUM_SUPPORTED_VERSION must not exceed APP_LATEST_VERSION");
  }

  const configuredAt = readOptionalISODate(environment.APP_VERSION_CONFIGURED_AT, "APP_VERSION_CONFIGURED_AT");
  const forceUpgradeEffectiveAt = readOptionalISODate(
    environment.APP_FORCE_UPGRADE_EFFECTIVE_AT,
    "APP_FORCE_UPGRADE_EFFECTIVE_AT",
  );
  if (forceUpgradeEffectiveAt && (!configuredAt || Date.parse(forceUpgradeEffectiveAt) <= Date.parse(configuredAt))) {
    throw new Error("APP_FORCE_UPGRADE_EFFECTIVE_AT requires an earlier APP_VERSION_CONFIGURED_AT");
  }

  const configuredURL = environment.APP_STORE_URL?.trim();
  const appStoreURL = configuredURL || (appAppleId ? `https://apps.apple.com/app/id${appAppleId}` : "https://apps.apple.com/");
  if ((requireStoreURL && !configuredURL && !appAppleId) || !isHTTPSURL(appStoreURL)) {
    throw new Error("APP_STORE_URL or APPLE_APP_ID is required and must produce an HTTPS URL");
  }

  return {
    minimumSupportedVersion,
    latestVersion,
    forceUpgradeEffectiveAt,
    configuredAt,
    appStoreURL,
    updateTitle: readBoundedText(environment.APP_UPDATE_TITLE, "发现新版本", "APP_UPDATE_TITLE", 80),
    updateMessage: readBoundedText(
      environment.APP_UPDATE_MESSAGE,
      "更新后即可体验最新功能。",
      "APP_UPDATE_MESSAGE",
      300,
    ),
    releaseNotes: readReleaseNotes(environment.APP_RELEASE_NOTES_JSON),
  };
}

function readReleaseNotes(value: string | undefined): Record<string, AppReleaseNotes> {
  if (!value?.trim()) return {};
  let decoded: unknown;
  try {
    decoded = JSON.parse(value);
  } catch {
    throw new Error("APP_RELEASE_NOTES_JSON must be valid JSON");
  }
  if (!decoded || typeof decoded !== "object" || Array.isArray(decoded)) {
    throw new Error("APP_RELEASE_NOTES_JSON must be an object keyed by app version");
  }

  const notes: Record<string, AppReleaseNotes> = {};
  for (const [version, raw] of Object.entries(decoded)) {
    assertAppVersion(version, "APP_RELEASE_NOTES_JSON version key");
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new Error(`Invalid release notes for ${version}`);
    const entry = raw as Record<string, unknown>;
    if (typeof entry.title !== "string" || entry.title.trim().length === 0 || entry.title.length > 80
      || typeof entry.summary !== "string" || entry.summary.length > 300
      || !Array.isArray(entry.items) || entry.items.length > 12
      || entry.items.some((item) => typeof item !== "string" || item.trim().length === 0 || item.length > 160)) {
      throw new Error(`Invalid release notes for ${version}`);
    }
    notes[version] = {
      title: entry.title.trim(),
      summary: entry.summary.trim(),
      items: (entry.items as string[]).map((item) => item.trim()),
    };
  }
  return notes;
}

function assertAppVersion(value: string, name: string): void {
  if (!/^\d+(?:\.\d+){1,3}$/.test(value)) throw new Error(`${name} must be a numeric dotted version`);
}

function compareAppVersions(lhs: string, rhs: string): number {
  const left = lhs.split(".").map(Number);
  const right = rhs.split(".").map(Number);
  for (let index = 0; index < Math.max(left.length, right.length); index += 1) {
    const difference = (left[index] ?? 0) - (right[index] ?? 0);
    if (difference !== 0) return difference;
  }
  return 0;
}

function readOptionalISODate(value: string | undefined, name: string): string | undefined {
  const normalized = value?.trim();
  if (!normalized) return undefined;
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/.test(normalized) || Number.isNaN(Date.parse(normalized))) {
    throw new Error(`${name} must be an ISO 8601 UTC timestamp`);
  }
  return normalized;
}

function readBoundedText(value: string | undefined, fallback: string, name: string, maximumLength: number): string {
  const normalized = value?.trim() || fallback;
  if (normalized.length > maximumLength) throw new Error(`${name} must not exceed ${maximumLength} characters`);
  return normalized;
}

function isHTTPSURL(value: string): boolean {
  try {
    return new URL(value).protocol === "https:";
  } catch {
    return false;
  }
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
    monthlyProductId: environment.APPLE_MONTHLY_PRODUCT_ID?.trim() || "com.kakaword.app.membership.month",
    annualProductId: environment.APPLE_ANNUAL_PRODUCT_ID?.trim() || "com.kakaword.app.membership.annual",
    memberQuotaDefault: readNonNegativeInteger(environment.MEMBER_QUOTA_DEFAULT, 100, "MEMBER_QUOTA_DEFAULT"),
    memberQuotaUnlimited: readBoolean(environment.MEMBER_QUOTA_UNLIMITED, false, "MEMBER_QUOTA_UNLIMITED"),
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

function readNonNegativeInteger(value: string | undefined, fallback: number, name: string): number {
  const parsed = value == null || value === "" ? fallback : Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 0 || parsed > 1_000_000) {
    throw new Error(`${name} must be an integer between 0 and 1000000`);
  }
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
