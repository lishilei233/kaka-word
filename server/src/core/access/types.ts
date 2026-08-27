export type SubscriptionState = "none" | "active" | "grace" | "expired" | "revoked";
export type AccessEnvironment = "Sandbox" | "Production" | "Xcode" | "LocalTesting";

export type EntitlementSummary = {
  tier: "free" | "member";
  productId: string | null;
  subscriptionState: SubscriptionState;
  limit: number;
  used: number;
  reserved: number;
  remaining: number;
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
};

export type BootstrapInput = {
  installationId: string;
  deviceToken: string;
};

export type BootstrapResult = {
  accessToken: string;
  entitlement: EntitlementSummary;
};

export type AggregateMetricInput = {
  eventName: string;
  productId?: string | null;
  outcome?: string | null;
};

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

export interface AccessService {
  bootstrap(input: BootstrapInput): Promise<BootstrapResult>;
  authenticate(rawToken: string | undefined): Promise<AccessPrincipal | null>;
  status(principal: AccessPrincipal): Promise<EntitlementSummary>;
  syncSubscription(
    principal: AccessPrincipal,
    signedTransaction: string,
    signedRenewalInfo?: string,
  ): Promise<EntitlementSummary>;
  processStoreNotification(signedPayload: string): Promise<void>;
  recordMetric(input: AggregateMetricInput): Promise<void>;
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
    periodStart: null,
    resetAt: null,
    expiresAt: null,
    autoRenewEnabled: null,
    vocabularyCorrectionEnabled: true,
  };
}
