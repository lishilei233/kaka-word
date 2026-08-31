import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";
import { createApp } from "../app.js";
import type { ServerConfig } from "../config.js";
import {
  StoreSyncUnavailableError,
  StoreTransactionInvalidError,
} from "../core/access/index.js";
import type {
  AccessPrincipal,
  AccessService,
  BootstrapInput,
  BootstrapResult,
  EntitlementSummary,
  QuotaReservation,
  StoreSyncResult,
} from "../core/access/types.js";
import { MockVisionProvider } from "../core/image-analysis/providers/mock.js";
import type { AnalyzeUsageLimiter } from "../core/usage-limits/index.js";
import type { Logger } from "../utils/logger.js";

const logger: Logger = { debug() {}, info() {}, warn() {}, error() {} };
const config: ServerConfig = {
  port: 0,
  maxUploadBytes: 5 * 1024 * 1024,
  logLevel: "error",
  vision: { name: "mock", model: "mock" },
  usageLimits: {
    enabled: false,
    databaseURL: "",
    ipHashSecret: "",
    perMinute: 10,
    dailyLimit: 500,
    dailyTimeZone: "Asia/Shanghai",
    trustProxy: false,
  },
  access: {
    enabled: true,
    databaseURL: "postgres://unused",
    tokenHashSecret: "test-secret-that-is-at-least-32-characters",
    tokenTTLSeconds: 3_600,
    bundleId: "com.kakaword.app",
    appAppleId: 123456789,
    appleRootCertificatePaths: [],
    appleOnlineChecks: false,
    monthlyProductId: "com.kakaword.app.membership.month",
    annualProductId: "com.kakaword.app.membership.annual",
    deviceCheck: { keyId: "test", teamId: "test", privateKey: "test", environment: "development" },
  },
};

test("syncs a verified store transaction", async () => {
  const service = new FakeAccessService();
  const response = await appFor(service).request("/v1/store/sync", syncRequest());

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("x-request-id"), "store-test-request");
  assert.deepEqual(await response.json(), {
    entitlement: memberEntitlement,
    syncedTransactionState: "active",
  });
  assert.equal(service.syncCalls, 1);
});

test("returns the submitted transaction state independently of the final entitlement", async () => {
  const service = new FakeAccessService(undefined, {
    entitlement: freeEntitlement,
    syncedTransactionState: "expired",
  });
  const response = await appFor(service).request("/v1/store/sync", syncRequest());

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    entitlement: freeEntitlement,
    syncedTransactionState: "expired",
  });
});

test("rejects an active transaction without active member entitlement", async () => {
  const service = new FakeAccessService(undefined, {
    entitlement: freeEntitlement,
    syncedTransactionState: "active",
  });
  const response = await appFor(service).request("/v1/store/sync", syncRequest());

  assert.equal(response.status, 503);
  assert.equal((await response.json()).error, "STORE_SYNC_UNAVAILABLE");
});

test("rejects unauthenticated and malformed sync requests", async () => {
  const service = new FakeAccessService();
  const unauthenticated = await appFor(service).request("/v1/store/sync", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ signedTransaction: "x".repeat(64) }),
  });
  assert.equal(unauthenticated.status, 401);

  const malformed = await appFor(service).request("/v1/store/sync", syncRequest("short"));
  assert.equal(malformed.status, 400);
  assert.equal(service.syncCalls, 0);
});

test("returns 400 for a permanently invalid Apple transaction", async () => {
  const service = new FakeAccessService(new StoreTransactionInvalidError("bad jws"));
  const response = await appFor(service).request("/v1/store/sync", syncRequest());

  assert.equal(response.status, 400);
  assert.equal((await response.json()).error, "TRANSACTION_VERIFICATION_FAILED");
  assert.equal(response.headers.get("retry-after"), null);
});

test("returns retryable 503 for Apple and internal sync failures", async () => {
  for (const error of [new StoreSyncUnavailableError(), new Error("database unavailable")]) {
    const response = await appFor(new FakeAccessService(error)).request("/v1/store/sync", syncRequest());
    assert.equal(response.status, 503);
    assert.equal((await response.json()).error, "STORE_SYNC_UNAVAILABLE");
    assert.ok(Number(response.headers.get("retry-after")) > 0);
  }
});

function appFor(accessService: AccessService) {
  return createApp({
    config,
    provider: new MockVisionProvider(),
    usageLimiter: new NeverCalledLimiter(),
    accessService,
    logger,
  });
}

function syncRequest(signedTransaction = "signed-transaction-".padEnd(64, "x")): RequestInit {
  return {
    method: "POST",
    headers: {
      authorization: "Bearer test-access-token",
      "content-type": "application/json",
      "x-request-id": "store-test-request",
    },
    body: JSON.stringify({ signedTransaction }),
  };
}

const memberEntitlement: EntitlementSummary = {
  tier: "member",
  productId: "com.kakaword.app.membership.annual",
  subscriptionState: "active",
  limit: 100,
  used: 0,
  reserved: 0,
  remaining: 100,
  periodStart: "2026-08-01T00:00:00.000Z",
  resetAt: "2026-09-01T00:00:00.000Z",
  expiresAt: "2027-08-01T00:00:00.000Z",
  autoRenewEnabled: true,
  vocabularyCorrectionEnabled: true,
};

const freeEntitlement: EntitlementSummary = {
  tier: "free",
  productId: null,
  subscriptionState: "none",
  limit: 3,
  used: 0,
  reserved: 0,
  remaining: 3,
  periodStart: null,
  resetAt: null,
  expiresAt: null,
  autoRenewEnabled: null,
  vocabularyCorrectionEnabled: false,
};

class FakeAccessService implements AccessService {
  syncCalls = 0;
  private readonly principal: AccessPrincipal = {
    accessTokenHash: "test",
    installationId: randomUUID(),
    subscriptionEnvironment: null,
    originalTransactionId: null,
  };

  constructor(
    private readonly syncError?: Error,
    private readonly syncResult: StoreSyncResult = {
      entitlement: memberEntitlement,
      syncedTransactionState: "active",
    },
  ) {}

  async bootstrap(_input: BootstrapInput): Promise<BootstrapResult> {
    return { accessToken: "test-access-token", entitlement: memberEntitlement };
  }
  async authenticate(rawToken: string | undefined): Promise<AccessPrincipal | null> {
    return rawToken === "Bearer test-access-token" ? this.principal : null;
  }
  async status(): Promise<EntitlementSummary> { return memberEntitlement; }
  async syncSubscription(): Promise<StoreSyncResult> {
    this.syncCalls += 1;
    if (this.syncError) throw this.syncError;
    return this.syncResult;
  }
  async processStoreNotification(): Promise<void> {}
  async recordMetric(): Promise<void> {}
  async reserveAnalyze(): Promise<QuotaReservation> { throw new Error("not used"); }
  async commitAnalyze(): Promise<EntitlementSummary> { throw new Error("not used"); }
  async releaseAnalyze(): Promise<void> {}
  async close(): Promise<void> {}
}

class NeverCalledLimiter implements AnalyzeUsageLimiter {
  async consumeMinute(): Promise<never> { throw new Error("not used"); }
  async consumeDaily(): Promise<never> { throw new Error("not used"); }
  async close(): Promise<void> {}
}
