import { randomUUID } from "node:crypto";
import {
  disabledEntitlement,
  type AccessPrincipal,
  type AggregateMetricInput,
  type AccessService,
  type BootstrapInput,
  type BootstrapResult,
  type EntitlementSummary,
  type QuotaReservation,
  type RecognitionFeedbackInput,
  type StoreSyncResult,
} from "./types.js";

export class DisabledAccessService implements AccessService {
  async bootstrap(_input: BootstrapInput): Promise<BootstrapResult> {
    return { accessToken: "access-control-disabled", entitlement: disabledEntitlement() };
  }

  async authenticate(_rawToken: string | undefined): Promise<AccessPrincipal | null> {
    return {
      accessTokenHash: "disabled",
      installationId: "disabled",
      subscriptionEnvironment: null,
      originalTransactionId: null,
    };
  }

  async status(): Promise<EntitlementSummary> {
    return disabledEntitlement();
  }

  async syncSubscription(): Promise<StoreSyncResult> {
    return {
      entitlement: disabledEntitlement(),
      syncedTransactionState: "active",
    };
  }

  async processStoreNotification(_signedPayload: string, _requestId?: string): Promise<void> {}
  async recordMetric(_input: AggregateMetricInput): Promise<void> {}
  async recordRecognitionFeedback(_input: RecognitionFeedbackInput): Promise<void> {}

  async reserveAnalyze(): Promise<QuotaReservation> {
    return { allowed: true, reservationId: randomUUID(), entitlement: disabledEntitlement() };
  }

  async commitAnalyze(): Promise<EntitlementSummary> {
    return disabledEntitlement();
  }

  async releaseAnalyze(): Promise<void> {}
  async close(): Promise<void> {}
}
