export class DisabledAnalyzeUsageLimiter {
    async consumeMinute() {
        return { allowed: true, remaining: Number.MAX_SAFE_INTEGER };
    }
    async consumeDaily() {
        return { allowed: true, remaining: Number.MAX_SAFE_INTEGER };
    }
    async close() { }
}
