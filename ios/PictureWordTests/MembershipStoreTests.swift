import Foundation
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

    func testTransactionOrderingIsDeterministic() {
        let purchase = Date(timeIntervalSince1970: 1_000)
        let keys = [
            TransactionOrderingKey(purchaseDate: purchase, expirationDate: nil, transactionID: 4),
            TransactionOrderingKey(purchaseDate: purchase.addingTimeInterval(-1), expirationDate: nil, transactionID: 9),
            TransactionOrderingKey(purchaseDate: purchase, expirationDate: purchase.addingTimeInterval(10), transactionID: 3),
            TransactionOrderingKey(purchaseDate: purchase, expirationDate: purchase.addingTimeInterval(10), transactionID: 2),
        ]

        XCTAssertEqual(keys.sorted().map(\.transactionID), [9, 4, 2, 3])
    }

    func testEntitlementSyncQueueCoalescesRequestsIntoNextBatch() {
        var queue = EntitlementSyncQueueState()

        let first = queue.enqueue()
        XCTAssertEqual(queue.nextBatchRevision, first)

        let second = queue.enqueue()
        let third = queue.enqueue()
        XCTAssertEqual(queue.nextBatchRevision, third)
        XCTAssertFalse(queue.isSatisfied(second))

        queue.complete(first)
        XCTAssertEqual(queue.nextBatchRevision, third)
        XCTAssertFalse(queue.isSatisfied(second))

        queue.complete(third)
        XCTAssertTrue(queue.isSatisfied(second))
        XCTAssertTrue(queue.isSatisfied(third))
        XCTAssertNil(queue.nextBatchRevision)
    }

    func testEntitlementSyncQueueCompletionCannotRegress() {
        var queue = EntitlementSyncQueueState()
        let first = queue.enqueue()
        let second = queue.enqueue()

        queue.complete(second)
        queue.complete(first)

        XCTAssertTrue(queue.isSatisfied(first))
        XCTAssertTrue(queue.isSatisfied(second))
        XCTAssertNil(queue.nextBatchRevision)
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

    private func makeMemberEntitlement(remaining: Int) -> EntitlementSummary {
        EntitlementSummary(
            tier: "member",
            productId: MembershipStore.annualProductId,
            subscriptionState: "active",
            limit: 100,
            used: 100 - remaining,
            reserved: 0,
            remaining: remaining,
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
        lock.withLock { values.removeValue(forKey: account) }
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
