export type UsageLimitDecision =
  | { allowed: true; remaining: number }
  | { allowed: false; retryAfterSeconds: number };

export interface AnalyzeUsageLimiter {
  consumeMinute(clientIP: string): Promise<UsageLimitDecision>;
  consumeDaily(): Promise<UsageLimitDecision>;
  close(): Promise<void>;
}

export class DisabledAnalyzeUsageLimiter implements AnalyzeUsageLimiter {
  async consumeMinute(): Promise<UsageLimitDecision> {
    return { allowed: true, remaining: Number.MAX_SAFE_INTEGER };
  }

  async consumeDaily(): Promise<UsageLimitDecision> {
    return { allowed: true, remaining: Number.MAX_SAFE_INTEGER };
  }

  async close(): Promise<void> {}
}
