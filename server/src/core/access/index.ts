import type { AccessConfig } from "../../config.js";
import type { Logger } from "../../utils/logger.js";
import { createAppleSignedDataVerifier } from "./apple.js";
import { AppleDeviceCheckClient } from "./device-check.js";
import { DisabledAccessService } from "./disabled.js";
import { PostgresAccessService } from "./postgres.js";
import type { AccessService } from "./types.js";

export async function createAccessService(config: AccessConfig, logger: Logger): Promise<AccessService> {
  if (!config.enabled) return new DisabledAccessService();
  const verifier = await createAppleSignedDataVerifier(config);
  const deviceCheck = new AppleDeviceCheckClient(config.deviceCheck);
  return new PostgresAccessService(config, verifier, deviceCheck, logger);
}

export { DisabledAccessService } from "./disabled.js";
export { DeviceAttestationRequiredError, PostgresAccessService } from "./postgres.js";
export type {
  AccessPrincipal,
  AggregateMetricInput,
  AccessService,
  EntitlementSummary,
  QuotaReservation,
  StoreNotification,
  StoreSyncResult,
  StoreSignedDataVerifying,
  SyncedTransactionState,
  SubscriptionTransaction,
} from "./types.js";
export { StoreSyncUnavailableError, StoreTransactionInvalidError } from "./types.js";
export { isValidOperationId } from "./types.js";
