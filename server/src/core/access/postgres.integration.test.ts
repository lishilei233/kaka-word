import "dotenv/config";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { Pool } from "pg";
import type { AccessConfig } from "../../config.js";
import type { Logger } from "../../utils/logger.js";
import { PostgresAccessService } from "./postgres.js";
import type {
  DeviceChecking,
  StoreNotification,
  StoreSignedDataVerifying,
  SubscriptionTransaction,
} from "./types.js";

const testDatabaseURL = process.env.TEST_DATABASE_URL?.trim();
const logger: Logger = { debug() {}, info() {}, warn() {}, error() {} };

test("PostgreSQL access quotas are atomic, idempotent, and shared by Apple purchase identity", {
  skip: !testDatabaseURL && "TEST_DATABASE_URL is not configured",
}, async (t) => {
  assert.ok(testDatabaseURL);
  const schema = `picture_word_access_${process.pid}_${Date.now()}`;
  const adminPool = new Pool({ connectionString: testDatabaseURL });
  await adminPool.query(`CREATE SCHEMA ${schema}`);
  t.after(async () => {
    await adminPool.query(`DROP SCHEMA IF EXISTS ${schema} CASCADE`);
    await adminPool.end();
  });

  const isolatedURL = new URL(testDatabaseURL);
  isolatedURL.searchParams.set("options", `-c search_path=${schema}`);
  const migration = [
    await readFile(new URL("../../../migrations/002_subscriptions.sql", import.meta.url), "utf8"),
    await readFile(new URL("../../../migrations/003_subscription_transactions.sql", import.meta.url), "utf8"),
  ].join("\n");
  const setupPool = new Pool({ connectionString: isolatedURL.toString() });
  await setupPool.query(migration);
  await setupPool.query(migration);

  const verifier = new FakeStoreVerifier();
  const deviceCheck = new FakeDeviceCheck();
  const serviceConfig = accessConfig(isolatedURL.toString());
  const service = new PostgresAccessService(serviceConfig, verifier, deviceCheck, logger);
  t.after(async () => {
    await service.close();
    await setupPool.end();
  });

  const firstBootstrap = await service.bootstrap({ installationId: randomUUID(), deviceToken: "device-a-token-value" });
  const firstPrincipal = await service.authenticate(`Bearer ${firstBootstrap.accessToken}`);
  assert.ok(firstPrincipal);

  const freeReservations = await Promise.all(
    Array.from({ length: 4 }, () => service.reserveAnalyze(firstPrincipal, randomUUID(), "device-a-token-value")),
  );
  assert.equal(freeReservations.filter((result) => result.allowed).length, 3);
  for (const result of freeReservations) {
    if (result.allowed) await service.commitAnalyze(result.reservationId, "device-a-token-value");
  }
  assert.equal((await service.status(firstPrincipal)).remaining, 0);
  assert.equal(deviceCheck.bits.get("device-a-token-value"), 3);

  const reinstall = await service.bootstrap({ installationId: randomUUID(), deviceToken: "device-a-token-value" });
  assert.equal(reinstall.entitlement.used, 3);
  assert.equal(reinstall.entitlement.remaining, 0);

  const memberTransaction = verifier.transaction;
  const firstMemberEntitlement = (await service.syncSubscription(firstPrincipal, "signed-transaction")).entitlement;
  assert.equal(firstMemberEntitlement.tier, "member");
  await service.syncSubscription(firstPrincipal, "signed-transaction-retry");
  assert.equal((await setupPool.query("SELECT COUNT(*)::integer AS count FROM picture_word_subscription_transactions")).rows[0].count, 1);
  const firstMemberReservation = await service.reserveAnalyze(firstPrincipal, randomUUID());
  assert.equal(firstMemberReservation.allowed, true);
  if (!firstMemberReservation.allowed) throw new Error("expected member reservation");
  await service.commitAnalyze(firstMemberReservation.reservationId);

  const secondBootstrap = await service.bootstrap({ installationId: randomUUID(), deviceToken: "device-b-token-value" });
  const secondPrincipal = await service.authenticate(`Bearer ${secondBootstrap.accessToken}`);
  assert.ok(secondPrincipal);
  verifier.transaction = memberTransaction;
  const secondMemberEntitlement = (await service.syncSubscription(secondPrincipal, "same-original-transaction")).entitlement;
  assert.equal(secondMemberEntitlement.used, 1);
  assert.equal(secondMemberEntitlement.remaining, 99);

  verifier.transaction = {
    ...memberTransaction,
    transactionId: "200000000000002",
    productId: "com.kakaword.app.membership.month",
    purchaseDate: new Date(memberTransaction.purchaseDate.getTime() + 60_000),
    expiresDate: new Date(Date.now() + 31 * 24 * 60 * 60 * 1_000),
  };
  const switchedEntitlement = (await service.syncSubscription(secondPrincipal, "newer-plan-transaction")).entitlement;
  assert.equal(switchedEntitlement.productId, "com.kakaword.app.membership.month");
  assert.equal((await setupPool.query("SELECT COUNT(*)::integer AS count FROM picture_word_subscription_transactions")).rows[0].count, 2);

  verifier.transaction = memberTransaction;
  const replayedOldEntitlement = (await service.syncSubscription(secondPrincipal, "older-plan-transaction")).entitlement;
  assert.equal(replayedOldEntitlement.productId, "com.kakaword.app.membership.month");

  verifier.transaction = {
    ...memberTransaction,
    originalTransactionId: "100000000000777",
    transactionId: "200000000000777",
    originalPurchaseDate: new Date(Date.now() - 2 * 60 * 60 * 1_000),
    purchaseDate: new Date(Date.now() - 2 * 60 * 60 * 1_000),
    expiresDate: new Date(Date.now() - 60 * 60 * 1_000),
  };
  const expiredResult = await service.syncSubscription(secondPrincipal, "expired-unfinished-transaction");
  assert.equal(expiredResult.syncedTransactionState, "expired");
  assert.equal(expiredResult.entitlement.tier, "free");
  const principalAfterExpiredAudit = await service.authenticate(`Bearer ${secondBootstrap.accessToken}`);
  assert.equal(principalAfterExpiredAudit?.originalTransactionId, memberTransaction.originalTransactionId);

  const thirdBootstrap = await service.bootstrap({ installationId: randomUUID(), deviceToken: "device-c-token-value" });
  const thirdPrincipal = await service.authenticate(`Bearer ${thirdBootstrap.accessToken}`);
  assert.ok(thirdPrincipal);
  verifier.transaction = {
    ...memberTransaction,
    originalTransactionId: "100000000000999",
    transactionId: "200000000000999",
  };
  const isolatedEntitlement = (await service.syncSubscription(thirdPrincipal, "different-original-transaction")).entitlement;
  assert.equal(isolatedEntitlement.used, 0);
  assert.equal(isolatedEntitlement.remaining, 100);

  const concurrentMemberReservations = await Promise.all(
    Array.from({ length: 100 }, () => service.reserveAnalyze(secondPrincipal, randomUUID())),
  );
  assert.equal(concurrentMemberReservations.filter((result) => result.allowed).length, 99);
  const status = await service.status(secondPrincipal);
  assert.equal(status.used, 1);
  assert.equal(status.reserved, 99);
  assert.equal(status.remaining, 0);

  serviceConfig.memberQuotaUnlimited = true;
  const environmentUnlimited = await service.status(secondPrincipal);
  assert.equal(environmentUnlimited.unlimited, true);
  assert.equal((await service.reserveAnalyze(secondPrincipal, randomUUID())).allowed, true);
});

function accessConfig(databaseURL: string): AccessConfig {
  return {
    enabled: true,
    databaseURL,
    tokenHashSecret: "integration-access-secret-at-least-32-characters",
    tokenTTLSeconds: 3_600,
    bundleId: "com.kakaword.app",
    appAppleId: 123456789,
    appleRootCertificatePaths: [],
    appleOnlineChecks: false,
    monthlyProductId: "com.kakaword.app.membership.month",
    annualProductId: "com.kakaword.app.membership.annual",
    deviceCheck: { keyId: "test", teamId: "test", privateKey: "test", environment: "development" },
  };
}

class FakeDeviceCheck implements DeviceChecking {
  readonly bits = new Map<string, number>();
  async queryBits(deviceToken: string): Promise<number> { return this.bits.get(deviceToken) ?? 0; }
  async updateBits(deviceToken: string, usedCount: number): Promise<void> { this.bits.set(deviceToken, usedCount); }
}

class FakeStoreVerifier implements StoreSignedDataVerifying {
  transaction: SubscriptionTransaction = {
    environment: "Sandbox",
    originalTransactionId: "100000000000001",
    transactionId: "200000000000001",
    productId: "com.kakaword.app.membership.annual",
    originalPurchaseDate: new Date(Date.now() - 24 * 60 * 60 * 1_000),
    purchaseDate: new Date(Date.now() - 24 * 60 * 60 * 1_000),
    expiresDate: new Date(Date.now() + 365 * 24 * 60 * 60 * 1_000),
    revokedAt: null,
    gracePeriodExpiresDate: null,
    autoRenewEnabled: true,
  };

  async verifyTransaction(): Promise<SubscriptionTransaction> { return this.transaction; }
  async verifyNotification(): Promise<StoreNotification> {
    throw new Error("not used");
  }
}
