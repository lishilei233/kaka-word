import { readFile } from "node:fs/promises";
import {
  Environment,
  InAppOwnershipType,
  SignedDataVerifier,
  type JWSRenewalInfoDecodedPayload,
  type JWSTransactionDecodedPayload,
} from "@apple/app-store-server-library";
import type { AccessConfig } from "../../config.js";
import type {
  AccessEnvironment,
  StoreNotification,
  StoreSignedDataVerifying,
  SubscriptionTransaction,
} from "./types.js";

export async function createAppleSignedDataVerifier(config: AccessConfig): Promise<AppleSignedDataVerifier> {
  const roots = await Promise.all(config.appleRootCertificatePaths.map((path) => readFile(path)));
  return new AppleSignedDataVerifier(config, roots);
}

export class AppleSignedDataVerifier implements StoreSignedDataVerifying {
  private readonly production: SignedDataVerifier;
  private readonly sandbox: SignedDataVerifier;
  private readonly allowedProducts: Set<string>;

  constructor(config: AccessConfig, roots: Buffer[]) {
    this.production = new SignedDataVerifier(
      roots,
      config.appleOnlineChecks,
      Environment.PRODUCTION,
      config.bundleId,
      config.appAppleId,
    );
    this.sandbox = new SignedDataVerifier(
      roots,
      config.appleOnlineChecks,
      Environment.SANDBOX,
      config.bundleId,
    );
    this.allowedProducts = new Set([config.monthlyProductId, config.annualProductId]);
  }

  async verifyTransaction(signedTransaction: string, signedRenewalInfo?: string): Promise<SubscriptionTransaction> {
    const { transaction, verifier } = await this.verifyInEitherEnvironment(
      (candidate) => candidate.verifyAndDecodeTransaction(signedTransaction),
    );
    const renewal = signedRenewalInfo
      ? await verifier.verifyAndDecodeRenewalInfo(signedRenewalInfo)
      : undefined;
    return this.normalizeTransaction(transaction, renewal);
  }

  async verifyNotification(signedPayload: string): Promise<StoreNotification> {
    const { transaction: notification, verifier } = await this.verifyInEitherEnvironment(
      (candidate) => candidate.verifyAndDecodeNotification(signedPayload),
    );
    const data = notification.data;
    let normalizedTransaction: SubscriptionTransaction | null = null;
    if (data?.signedTransactionInfo) {
      const decodedTransaction = await verifier.verifyAndDecodeTransaction(data.signedTransactionInfo);
      const decodedRenewal = data.signedRenewalInfo
        ? await verifier.verifyAndDecodeRenewalInfo(data.signedRenewalInfo)
        : undefined;
      normalizedTransaction = this.normalizeTransaction(decodedTransaction, decodedRenewal);
    }
    const environment = normalizeEnvironment(data?.environment ?? normalizedTransaction?.environment);
    const notificationUUID = notification.notificationUUID?.trim();
    if (!notificationUUID || !environment) throw new Error("Apple notification is missing identifiers");
    return {
      environment,
      notificationUUID,
      notificationType: notification.notificationType?.toString() ?? "UNKNOWN",
      subtype: notification.subtype?.toString() ?? null,
      status: typeof data?.status === "number" ? data.status : null,
      transaction: normalizedTransaction,
    };
  }

  private normalizeTransaction(
    transaction: JWSTransactionDecodedPayload,
    renewal?: JWSRenewalInfoDecodedPayload,
  ): SubscriptionTransaction {
    const originalTransactionId = transaction.originalTransactionId?.trim();
    const transactionId = transaction.transactionId?.trim();
    const productId = transaction.productId?.trim();
    const environment = normalizeEnvironment(transaction.environment);
    if (!originalTransactionId || !transactionId || !productId || !environment) {
      throw new Error("Apple transaction is missing required identifiers");
    }
    if (!this.allowedProducts.has(productId)) throw new Error("Apple transaction product is not allowed");
    if (transaction.inAppOwnershipType === InAppOwnershipType.FAMILY_SHARED) {
      throw new Error("Family-shared subscriptions are not supported");
    }
    if (renewal?.originalTransactionId && renewal.originalTransactionId !== originalTransactionId) {
      throw new Error("Apple renewal info does not match the transaction");
    }

    return {
      environment,
      originalTransactionId,
      transactionId,
      productId,
      originalPurchaseDate: requiredDate(transaction.originalPurchaseDate, "originalPurchaseDate"),
      purchaseDate: requiredDate(transaction.purchaseDate, "purchaseDate"),
      expiresDate: requiredDate(transaction.expiresDate, "expiresDate"),
      revokedAt: optionalDate(transaction.revocationDate),
      gracePeriodExpiresDate: optionalDate(renewal?.gracePeriodExpiresDate),
      autoRenewEnabled: typeof renewal?.autoRenewStatus === "number"
        ? renewal.autoRenewStatus === 1
        : null,
    };
  }

  private async verifyInEitherEnvironment<T>(
    operation: (verifier: SignedDataVerifier) => Promise<T>,
  ): Promise<{ transaction: T; verifier: SignedDataVerifier }> {
    try {
      return { transaction: await operation(this.production), verifier: this.production };
    } catch (productionError) {
      try {
        return { transaction: await operation(this.sandbox), verifier: this.sandbox };
      } catch (sandboxError) {
        throw new AggregateError([productionError, sandboxError], "Apple signed data verification failed");
      }
    }
  }
}

function normalizeEnvironment(value: unknown): AccessEnvironment | null {
  if (value === "Production" || value === "Sandbox" || value === "Xcode" || value === "LocalTesting") {
    return value;
  }
  return null;
}

function requiredDate(value: number | undefined, name: string): Date {
  const date = optionalDate(value);
  if (!date) throw new Error(`Apple transaction is missing ${name}`);
  return date;
}

function optionalDate(value: number | undefined): Date | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}
