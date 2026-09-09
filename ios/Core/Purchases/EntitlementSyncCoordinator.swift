import CryptoKit
import Foundation
import OSLog

protocol MembershipEntitlementAPI: Sendable {
    func loadEntitlementStatus() async throws -> EntitlementSummary
    func syncSubscription(
        signedTransaction: String,
        signedRenewalInfo: String?,
        requestID: String
    ) async throws -> StoreSyncReceipt
}

extension AccessCredentialStore: MembershipEntitlementAPI {
    func loadEntitlementStatus() async throws -> EntitlementSummary {
        do {
            return try await status()
        } catch let error as AccessCredentialError {
            if error.isUnauthorized {
                return try await bootstrapIfNeeded(force: true)
            }
            throw error
        }
    }
}

struct MembershipSyncClock: Sendable {
    var now: @Sendable () -> Date

    static let live = MembershipSyncClock(now: { Date() })
}

enum EntitlementSyncReason: String, Sendable {
    case startup
    case foreground
    case settings
    case purchasePreflight
    case purchase
    case restore
    case transactionUpdate
    case manual
}

struct EntitlementSyncStatistics: Equatable, Sendable {
    var currentCount = 0
    var unfinishedCount = 0
    var bufferedCount = 0
    var chainCount = 0
    var activeCount = 0
    var revokedCount = 0
    var syncedCount = 0
    var locallyFinishedCount = 0
    var duplicateCount = 0
    var unverifiedCount = 0
    var finishedCount = 0
}

struct EntitlementSyncResult: Sendable {
    let workID: UUID
    let entitlement: EntitlementSummary
    let statistics: EntitlementSyncStatistics
}

enum EntitlementSyncSubmission: Sendable {
    case buffered
    case ignored
    case unverified(UnverifiedStoreTransaction)
    case started(Task<EntitlementSyncResult, Error>)
    case joined(Task<EntitlementSyncResult, Error>)
}

struct SubscriptionReconciliationPlan: Sendable {
    struct Chain: Sendable {
        let representative: StoreTransactionObservation
        let observations: [StoreTransactionObservation]
        let transactionsToFinish: [StoreTransactionObservation]
    }

    let chainsToSync: [Chain]
    let transactionsToFinishLocally: [StoreTransactionObservation]
    let chainCount: Int
    let duplicateCount: Int
}

enum SubscriptionReconciliationPlanner {
    static func makePlan(
        observations: [StoreTransactionObservation],
        handledFingerprints: Set<StoreTransactionFingerprint>,
        now: Date
    ) -> SubscriptionReconciliationPlan {
        var transactionsByID: [UInt64: MergedTransaction] = [:]
        for observation in observations {
            if var existing = transactionsByID[observation.id] {
                existing.append(observation)
                transactionsByID[observation.id] = existing
            } else {
                transactionsByID[observation.id] = MergedTransaction(observation)
            }
        }

        let grouped = Dictionary(grouping: transactionsByID.values) {
            $0.selected.originalID
        }
        var chainsToSync: [SubscriptionReconciliationPlan.Chain] = []
        var localFinishes: [StoreTransactionObservation] = []

        for chain in grouped.values {
            guard let representative = chain.map(\.selected).max(by: isOrderedBefore) else { continue }
            let chainObservations = chain.flatMap(\.observations)
            let finishable = uniqueFinishableObservations(chainObservations)
            if handledFingerprints.contains(representative.fingerprint)
                || !requiresServerSync(representative, now: now) {
                localFinishes.append(contentsOf: finishable)
                continue
            }
            chainsToSync.append(SubscriptionReconciliationPlan.Chain(
                representative: representative,
                observations: chainObservations,
                transactionsToFinish: finishable
            ))
        }

        chainsToSync.sort {
            isOrderedBefore($0.representative, $1.representative)
        }
        let duplicateCount = max(0, observations.count - transactionsByID.count)
        return SubscriptionReconciliationPlan(
            chainsToSync: chainsToSync,
            transactionsToFinishLocally: uniqueFinishableObservations(localFinishes),
            chainCount: grouped.count,
            duplicateCount: duplicateCount
        )
    }

    static func requiresServerSync(
        _ observation: StoreTransactionObservation,
        now: Date
    ) -> Bool {
        if observation.revocationDate != nil { return true }
        if observation.isUpgraded { return false }
        if observation.source == .currentEntitlement { return true }
        guard let expirationDate = observation.expirationDate else { return true }
        return expirationDate > now
    }

    private struct MergedTransaction {
        var selected: StoreTransactionObservation
        var observations: [StoreTransactionObservation]

        init(_ observation: StoreTransactionObservation) {
            selected = observation
            observations = [observation]
        }

        mutating func append(_ observation: StoreTransactionObservation) {
            observations.append(observation)
            if observation.revocationDate != nil && selected.revocationDate == nil {
                selected = observation
            } else if selected.revocationDate == nil,
                      observation.fingerprint != selected.fingerprint {
                selected = observation
            }
        }
    }

    private static func isOrderedBefore(
        _ left: StoreTransactionObservation,
        _ right: StoreTransactionObservation
    ) -> Bool {
        if left.purchaseDate != right.purchaseDate {
            return left.purchaseDate < right.purchaseDate
        }
        return left.id < right.id
    }

    private static func uniqueFinishableObservations(
        _ observations: [StoreTransactionObservation]
    ) -> [StoreTransactionObservation] {
        var byID: [UInt64: StoreTransactionObservation] = [:]
        for observation in observations where observation.requiresFinish {
            byID[observation.id] = observation
        }
        return byID.values.sorted(by: isOrderedBefore)
    }
}

struct TransactionSyncDeferredError: LocalizedError, Sendable {
    let underlying: AccessCredentialError
    let syncAttemptID: UUID
    let requestID: String

    var errorDescription: String? { underlying.errorDescription }
}

actor EntitlementSyncCoordinator {
    private enum WorkMode: String, Equatable, Sendable {
        case reconciliation
        case targeted
        case statusOnly
    }

    private struct ActiveWork {
        let id: UUID
        let task: Task<EntitlementSyncResult, Error>
    }

    private static let logger = Logger(
        subsystem: "com.kakaword.app",
        category: "entitlement-reconciliation"
    )

    private let gateway: any StoreKitTransactionProviding
    private let api: any MembershipEntitlementAPI
    private let supportedProductIDs: Set<String>
    private let clock: MembershipSyncClock
    private var handledFingerprints: Set<StoreTransactionFingerprint> = []
    private var bufferedUpdates: [StoreTransactionObservation] = []
    private var startupCompleted = false
    private var activeWork: ActiveWork?

    init(
        gateway: any StoreKitTransactionProviding,
        api: any MembershipEntitlementAPI,
        supportedProductIDs: Set<String>,
        clock: MembershipSyncClock = .live
    ) {
        self.gateway = gateway
        self.api = api
        self.supportedProductIDs = supportedProductIDs
        self.clock = clock
    }

    func submitReconciliation(reason: EntitlementSyncReason) -> EntitlementSyncSubmission {
        if let activeWork {
            return .joined(activeWork.task)
        }
        return start(mode: .reconciliation, reason: reason)
    }

    func submitStatusRefresh(reason: EntitlementSyncReason) -> EntitlementSyncSubmission {
        if let activeWork {
            return .joined(activeWork.task)
        }
        return start(mode: .statusOnly, reason: reason)
    }

    func submit(
        event: StoreTransactionEvent,
        reason: EntitlementSyncReason
    ) async -> EntitlementSyncSubmission {
        switch event {
        case .unverified(let transaction):
            return .unverified(transaction)
        case .verified(let observation):
            if handledFingerprints.contains(observation.fingerprint) {
                await observation.finish()
                Self.logger.debug(
                    "store update ignored duplicate transaction_hash=\(Self.transactionHash(observation.id), privacy: .public) credential_hash=\(observation.fingerprint.logHash, privacy: .public)"
                )
                return .ignored
            }
            bufferedUpdates.append(observation)
            if !startupCompleted {
                return .buffered
            }
            if let activeWork {
                return .joined(activeWork.task)
            }
            return start(mode: .targeted, reason: reason)
        }
    }

    func hasCompletedStartup() -> Bool {
        startupCompleted
    }

    private func start(
        mode: WorkMode,
        reason: EntitlementSyncReason
    ) -> EntitlementSyncSubmission {
        let workID = UUID()
        let task = Task { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.runAndComplete(
                workID: workID,
                mode: mode,
                reason: reason
            )
        }
        activeWork = ActiveWork(id: workID, task: task)
        return .started(task)
    }

    private func runAndComplete(
        workID: UUID,
        mode: WorkMode,
        reason: EntitlementSyncReason
    ) async throws -> EntitlementSyncResult {
        do {
            let result = try await run(workID: workID, mode: mode, reason: reason)
            if mode == .reconciliation {
                startupCompleted = true
            }
            if activeWork?.id == workID {
                activeWork = nil
            }
            return result
        } catch {
            if activeWork?.id == workID {
                activeWork = nil
            }
            throw error
        }
    }

    private func run(
        workID: UUID,
        mode: WorkMode,
        reason: EntitlementSyncReason
    ) async throws -> EntitlementSyncResult {
        let startedAt = clock.now()
        var statistics = EntitlementSyncStatistics()
        var observations: [StoreTransactionObservation] = []
        var capturedBufferedUpdates: [StoreTransactionObservation] = []
        var sawXcodeEnvironment = false
        var sawServerEnvironment = false

        if mode == .reconciliation {
            let snapshot = await gateway.snapshot(supportedProductIDs: supportedProductIDs)
            observations.append(contentsOf: snapshot.observations)
            statistics.currentCount = snapshot.currentCount
            statistics.unfinishedCount = snapshot.unfinishedCount
            statistics.unverifiedCount += snapshot.unverified.count
        }

        let initiallyBuffered = takeBufferedUpdates()
        observations.append(contentsOf: initiallyBuffered)
        capturedBufferedUpdates.append(contentsOf: initiallyBuffered)
        statistics.bufferedCount += initiallyBuffered.count

        Self.logger.info(
            "entitlement reconciliation started reconciliation_id=\(workID.uuidString.lowercased(), privacy: .public) source=\(reason.rawValue, privacy: .public) mode=\(mode.rawValue, privacy: .public) current=\(statistics.currentCount, privacy: .public) unfinished=\(statistics.unfinishedCount, privacy: .public) buffered=\(statistics.bufferedCount, privacy: .public)"
        )

        do {
            var pending = observations
            while true {
                if !pending.isEmpty {
                    sawXcodeEnvironment = sawXcodeEnvironment
                        || pending.contains(where: \.isXcodeEnvironment)
                    sawServerEnvironment = sawServerEnvironment
                        || pending.contains(where: { !$0.isXcodeEnvironment })
                    let plan = SubscriptionReconciliationPlanner.makePlan(
                        observations: pending,
                        handledFingerprints: handledFingerprints,
                        now: clock.now()
                    )
                    statistics.chainCount += plan.chainCount
                    statistics.duplicateCount += plan.duplicateCount
                    statistics.revokedCount += plan.chainsToSync.filter {
                        $0.representative.revocationDate != nil
                    }.count
                    statistics.activeCount += plan.chainsToSync.filter {
                        $0.representative.revocationDate == nil
                    }.count
                    let execution = try await execute(plan)
                    statistics.syncedCount += execution.syncedCount
                    statistics.locallyFinishedCount += execution.locallyFinishedCount
                    statistics.finishedCount += execution.finishedCount
                }

                let entitlement: EntitlementSummary
                if sawXcodeEnvironment && !sawServerEnvironment {
                    entitlement = Self.localEntitlement(
                        observations: observations,
                        now: clock.now()
                    )
                } else {
                    entitlement = try await api.loadEntitlementStatus()
                }

                let lateUpdates = takeBufferedUpdates()
                if lateUpdates.isEmpty {
                    let duration = Int(max(0, clock.now().timeIntervalSince(startedAt)) * 1_000)
                    Self.logger.info(
                        "entitlement reconciliation completed reconciliation_id=\(workID.uuidString.lowercased(), privacy: .public) source=\(reason.rawValue, privacy: .public) mode=\(mode.rawValue, privacy: .public) chains=\(statistics.chainCount, privacy: .public) active=\(statistics.activeCount, privacy: .public) revoked=\(statistics.revokedCount, privacy: .public) logical_store_syncs=\(statistics.syncedCount, privacy: .public) local_finished=\(statistics.locallyFinishedCount, privacy: .public) duplicates=\(statistics.duplicateCount, privacy: .public) unverified=\(statistics.unverifiedCount, privacy: .public) finished=\(statistics.finishedCount, privacy: .public) duration_ms=\(duration, privacy: .public)"
                    )
                    return EntitlementSyncResult(
                        workID: workID,
                        entitlement: entitlement,
                        statistics: statistics
                    )
                }
                statistics.bufferedCount += lateUpdates.count
                capturedBufferedUpdates.append(contentsOf: lateUpdates)
                observations.append(contentsOf: lateUpdates)
                pending = lateUpdates
            }
        } catch {
            restoreBufferedUpdates(capturedBufferedUpdates)
            let duration = Int(max(0, clock.now().timeIntervalSince(startedAt)) * 1_000)
            Self.logger.error(
                "entitlement reconciliation failed reconciliation_id=\(workID.uuidString.lowercased(), privacy: .public) source=\(reason.rawValue, privacy: .public) duration_ms=\(duration, privacy: .public)"
            )
            throw error
        }
    }

    private struct ExecutionStatistics {
        var syncedCount = 0
        var locallyFinishedCount = 0
        var finishedCount = 0
    }

    private func execute(
        _ plan: SubscriptionReconciliationPlan
    ) async throws -> ExecutionStatistics {
        var statistics = ExecutionStatistics()
        for observation in plan.transactionsToFinishLocally {
            await observation.finish()
            handledFingerprints.insert(observation.fingerprint)
            statistics.locallyFinishedCount += 1
            statistics.finishedCount += 1
        }

        for chain in plan.chainsToSync {
            let representative = chain.representative
            if representative.isXcodeEnvironment {
                markHandled(chain.observations)
                for observation in chain.transactionsToFinish {
                    await observation.finish()
                    statistics.finishedCount += 1
                }
                continue
            }

            let syncAttemptID = UUID()
            let requestID = syncAttemptID.uuidString.lowercased()
            let syncStartedAt = clock.now()
            do {
                let renewalInfo = await gateway.signedRenewalInfo(for: representative)
                let receipt = try await api.syncSubscription(
                    signedTransaction: representative.signedTransaction,
                    signedRenewalInfo: renewalInfo,
                    requestID: requestID
                )
                if !Self.isConsistent(receipt: receipt, with: representative) {
                    throw AccessCredentialError.server(
                        code: "STORE_SYNC_UNAVAILABLE",
                        message: "服务器返回的交易状态与会员权益不一致",
                        requestID: receipt.requestID,
                        retryable: true
                    )
                }
                markHandled(chain.observations)
                for observation in chain.transactionsToFinish {
                    await observation.finish()
                    statistics.finishedCount += 1
                }
                statistics.syncedCount += 1
                Self.logger.info(
                    "store sync completed category=success state=\(receipt.syncedTransactionState.rawValue, privacy: .public) request_id=\(receipt.requestID, privacy: .public) transaction_hash=\(Self.transactionHash(representative.id), privacy: .public) credential_hash=\(representative.fingerprint.logHash, privacy: .public) duration_ms=\(Int(max(0, self.clock.now().timeIntervalSince(syncStartedAt)) * 1_000), privacy: .public)"
                )
            } catch let error as AccessCredentialError where error.isRetryable {
                Self.logger.error(
                    "store sync deferred category=\(error.categoryCode, privacy: .public) request_id=\(error.requestID ?? requestID, privacy: .public) transaction_hash=\(Self.transactionHash(representative.id), privacy: .public) credential_hash=\(representative.fingerprint.logHash, privacy: .public) duration_ms=\(Int(max(0, self.clock.now().timeIntervalSince(syncStartedAt)) * 1_000), privacy: .public)"
                )
                throw TransactionSyncDeferredError(
                    underlying: error,
                    syncAttemptID: syncAttemptID,
                    requestID: error.requestID ?? requestID
                )
            }
        }
        return statistics
    }

    private func markHandled(_ observations: [StoreTransactionObservation]) {
        for observation in observations {
            handledFingerprints.insert(observation.fingerprint)
        }
    }

    private func takeBufferedUpdates() -> [StoreTransactionObservation] {
        let updates = bufferedUpdates
        bufferedUpdates.removeAll(keepingCapacity: true)
        return updates
    }

    private func restoreBufferedUpdates(_ observations: [StoreTransactionObservation]) {
        for observation in observations where !handledFingerprints.contains(observation.fingerprint) {
            if bufferedUpdates.contains(where: { $0.fingerprint == observation.fingerprint }) {
                continue
            }
            bufferedUpdates.append(observation)
        }
    }

    private static func transactionHash(_ transactionID: UInt64) -> String {
        SHA256.hash(data: Data(String(transactionID).utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func isConsistent(
        receipt: StoreSyncReceipt,
        with observation: StoreTransactionObservation
    ) -> Bool {
        if observation.revocationDate != nil {
            return receipt.syncedTransactionState == .revoked
                && !receipt.entitlement.isMember
        }
        return (receipt.syncedTransactionState == .active
            || receipt.syncedTransactionState == .grace)
            && receipt.entitlement.isMember
    }

    private static func localEntitlement(
        observations: [StoreTransactionObservation],
        now: Date
    ) -> EntitlementSummary {
        let active = observations
            .filter {
                $0.revocationDate == nil
                    && !$0.isUpgraded
                    && ($0.expirationDate ?? .distantFuture) > now
            }
            .max {
                if $0.purchaseDate != $1.purchaseDate {
                    return $0.purchaseDate < $1.purchaseDate
                }
                return $0.id < $1.id
            }
        guard let active else {
            return EntitlementSummary(
                tier: "free", productId: nil, subscriptionState: "none",
                limit: 3, used: 0, reserved: 0, remaining: 3,
                unlimited: false,
                periodStart: nil, resetAt: nil, expiresAt: nil,
                autoRenewEnabled: nil, vocabularyCorrectionEnabled: false
            )
        }

        let formatter = ISO8601DateFormatter()
        let expiration = active.expirationDate ?? now
        let nextMonth = Calendar(identifier: .gregorian).date(
            byAdding: .month,
            value: 1,
            to: now
        ) ?? expiration
        return EntitlementSummary(
            tier: "member", productId: active.productID, subscriptionState: "active",
            limit: 100, used: 0, reserved: 0, remaining: 100,
            unlimited: false,
            periodStart: formatter.string(from: now),
            resetAt: formatter.string(from: min(nextMonth, expiration)),
            expiresAt: formatter.string(from: expiration),
            autoRenewEnabled: true, vocabularyCorrectionEnabled: true
        )
    }
}
