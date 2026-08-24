import { PostgresAnalyzeUsageLimiter } from "./postgres.js";
import { DisabledAnalyzeUsageLimiter } from "./types.js";
export function createAnalyzeUsageLimiter(config, logger) {
    if (!config.enabled)
        return new DisabledAnalyzeUsageLimiter();
    return new PostgresAnalyzeUsageLimiter({
        databaseURL: config.databaseURL,
        ipHashSecret: config.ipHashSecret,
        perMinute: config.perMinute,
        dailyLimit: config.dailyLimit,
        dailyTimeZone: config.dailyTimeZone,
    }, logger);
}
export { DisabledAnalyzeUsageLimiter } from "./types.js";
