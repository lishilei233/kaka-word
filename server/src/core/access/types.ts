import type { ActivityEvent } from './activity.js';
export type SubscriptionState = "none" | "active" | "grace" | "expired" | "revoked";
export type SyncedTransactionState = Exclude<SubscriptionState, "none">;
export type AccessEnvironment = "Sandbox" | "Production" | "Xcode" | "LocalTesting";
export const accessEnvironments: readonly AccessEnvironment[] = ["Sandbox", "Production", "Xcode", "LocalTesting"];

export type EntitlementSummary = {
  tier: "free" | "member";
  productId: string | null;
  subscriptionState: SubscriptionState;
  limit: number;
  used: number;
  reserved: number;
  remaining: number;
  unlimited?: boolean;
  periodStart: string | null;
  resetAt: string | null;
  expiresAt: string | null;
  autoRenewEnabled: boolean | null;
  vocabularyCorrectionEnabled: boolean;
};

export type AccessPrincipal = {
  accessTokenHash: string;
  installationId: string;
  subscriptionEnvironment: AccessEnvironment | null;
  originalTransactionId: string | null;
  storeEnvironment: AccessEnvironment | null;
};

export type BootstrapInput = {
  installationId: string;
  deviceToken: string;
  storeEnvironment?: AccessEnvironment;
};

export type BootstrapResult = {
  accessToken: string;
  entitlement: EntitlementSummary;
};

export type StoreSyncResult = {
  entitlement: EntitlementSummary;
  syncedTransactionState: SyncedTransactionState;
};

export type AggregateMetricInput = {
  eventName: string;
  productId?: string | null;
  outcome?: string | null;
};

export type RecognitionFeedbackSelection = "first" | "second" | "third" | "other";

export type RecognitionFeedbackWord = {
  english: string;
  chinese: string;
};

export type RecognitionFeedbackInput = {
  original: RecognitionFeedbackWord;
  selected: RecognitionFeedbackWord;
  selection: RecognitionFeedbackSelection;
};

export type InstallationMetric = "recognition_attempt" | "recognition_success";

export type SubscriptionTransaction = {
  environment: AccessEnvironment;
  originalTransactionId: string;
  transactionId: string;
  productId: string;
  originalPurchaseDate: Date;
  purchaseDate: Date;
  expiresDate: Date;
  revokedAt: Date | null;
  gracePeriodExpiresDate: Date | null;
  autoRenewEnabled: boolean | null;
};

export type StoreNotification = {
  environment: AccessEnvironment;
  notificationUUID: string;
  notificationType: string;
  subtype: string | null;
  status: number | null;
  transaction: SubscriptionTransaction | null;
};

export class StoreTransactionInvalidError extends Error {
  constructor(message = "Apple transaction is invalid", options?: ErrorOptions) {
    super(message, options);
    this.name = "StoreTransactionInvalidError";
  }
}

export class StoreSyncUnavailableError extends Error {
  constructor(message = "Apple transaction verification is temporarily unavailable", options?: ErrorOptions) {
    super(message, options);
    this.name = "StoreSyncUnavailableError";
  }
}

export type QuotaReservation =
  | { allowed: true; reservationId: string; entitlement: EntitlementSummary }
  | { allowed: false; entitlement: EntitlementSummary }
  | { allowed: false; conflict: true; entitlement: EntitlementSummary };

export interface StoreSignedDataVerifying {
  verifyTransaction(signedTransaction: string, signedRenewalInfo?: string): Promise<SubscriptionTransaction>;
  verifyNotification(signedPayload: string): Promise<StoreNotification>;
}

export interface DeviceChecking {
  queryBits(deviceToken: string): Promise<number>;
  updateBits(deviceToken: string, usedCount: number): Promise<void>;
}

export const recognitionOutcomes = ['processing', 'success', 'empty', 'failure', 'cancelled', 'quota_exhausted', 'rate_limited', 'unfinished'] as const;
export type RecognitionOutcome = typeof recognitionOutcomes[number];
export type QuotaSnapshot = Pick<EntitlementSummary, 'tier' | 'limit' | 'used' | 'reserved' | 'remaining' | 'unlimited' | 'periodStart' | 'resetAt'>;
export type RecognitionAttemptInput = {
  installationId: string; operationId: string; requestId: string; startedAt: Date;
  environment: AccessEnvironment | null; appVersion: string | null; appBuild: string | null;
  quotaBefore: QuotaSnapshot;
};
export type RecognitionAttemptResult = {
  operationId: string; installationId: string; outcome: Exclude<RecognitionOutcome, 'processing' | 'unfinished'>;
  reasonCode: string | null; stage: string; quotaAfter: QuotaSnapshot | null;
};

export interface AccessService {
  bootstrap(input: BootstrapInput): Promise<BootstrapResult>;
  authenticate(rawToken: string | undefined, storeEnvironment?: AccessEnvironment): Promise<AccessPrincipal | null>;
  status(principal: AccessPrincipal): Promise<EntitlementSummary>;
  syncSubscription(
    principal: AccessPrincipal,
    signedTransaction: string,
    signedRenewalInfo?: string,
    requestId?: string,
  ): Promise<StoreSyncResult>;
  processStoreNotification(signedPayload: string, requestId?: string): Promise<void>;
  recordActivityEvents(installationId: string, events: ActivityEvent[]): Promise<void>;
  recordMetric(input: AggregateMetricInput): Promise<void>;
  recordRecognitionFeedback(installationId: string, input: RecognitionFeedbackInput, storeEnvironment?: AccessEnvironment | null): Promise<void>;
  recordInstallationMetric(installationId: string, metric: InstallationMetric, storeEnvironment?: AccessEnvironment | null): Promise<void>;
  beginRecognitionAttempt(input: RecognitionAttemptInput): Promise<boolean>;
  finishRecognitionAttempt(result: RecognitionAttemptResult): Promise<void>;
  maintainRecognitionAttempts(): Promise<void>;
  reserveAnalyze(principal: AccessPrincipal, operationId: string, deviceToken?: string): Promise<QuotaReservation>;
  commitAnalyze(reservationId: string, deviceToken?: string): Promise<EntitlementSummary>;
  releaseAnalyze(reservationId: string): Promise<void>;
  close(): Promise<void>;
}

export function isValidOperationId(value: string | undefined): value is string {
  return value != null && /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

export function disabledEntitlement(): EntitlementSummary {
  return {
    tier: "member",
    productId: null,
    subscriptionState: "active",
    limit: Number.MAX_SAFE_INTEGER,
    used: 0,
    reserved: 0,
    remaining: Number.MAX_SAFE_INTEGER,
    unlimited: true,
    periodStart: null,
    resetAt: null,
    expiresAt: null,
    autoRenewEnabled: null,
    vocabularyCorrectionEnabled: true,
  };
}
