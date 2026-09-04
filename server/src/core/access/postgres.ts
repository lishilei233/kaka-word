import { createHmac, randomBytes, randomUUID } from "node:crypto";
import { Pool, type PoolClient } from "pg";
import type { AccessConfig } from "../../config.js";
import type { Logger } from "../../utils/logger.js";
import { monthlyQuotaPeriod } from "./quota-period.js";
import { StoreSyncUnavailableError } from "./types.js";
import type {
  AccessEnvironment,
  AggregateMetricInput,
  AccessPrincipal,
  AccessService,
  BootstrapInput,
  BootstrapResult,
  DeviceChecking,
  EntitlementSummary,
  QuotaReservation,
  StoreNotification,
  StoreSignedDataVerifying,
  StoreSyncResult,
  SubscriptionState,
  SubscriptionTransaction,
} from "./types.js";

type InstallationRow = { id: string; free_used: number };
type AccessTokenRow = {
  token_hash: string;
  installation_id: string;
  subscription_environment: AccessEnvironment | null;
  original_transaction_id: string | null;
};
type SubscriptionRow = {
  environment: AccessEnvironment;
  original_transaction_id: string;
  product_id: string;
  state: Exclude<SubscriptionState, "none">;
  original_purchase_at: Date;
  expires_at: Date;
  grace_expires_at: Date | null;
  revoked_at: Date | null;
  auto_renew_enabled: boolean | null;
};
type QuotaPeriodRow = { used_count: number; reserved_count: number; quota_limit: number };
type OperationRow = {
  reservation_id: string;
  installation_id: string;
  subject_type: "free" | "subscription";
  subject_id: string;
  period_start: Date | null;
  state: "reserved" | "committed" | "released";
  lease_expires_at: Date;
};

const FREE_LIMIT = 3;
const UNLIMITED_MEMBER_LIMIT = 2_147_483_647;
const RESERVATION_TTL_MS = 10 * 60 * 1_000;

export class PostgresAccessService implements AccessService {
  private readonly pool: Pool;

  constructor(
    private readonly config: AccessConfig,
    private readonly verifier: StoreSignedDataVerifying,
    private readonly deviceCheck: DeviceChecking,
    private readonly logger: Logger,
  ) {
    this.pool = new Pool({ connectionString: config.databaseURL });
  }

  async bootstrap(input: BootstrapInput): Promise<BootstrapResult> {
    const deviceUsed = await this.deviceCheck.queryBits(input.deviceToken);
    const installationHash = this.hash(`installation:${input.installationId}`);
    const rawToken = randomBytes(32).toString("base64url");
    const tokenHash = this.hash(`access:${rawToken}`);
    const client = await this.pool.connect();
    let installationId = "";
    try {
      await client.query("BEGIN");
      const installation = await client.query<InstallationRow>(
        `
          INSERT INTO picture_word_installations (installation_hash, free_used)
          VALUES ($1, $2)
          ON CONFLICT (installation_hash) DO UPDATE
          SET free_used = GREATEST(picture_word_installations.free_used, EXCLUDED.free_used),
              updated_at = clock_timestamp()
          RETURNING id::text, free_used
        `,
        [installationHash, deviceUsed],
      );
      installationId = requiredRow(installation.rows[0], "installation").id;
      await client.query(
        `
          INSERT INTO picture_word_access_tokens (token_hash, installation_id, expires_at)
          VALUES ($1, $2::uuid, clock_timestamp() + ($3::text || ' seconds')::interval)
        `,
        [tokenHash, installationId, this.config.tokenTTLSeconds],
      );
      await client.query("COMMIT");
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }

    const principal: AccessPrincipal = {
      accessTokenHash: tokenHash,
      installationId,
      subscriptionEnvironment: null,
      originalTransactionId: null,
    };
    return { accessToken: rawToken, entitlement: await this.status(principal) };
  }

  async authenticate(rawToken: string | undefined): Promise<AccessPrincipal | null> {
    if (!rawToken?.startsWith("Bearer ")) return null;
    const value = rawToken.slice("Bearer ".length).trim();
    if (!value) return null;
    const tokenHash = this.hash(`access:${value}`);
    const result = await this.pool.query<AccessTokenRow>(
      `
        UPDATE picture_word_access_tokens
        SET last_used_at = clock_timestamp()
        WHERE token_hash = $1 AND expires_at > clock_timestamp()
        RETURNING token_hash, installation_id::text, subscription_environment, original_transaction_id
      `,
      [tokenHash],
    );
    const row = result.rows[0];
    if (!row) return null;
    return {
      accessTokenHash: row.token_hash,
      installationId: row.installation_id,
      subscriptionEnvironment: row.subscription_environment,
      originalTransactionId: row.original_transaction_id,
    };
  }

  async status(principal: AccessPrincipal): Promise<EntitlementSummary> {
    await this.cleanupExpiredReservations();
    const installation = await this.loadInstallation(principal.installationId);
    const subscription = await this.loadUsableSubscription(principal);
    if (!subscription) return freeEntitlement(installation.free_used);
    return await this.memberEntitlement(subscription);
  }

  async syncSubscription(
    principal: AccessPrincipal,
    signedTransaction: string,
    signedRenewalInfo?: string,
    requestId?: string,
  ): Promise<StoreSyncResult> {
    const transaction = await this.verifier.verifyTransaction(signedTransaction, signedRenewalInfo);
    const syncedTransactionState = notificationState(undefined, transaction);
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      await this.upsertSubscriptionTransaction(client, transaction);
      await this.upsertSubscription(client, transaction);
      // An audited inactive transaction must not detach this installation from a
      // different active subscription chain. Active/grace transactions are the
      // only proof that can become the token's current membership binding.
      if (syncedTransactionState === "active" || syncedTransactionState === "grace") {
        await client.query(
          `
            UPDATE picture_word_access_tokens
            SET subscription_environment = $1, original_transaction_id = $2
            WHERE token_hash = $3 AND installation_id = $4::uuid
          `,
          [transaction.environment, transaction.originalTransactionId, principal.accessTokenHash, principal.installationId],
        );
      }
      await client.query("COMMIT");
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
    const entitlement = await this.status({
      ...principal,
      subscriptionEnvironment: transaction.environment,
      originalTransactionId: transaction.originalTransactionId,
    });
    if ((syncedTransactionState === "active" || syncedTransactionState === "grace")
        && !isActiveMemberEntitlement(entitlement)) {
      throw new StoreSyncUnavailableError("Persisted active transaction did not produce an active entitlement");
    }
    this.logger.info("store.sync_completed", {
      requestId,
      environment: transaction.environment,
      productId: transaction.productId,
      syncedTransactionState,
      originalTransactionHash: this.hash(`store-original:${transaction.originalTransactionId}`).slice(0, 16),
      transactionHash: this.hash(`store-transaction:${transaction.transactionId}`).slice(0, 16),
    });
    return { entitlement, syncedTransactionState };
  }

  async processStoreNotification(signedPayload: string, requestId?: string): Promise<void> {
    const notification = await this.verifier.verifyNotification(signedPayload);
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      const inserted = await client.query(
        `
          INSERT INTO picture_word_store_notifications
            (environment, notification_uuid, notification_type, subtype)
          VALUES ($1, $2::uuid, $3, $4)
          ON CONFLICT (environment, notification_uuid) DO NOTHING
          RETURNING notification_uuid
        `,
        [notification.environment, notification.notificationUUID, notification.notificationType, notification.subtype],
      );
      if ((inserted.rowCount ?? 0) === 0) {
        await client.query("ROLLBACK");
        return;
      }
      if (notification.transaction) {
        await this.upsertSubscriptionTransaction(client, notification.transaction);
        await this.upsertSubscription(client, notification.transaction, notification);
      }
      await client.query("COMMIT");
      if (notification.transaction) {
        this.logger.info("store.notification_processed", {
          requestId,
          environment: notification.transaction.environment,
          productId: notification.transaction.productId,
          originalTransactionHash: this.hash(`store-original:${notification.transaction.originalTransactionId}`).slice(0, 16),
          transactionHash: this.hash(`store-transaction:${notification.transaction.transactionId}`).slice(0, 16),
        });
      }
      await this.recordMetric({
        eventName: "subscription_event",
        productId: notification.transaction?.productId,
        outcome: notification.notificationType,
      }).catch((error) => {
        this.logger.warn("metrics.subscription_event_failed", {
          notificationUUID: notification.notificationUUID,
          message: error instanceof Error ? error.message : String(error),
        });
      });
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }

  async recordMetric(input: AggregateMetricInput): Promise<void> {
    const eventName = input.eventName.trim().slice(0, 64);
    const productId = input.productId?.trim().slice(0, 128) ?? "";
    const outcome = input.outcome?.trim().slice(0, 64) ?? "";
    if (!eventName) return;
    await this.pool.query(
      `INSERT INTO picture_word_aggregate_metrics_daily
        (metric_date, event_name, product_id, outcome, event_count)
       VALUES ((clock_timestamp() AT TIME ZONE 'Asia/Shanghai')::date, $1, $2, $3, 1)
       ON CONFLICT (metric_date, event_name, product_id, outcome) DO UPDATE
       SET event_count = picture_word_aggregate_metrics_daily.event_count + 1,
           updated_at = clock_timestamp()`,
      [eventName, productId, outcome],
    );
  }

  async reserveAnalyze(
    principal: AccessPrincipal,
    operationId: string,
    deviceToken?: string,
  ): Promise<QuotaReservation> {
    const subscription = await this.loadUsableSubscription(principal);
    let deviceUsed: number | null = null;
    if (!subscription) {
      if (!deviceToken) throw new DeviceAttestationRequiredError();
      deviceUsed = await this.deviceCheck.queryBits(deviceToken);
      const installation = await this.loadInstallation(principal.installationId);
      if (installation.free_used > deviceUsed) {
        try {
          await this.deviceCheck.updateBits(deviceToken, installation.free_used);
          deviceUsed = installation.free_used;
          await this.clearDeviceCheckSyncTask(installation.id);
        } catch (error) {
          await this.recordDeviceCheckSyncFailure(installation.id, installation.free_used, error);
          this.logger.warn("device_check.resync_failed", {
            installationId: principal.installationId,
            freeUsed: installation.free_used,
            message: error instanceof Error ? error.message : String(error),
          });
        }
      }
    }

    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      await this.cleanupExpiredReservations(client);
      if (deviceUsed != null) {
        await client.query(
          `UPDATE picture_word_installations SET free_used = GREATEST(free_used, $1), updated_at = clock_timestamp() WHERE id = $2::uuid`,
          [deviceUsed, principal.installationId],
        );
      }

      const existing = await client.query<OperationRow>(
        `SELECT reservation_id::text, installation_id::text, subject_type, subject_id, period_start,
                state, lease_expires_at
         FROM picture_word_quota_operations WHERE operation_id = $1::uuid FOR UPDATE`,
        [operationId],
      );
      const existingRow = existing.rows[0];
      if (existingRow) {
        const entitlement = await this.entitlementInTransaction(client, principal);
        await client.query("COMMIT");
        if (existingRow.installation_id === principal.installationId && existingRow.state === "reserved"
            && existingRow.lease_expires_at > new Date()) {
          return { allowed: true, reservationId: existingRow.reservation_id, entitlement };
        }
        return { allowed: false, conflict: true, entitlement };
      }

      const currentSubscription = await this.loadUsableSubscription(principal, client);
      let result: QuotaReservation;
      if (currentSubscription) {
        result = await this.reserveMember(client, principal, operationId, currentSubscription);
      } else {
        result = await this.reserveFree(client, principal, operationId);
      }
      await client.query("COMMIT");
      return result;
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }

  async commitAnalyze(reservationId: string, deviceToken?: string): Promise<EntitlementSummary> {
    const client = await this.pool.connect();
    let freeUsed: number | null = null;
    let principal: AccessPrincipal | null = null;
    try {
      await client.query("BEGIN");
      const operation = await client.query<OperationRow>(
        `SELECT reservation_id::text, installation_id::text, subject_type, subject_id, period_start,
                state, lease_expires_at
         FROM picture_word_quota_operations WHERE reservation_id = $1::uuid FOR UPDATE`,
        [reservationId],
      );
      const row = requiredRow(operation.rows[0], "quota reservation");
      principal = await this.principalForOperation(client, row);
      if (row.state === "reserved" && row.lease_expires_at > new Date()) {
        if (row.subject_type === "free") {
          const updated = await client.query<InstallationRow>(
            `UPDATE picture_word_installations
             SET free_used = LEAST($1, free_used + 1), updated_at = clock_timestamp()
             WHERE id = $2::uuid RETURNING id::text, free_used`,
            [FREE_LIMIT, row.installation_id],
          );
          freeUsed = requiredRow(updated.rows[0], "installation").free_used;
        } else {
          await client.query(
            `UPDATE picture_word_quota_periods
             SET used_count = used_count + 1,
                 reserved_count = GREATEST(0, reserved_count - 1),
                 updated_at = clock_timestamp()
             WHERE subject_type = 'subscription' AND subject_id = $1 AND period_start = $2`,
            [row.subject_id, row.period_start],
          );
        }
        await client.query(
          `UPDATE picture_word_quota_operations
           SET state = 'committed', committed_at = clock_timestamp()
           WHERE reservation_id = $1::uuid`,
          [reservationId],
        );
      } else if (row.state === "reserved") {
        await this.releaseOperation(client, row);
      }
      const entitlement = await this.entitlementInTransaction(client, principal);
      await client.query("COMMIT");

      if (freeUsed != null && deviceToken) {
        try {
          await this.deviceCheck.updateBits(deviceToken, freeUsed);
          await this.clearDeviceCheckSyncTask(principal.installationId);
        } catch (error) {
          await this.recordDeviceCheckSyncFailure(principal.installationId, freeUsed, error);
          this.logger.warn("device_check.update_failed", {
            installationId: principal.installationId,
            freeUsed,
            message: error instanceof Error ? error.message : String(error),
          });
        }
      }
      return entitlement;
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }

  async releaseAnalyze(reservationId: string): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      const result = await client.query<OperationRow>(
        `SELECT reservation_id::text, installation_id::text, subject_type, subject_id, period_start,
                state, lease_expires_at
         FROM picture_word_quota_operations WHERE reservation_id = $1::uuid FOR UPDATE`,
        [reservationId],
      );
      if (result.rows[0]?.state === "reserved") await this.releaseOperation(client, result.rows[0]);
      await client.query("COMMIT");
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }

  async close(): Promise<void> {
    await this.pool.end();
  }

  private async reserveFree(
    client: PoolClient,
    principal: AccessPrincipal,
    operationId: string,
  ): Promise<QuotaReservation> {
    const installationResult = await client.query<InstallationRow>(
      `SELECT id::text, free_used FROM picture_word_installations WHERE id = $1::uuid FOR UPDATE`,
      [principal.installationId],
    );
    const installation = requiredRow(installationResult.rows[0], "installation");
    const reservedResult = await client.query<{ count: number }>(
      `SELECT COUNT(*)::integer AS count FROM picture_word_quota_operations
       WHERE installation_id = $1::uuid AND subject_type = 'free' AND state = 'reserved'
         AND lease_expires_at > clock_timestamp()`,
      [principal.installationId],
    );
    const reserved = reservedResult.rows[0]?.count ?? 0;
    if (installation.free_used + reserved >= FREE_LIMIT) {
      return { allowed: false, entitlement: freeEntitlement(installation.free_used, reserved) };
    }
    const reservationId = randomUUID();
    await client.query(
      `INSERT INTO picture_word_quota_operations
        (operation_id, reservation_id, installation_id, subject_type, subject_id, state, lease_expires_at)
       VALUES ($1::uuid, $2::uuid, $3::uuid, 'free', $3::text, 'reserved', $4)`,
      [operationId, reservationId, principal.installationId, new Date(Date.now() + RESERVATION_TTL_MS)],
    );
    return {
      allowed: true,
      reservationId,
      entitlement: freeEntitlement(installation.free_used, reserved + 1),
    };
  }

  private async reserveMember(
    client: PoolClient,
    principal: AccessPrincipal,
    operationId: string,
    subscription: SubscriptionRow,
  ): Promise<QuotaReservation> {
    const period = monthlyQuotaPeriod(subscription.original_purchase_at, new Date());
    const subjectId = subscriptionSubjectId(subscription.environment, subscription.original_transaction_id);
    const effectiveLimit = this.memberLimit;
    await client.query(
      `INSERT INTO picture_word_quota_periods
        (subject_type, subject_id, period_start, period_end, quota_limit)
       VALUES ('subscription', $1, $2, $3, $4)
       ON CONFLICT (subject_type, subject_id, period_start) DO NOTHING`,
      [subjectId, period.start, period.end, effectiveLimit],
    );
    const quotaResult = await client.query<QuotaPeriodRow>(
      `SELECT used_count, reserved_count, quota_limit FROM picture_word_quota_periods
       WHERE subject_type = 'subscription' AND subject_id = $1 AND period_start = $2 FOR UPDATE`,
      [subjectId, period.start],
    );
    const quota = requiredRow(quotaResult.rows[0], "quota period");
    quota.quota_limit = effectiveLimit;
    await client.query(
      `UPDATE picture_word_quota_periods SET quota_limit = $3, updated_at = clock_timestamp()
       WHERE subject_type = 'subscription' AND subject_id = $1 AND period_start = $2`,
      [subjectId, period.start, effectiveLimit],
    );
    if (quota.quota_limit !== UNLIMITED_MEMBER_LIMIT
        && quota.used_count + quota.reserved_count >= quota.quota_limit) {
      return { allowed: false, entitlement: memberEntitlementFrom(subscription, quota, period) };
    }
    const reservationId = randomUUID();
    await client.query(
      `INSERT INTO picture_word_quota_operations
        (operation_id, reservation_id, installation_id, subject_type, subject_id, period_start, state, lease_expires_at)
       VALUES ($1::uuid, $2::uuid, $3::uuid, 'subscription', $4, $5, 'reserved', $6)`,
      [operationId, reservationId, principal.installationId, subjectId, period.start, new Date(Date.now() + RESERVATION_TTL_MS)],
    );
    quota.reserved_count += 1;
    await client.query(
      `UPDATE picture_word_quota_periods SET reserved_count = $3, updated_at = clock_timestamp()
       WHERE subject_type = 'subscription' AND subject_id = $1 AND period_start = $2`,
      [subjectId, period.start, quota.reserved_count],
    );
    return {
      allowed: true,
      reservationId,
      entitlement: memberEntitlementFrom(subscription, quota, period),
    };
  }

  private async entitlementInTransaction(client: PoolClient, principal: AccessPrincipal): Promise<EntitlementSummary> {
    const installation = await this.loadInstallation(principal.installationId, client);
    const subscription = await this.loadUsableSubscription(principal, client);
    if (!subscription) {
      const reserved = await client.query<{ count: number }>(
        `SELECT COUNT(*)::integer AS count FROM picture_word_quota_operations
         WHERE installation_id = $1::uuid AND subject_type = 'free' AND state = 'reserved'
           AND lease_expires_at > clock_timestamp()`,
        [principal.installationId],
      );
      return freeEntitlement(installation.free_used, reserved.rows[0]?.count ?? 0);
    }
    const period = monthlyQuotaPeriod(subscription.original_purchase_at, new Date());
    const subjectId = subscriptionSubjectId(subscription.environment, subscription.original_transaction_id);
    const effectiveLimit = this.memberLimit;
    const quota = await client.query<QuotaPeriodRow>(
      `SELECT used_count, reserved_count, quota_limit FROM picture_word_quota_periods
       WHERE subject_type = 'subscription' AND subject_id = $1 AND period_start = $2`,
      [subjectId, period.start],
    );
    if (quota.rows[0]?.quota_limit !== effectiveLimit) {
      await client.query(
        `UPDATE picture_word_quota_periods SET quota_limit = $3, updated_at = clock_timestamp()
         WHERE subject_type = 'subscription' AND subject_id = $1 AND period_start = $2`,
        [subjectId, period.start, effectiveLimit],
      );
    }
    return memberEntitlementFrom(
      subscription,
      quota.rows[0]
        ? { ...quota.rows[0], quota_limit: effectiveLimit }
        : { used_count: 0, reserved_count: 0, quota_limit: effectiveLimit },
      period,
    );
  }

  private async memberEntitlement(subscription: SubscriptionRow): Promise<EntitlementSummary> {
    const period = monthlyQuotaPeriod(subscription.original_purchase_at, new Date());
    const subjectId = subscriptionSubjectId(subscription.environment, subscription.original_transaction_id);
    const effectiveLimit = this.memberLimit;
    const result = await this.pool.query<QuotaPeriodRow>(
      `SELECT used_count, reserved_count, quota_limit FROM picture_word_quota_periods
       WHERE subject_type = 'subscription' AND subject_id = $1 AND period_start = $2`,
      [subjectId, period.start],
    );
    if (result.rows[0]?.quota_limit !== effectiveLimit) {
      await this.pool.query(
        `UPDATE picture_word_quota_periods SET quota_limit = $3, updated_at = clock_timestamp()
         WHERE subject_type = 'subscription' AND subject_id = $1 AND period_start = $2`,
        [subjectId, period.start, effectiveLimit],
      );
    }
    return memberEntitlementFrom(
      subscription,
      result.rows[0]
        ? { ...result.rows[0], quota_limit: effectiveLimit }
        : { used_count: 0, reserved_count: 0, quota_limit: effectiveLimit },
      period,
    );
  }

  private get memberLimit(): number {
    return this.config.memberQuotaUnlimited === true
      ? UNLIMITED_MEMBER_LIMIT
      : this.config.memberQuotaDefault ?? 100;
  }

  private async loadInstallation(id: string, client: Pool | PoolClient = this.pool): Promise<InstallationRow> {
    const result = await client.query<InstallationRow>(
      `SELECT id::text, free_used FROM picture_word_installations WHERE id = $1::uuid`,
      [id],
    );
    return requiredRow(result.rows[0], "installation");
  }

  private async loadUsableSubscription(
    principal: AccessPrincipal,
    client: Pool | PoolClient = this.pool,
  ): Promise<SubscriptionRow | null> {
    if (!principal.subscriptionEnvironment || !principal.originalTransactionId) return null;
    const result = await client.query<SubscriptionRow>(
      `SELECT environment, original_transaction_id, product_id, state, original_purchase_at,
              expires_at, grace_expires_at, revoked_at, auto_renew_enabled
       FROM picture_word_subscriptions
       WHERE environment = $1 AND original_transaction_id = $2`,
      [principal.subscriptionEnvironment, principal.originalTransactionId],
    );
    const row = result.rows[0];
    return row && effectiveState(row) !== "expired" && effectiveState(row) !== "revoked" ? row : null;
  }

  private async upsertSubscription(
    client: PoolClient,
    transaction: SubscriptionTransaction,
    notification?: StoreNotification,
  ): Promise<void> {
    const state = notificationState(notification, transaction);
    await client.query(
      `
        INSERT INTO picture_word_subscriptions
          (environment, original_transaction_id, latest_transaction_id, product_id, state,
           original_purchase_at, purchase_at, expires_at, grace_expires_at, revoked_at,
           auto_renew_enabled, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, clock_timestamp())
        ON CONFLICT (environment, original_transaction_id) DO UPDATE
        SET latest_transaction_id = EXCLUDED.latest_transaction_id,
            product_id = EXCLUDED.product_id,
            state = EXCLUDED.state,
            original_purchase_at = LEAST(picture_word_subscriptions.original_purchase_at, EXCLUDED.original_purchase_at),
            purchase_at = EXCLUDED.purchase_at,
            expires_at = EXCLUDED.expires_at,
            grace_expires_at = EXCLUDED.grace_expires_at,
            revoked_at = EXCLUDED.revoked_at,
            auto_renew_enabled = COALESCE(EXCLUDED.auto_renew_enabled, picture_word_subscriptions.auto_renew_enabled),
            updated_at = clock_timestamp()
        WHERE EXCLUDED.purchase_at > picture_word_subscriptions.purchase_at
           OR (
             EXCLUDED.purchase_at = picture_word_subscriptions.purchase_at
             AND (picture_word_subscriptions.state <> 'revoked' OR EXCLUDED.state = 'revoked')
           )
      `,
      [
        transaction.environment,
        transaction.originalTransactionId,
        transaction.transactionId,
        transaction.productId,
        state,
        transaction.originalPurchaseDate,
        transaction.purchaseDate,
        transaction.expiresDate,
        transaction.gracePeriodExpiresDate,
        transaction.revokedAt,
        transaction.autoRenewEnabled,
      ],
    );
  }

  private async upsertSubscriptionTransaction(
    client: PoolClient,
    transaction: SubscriptionTransaction,
  ): Promise<void> {
    await client.query(
      `
        INSERT INTO picture_word_subscription_transactions
          (environment, transaction_id, original_transaction_id, product_id,
           original_purchase_at, purchase_at, expires_at, revoked_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        ON CONFLICT (environment, transaction_id) DO UPDATE
        SET original_transaction_id = EXCLUDED.original_transaction_id,
            product_id = EXCLUDED.product_id,
            original_purchase_at = EXCLUDED.original_purchase_at,
            purchase_at = EXCLUDED.purchase_at,
            expires_at = EXCLUDED.expires_at,
            revoked_at = COALESCE(EXCLUDED.revoked_at, picture_word_subscription_transactions.revoked_at),
            last_seen_at = clock_timestamp()
      `,
      [
        transaction.environment,
        transaction.transactionId,
        transaction.originalTransactionId,
        transaction.productId,
        transaction.originalPurchaseDate,
        transaction.purchaseDate,
        transaction.expiresDate,
        transaction.revokedAt,
      ],
    );
  }

  private async cleanupExpiredReservations(client?: PoolClient): Promise<void> {
    const executor = client ?? this.pool;
    await executor.query(
      `
        WITH expired AS (
          UPDATE picture_word_quota_operations
          SET state = 'released'
          WHERE state = 'reserved' AND lease_expires_at <= clock_timestamp()
          RETURNING subject_type, subject_id, period_start
        ), grouped AS (
          SELECT subject_id, period_start, COUNT(*)::integer AS released_count
          FROM expired WHERE subject_type = 'subscription'
          GROUP BY subject_id, period_start
        )
        UPDATE picture_word_quota_periods AS quota
        SET reserved_count = GREATEST(0, quota.reserved_count - grouped.released_count),
            updated_at = clock_timestamp()
        FROM grouped
        WHERE quota.subject_type = 'subscription'
          AND quota.subject_id = grouped.subject_id
          AND quota.period_start = grouped.period_start
      `,
    );
  }

  private async releaseOperation(client: PoolClient, row: OperationRow): Promise<void> {
    await client.query(
      `UPDATE picture_word_quota_operations SET state = 'released' WHERE reservation_id = $1::uuid`,
      [row.reservation_id],
    );
    if (row.subject_type === "subscription") {
      await client.query(
        `UPDATE picture_word_quota_periods
         SET reserved_count = GREATEST(0, reserved_count - 1), updated_at = clock_timestamp()
         WHERE subject_type = 'subscription' AND subject_id = $1 AND period_start = $2`,
        [row.subject_id, row.period_start],
      );
    }
  }

  private async principalForOperation(client: PoolClient, row: OperationRow): Promise<AccessPrincipal> {
    if (row.subject_type === "subscription") {
      const separator = row.subject_id.indexOf(":");
      return {
        accessTokenHash: "operation",
        installationId: row.installation_id,
        subscriptionEnvironment: row.subject_id.slice(0, separator) as AccessEnvironment,
        originalTransactionId: row.subject_id.slice(separator + 1),
      };
    }
    return {
      accessTokenHash: "operation",
      installationId: row.installation_id,
      subscriptionEnvironment: null,
      originalTransactionId: null,
    };
  }

  private hash(value: string): string {
    return createHmac("sha256", this.config.tokenHashSecret).update(value).digest("hex");
  }

  private async recordDeviceCheckSyncFailure(installationId: string, targetUsed: number, error: unknown): Promise<void> {
    const message = (error instanceof Error ? error.message : String(error)).slice(0, 512);
    await this.pool.query(
      `INSERT INTO picture_word_devicecheck_sync_tasks
        (installation_id, target_used, attempt_count, last_error, next_attempt_at)
       VALUES ($1::uuid, $2, 1, $3, clock_timestamp() + INTERVAL '5 minutes')
       ON CONFLICT (installation_id) DO UPDATE
       SET target_used = GREATEST(picture_word_devicecheck_sync_tasks.target_used, EXCLUDED.target_used),
           attempt_count = picture_word_devicecheck_sync_tasks.attempt_count + 1,
           last_error = EXCLUDED.last_error,
           next_attempt_at = clock_timestamp() + LEAST(
             INTERVAL '6 hours',
             INTERVAL '5 minutes' * POWER(
               2::double precision,
               LEAST(picture_word_devicecheck_sync_tasks.attempt_count, 6)::double precision
             )
           ),
           updated_at = clock_timestamp()`,
      [installationId, targetUsed, message],
    ).catch((databaseError) => {
      this.logger.error("device_check.sync_task_write_failed", {
        installationId,
        message: databaseError instanceof Error ? databaseError.message : String(databaseError),
      });
    });
  }

  private async clearDeviceCheckSyncTask(installationId: string): Promise<void> {
    await this.pool.query(
      `DELETE FROM picture_word_devicecheck_sync_tasks WHERE installation_id = $1::uuid`,
      [installationId],
    ).catch((error) => {
      this.logger.warn("device_check.sync_task_clear_failed", {
        installationId,
        message: error instanceof Error ? error.message : String(error),
      });
    });
  }
}

export class DeviceAttestationRequiredError extends Error {
  constructor() {
    super("A fresh DeviceCheck token is required for free recognition");
  }
}

function freeEntitlement(used: number, reserved = 0): EntitlementSummary {
  return {
    tier: "free",
    productId: null,
    subscriptionState: "none",
    limit: FREE_LIMIT,
    used,
    reserved,
    remaining: Math.max(0, FREE_LIMIT - used - reserved),
    periodStart: null,
    resetAt: null,
    expiresAt: null,
    autoRenewEnabled: null,
    vocabularyCorrectionEnabled: false,
  };
}

function memberEntitlementFrom(
  subscription: SubscriptionRow,
  quota: QuotaPeriodRow,
  period: { start: Date; end: Date },
): EntitlementSummary {
  const state = effectiveState(subscription);
  return {
    tier: "member",
    productId: subscription.product_id,
    subscriptionState: state,
    limit: quota.quota_limit,
    used: quota.used_count,
    reserved: quota.reserved_count,
    remaining: Math.max(0, quota.quota_limit - quota.used_count - quota.reserved_count),
    unlimited: quota.quota_limit === UNLIMITED_MEMBER_LIMIT,
    periodStart: period.start.toISOString(),
    resetAt: period.end.toISOString(),
    expiresAt: subscription.expires_at.toISOString(),
    autoRenewEnabled: subscription.auto_renew_enabled,
    vocabularyCorrectionEnabled: state === "active" || state === "grace",
  };
}

function effectiveState(subscription: SubscriptionRow): Exclude<SubscriptionState, "none"> {
  if (subscription.revoked_at || subscription.state === "revoked") return "revoked";
  if (subscription.state === "expired") return "expired";
  const now = Date.now();
  if (subscription.state === "grace") {
    return subscription.grace_expires_at && subscription.grace_expires_at.getTime() > now ? "grace" : "expired";
  }
  if (subscription.expires_at.getTime() > now) return "active";
  if (subscription.grace_expires_at && subscription.grace_expires_at.getTime() > now) return "grace";
  return "expired";
}

function isActiveMemberEntitlement(entitlement: EntitlementSummary): boolean {
  return entitlement.tier === "member"
    && (entitlement.subscriptionState === "active" || entitlement.subscriptionState === "grace");
}

function notificationState(
  notification: StoreNotification | undefined,
  transaction: SubscriptionTransaction,
): Exclude<SubscriptionState, "none"> {
  if (transaction.revokedAt || notification?.status === 5
      || notification?.notificationType === "REFUND" || notification?.notificationType === "REVOKE") {
    return "revoked";
  }
  if (notification?.status === 4
      || (transaction.gracePeriodExpiresDate && transaction.gracePeriodExpiresDate > new Date())) {
    return "grace";
  }
  if (notification?.status === 2 || notification?.status === 3
      || notification?.notificationType === "EXPIRED"
      || notification?.notificationType === "GRACE_PERIOD_EXPIRED") {
    return "expired";
  }
  return transaction.expiresDate > new Date() ? "active" : "expired";
}

function subscriptionSubjectId(environment: AccessEnvironment, originalTransactionId: string): string {
  return `${environment}:${originalTransactionId}`;
}

function requiredRow<T>(value: T | undefined, name: string): T {
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}
