import { randomUUID } from "node:crypto";
import {
  disabledEntitlement,
  type AccessPrincipal,
  type AccessService,
  type BootstrapInput,
  type BootstrapResult,
  type EntitlementSummary,
  type QuotaReservation,
} from "./types.js";

export class DisabledAccessService implements AccessService {
  async bootstrap(_input: BootstrapInput): Promise<BootstrapResult> {
    return { accessToken: "access-control-disabled", entitlement: disabledEntitlement() };
  }

  async authenticate(): Promise<AccessPrincipal> {
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

  async syncSubscription(): Promise<EntitlementSummary> {
    return disabledEntitlement();
  }

  async processStoreNotification(): Promise<void> {}
  async recordMetric(): Promise<void> {}

  async reserveAnalyze(): Promise<QuotaReservation> {
    return { allowed: true, reservationId: randomUUID(), entitlement: disabledEntitlement() };
  }

  async commitAnalyze(): Promise<EntitlementSummary> {
    return disabledEntitlement();
  }

  async releaseAnalyze(): Promise<void> {}
  async close(): Promise<void> {}
}
