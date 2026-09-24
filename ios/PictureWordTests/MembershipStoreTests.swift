import Foundation
import StoreKit
import StoreKitTest
import SwiftUI
import XCTest
@testable import PictureWord

final class MembershipStoreTests: XCTestCase {
    override class func tearDown() {
        MembershipMockURLProtocol.removeAllHandlers()
        super.tearDown()
    }

    func testConcurrentBootstrapUsesOneRequestAndOneToken() async throws {
        let host = "bootstrap.picture-word.test"
        let requests = LockedCapture<URLRequest>()
        MembershipMockURLProtocol.setHandler(for: host) { request in
            requests.append(request)
            Thread.sleep(forTimeInterval: 0.05)
            return .json(status: 200, body: Self.bootstrapJSON(token: "shared-token"))
        }
        let keychain = FakeKeychain()
        let store = AccessCredentialStore(
            baseURL: try XCTUnwrap(URL(string: "https://\(host)")),
            keychain: keychain,
            session: makeSession(),
            deviceTokenProvider: { "test-device-token" }
        )

        async let first = store.bootstrapIfNeeded(force: true)
        async let second = store.bootstrapIfNeeded(force: true)
        let values = try await (first, second)

        XCTAssertEqual(values.0, values.1)
        XCTAssertEqual(requests.values.count, 1)
        XCTAssertEqual(keychain.string(for: "access-token"), "shared-token")
    }

    func testStoreSyncRetries503ThreeTimesWithSameRequestID() async throws {
        let host = "retry.picture-word.test"
        let requests = LockedCapture<URLRequest>()
        MembershipMockURLProtocol.setHandler(for: host) { request in
            requests.append(request)
            if requests.values.count < 3 {
                return .json(
                    status: 503,
                    headers: ["Retry-After": "0", "X-Request-ID": "server-request"],
                    body: Self.errorJSON(code: "STORE_SYNC_UNAVAILABLE")
                )
            }
            return .json(
                status: 200,
                body: Self.storeSyncJSON(tier: "member", transactionState: "active")
            )
        }
        let keychain = FakeKeychain(values: ["access-token": "existing-token"])
        let store = AccessCredentialStore(
            baseURL: try XCTUnwrap(URL(string: "https://\(host)")),
            keychain: keychain,
            session: makeSession(),
            deviceTokenProvider: { "test-device-token" }
        )

        let receipt = try await store.syncSubscription(
            signedTransaction: "signed-transaction",
            signedRenewalInfo: nil
        )

        let captured = requests.values
        XCTAssertTrue(receipt.entitlement.isMember)
        XCTAssertEqual(receipt.syncedTransactionState, .active)
        XCTAssertEqual(captured.count, 3)
        XCTAssertEqual(Set(captured.compactMap { $0.value(forHTTPHeaderField: "X-Request-ID") }).count, 1)
    }

    func testStoreSyncDoesNotRetry400() async throws {
        let host = "invalid.picture-word.test"
        let requests = LockedCapture<URLRequest>()
        MembershipMockURLProtocol.setHandler(for: host) { request in
            requests.append(request)
            return .json(
                status: 400,
                headers: ["X-Request-ID": "invalid-request"],
                body: Self.errorJSON(code: "TRANSACTION_VERIFICATION_FAILED")
            )
        }
        let store = AccessCredentialStore(
            baseURL: try XCTUnwrap(URL(string: "https://\(host)")),
            keychain: FakeKeychain(values: ["access-token": "existing-token"]),
            session: makeSession(),
            deviceTokenProvider: { "test-device-token" }
        )

        do {
            _ = try await store.syncSubscription(
                signedTransaction: "invalid-transaction",
                signedRenewalInfo: nil
            )
            XCTFail("Expected a verification error")
        } catch let error as AccessCredentialError {
            guard case .server(let code, _, let requestID, let retryable) = error else {
                return XCTFail("Unexpected access error: \(error)")
            }
            XCTAssertEqual(code, "TRANSACTION_VERIFICATION_FAILED")
            XCTAssertEqual(requestID, "invalid-request")
            XCTAssertFalse(retryable)
        }

        XCTAssertEqual(requests.values.count, 1)
    }

    func testStoreSyncDecodesProcessedExpiredTransactionWithoutMembership() async throws {
        let host = "expired.picture-word.test"
        MembershipMockURLProtocol.setHandler(for: host) { _ in
            .json(
                status: 200,
                body: Self.storeSyncJSON(tier: "free", transactionState: "expired")
            )
        }
        let store = AccessCredentialStore(
            baseURL: try XCTUnwrap(URL(string: "https://\(host)")),
            keychain: FakeKeychain(values: ["access-token": "existing-token"]),
            session: makeSession(),
            deviceTokenProvider: { "test-device-token" }
        )

        let receipt = try await store.syncSubscription(
            signedTransaction: "expired-transaction",
            signedRenewalInfo: nil
        )

        XCTAssertEqual(receipt.syncedTransactionState, .expired)
        XCTAssertFalse(receipt.entitlement.isMember)
    }

    func testSuccessfulEntitlementSyncClearsOnlySyncFailureNotice() {
        let failed = MembershipNotice(
            text: "temporary",
            source: .purchase,
            category: .awaitingTransactionSync,
            requestID: "request-id",
            syncAttemptID: UUID()
        )
        let informational = MembershipNotice(
            text: "会员已开通",
            source: .purchase,
            category: .information,
            requestID: nil,
            syncAttemptID: nil
        )

        XCTAssertNil(MembershipNotice.afterSuccessfulEntitlementSync(failed))
        XCTAssertEqual(MembershipNotice.afterSuccessfulEntitlementSync(informational), informational)
    }

    func testSettingsDisplayStateDistinguishesInitialRefreshFreshAndFailure() {
        XCTAssertEqual(MembershipSettingsDisplayState.idle.statusText, "等待读取会员状态…")
        XCTAssertEqual(MembershipSettingsDisplayState.initialLoading.statusText, "正在读取会员状态…")
        XCTAssertEqual(MembershipSettingsDisplayState.refreshing.statusText, "正在刷新会员状态…")
        XCTAssertEqual(MembershipSettingsDisplayState.loaded.statusText, "会员状态已更新")
        XCTAssertEqual(MembershipSettingsDisplayState.failedWithCachedValue.statusText, "显示上次数据，刷新失败")
        XCTAssertEqual(MembershipSettingsDisplayState.failedWithoutCachedValue.statusText, "暂时无法读取")

        XCTAssertEqual(
            MembershipSettingsDisplayState.resolve(
                loadState: .loading(hasCachedValue: false),
                isRefreshing: false
            ),
            .initialLoading
        )
        XCTAssertEqual(
            MembershipSettingsDisplayState.resolve(
                loadState: .loading(hasCachedValue: true),
                isRefreshing: false
            ),
            .refreshing
        )
        XCTAssertEqual(
            MembershipSettingsDisplayState.resolve(
                loadState: .loaded,
                isRefreshing: false
            ),
            .loaded
        )
        XCTAssertEqual(
            MembershipSettingsDisplayState.resolve(
                loadState: .failed(message: "temporary", hasCachedValue: true, requestID: nil),
                isRefreshing: false
            ),
            .failedWithCachedValue
        )
        XCTAssertEqual(
            MembershipSettingsDisplayState.resolve(
                loadState: .failed(message: "temporary", hasCachedValue: false, requestID: nil),
                isRefreshing: false
            ),
            .failedWithoutCachedValue
        )
    }

    func testSettingsDisplayStateTreatsAnActiveSyncAsRefreshing() {
        XCTAssertEqual(
            MembershipSettingsDisplayState.resolve(
                loadState: .loaded,
                isRefreshing: true
            ),
            .refreshing
        )
        XCTAssertEqual(
            MembershipSettingsDisplayState.resolve(
                loadState: .loading(hasCachedValue: false),
                isRefreshing: true
            ),
            .initialLoading
        )
    }

    func testSettingsQuotaTextNeverInventsUnavailableQuota() {
        XCTAssertEqual(
            MembershipSettingsDisplayState.quotaText(
                entitlement: nil,
                state: .initialLoading
            ),
            "正在读取识别额度…"
        )
        XCTAssertEqual(
            MembershipSettingsDisplayState.quotaText(
                entitlement: nil,
                state: .failedWithoutCachedValue
            ),
            "暂时无法读取"
        )
    }

    func testSettingsQuotaTextStaysCompactForCachedValueStates() {
        let entitlement = makeMemberEntitlement(remaining: 27)

        XCTAssertEqual(
            MembershipSettingsDisplayState.quotaText(
                entitlement: entitlement,
                state: .loaded
            ),
            "本期剩余 27/100 次识别"
        )
        XCTAssertEqual(
            MembershipSettingsDisplayState.quotaText(
                entitlement: entitlement,
                state: .refreshing
            ),
            "本期剩余 27/100 次识别"
        )
        XCTAssertEqual(
            MembershipSettingsDisplayState.quotaText(
                entitlement: entitlement,
                state: .failedWithCachedValue
            ),
            "本期剩余 27/100 次识别"
        )
    }

    func testUnlimitedQuotaUsesExplicitCopyAndPaywallState() {
        let entitlement = makeMemberEntitlement(remaining: Int.max, unlimited: true)

        XCTAssertEqual(
            MembershipSettingsDisplayState.quotaText(entitlement: entitlement, state: .loaded),
            "本期识别额度：无限"
        )
        XCTAssertEqual(
            MembershipStore.membershipPaywallState(
                entitlement: entitlement,
                loadState: .loaded,
                isRefreshing: false
            ),
            .unlimited
        )
    }

    func testForegroundRefreshPolicyUsesFiveMinuteStatusWindow() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertFalse(MembershipLifecycleRefreshPolicy.shouldRefreshAfterForeground(
            lastSuccessfulRefreshAt: now.addingTimeInterval(-299),
            now: now
        ))
        XCTAssertTrue(MembershipLifecycleRefreshPolicy.shouldRefreshAfterForeground(
            lastSuccessfulRefreshAt: now.addingTimeInterval(-300),
            now: now
        ))
        XCTAssertTrue(MembershipLifecycleRefreshPolicy.shouldRefreshAfterForeground(
            lastSuccessfulRefreshAt: nil,
            now: now
        ))
    }

    func testSettingsRefreshPolicyRetriesOnlyFailedStartup() {
        XCTAssertFalse(MembershipLifecycleRefreshPolicy.shouldRetryAfterSettingsPresentation(
            loadState: .loaded
        ))
        XCTAssertFalse(MembershipLifecycleRefreshPolicy.shouldRetryAfterSettingsPresentation(
            loadState: .loading(hasCachedValue: true)
        ))
        XCTAssertTrue(MembershipLifecycleRefreshPolicy.shouldRetryAfterSettingsPresentation(
            loadState: .failed(message: "offline", hasCachedValue: true, requestID: nil)
        ))
    }

    func testPaywallDoesNotShowExhaustedWhileEntitlementIsBeingSynced() {
        let exhausted = makeMemberEntitlement(remaining: 0)

        XCTAssertEqual(
            MembershipStore.membershipPaywallState(
                entitlement: exhausted,
                loadState: .loading(hasCachedValue: true),
                isRefreshing: true
            ),
            .syncing
        )
        XCTAssertEqual(
            MembershipStore.membershipPaywallState(
                entitlement: exhausted,
                loadState: .loaded,
                isRefreshing: true
            ),
            .syncing
        )
    }

    func testPaywallShowsFreshRemainingQuotaAndOnlyThenCanShowExhausted() {
        let active = makeMemberEntitlement(remaining: 27)
        let exhausted = makeMemberEntitlement(remaining: 0)

        XCTAssertEqual(
            MembershipStore.membershipPaywallState(
                entitlement: active,
                loadState: .loaded,
                isRefreshing: false
            ),
            .active(remaining: 27, limit: 100)
        )
        XCTAssertEqual(
            MembershipStore.membershipPaywallState(
                entitlement: exhausted,
                loadState: .loaded,
                isRefreshing: false
            ),
            .exhausted
        )
    }

    func testPaywallUsesRecoverableUnavailableStateAfterSyncFailure() {
        XCTAssertEqual(
            MembershipStore.membershipPaywallState(
                entitlement: makeMemberEntitlement(remaining: 0),
                loadState: .failed(message: "temporary", hasCachedValue: true, requestID: "request-id"),
                isRefreshing: false
            ),
            .unavailable
        )
    }

    func testNineRenewalsInOneChainProduceOneServerSyncPlan() {
        let now = Date(timeIntervalSince1970: 20_000)
        var observations: [StoreTransactionObservation] = []
        for index in 1...9 {
            let purchaseOffset = TimeInterval(index - 9) * 2_000
            observations.append(makeObservation(
                id: UInt64(index),
                originalID: 1,
                purchaseDate: now.addingTimeInterval(purchaseOffset),
                expirationDate: index == 9 ? now.addingTimeInterval(2_000) : now.addingTimeInterval(-1)
            ))
        }

        let plan = SubscriptionReconciliationPlanner.makePlan(
            observations: observations,
            handledFingerprints: [],
            now: now
        )

        XCTAssertEqual(plan.chainCount, 1)
        XCTAssertEqual(plan.chainsToSync.count, 1)
        XCTAssertEqual(plan.chainsToSync.first?.representative.id, 9)
        XCTAssertEqual(plan.chainsToSync.first?.transactionsToFinish.count, 9)
    }

    func testTwoIndependentActiveChainsProduceAtMostOneSyncEach() {
        let now = Date(timeIntervalSince1970: 20_000)
        let observations = [
            makeObservation(
                id: 10,
                originalID: 1,
                purchaseDate: now,
                expirationDate: now.addingTimeInterval(1_000)
            ),
            makeObservation(
                id: 20,
                originalID: 2,
                purchaseDate: now,
                expirationDate: now.addingTimeInterval(1_000)
            ),
        ]

        let plan = SubscriptionReconciliationPlanner.makePlan(
            observations: observations,
            handledFingerprints: [],
            now: now
        )

        XCTAssertEqual(plan.chainCount, 2)
        XCTAssertEqual(plan.chainsToSync.count, 2)
    }

    func testExpiredHistoryAcrossMultipleChainsFinishesLocallyWithoutSync() {
        let now = Date(timeIntervalSince1970: 20_000)
        var observations: [StoreTransactionObservation] = []
        for index in 1...9 {
            let purchaseOffset = TimeInterval(index - 10) * 1_000
            observations.append(makeObservation(
                id: UInt64(index),
                originalID: index < 5 ? 1 : 2,
                purchaseDate: now.addingTimeInterval(purchaseOffset),
                expirationDate: now.addingTimeInterval(-100)
            ))
        }

        let plan = SubscriptionReconciliationPlanner.makePlan(
            observations: observations,
            handledFingerprints: [],
            now: now
        )

        XCTAssertEqual(plan.chainCount, 2)
        XCTAssertTrue(plan.chainsToSync.isEmpty)
        XCTAssertEqual(plan.transactionsToFinishLocally.count, 9)
    }

    func testRevokedLatestTransactionProducesOneServerSyncPlan() {
        let now = Date(timeIntervalSince1970: 20_000)
        let revoked = makeObservation(
            id: 9,
            originalID: 1,
            purchaseDate: now,
            expirationDate: now.addingTimeInterval(-1),
            revocationDate: now
        )

        let plan = SubscriptionReconciliationPlanner.makePlan(
            observations: [revoked],
            handledFingerprints: [],
            now: now
        )

        XCTAssertEqual(plan.chainsToSync.count, 1)
        XCTAssertEqual(plan.chainsToSync.first?.representative.id, 9)
    }

    func testRevokedLatestTransactionSyncsOnceThenFinishes() async throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let recorder = FinishRecorder()
        let revoked = makeObservation(
            id: 9,
            purchaseDate: now,
            expirationDate: now.addingTimeInterval(-1),
            revocationDate: now,
            recorder: recorder
        )
        let gateway = FakeStoreKitTransactionGateway(observations: [revoked])
        let api = FakeMembershipEntitlementAPI(
            syncedState: .revoked,
            returnsMember: false
        )
        let coordinator = makeCoordinator(gateway: gateway, api: api, now: now)

        _ = try await result(from: await coordinator.submitReconciliation(reason: .startup))

        let syncCallCount = await api.syncCallCount()
        let finishedIDs = await recorder.finishedIDs()
        XCTAssertEqual(syncCallCount, 1)
        XCTAssertEqual(finishedIDs, [9])
    }

    func testSameTransactionUsesChangedJWSButKeepsRevocationPriority() {
        let now = Date(timeIntervalSince1970: 20_000)
        let original = makeObservation(
            id: 9,
            purchaseDate: now,
            expirationDate: now.addingTimeInterval(1_000),
            signedTransaction: "jws-original"
        )
        let revoked = makeObservation(
            id: 9,
            purchaseDate: now,
            expirationDate: now.addingTimeInterval(1_000),
            revocationDate: now,
            signedTransaction: "jws-revoked"
        )
        let stale = makeObservation(
            id: 9,
            purchaseDate: now,
            expirationDate: now.addingTimeInterval(1_000),
            signedTransaction: "jws-stale"
        )

        let plan = SubscriptionReconciliationPlanner.makePlan(
            observations: [original, revoked, stale],
            handledFingerprints: [],
            now: now
        )

        XCTAssertEqual(plan.duplicateCount, 2)
        XCTAssertEqual(plan.chainsToSync.first?.representative.signedTransaction, "jws-revoked")
    }

    func testStartupBuffersUpdateAndCoalescesConcurrentLifecycleRequests() async throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let recorder = FinishRecorder()
        let snapshotTransaction = makeObservation(
            id: 8,
            originalID: 1,
            purchaseDate: now.addingTimeInterval(-1_000),
            expirationDate: now.addingTimeInterval(-1),
            recorder: recorder
        )
        let latestUpdate = makeObservation(
            id: 9,
            originalID: 1,
            purchaseDate: now,
            expirationDate: now.addingTimeInterval(1_000),
            source: .update,
            recorder: recorder
        )
        let gateway = FakeStoreKitTransactionGateway(observations: [snapshotTransaction])
        let api = FakeMembershipEntitlementAPI()
        let coordinator = makeCoordinator(gateway: gateway, api: api, now: now)

        let buffered = await coordinator.submit(event: .verified(latestUpdate), reason: .transactionUpdate)
        guard case .buffered = buffered else { return XCTFail("Expected buffered update") }
        let startup = await coordinator.submitReconciliation(reason: .startup)
        let foreground = await coordinator.submitStatusRefresh(reason: .foreground)
        guard case .joined = foreground else { return XCTFail("Expected lifecycle request to join startup") }
        let result = try await result(from: startup)

        XCTAssertEqual(result.statistics.chainCount, 1)
        let syncCallCount = await api.syncCallCount()
        let statusCallCount = await api.statusCallCount()
        let finishedIDs = await recorder.finishedIDs()
        XCTAssertEqual(syncCallCount, 1)
        XCTAssertEqual(statusCallCount, 1)
        XCTAssertEqual(Set(finishedIDs), Set([8, 9]))
    }

    func testNineRenewalsCoordinatorSyncsOnceAndFinishesAll() async throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let recorder = FinishRecorder()
        var observations: [StoreTransactionObservation] = []
        for index in 1...9 {
            observations.append(makeObservation(
                id: UInt64(index),
                originalID: 1,
                purchaseDate: now.addingTimeInterval(TimeInterval(index)),
                expirationDate: index == 9
                    ? now.addingTimeInterval(1_000)
                    : now.addingTimeInterval(-1_000),
                recorder: recorder
            ))
        }
        let gateway = FakeStoreKitTransactionGateway(observations: observations)
        let api = FakeMembershipEntitlementAPI()
        let coordinator = makeCoordinator(gateway: gateway, api: api, now: now)

        let result = try await result(from: await coordinator.submitReconciliation(reason: .startup))

        let syncCallCount = await api.syncCallCount()
        let statusCallCount = await api.statusCallCount()
        let finishedIDs = await recorder.finishedIDs()
        XCTAssertEqual(result.statistics.chainCount, 1)
        XCTAssertEqual(syncCallCount, 1)
        XCTAssertEqual(statusCallCount, 1)
        XCTAssertEqual(Set(finishedIDs), Set((1...9).map { UInt64($0) }))
    }

    func testSuccessfulFingerprintIsIgnoredButChangedJWSIsProcessed() async throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let initial = makeObservation(
            id: 9,
            purchaseDate: now,
            expirationDate: now.addingTimeInterval(1_000),
            signedTransaction: "jws-a"
        )
        let gateway = FakeStoreKitTransactionGateway(observations: [initial])
        let api = FakeMembershipEntitlementAPI()
        let coordinator = makeCoordinator(gateway: gateway, api: api, now: now)
        _ = try await result(from: await coordinator.submitReconciliation(reason: .startup))

        let duplicate = await coordinator.submit(
            event: .verified(makeObservation(
                id: 9,
                purchaseDate: now,
                expirationDate: now.addingTimeInterval(1_000),
                source: .update,
                signedTransaction: "jws-a"
            )),
            reason: .transactionUpdate
        )
        guard case .ignored = duplicate else { return XCTFail("Expected duplicate to be ignored") }
        let changed = await coordinator.submit(
            event: .verified(makeObservation(
                id: 9,
                purchaseDate: now,
                expirationDate: now.addingTimeInterval(1_000),
                source: .update,
                signedTransaction: "jws-b"
            )),
            reason: .transactionUpdate
        )
        _ = try await result(from: changed)

        let syncCallCount = await api.syncCallCount()
        XCTAssertEqual(syncCallCount, 2)
    }

    func testFailedSyncDoesNotFinishAndCanRetry() async throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let recorder = FinishRecorder()
        let observation = makeObservation(
            id: 9,
            purchaseDate: now,
            expirationDate: now.addingTimeInterval(1_000),
            recorder: recorder
        )
        let gateway = FakeStoreKitTransactionGateway(observations: [observation])
        let api = FakeMembershipEntitlementAPI(failuresRemaining: 1)
        let coordinator = makeCoordinator(gateway: gateway, api: api, now: now)

        do {
            _ = try await result(from: await coordinator.submitReconciliation(reason: .startup))
            XCTFail("Expected a retryable sync error")
        } catch {
            let finishedIDs = await recorder.finishedIDs()
            XCTAssertTrue(finishedIDs.isEmpty)
        }

        _ = try await result(from: await coordinator.submitReconciliation(reason: .manual))
        let syncCallCount = await api.syncCallCount()
        let finishedIDs = await recorder.finishedIDs()
        XCTAssertEqual(syncCallCount, 2)
        XCTAssertEqual(finishedIDs, [9])
    }

    func testUnverifiedTransactionDoesNotBlockVerifiedChain() async throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let recorder = FinishRecorder()
        let gateway = FakeStoreKitTransactionGateway(
            observations: [makeObservation(
                id: 9,
                purchaseDate: now,
                expirationDate: now.addingTimeInterval(1_000),
                recorder: recorder
            )],
            unverifiedCount: 1
        )
        let api = FakeMembershipEntitlementAPI()
        let coordinator = makeCoordinator(gateway: gateway, api: api, now: now)

        let result = try await result(from: await coordinator.submitReconciliation(reason: .startup))

        let syncCallCount = await api.syncCallCount()
        let finishedIDs = await recorder.finishedIDs()
        XCTAssertEqual(result.statistics.unverifiedCount, 1)
        XCTAssertEqual(syncCallCount, 1)
        XCTAssertEqual(finishedIDs, [9])
    }

    func testStatusRefreshDoesNotRescanStoreKitOrCallStoreSync() async throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let gateway = FakeStoreKitTransactionGateway(observations: [makeObservation(
            id: 9,
            purchaseDate: now.addingTimeInterval(-2_000),
            expirationDate: now.addingTimeInterval(-1_000)
        )])
        let api = FakeMembershipEntitlementAPI()
        let coordinator = makeCoordinator(gateway: gateway, api: api, now: now)
        _ = try await result(from: await coordinator.submitReconciliation(reason: .startup))

        _ = try await result(from: await coordinator.submitStatusRefresh(reason: .foreground))

        let snapshotCount = await gateway.snapshotCallCount()
        let syncCallCount = await api.syncCallCount()
        let statusCallCount = await api.statusCallCount()
        XCTAssertEqual(snapshotCount, 1)
        XCTAssertEqual(syncCallCount, 0)
        XCTAssertEqual(statusCallCount, 2)
    }

    func testSubscriptionDiscountUsesLocalPricesAndCurrency() {
        XCTAssertEqual(
            SubscriptionDiscountCalculator.savingsPercent(
                monthlyPrice: 10,
                annualPrice: 60,
                monthlyCurrencyCode: "CNY",
                annualCurrencyCode: "CNY"
            ),
            50
        )
    }

    func testAnnualIntroductoryOfferDisplaysFullChargeSavingsAndRenewal() throws {
        let offer = try XCTUnwrap(annualOffer(eligible: true))
        XCTAssertEqual(offer.priceText, "首年 ¥78.00")
        XCTAssertEqual(offer.purchaseTitle, "以 ¥78.00 开通首年会员")
        XCTAssertTrue(offer.detail.contains("30.00"))
        XCTAssertTrue(offer.detail.contains("之后 ¥108.00/年"))
        XCTAssertTrue(offer.renewalDisclosure.contains("自动续订"))
    }

    @MainActor
    func testStoreKitAnnualOfferChargesFirstYearThenStandardRenewalAndRefreshesEligibility() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "KakawordSubscriptions", withExtension: "storekit"
        ))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.storefront = "CHN"
        session.locale = Locale(identifier: "zh_CN")
        defer {
            session.clearTransactions()
            session.resetToDefaultState()
        }
        let cachedEntitlement = UserDefaults.standard.data(forKey: "membership.cachedEntitlement")
        defer { UserDefaults.standard.set(cachedEntitlement, forKey: "membership.cachedEntitlement") }
        let store = MembershipStore(
            storeKitGateway: FakeStoreKitTransactionGateway(observations: []),
            entitlementAPI: FakeMembershipEntitlementAPI(returnsMember: false)
        )
        await store.refreshCurrentEntitlements()
        await store.prepareProducts(force: true)
        let annual = try XCTUnwrap(store.annualProduct)
        let introduction = try XCTUnwrap(annual.subscription?.introductoryOffer)
        XCTAssertEqual(annual.price, 108)
        XCTAssertEqual(store.monthlyProduct?.price, 15)
        XCTAssertNil(store.monthlyProduct?.subscription?.introductoryOffer)
        XCTAssertEqual(introduction.price, 78)
        XCTAssertEqual(introduction.paymentMode, .payUpFront)
        XCTAssertEqual(introduction.period, .yearly)
        XCTAssertEqual(introduction.periodCount, 1)
        XCTAssertEqual(store.annualIntroductoryOffer?.displayPrice, introduction.displayPrice)

        _ = try await session.buyProduct(identifier: annual.id)
        let firstResult = await Transaction.latest(for: annual.id)
        guard case .verified(let firstTransaction) = firstResult else {
            return XCTFail("Expected a verified local introductory purchase")
        }
        XCTAssertEqual(firstTransaction.price, 78)
        await firstTransaction.finish()
        await store.prepareProducts(force: true)
        XCTAssertNil(store.annualIntroductoryOffer)

        try session.forceRenewalOfSubscription(productIdentifier: annual.id)
        // StoreKit 2's transaction cache can lag behind SKTestSession's renewal.
        // Wait for the new transaction rather than asserting on the first charge.
        var renewedTransaction: StoreKit.Transaction?
        for _ in 0..<50 {
            if case .verified(let candidate) = await Transaction.latest(for: annual.id),
               candidate.id != firstTransaction.id {
                renewedTransaction = candidate
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        let renewal = try XCTUnwrap(renewedTransaction, "Expected a new verified local renewal")
        XCTAssertEqual(renewal.price, 108)
        await renewal.finish()
        try session.expireSubscription(productIdentifier: annual.id)
        await store.prepareProducts(force: true)
        XCTAssertNil(store.annualIntroductoryOffer, "An expired subscription must not regain its consumed offer")
    }

    func testAnnualIntroductoryOfferRequiresConfirmedAppleEligibility() {
        XCTAssertNil(annualOffer(eligible: nil))
        XCTAssertNil(annualOffer(eligible: false))
        XCTAssertNotNil(annualOffer(eligible: true))
    }

    @MainActor
    func testIntroductoryPriceCardExpandsForAccessibilityTypeOnSmallAndLargeScreens() throws {
        let offer = try XCTUnwrap(annualOffer(eligible: true))
        for width: CGFloat in [284, 394] {
            var previousHeight: CGFloat = 0
            for size: DynamicTypeSize in [.large, .accessibility3] {
                let card = MembershipPlanCard(
                    title: "新人年会员", badge: "推荐", priceText: offer.priceText,
                    detail: offer.detail, selected: true, onSelect: {}
                )
                .frame(width: width)
                .environment(\.dynamicTypeSize, size)
                .padding(18)
                .background(Color.paper)
                let renderer = ImageRenderer(content: card)
                let image = try XCTUnwrap(renderer.uiImage)
                XCTAssertEqual(image.size.width, width + 36, accuracy: 1)
                XCTAssertGreaterThan(image.size.height, previousHeight)
                previousHeight = image.size.height
                let attachment = XCTAttachment(image: image)
                attachment.name = "introductory-offer-\(Int(width + 36))-\(size)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testAnnualIntroductoryOfferDoesNotMislabelOtherOfferDurationsOrModes() {
        XCTAssertNil(annualOffer(eligible: true, mode: .freeTrial))
        XCTAssertNil(annualOffer(eligible: true, mode: .payAsYouGo))
        XCTAssertNil(annualOffer(eligible: true, period: .monthly))
        XCTAssertNil(annualOffer(eligible: true, count: 2))
        XCTAssertNil(annualOffer(eligible: true, subscriptionPeriod: .monthly))
        XCTAssertNil(annualOffer(eligible: true, offerPrice: 0))
        XCTAssertNil(annualOffer(eligible: true, offerPrice: 108))
        XCTAssertNil(annualOffer(eligible: true, offerPrice: 120))
    }

    func testAnnualIntroductoryOfferUsesStoreKitPricesRatherThanCampaignConstants() throws {
        let style = Decimal.FormatStyle.Currency(code: "USD").locale(Locale(identifier: "en_US"))
        let offer = try XCTUnwrap(AnnualIntroductoryOffer.make(
            isEligible: true, regularPrice: 20, offerPrice: 12,
            displayPrice: "$12.00", renewalPrice: "$20.00", priceFormatStyle: style,
            paymentMode: .payUpFront, period: .yearly, periodCount: 1, subscriptionPeriod: .yearly
        ))
        XCTAssertEqual(offer.detail, "首年省 $8.00，之后 $20.00/年")
        XCTAssertEqual(offer.purchaseTitle, "以 $12.00 开通首年会员")
    }

    private func annualOffer(
        eligible: Bool?,
        mode: Product.SubscriptionOffer.PaymentMode = .payUpFront,
        period: Product.SubscriptionPeriod = .yearly,
        count: Int = 1,
        subscriptionPeriod: Product.SubscriptionPeriod = .yearly,
        offerPrice: Decimal = 78
    ) -> AnnualIntroductoryOffer? {
        AnnualIntroductoryOffer.make(
            isEligible: eligible, regularPrice: 108, offerPrice: offerPrice,
            displayPrice: "¥78.00", renewalPrice: "¥108.00",
            priceFormatStyle: Decimal.FormatStyle.Currency(code: "CNY").locale(Locale(identifier: "zh_CN")),
            paymentMode: mode, period: period, periodCount: count, subscriptionPeriod: subscriptionPeriod
        )
    }

    func testSubscriptionDiscountFallsBackWhenPricesAreNotComparable() {
        XCTAssertNil(discount(monthly: 10, annual: 120, currency: "CNY"))
        XCTAssertNil(discount(monthly: 10, annual: 60, currency: "USD", annualCurrency: "CNY"))
        XCTAssertNil(discount(monthly: 0, annual: 60, currency: "CNY"))
        XCTAssertNil(discount(monthly: 10, annual: 60, currency: nil))
    }

    func testSubscriptionDiscountRoundsAndSuppressesZeroPercent() {
        XCTAssertEqual(discount(monthly: 10, annual: 99, currency: "USD"), 18)
        XCTAssertNil(discount(monthly: 100, annual: 1199, currency: "USD"))
    }

    func testMembershipPlanConfigBuildsFiniteQuotaCopy() {
        let config = MembershipPlanConfig(limit: 240, unlimited: false)

        XCTAssertEqual(config.paywallBenefitText, "每月 240 次完整拍照识词")
    }

    func testMembershipPlanConfigBuildsUnlimitedQuotaCopy() {
        let config = MembershipPlanConfig(limit: 240, unlimited: true)

        XCTAssertEqual(config.paywallBenefitText, "每月无限次完整拍照识词")
    }

    func testMembershipPlanConfigClientLoadsPublicConfiguration() async throws {
        let host = "membership-config.picture-word.test"
        MembershipMockURLProtocol.setHandler(for: host) { request in
            XCTAssertEqual(request.url?.path, "/v1/membership/config")
            return .json(status: 200, body: Data("""
            {"quota":{"limit":180,"unlimited":false}}
            """.utf8))
        }
        let client = MembershipPlanConfigClient(
            baseURL: try XCTUnwrap(URL(string: "https://\(host)")),
            session: makeSession()
        )

        let config = try await client.fetch()

        XCTAssertEqual(config, MembershipPlanConfig(limit: 180, unlimited: false))
    }

    private func makeObservation(
        id: UInt64,
        originalID: UInt64 = 1,
        purchaseDate: Date,
        expirationDate: Date?,
        revocationDate: Date? = nil,
        isUpgraded: Bool = false,
        source: StoreTransactionSource = .unfinished,
        signedTransaction: String? = nil,
        recorder: FinishRecorder? = nil
    ) -> StoreTransactionObservation {
        StoreTransactionObservation(
            id: id,
            originalID: originalID,
            productID: MembershipStore.monthlyProductId,
            purchaseDate: purchaseDate,
            expirationDate: expirationDate,
            revocationDate: revocationDate,
            isUpgraded: isUpgraded,
            isXcodeEnvironment: false,
            signedTransaction: signedTransaction ?? "jws-\(id)",
            source: source,
            requiresFinish: source != .currentEntitlement,
            finishOperation: { await recorder?.record(id) }
        )
    }

    private func makeCoordinator(
        gateway: any StoreKitTransactionProviding,
        api: any MembershipEntitlementAPI,
        now: Date
    ) -> EntitlementSyncCoordinator {
        EntitlementSyncCoordinator(
            gateway: gateway,
            api: api,
            supportedProductIDs: [
                MembershipStore.monthlyProductId,
                MembershipStore.annualProductId,
            ],
            clock: MembershipSyncClock(now: { now })
        )
    }

    private func result(
        from submission: EntitlementSyncSubmission
    ) async throws -> EntitlementSyncResult {
        switch submission {
        case .started(let task), .joined(let task):
            return try await task.value
        case .buffered:
            throw TestFailure.unexpectedSubmission("buffered")
        case .ignored:
            throw TestFailure.unexpectedSubmission("ignored")
        case .unverified:
            throw TestFailure.unexpectedSubmission("unverified")
        }
    }

    private func discount(
        monthly: Decimal,
        annual: Decimal,
        currency: String?,
        annualCurrency: String? = nil
    ) -> Int? {
        SubscriptionDiscountCalculator.savingsPercent(
            monthlyPrice: monthly,
            annualPrice: annual,
            monthlyCurrencyCode: currency,
            annualCurrencyCode: annualCurrency ?? currency
        )
    }

    private func makeMemberEntitlement(remaining: Int, unlimited: Bool = false) -> EntitlementSummary {
        EntitlementSummary(
            tier: "member",
            productId: MembershipStore.annualProductId,
            subscriptionState: "active",
            limit: 100,
            used: 100 - remaining,
            reserved: 0,
            remaining: remaining,
            unlimited: unlimited,
            periodStart: "2026-08-01T00:00:00.000Z",
            resetAt: "2026-09-01T00:00:00.000Z",
            expiresAt: "2027-08-01T00:00:00.000Z",
            autoRenewEnabled: true,
            vocabularyCorrectionEnabled: true
        )
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MembershipMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func bootstrapJSON(token: String) -> Data {
        Data("""
        {"accessToken":"\(token)","entitlement":\(entitlementObjectJSON(tier: "free"))}
        """.utf8)
    }

    private static func storeSyncJSON(tier: String, transactionState: String) -> Data {
        Data("{\"entitlement\":\(entitlementObjectJSON(tier: tier)),\"syncedTransactionState\":\"\(transactionState)\"}".utf8)
    }

    private static func entitlementObjectJSON(tier: String) -> String {
        let isMember = tier == "member"
        return """
        {"tier":"\(tier)","productId":\(isMember ? "\"com.kakaword.app.membership.annual\"" : "null"),"subscriptionState":"\(isMember ? "active" : "none")","limit":\(isMember ? 100 : 3),"used":0,"reserved":0,"remaining":\(isMember ? 100 : 3),"periodStart":null,"resetAt":null,"expiresAt":null,"autoRenewEnabled":\(isMember ? "true" : "null"),"vocabularyCorrectionEnabled":\(isMember ? "true" : "false")}
        """
    }

    private static func errorJSON(code: String) -> Data {
        Data("{\"error\":\"\(code)\",\"message\":\"temporary error\"}".utf8)
    }
}

private enum TestFailure: Error {
    case unexpectedSubmission(String)
}

private actor FinishRecorder {
    private var storage: [UInt64] = []

    func record(_ id: UInt64) {
        storage.append(id)
    }

    func finishedIDs() -> [UInt64] {
        storage
    }
}

private actor FakeStoreKitTransactionGateway: StoreKitTransactionProviding {
    private let snapshotValue: StoreTransactionSnapshot
    private var snapshotRequests = 0

    init(
        observations: [StoreTransactionObservation],
        unverifiedCount: Int = 0
    ) {
        let unverified = (0..<unverifiedCount).map { index in
            UnverifiedStoreTransaction(
                transactionID: UInt64(10_000 + index),
                productID: MembershipStore.monthlyProductId,
                source: .unfinished
            )
        }
        snapshotValue = StoreTransactionSnapshot(
            observations: observations,
            unverified: unverified,
            currentCount: observations.filter { $0.source == .currentEntitlement }.count,
            unfinishedCount: observations.filter { $0.source == .unfinished }.count
        )
    }

    func snapshot(supportedProductIDs: Set<String>) -> StoreTransactionSnapshot {
        snapshotRequests += 1
        return snapshotValue
    }

    func updates(supportedProductIDs: Set<String>) -> AsyncStream<StoreTransactionEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func signedRenewalInfo(for observation: StoreTransactionObservation) -> String? {
        "renewal-\(observation.originalID)"
    }

    func register(products: [Product]) {}

    func snapshotCallCount() -> Int {
        snapshotRequests
    }
}

private actor FakeMembershipEntitlementAPI: MembershipEntitlementAPI {
    private var failuresRemaining: Int
    private let syncedState: SyncedTransactionState
    private let entitlement: EntitlementSummary
    private var syncRequests: [(signedTransaction: String, requestID: String)] = []
    private var statusRequests = 0

    init(
        failuresRemaining: Int = 0,
        syncedState: SyncedTransactionState = .active,
        returnsMember: Bool = true
    ) {
        self.failuresRemaining = failuresRemaining
        self.syncedState = syncedState
        entitlement = returnsMember ? Self.memberEntitlement : Self.freeEntitlement
    }

    func loadEntitlementStatus() -> EntitlementSummary {
        statusRequests += 1
        return entitlement
    }

    func syncSubscription(
        signedTransaction: String,
        signedRenewalInfo: String?,
        requestID: String
    ) throws -> StoreSyncReceipt {
        syncRequests.append((signedTransaction, requestID))
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw AccessCredentialError.server(
                code: "STORE_SYNC_UNAVAILABLE",
                message: "temporary",
                requestID: requestID,
                retryable: true
            )
        }
        return StoreSyncReceipt(
            entitlement: entitlement,
            syncedTransactionState: syncedState,
            requestID: requestID
        )
    }

    func syncCallCount() -> Int {
        syncRequests.count
    }

    func statusCallCount() -> Int {
        statusRequests
    }

    private static let memberEntitlement = EntitlementSummary(
        tier: "member",
        productId: MembershipStore.monthlyProductId,
        subscriptionState: "active",
        limit: 100,
        used: 0,
        reserved: 0,
        remaining: 100,
        unlimited: false,
        periodStart: nil,
        resetAt: nil,
        expiresAt: nil,
        autoRenewEnabled: true,
        vocabularyCorrectionEnabled: true
    )

    private static let freeEntitlement = EntitlementSummary(
        tier: "free",
        productId: nil,
        subscriptionState: "none",
        limit: 3,
        used: 0,
        reserved: 0,
        remaining: 3,
        unlimited: false,
        periodStart: nil,
        resetAt: nil,
        expiresAt: nil,
        autoRenewEnabled: nil,
        vocabularyCorrectionEnabled: false
    )
}

private final class FakeKeychain: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]

    init(values: [String: String] = [:]) {
        self.values = values
    }

    func string(for account: String) -> String? {
        lock.withLock { values[account] }
    }

    func set(_ value: String, for account: String) throws {
        lock.withLock { values[account] = value }
    }

    func delete(_ account: String) {
        _ = lock.withLock { values.removeValue(forKey: account) }
    }
}

private final class LockedCapture<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    var values: [Value] { lock.withLock { storage } }

    func append(_ value: Value) {
        lock.withLock { storage.append(value) }
    }
}

private final class MembershipMockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> MockResponse

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]

    static func setHandler(for host: String, handler: @escaping Handler) {
        lock.withLock { handlers[host] = handler }
    }

    static func removeAllHandlers() {
        lock.withLock { handlers.removeAll() }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let host = url.host,
              let handler = Self.lock.withLock({ Self.handlers[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let mock = try handler(request)
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: mock.status,
                httpVersion: "HTTP/1.1",
                headerFields: mock.headers
            ) else {
                throw URLError(.badServerResponse)
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: mock.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private struct MockResponse: Sendable {
    let status: Int
    let headers: [String: String]
    let body: Data

    static func json(status: Int, headers: [String: String] = [:], body: Data) -> MockResponse {
        var headers = headers
        headers["Content-Type"] = "application/json"
        return MockResponse(status: status, headers: headers, body: body)
    }
}
