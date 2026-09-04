import CryptoKit
import DeviceCheck
import Foundation
import OSLog
import Security
import StoreKit
import UIKit

enum MembershipNotification {
    static let entitlementDidChange = Notification.Name("MembershipStore.entitlementDidChange")
}

struct EntitlementSummary: Codable, Equatable, Sendable {
    let tier: String
    let productId: String?
    let subscriptionState: String
    let limit: Int
    let used: Int
    let reserved: Int
    let remaining: Int
    let unlimited: Bool?
    let periodStart: String?
    let resetAt: String?
    let expiresAt: String?
    let autoRenewEnabled: Bool?
    let vocabularyCorrectionEnabled: Bool

    var isMember: Bool {
        tier == "member" && (subscriptionState == "active" || subscriptionState == "grace")
    }

    var hasUnlimitedQuota: Bool { unlimited == true }

    var resetDate: Date? { resetAt.flatMap(Self.dateFormatter.date(from:)) }
    var expirationDate: Date? { expiresAt.flatMap(Self.dateFormatter.date(from:)) }

    private static let dateFormatter = ISO8601DateFormatter()
}

enum EntitlementLoadState: Equatable, Sendable {
    case idle
    case loading(hasCachedValue: Bool)
    case loaded
    case failed(message: String, hasCachedValue: Bool, requestID: String?)

    var hasFreshValue: Bool {
        if case .loaded = self { return true }
        return false
    }

    var hasCachedValue: Bool {
        switch self {
        case .loading(let hasCachedValue), .failed(_, let hasCachedValue, _):
            return hasCachedValue
        case .loaded:
            return true
        case .idle:
            return false
        }
    }
}

enum MembershipSettingsDisplayState: Equatable, Sendable {
    case idle
    case initialLoading
    case refreshing
    case loaded
    case failedWithCachedValue
    case failedWithoutCachedValue

    static func resolve(
        loadState: EntitlementLoadState,
        isRefreshing: Bool
    ) -> Self {
        if isRefreshing {
            return loadState.hasCachedValue ? .refreshing : .initialLoading
        }
        switch loadState {
        case .idle:
            return .idle
        case .loading(let hasCachedValue):
            return hasCachedValue ? .refreshing : .initialLoading
        case .loaded:
            return .loaded
        case .failed(_, let hasCachedValue, _):
            return hasCachedValue ? .failedWithCachedValue : .failedWithoutCachedValue
        }
    }

    var statusText: String {
        switch self {
        case .idle:
            return "等待读取会员状态…"
        case .initialLoading:
            return "正在读取会员状态…"
        case .refreshing:
            return "正在刷新会员状态…"
        case .loaded:
            return "会员状态已更新"
        case .failedWithCachedValue:
            return "显示上次数据，刷新失败"
        case .failedWithoutCachedValue:
            return "暂时无法读取"
        }
    }

    var isFailure: Bool {
        switch self {
        case .failedWithCachedValue, .failedWithoutCachedValue:
            return true
        default:
            return false
        }
    }

    var isLoading: Bool {
        switch self {
        case .initialLoading, .refreshing:
            return true
        default:
            return false
        }
    }

    var statusSymbol: String {
        switch self {
        case .idle:
            return "clock"
        case .loaded:
            return "checkmark.circle.fill"
        case .failedWithCachedValue, .failedWithoutCachedValue:
            return "exclamationmark.triangle.fill"
        case .initialLoading, .refreshing:
            return "arrow.triangle.2.circlepath"
        }
    }

    var isFresh: Bool { self == .loaded }

    static func quotaText(
        entitlement: EntitlementSummary?,
        state: Self
    ) -> String {
        guard let entitlement else {
            return state == .failedWithoutCachedValue
                ? "暂时无法读取"
                : "正在读取识别额度…"
        }
        let quota = entitlement.hasUnlimitedQuota
            ? "本期识别额度：无限"
            : "本期剩余 \(entitlement.remaining)/\(entitlement.limit) 次识别"
        return quota
    }
}

enum MembershipPaywallState: Equatable, Sendable {
    case syncing
    case active(remaining: Int, limit: Int)
    case unlimited
    case exhausted
    case unavailable
}

enum MembershipPurchasePhase: Equatable, Sendable {
    case preflight
    case waitingForApple
    case syncingEntitlement
}

enum MembershipActionOutcome: Equatable, Sendable {
    case active
    case pending
    case notFound
    case cancelled
    case awaitingSync
    case failed
}

enum SyncedTransactionState: String, Decodable, Sendable {
    case active
    case grace
    case expired
    case revoked
}

struct StoreSyncReceipt: Sendable {
    let entitlement: EntitlementSummary
    let syncedTransactionState: SyncedTransactionState
    let requestID: String
}

enum MembershipNoticeSource: String, Sendable {
    case startup
    case foreground
    case settings
    case purchase
    case restore
    case transactionUpdate
    case products
    case manual
}

enum MembershipNoticeCategory: String, Sendable {
    case information
    case entitlementFailure
    case awaitingTransactionSync
}

struct MembershipNotice: Equatable, Sendable {
    let text: String
    let source: MembershipNoticeSource
    let category: MembershipNoticeCategory
    let requestID: String?
    let syncAttemptID: UUID?

    var clearsAfterSuccessfulEntitlementSync: Bool {
        category == .entitlementFailure || category == .awaitingTransactionSync
    }

    static func afterSuccessfulEntitlementSync(_ notice: MembershipNotice?) -> MembershipNotice? {
        notice?.clearsAfterSuccessfulEntitlementSync == true ? nil : notice
    }
}

private enum TransactionDeliveryOutcome {
    case activated(requestID: String?)
    case processedInactive(state: SyncedTransactionState, requestID: String?)
    case awaitingSync(TransactionSyncDeferredError)
}

private struct StoreTransactionCandidate {
    let transaction: Transaction
    let signedTransaction: String

    var orderingKey: TransactionOrderingKey {
        TransactionOrderingKey(
            purchaseDate: transaction.purchaseDate,
            expirationDate: transaction.expirationDate,
            transactionID: transaction.id
        )
    }
}

struct TransactionOrderingKey: Comparable, Sendable {
    let purchaseDate: Date
    let expirationDate: Date?
    let transactionID: UInt64

    static func < (left: TransactionOrderingKey, right: TransactionOrderingKey) -> Bool {
        if left.purchaseDate != right.purchaseDate {
            return left.purchaseDate < right.purchaseDate
        }
        let leftExpiration = left.expirationDate ?? .distantPast
        let rightExpiration = right.expirationDate ?? .distantPast
        if leftExpiration != rightExpiration { return leftExpiration < rightExpiration }
        return left.transactionID < right.transactionID
    }
}

/// A small, deterministic state machine for coalescing entitlement-sync
/// requests. Requests that arrive while a batch is running advance the target
/// revision and are picked up by the next loop iteration instead of being lost.
struct EntitlementSyncQueueState: Equatable, Sendable {
    private(set) var requestedRevision: UInt64 = 0
    private(set) var completedRevision: UInt64 = 0

    mutating func enqueue() -> UInt64 {
        requestedRevision &+= 1
        return requestedRevision
    }

    var nextBatchRevision: UInt64? {
        completedRevision < requestedRevision ? requestedRevision : nil
    }

    mutating func complete(_ revision: UInt64) {
        completedRevision = max(completedRevision, min(revision, requestedRevision))
    }

    func isSatisfied(_ revision: UInt64) -> Bool {
        completedRevision >= revision
    }
}

struct AccessCredentials: Sendable {
    let accessToken: String
    let deviceCheckToken: String
}

enum AccessCredentialError: LocalizedError, Sendable {
    case deviceUnsupported
    case invalidResponse
    case transport(String)
    case server(code: String, message: String, requestID: String?, retryable: Bool)

    var errorDescription: String? {
        switch self {
        case .deviceUnsupported: return "当前设备暂时无法完成安全验证"
        case .invalidResponse: return "服务器返回了无法识别的会员信息"
        case .transport(let message): return message
        case .server(_, let message, let requestID, _):
            guard let requestID, !requestID.isEmpty else { return message }
            return "\(message)（参考编号：\(requestID)）"
        }
    }

    var isUnauthorized: Bool {
        if case .server(let code, _, _, _) = self { return code == "UNAUTHORIZED" }
        return false
    }

    var isRetryable: Bool {
        switch self {
        case .transport: return true
        case .server(_, _, _, let retryable): return retryable
        case .deviceUnsupported, .invalidResponse: return false
        }
    }

    var requestID: String? {
        if case .server(_, _, let requestID, _) = self { return requestID }
        return nil
    }

    var categoryCode: String {
        switch self {
        case .deviceUnsupported: return "device_unsupported"
        case .invalidResponse: return "invalid_response"
        case .transport: return "transport"
        case .server(let code, _, _, _): return code.lowercased()
        }
    }
}

private struct TransactionSyncDeferredError: LocalizedError, Sendable {
    let underlying: AccessCredentialError
    let syncAttemptID: UUID
    let requestID: String

    var errorDescription: String? { underlying.errorDescription }
}

actor AccessCredentialStore {
    static let shared = AccessCredentialStore()

    private let baseURL: URL
    private let keychain: any KeychainStoring
    private let session: URLSession
    private let deviceTokenProvider: @Sendable () async throws -> String
    private var accessToken: String?
    private var bootstrapTask: Task<BootstrapResponse, Error>?

    init(
        baseURL: URL = AppEnvironment.current.apiBaseURL,
        keychain: any KeychainStoring = AppKeychain(service: "com.kakaword.app.access"),
        session: URLSession = .shared,
        deviceTokenProvider: @escaping @Sendable () async throws -> String = {
            try await AccessCredentialStore.generateDeviceToken()
        }
    ) {
        self.baseURL = baseURL
        self.keychain = keychain
        self.session = session
        self.deviceTokenProvider = deviceTokenProvider
        accessToken = keychain.string(for: "access-token")
    }

    func bootstrapIfNeeded(force: Bool = false) async throws -> EntitlementSummary {
        if !force, accessToken != nil {
            do {
                return try await status()
            } catch let error as AccessCredentialError {
                if error.isUnauthorized {
                    clearAccessToken()
                } else {
                    throw error
                }
            }
        }

        if let bootstrapTask {
            let response = try await bootstrapTask.value
            return try acceptBootstrapResponse(response)
        }

        let task: Task<BootstrapResponse, Error> = Task { [baseURL] in
            let deviceToken = try await self.deviceTokenProvider()
            let installationId = try self.installationIdentifier()
            var request = URLRequest(url: baseURL.appendingPathComponent("v1/access/bootstrap"))
            request.httpMethod = "POST"
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(BootstrapRequest(
                installationId: installationId,
                deviceToken: deviceToken
            ))
            let response: BootstrapResponse = try await self.send(
                request,
                retryingTransientFailures: 1,
                deadlineSeconds: 30
            )
            return response
        }
        bootstrapTask = task
        do {
            let response = try await task.value
            bootstrapTask = nil
            return try acceptBootstrapResponse(response)
        } catch {
            bootstrapTask = nil
            throw error
        }
    }

    private func acceptBootstrapResponse(_ response: BootstrapResponse) throws -> EntitlementSummary {
        accessToken = response.accessToken
        try keychain.set(response.accessToken, for: "access-token")
        return response.entitlement
    }

    func status() async throws -> EntitlementSummary {
        let token = try await authorizationToken()
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/access/status"))
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let response: EntitlementResponse = try await send(
            request,
            retryingTransientFailures: 2,
            deadlineSeconds: 30
        )
        return response.entitlement
    }

    func syncSubscription(
        signedTransaction: String,
        signedRenewalInfo: String?,
        requestID: String = UUID().uuidString.lowercased()
    ) async throws -> StoreSyncReceipt {
        let token = try await authorizationToken()
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/store/sync"))
        request.httpMethod = "POST"
        // Apple online verification can take longer on a cold server. The endpoint is
        // idempotent, so retrying the same signed transaction is safe.
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(requestID, forHTTPHeaderField: "X-Request-ID")
        request.httpBody = try JSONEncoder().encode(StoreSyncRequest(
            signedTransaction: signedTransaction,
            signedRenewalInfo: signedRenewalInfo
        ))
        let response: StoreSyncResponse = try await send(
            request,
            retryingTransientFailures: 2,
            deadlineSeconds: 60
        )
        return StoreSyncReceipt(
            entitlement: response.entitlement,
            syncedTransactionState: response.syncedTransactionState,
            requestID: requestID
        )
    }

    func recordMetric(eventName: String, productId: String? = nil, outcome: String? = nil) async {
        guard let token = try? await authorizationToken() else { return }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/metrics"))
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(MetricRequest(
            eventName: eventName,
            productId: productId,
            outcome: outcome
        ))
        _ = try? await session.data(for: request)
    }

    func credentialsForAnalyze() async throws -> AccessCredentials {
        AccessCredentials(
            accessToken: try await authorizationToken(),
            deviceCheckToken: try await deviceTokenProvider()
        )
    }

    func authorizationToken() async throws -> String {
        if let accessToken { return accessToken }
        _ = try await bootstrapIfNeeded(force: true)
        guard let accessToken else { throw AccessCredentialError.invalidResponse }
        return accessToken
    }

    func clearAccessToken() {
        accessToken = nil
        keychain.delete("access-token")
    }

    private func installationIdentifier() throws -> UUID {
        if let value = keychain.string(for: "installation-id"), let identifier = UUID(uuidString: value) {
            return identifier
        }
        let identifier = UUID()
        try keychain.set(identifier.uuidString.lowercased(), for: "installation-id")
        return identifier
    }

    static func generateDeviceToken() async throws -> String {
#if targetEnvironment(simulator)
        return Data("picture-word-simulator-device-token".utf8).base64EncodedString()
#else
        guard DCDevice.current.isSupported else { throw AccessCredentialError.deviceUnsupported }
        return try await withCheckedThrowingContinuation { continuation in
            DCDevice.current.generateToken { data, error in
                if let data {
                    continuation.resume(returning: data.base64EncodedString())
                } else {
                    continuation.resume(throwing: error ?? AccessCredentialError.deviceUnsupported)
                }
            }
        }
#endif
    }

    private func send<Response: Decodable>(
        _ request: URLRequest,
        retryingTransientFailures retryCount: Int = 0,
        deadlineSeconds: TimeInterval = 30
    ) async throws -> Response {
        var remainingRetries = max(0, retryCount)
        var retryDelayNanoseconds: UInt64 = 500_000_000
        let deadline = Date().addingTimeInterval(max(1, deadlineSeconds))
        while true {
            guard deadline.timeIntervalSinceNow > 0 else {
                throw AccessCredentialError.transport("会员服务响应超时，请稍后重试")
            }
            do {
                var attemptRequest = request
                attemptRequest.timeoutInterval = min(
                    max(1, deadline.timeIntervalSinceNow),
                    request.timeoutInterval
                )
                let (data, response) = try await session.data(for: attemptRequest)
                guard let http = response as? HTTPURLResponse else {
                    throw AccessCredentialError.invalidResponse
                }
                if Self.isRetryableStatus(http.statusCode),
                   remainingRetries > 0,
                   deadline.timeIntervalSinceNow > 0 {
                    remainingRetries -= 1
                    let retryAfter = Self.retryDelay(from: http)
                    try await Self.waitBeforeRetry(
                        suggestedDelay: retryAfter,
                        fallbackNanoseconds: retryDelayNanoseconds,
                        deadline: deadline
                    )
                    retryDelayNanoseconds *= 2
                    continue
                }
                guard (200..<300).contains(http.statusCode) else {
                    let payload = try? JSONDecoder().decode(AccessServerError.self, from: data)
                    let code = http.statusCode == 401 ? "UNAUTHORIZED" : (payload?.error ?? "ACCESS_UNAVAILABLE")
                    throw AccessCredentialError.server(
                        code: code,
                        message: payload?.message ?? "会员服务暂时不可用",
                        requestID: http.value(forHTTPHeaderField: "X-Request-ID"),
                        retryable: Self.isRetryableStatus(http.statusCode)
                    )
                }
                guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
                    throw AccessCredentialError.invalidResponse
                }
                return decoded
            } catch let error as URLError where remainingRetries > 0
                && deadline.timeIntervalSinceNow > 0
                && Self.isTransient(error) {
                remainingRetries -= 1
                try await Self.waitBeforeRetry(
                    suggestedDelay: nil,
                    fallbackNanoseconds: retryDelayNanoseconds,
                    deadline: deadline
                )
                retryDelayNanoseconds *= 2
            } catch let error as URLError where Self.isTransient(error) {
                throw AccessCredentialError.transport(Self.transportMessage(for: error))
            }
        }
    }

    private static func waitBeforeRetry(
        suggestedDelay: TimeInterval?,
        fallbackNanoseconds: UInt64,
        deadline: Date
    ) async throws {
        let suggestedNanoseconds = suggestedDelay.map { UInt64(max(0, $0) * 1_000_000_000) }
        let requested = suggestedNanoseconds ?? fallbackNanoseconds
        let remaining = UInt64(max(0, deadline.timeIntervalSinceNow) * 1_000_000_000)
        guard remaining > 0 else { return }
        try await Task.sleep(nanoseconds: min(requested, remaining))
    }

    private static func retryDelay(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(value) else { return nil }
        return min(max(0, seconds), 10)
    }

    private static func isRetryableStatus(_ statusCode: Int) -> Bool {
        statusCode == 502 || statusCode == 503 || statusCode == 504
    }

    private static func transportMessage(for error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet:
            return "当前没有网络连接，请检查网络后重试"
        case .timedOut:
            return "会员服务响应超时，请稍后重试"
        default:
            return "暂时无法连接会员服务，请检查网络后重试"
        }
    }

    private static func isTransient(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet,
             .resourceUnavailable:
            return true
        default:
            return false
        }
    }

    nonisolated static func isTransientForMembership(_ error: URLError) -> Bool {
        isTransient(error)
    }
}

@MainActor
final class MembershipStore: ObservableObject {
    static let monthlyProductId = "com.kakaword.app.membership.month"
    static let annualProductId = "com.kakaword.app.membership.annual"
    private static let foregroundRefreshCooldown: TimeInterval = 3
    private static let logger = Logger(subsystem: "com.kakaword.app", category: "membership")

    @Published private(set) var entitlement: EntitlementSummary?
    @Published private(set) var entitlementLoadState: EntitlementLoadState = .idle
    @Published private(set) var lastSuccessfulRefreshAt: Date?
    @Published private(set) var products: [Product] = []
    @Published private(set) var productLoadFailed = false
    @Published private(set) var isLoading = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var purchasePhase: MembershipPurchasePhase?
    @Published private(set) var isRestoring = false
    @Published private(set) var isRefreshingEntitlements = false
    @Published private(set) var notice: MembershipNotice?
    @Published private(set) var message: String?

    private var transactionTask: Task<Void, Never>?
    private var entitlementTask: Task<Void, Never>?
    private var prepareTask: Task<Void, Never>?
    private var productPrepareTask: Task<Void, Never>?
    private var entitlementSyncLoopTask: Task<Void, Error>?
    private var entitlementSyncLoopID: UUID?
    private var entitlementSyncQueue = EntitlementSyncQueueState()
    private var pendingTransactionCandidates: [UInt64: StoreTransactionCandidate] = [:]
    private var lastEntitlementSyncFinishedAt: Date?
    private var didPrepare = false

    init() {
        let cached = Self.loadCachedEntitlement()
        entitlement = cached?.entitlement
        lastSuccessfulRefreshAt = cached?.savedAt
        transactionTask = listenForTransactions()
        entitlementTask = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(named: MembershipNotification.entitlementDidChange) {
                guard let entitlement = notification.object as? EntitlementSummary else { continue }
                self?.setEntitlement(entitlement)
            }
        }
    }

    deinit {
        transactionTask?.cancel()
        entitlementTask?.cancel()
        prepareTask?.cancel()
        productPrepareTask?.cancel()
        entitlementSyncLoopTask?.cancel()
    }

    var canStartRecognition: Bool { entitlement?.hasUnlimitedQuota == true || (entitlement?.remaining ?? 0) > 0 }
    var isMember: Bool { entitlement?.isMember == true }
    var hasFreshEntitlement: Bool { entitlementLoadState.hasFreshValue }
    var hasUnavailableEntitlement: Bool {
        if case .failed(_, let hasCachedValue, _) = entitlementLoadState {
            return !hasCachedValue
        }
        return false
    }
    var membershipPaywallState: MembershipPaywallState {
        Self.membershipPaywallState(
            entitlement: entitlement,
            loadState: entitlementLoadState,
            isRefreshing: isRefreshingEntitlements
        )
    }
    var entitlementFailureMessage: String? {
        if case .failed(let message, _, _) = entitlementLoadState { return message }
        return nil
    }
    var canPurchase: Bool {
        entitlement != nil && hasFreshEntitlement && !isMember
            && !isLoading && !isRefreshingEntitlements && !isPurchasing
    }

    var annualProduct: Product? { products.first { $0.id == Self.annualProductId } }
    var monthlyProduct: Product? { products.first { $0.id == Self.monthlyProductId } }

    static func membershipPaywallState(
        entitlement: EntitlementSummary?,
        loadState: EntitlementLoadState,
        isRefreshing: Bool
    ) -> MembershipPaywallState {
        guard let entitlement, entitlement.isMember else { return .unavailable }
        if case .failed = loadState { return .unavailable }
        guard !isRefreshing, loadState.hasFreshValue else { return .syncing }
        if entitlement.hasUnlimitedQuota { return .unlimited }
        return entitlement.remaining <= 0
            ? .exhausted
            : .active(remaining: max(0, entitlement.remaining), limit: entitlement.limit)
    }

    func dismissMessage() {
        notice = nil
        message = nil
    }

    func prepare() async {
        if let prepareTask {
            await prepareTask.value
            return
        }
        if let productPrepareTask {
            await productPrepareTask.value
        }
        guard !didPrepare || products.isEmpty else { return }
        let task: Task<Void, Never> = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performPrepare()
        }
        prepareTask = task
        await task.value
        prepareTask = nil
    }

    /// Loads StoreKit products for the paywall without refreshing entitlement state.
    /// The app-startup `prepare()` remains responsible for the initial entitlement sync.
    func prepareProducts() async {
        guard products.isEmpty else { return }
        if let prepareTask {
            await prepareTask.value
            return
        }
        if let productPrepareTask {
            await productPrepareTask.value
            return
        }
        let task: Task<Void, Never> = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performProductPrepare()
        }
        productPrepareTask = task
        await task.value
        productPrepareTask = nil
    }

    private func performProductPrepare() async {
        isLoading = true
        defer { isLoading = false }
        productLoadFailed = false
        do {
            products = sortProducts(try await Product.products(for: [
                Self.monthlyProductId,
                Self.annualProductId
            ]))
            productLoadFailed = products.isEmpty
            if productLoadFailed {
                setMessage(
                    "暂时没有找到可用的订阅商品，请确认 App Store 商品配置后重试",
                    source: .products
                )
            }
        } catch {
            productLoadFailed = true
            setMessage(error.localizedDescription, source: .products, category: .entitlementFailure)
        }
    }

    private func performPrepare() async {
        didPrepare = true
        isLoading = true
        defer { isLoading = false }
        productLoadFailed = false
        async let productRequest = Product.products(for: [Self.monthlyProductId, Self.annualProductId])
        beginEntitlementLoading()
        var bootstrapConfirmedMember = false
        do {
            let bootstrapEntitlement = try await AccessCredentialStore.shared.bootstrapIfNeeded()
            // An existing installation may already be bound on the server even when
            // this process has no UserDefaults cache. Preserve that known-good member
            // value if StoreKit refresh is temporarily unavailable.
            if bootstrapEntitlement.isMember {
                bootstrapConfirmedMember = true
                setEntitlement(bootstrapEntitlement)
            }
            try await requestEntitlementSync(source: .startup)
        } catch {
            if bootstrapConfirmedMember, Self.isRetryable(error) {
                // The server has already confirmed this token is bound to an
                // active subscription. A transient StoreKit audit failure must
                // not replace that fresh result with a contradictory error.
                entitlementLoadState = .loaded
            } else {
                // Startup failures are represented by entitlementLoadState and the
                // inline retry UI. Avoid presenting a modal alert for a transient
                // local-network permission race.
                setEntitlementFailure(error, source: .startup, publishMessage: false)
            }
        }
        do {
            products = sortProducts(try await productRequest)
            productLoadFailed = products.isEmpty
            if productLoadFailed {
                setMessage(
                    "暂时没有找到可用的订阅商品，请确认 App Store 商品配置后重试",
                    source: .products
                )
            }
        } catch {
            productLoadFailed = true
            setMessage(error.localizedDescription, source: .products, category: .entitlementFailure)
        }
    }

    func retryProducts() async {
        didPrepare = false
        await prepare()
    }

    func refreshStatus() async {
        await refreshCurrentEntitlements(source: .manual)
    }

    func refreshCurrentEntitlements(source: MembershipNoticeSource = .foreground) async {
        await refreshCurrentEntitlements(source: source, candidate: nil)
    }

    private func refreshCurrentEntitlements(
        source: MembershipNoticeSource,
        candidate: StoreTransactionCandidate?
    ) async {
        beginEntitlementLoading()
        do {
            try await requestEntitlementSync(source: source, candidate: candidate)
        } catch {
            setEntitlementFailure(
                error,
                prefix: "会员状态同步失败",
                source: source,
                publishMessage: false
            )
        }
    }

    func refreshAfterForegroundActivation() async {
        // A cold-launch active callback may precede prepare(); startup owns that
        // first request. Once prepare has begun, foreground requests join the
        // same serialized queue even if startup is still running.
        guard didPrepare else { return }
        if !isRefreshingEntitlements,
           let lastEntitlementSyncFinishedAt,
           Date().timeIntervalSince(lastEntitlementSyncFinishedAt) < Self.foregroundRefreshCooldown {
            return
        }
        await refreshCurrentEntitlements(source: .foreground)
    }

    func refreshForSettingsPresentation() async {
        // Settings can be opened while the root startup task is still waiting for
        // the local-network permission decision. Share that work before deciding
        // whether a fresh settings request is needed.
        if let prepareTask {
            await prepareTask.value
        } else if !didPrepare {
            await prepare()
        }
        guard !Task.isCancelled else { return }
        guard !isRefreshingEntitlements else { return }

        if case .failed = entitlementLoadState {
            await retryFailedEntitlementAfterCooldown()
            return
        }

        guard Self.shouldRefreshForSettingsPresentation(
            loadState: entitlementLoadState,
            isRefreshing: isRefreshingEntitlements,
            lastFinishedAt: lastEntitlementSyncFinishedAt,
            now: Date()
        ) else { return }
        await refreshCurrentEntitlements(source: .settings)
    }

    static func shouldRefreshForSettingsPresentation(
        loadState: EntitlementLoadState,
        isRefreshing: Bool,
        lastFinishedAt: Date?,
        now: Date,
        cooldown: TimeInterval = 3
    ) -> Bool {
        guard !isRefreshing else { return false }
        if case .loading = loadState { return false }
        guard let lastFinishedAt else { return true }
        return now.timeIntervalSince(lastFinishedAt) >= cooldown
    }

    private func retryFailedEntitlementAfterCooldown() async {
        guard case .failed = entitlementLoadState else { return }
        if let lastEntitlementSyncFinishedAt {
            let remaining = Self.foregroundRefreshCooldown
                - Date().timeIntervalSince(lastEntitlementSyncFinishedAt)
            if remaining > 0 {
                do {
                    try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                } catch {
                    return
                }
            }
        }
        guard !Task.isCancelled, case .failed = entitlementLoadState else { return }
        await refreshCurrentEntitlements(source: .settings)
    }

    func purchase(_ product: Product) async -> MembershipActionOutcome {
        guard !isPurchasing else { return .failed }
        isPurchasing = true
        purchasePhase = .preflight
        defer {
            isPurchasing = false
            purchasePhase = nil
        }
        let purchaseStartedAt = Date()
        Self.logger.info("purchase started product_id=\(product.id, privacy: .public)")
        defer {
            let duration = Int(max(0, Date().timeIntervalSince(purchaseStartedAt)) * 1_000)
            Self.logger.info("purchase finished product_id=\(product.id, privacy: .public) duration_ms=\(duration, privacy: .public)")
        }
        var applePurchaseCompleted = false
        do {
            // Re-read StoreKit and server state immediately before presenting Apple's
            // purchase sheet. This prevents a stale free cache on a new device from
            // initiating a plan change for an already-active subscriber.
            beginEntitlementLoading()
            let preflightStartedAt = Date()
            try await requestEntitlementSync(source: .purchase)
            let preflightDuration = Int(max(0, Date().timeIntervalSince(preflightStartedAt)) * 1_000)
            Self.logger.info("purchase phase=preflight_sync_completed product_id=\(product.id, privacy: .public) duration_ms=\(preflightDuration, privacy: .public)")
            guard !isMember else {
                setMessage("已找到有效会员，无需重复购买", source: .purchase)
                return .active
            }
            purchasePhase = .waitingForApple
            let applePurchaseStartedAt = Date()
            let purchaseResult = try await product.purchase()
            let applePurchaseDuration = Int(max(0, Date().timeIntervalSince(applePurchaseStartedAt)) * 1_000)
            Self.logger.info("purchase phase=apple_result_received product_id=\(product.id, privacy: .public) duration_ms=\(applePurchaseDuration, privacy: .public)")
            switch purchaseResult {
            case .success(let result):
                guard case .verified(let transaction) = result else {
                    setMessage("App Store 无法验证这笔购买，请稍后重试", source: .purchase)
                    recordMetric("purchase_result", productId: product.id, outcome: "unverified")
                    return .failed
                }
                applePurchaseCompleted = true
                purchasePhase = .syncingEntitlement
                let entitlementSyncStartedAt = Date()
                try await requestEntitlementSync(
                    source: .purchase,
                    candidate: StoreTransactionCandidate(
                        transaction: transaction,
                        signedTransaction: result.jwsRepresentation
                    )
                )
                let entitlementSyncDuration = Int(max(0, Date().timeIntervalSince(entitlementSyncStartedAt)) * 1_000)
                Self.logger.info("purchase phase=post_apple_sync_completed product_id=\(product.id, privacy: .public) duration_ms=\(entitlementSyncDuration, privacy: .public)")
                if isMember {
                    recordMetric("purchase_result", productId: product.id, outcome: "success")
                    return .active
                } else {
                    setMessage("已清理过期测试交易，请再次点击购买", source: .purchase)
                    recordMetric("purchase_result", productId: product.id, outcome: "stale_transaction_cleared")
                    return .notFound
                }
            case .pending:
                setMessage("购买正在等待批准，批准后会员会自动生效", source: .purchase)
                recordMetric("purchase_result", productId: product.id, outcome: "pending")
                return .pending
            case .userCancelled:
                dismissMessage()
                recordMetric("purchase_result", productId: product.id, outcome: "cancelled")
                return .cancelled
            @unknown default:
                setMessage("购买状态暂时无法确认", source: .purchase)
                return .failed
            }
        } catch {
            setEntitlementFailure(error, source: .purchase)
            if applePurchaseCompleted, Self.isRetryable(error) {
                let details = Self.syncFailureDetails(error)
                setMessage(
                    "购买已完成，但会员权益暂时无法同步。请保持网络连接，应用会自动重试。",
                    source: .purchase,
                    category: .awaitingTransactionSync,
                    requestID: details.requestID,
                    syncAttemptID: details.syncAttemptID
                )
                recordMetric("purchase_result", productId: product.id, outcome: "awaiting_sync")
                return .awaitingSync
            }
            setMessage(error.localizedDescription, source: .purchase, category: .entitlementFailure)
            recordMetric("purchase_result", productId: product.id, outcome: "failed")
            return .failed
        }
    }

    func restorePurchases() async -> MembershipActionOutcome {
        guard !isPurchasing else { return .failed }
        isPurchasing = true
        isRestoring = true
        defer {
            isRestoring = false
            isPurchasing = false
        }
        do {
            beginEntitlementLoading()
            try await AppStore.sync()
            try await requestEntitlementSync(source: .restore)
            setMessage(isMember ? "购买记录已恢复" : "没有找到可恢复的有效会员", source: .restore)
            recordMetric("restore_result", outcome: isMember ? "success" : "not_found")
            return isMember ? .active : .notFound
        } catch {
            setMessage(restoreErrorMessage(error), source: .restore, category: .entitlementFailure)
            if Self.isCancellation(error) {
                entitlementLoadState = entitlement == nil ? .idle : .loaded
                recordMetric("restore_result", outcome: "cancelled")
                return .cancelled
            }
            setEntitlementFailure(error, source: .restore)
            if Self.isRetryable(error) {
                recordMetric("restore_result", outcome: "awaiting_sync")
                return .awaitingSync
            }
            recordMetric("restore_result", outcome: "failed")
            return .failed
        }
    }

    func showManageSubscriptions() async {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            setMessage("暂时无法打开订阅管理", source: .manual)
            return
        }
        do {
            try await AppStore.showManageSubscriptions(in: scene)
            await refreshCurrentEntitlements(source: .manual)
        } catch {
            setMessage(error.localizedDescription, source: .manual, category: .entitlementFailure)
        }
    }

    private func requestEntitlementSync(
        source: MembershipNoticeSource,
        candidate: StoreTransactionCandidate? = nil
    ) async throws {
        let syncStartedAt = Date()
        if let candidate {
            pendingTransactionCandidates[candidate.transaction.id] = candidate
        }
        let requestedRevision = entitlementSyncQueue.enqueue()
        Self.logger.debug(
            "entitlement sync requested source=\(source.rawValue, privacy: .public) revision=\(requestedRevision, privacy: .public)"
        )

        while !entitlementSyncQueue.isSatisfied(requestedRevision) {
            let (loopID, task) = ensureEntitlementSyncLoop()
            do {
                try await task.value
                finishEntitlementSyncLoop(loopID)
            } catch {
                finishEntitlementSyncLoop(loopID)
                // A caller only depends on the batch containing its own
                // revision. A later coalesced batch may fail without changing
                // an earlier request that already completed successfully.
                if entitlementSyncQueue.isSatisfied(requestedRevision) { return }
                let duration = Int(max(0, Date().timeIntervalSince(syncStartedAt)) * 1_000)
                Self.logger.error("entitlement sync failed source=\(source.rawValue, privacy: .public) revision=\(requestedRevision, privacy: .public) duration_ms=\(duration, privacy: .public)")
                throw error
            }
        }
        let duration = Int(max(0, Date().timeIntervalSince(syncStartedAt)) * 1_000)
        Self.logger.info("entitlement sync completed source=\(source.rawValue, privacy: .public) revision=\(requestedRevision, privacy: .public) duration_ms=\(duration, privacy: .public)")
    }

    private func ensureEntitlementSyncLoop() -> (UUID, Task<Void, Error>) {
        if let entitlementSyncLoopID, let entitlementSyncLoopTask {
            return (entitlementSyncLoopID, entitlementSyncLoopTask)
        }

        let loopID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            try await self.runEntitlementSyncLoop()
        }
        entitlementSyncLoopID = loopID
        entitlementSyncLoopTask = task
        isRefreshingEntitlements = true
        return (loopID, task)
    }

    private func finishEntitlementSyncLoop(_ loopID: UUID) {
        guard entitlementSyncLoopID == loopID else { return }
        entitlementSyncLoopTask = nil
        entitlementSyncLoopID = nil
        isRefreshingEntitlements = false
        lastEntitlementSyncFinishedAt = Date()
    }

    private func runEntitlementSyncLoop() async throws {
        // Finish only the batch that was ready when this task started. Requests
        // arriving during the batch get a new task, so purchase callers don't
        // wait for unrelated foreground or transaction-update refreshes.
        guard let batchRevision = entitlementSyncQueue.nextBatchRevision else { return }
        try Task.checkCancellation()
        try await performCurrentEntitlementSync()
        entitlementSyncQueue.complete(batchRevision)
        Self.logger.debug(
            "entitlement sync batch completed revision=\(batchRevision, privacy: .public)"
        )
    }

    private func performCurrentEntitlementSync() async throws {
        // Explicit StoreKit updates and purchase results seed the batch so a
        // revoked or otherwise no-longer-current transaction is still audited.
        // The StoreKit sequences then fill in every other unfinished/current
        // transaction, with transaction ID providing idempotent de-duplication.
        var transactionsByID = pendingTransactionCandidates
        for await result in Transaction.unfinished {
            try appendCandidate(result, to: &transactionsByID)
        }
        for await result in Transaction.currentEntitlements {
            try appendCandidate(result, to: &transactionsByID)
        }
        let transactions = transactionsByID.values.sorted { $0.orderingKey < $1.orderingKey }
        if transactions.isEmpty {
            setEntitlement(try await loadStatus())
            return
        }
        for item in transactions {
            switch try await deliver(item.transaction, signedTransaction: item.signedTransaction) {
            case .activated, .processedInactive:
                if pendingTransactionCandidates[item.transaction.id]?.signedTransaction
                    == item.signedTransaction {
                    pendingTransactionCandidates[item.transaction.id] = nil
                }
                continue
            case .awaitingSync(let deferred):
                throw deferred
            }
        }
        // Every submitted transaction response describes its subscription chain.
        // Reload once after the deterministic batch so the published value reflects
        // the token's final binding rather than an intermediate transaction.
        setEntitlement(try await loadStatus())
    }

    private func appendCandidate(
        _ result: VerificationResult<Transaction>,
        to transactionsByID: inout [UInt64: StoreTransactionCandidate]
    ) throws {
        switch result {
        case .verified(let transaction):
            guard Self.isSupported(transaction) else { return }
            if transactionsByID[transaction.id] == nil {
                transactionsByID[transaction.id] = StoreTransactionCandidate(
                    transaction: transaction,
                    signedTransaction: result.jwsRepresentation
                )
            }
        case .unverified(let transaction, _):
            guard Self.isSupported(transaction) else { return }
            throw AccessCredentialError.server(
                code: "UNVERIFIED_APP_STORE_TRANSACTION",
                message: "发现一笔无法验证的购买，请稍后重试或联系 Apple 支持",
                requestID: nil,
                retryable: false
            )
        }
    }

    private static func isSupported(_ transaction: Transaction) -> Bool {
        transaction.productID == monthlyProductId || transaction.productID == annualProductId
    }

    private func loadStatus() async throws -> EntitlementSummary {
        do {
            return try await AccessCredentialStore.shared.status()
        } catch let error as AccessCredentialError {
            if error.isUnauthorized {
                return try await AccessCredentialStore.shared.bootstrapIfNeeded(force: true)
            }
            throw error
        }
    }

    private func restoreErrorMessage(_ error: Error) -> String {
        if Self.isCancellation(error) {
            return "已取消恢复购买，没有产生任何更改"
        }
        return error.localizedDescription
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if let storeKitError = error as? StoreKitError,
           case .userCancelled = storeKitError { return true }
        let nsError = error as NSError
        if (nsError.domain == SKErrorDomain && nsError.code == SKError.paymentCancelled.rawValue)
            || (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) {
            return true
        }
        let description = error.localizedDescription.lowercased()
        return description.contains("request canceled")
            || description.contains("request cancelled")
            || description.contains("user canceled")
            || description.contains("user cancelled")
    }

    private static func isRetryable(_ error: Error) -> Bool {
        if let deferred = error as? TransactionSyncDeferredError { return deferred.underlying.isRetryable }
        if let accessError = error as? AccessCredentialError { return accessError.isRetryable }
        if let urlError = error as? URLError { return AccessCredentialStore.isTransientForMembership(urlError) }
        return false
    }

    private func deliver(
        _ transaction: Transaction,
        signedTransaction: String
    ) async throws -> TransactionDeliveryOutcome {
        let syncAttemptID = UUID()
        let syncStartedAt = Date()
#if DEBUG
        if transaction.environment == .xcode {
            let updated = await localEntitlement(for: transaction)
            setEntitlement(updated)
            if updated.isMember {
                await transaction.finish()
                return .activated(requestID: nil)
            }
            await transaction.finish()
            let state: SyncedTransactionState = transaction.revocationDate == nil ? .expired : .revoked
            return .processedInactive(state: state, requestID: nil)
        }
#endif
        let renewalInfo = await signedRenewalInfo(for: transaction)
        let requestID = syncAttemptID.uuidString.lowercased()
        do {
            let receipt = try await AccessCredentialStore.shared.syncSubscription(
                signedTransaction: signedTransaction,
                signedRenewalInfo: renewalInfo,
                requestID: requestID
            )
            let transactionHash = Self.hashedTransactionID(transaction.id)
            Self.logger.info(
                "store sync completed category=success state=\(receipt.syncedTransactionState.rawValue, privacy: .public) request_id=\(receipt.requestID, privacy: .public) transaction_hash=\(transactionHash, privacy: .public) duration_ms=\(Int(max(0, Date().timeIntervalSince(syncStartedAt)) * 1_000), privacy: .public)"
            )
            switch receipt.syncedTransactionState {
            case .active, .grace:
                guard receipt.entitlement.isMember else {
                    let error = AccessCredentialError.server(
                        code: "STORE_SYNC_UNAVAILABLE",
                        message: "服务器返回的交易状态与会员权益不一致",
                        requestID: receipt.requestID,
                        retryable: true
                    )
                    return .awaitingSync(TransactionSyncDeferredError(
                        underlying: error,
                        syncAttemptID: syncAttemptID,
                        requestID: receipt.requestID
                    ))
                }
                setEntitlement(receipt.entitlement)
                await transaction.finish()
                return .activated(requestID: receipt.requestID)
            case .expired, .revoked:
                setEntitlement(receipt.entitlement)
                await transaction.finish()
                return .processedInactive(
                    state: receipt.syncedTransactionState,
                    requestID: receipt.requestID
                )
            }
        } catch let error as AccessCredentialError where error.isRetryable {
            let transactionHash = Self.hashedTransactionID(transaction.id)
            Self.logger.error(
                "store sync deferred category=\(error.categoryCode, privacy: .public) request_id=\(error.requestID ?? requestID, privacy: .public) transaction_hash=\(transactionHash, privacy: .public) duration_ms=\(Int(max(0, Date().timeIntervalSince(syncStartedAt)) * 1_000), privacy: .public)"
            )
            return .awaitingSync(TransactionSyncDeferredError(
                underlying: error,
                syncAttemptID: syncAttemptID,
                requestID: error.requestID ?? requestID
            ))
        }
    }

    private func signedRenewalInfo(for transaction: Transaction) async -> String? {
        guard let product = products.first(where: { $0.id == transaction.productID }),
              let subscription = product.subscription,
              let statuses = try? await subscription.status else { return nil }
        for status in statuses {
            guard case .verified(let statusTransaction) = status.transaction,
                  statusTransaction.originalID == transaction.originalID,
                  case .verified = status.renewalInfo else { continue }
            return status.renewalInfo.jwsRepresentation
        }
        return nil
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                switch result {
                case .verified(let transaction):
                    guard transaction.productID == Self.monthlyProductId || transaction.productID == Self.annualProductId else { continue }
                    // Carry the exact update into the serialized sync pipeline.
                    // A plain full refresh could miss this event when another
                    // refresh was already running; the candidate is retained
                    // until its server result is successfully processed.
                    await self?.refreshCurrentEntitlements(
                        source: .transactionUpdate,
                        candidate: StoreTransactionCandidate(
                            transaction: transaction,
                            signedTransaction: result.jwsRepresentation
                        )
                    )
                case .unverified:
                    self?.setMessage(
                        "App Store 无法验证这笔购买，会员权益尚未生效",
                        source: .transactionUpdate,
                        category: .entitlementFailure
                    )
                }
            }
        }
    }

    private func sortProducts(_ products: [Product]) -> [Product] {
        products.sorted { left, right in
            let leftRank = left.id == Self.annualProductId ? 0 : 1
            let rightRank = right.id == Self.annualProductId ? 0 : 1
            return leftRank < rightRank
        }
    }

    private func setEntitlement(_ value: EntitlementSummary) {
        clearNoticeAfterSuccessfulEntitlementSync()
        entitlement = value
        entitlementLoadState = .loaded
        lastSuccessfulRefreshAt = Date()
        let cached = CachedEntitlement(entitlement: value, savedAt: lastSuccessfulRefreshAt ?? Date())
        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(data, forKey: "membership.cachedEntitlement")
        }
    }

    private func beginEntitlementLoading() {
        let hasCachedValue = entitlement != nil
        // Several UI paths can request the same serialized sync batch at once
        // (startup, scene activation, settings and the transaction listener).
        // Re-publishing an identical loading state makes SwiftUI animate the
        // settings row repeatedly even though no new work has started.
        if case .loading(let currentHasCachedValue) = entitlementLoadState,
           currentHasCachedValue == hasCachedValue {
            return
        }
        entitlementLoadState = .loading(hasCachedValue: hasCachedValue)
    }

    private func setEntitlementFailure(
        _ error: Error,
        prefix: String? = nil,
        source: MembershipNoticeSource = .manual,
        publishMessage: Bool = true
    ) {
        let baseMessage = error.localizedDescription
        let text = prefix.map { "\($0)：\(baseMessage)" } ?? baseMessage
        let details = Self.syncFailureDetails(error)
        entitlementLoadState = .failed(
            message: text,
            hasCachedValue: entitlement != nil,
            requestID: details.requestID
        )
        if publishMessage {
            setMessage(
                text,
                source: source,
                category: .entitlementFailure,
                requestID: details.requestID,
                syncAttemptID: details.syncAttemptID
            )
        }
    }

    private func setMessage(
        _ text: String,
        source: MembershipNoticeSource,
        category: MembershipNoticeCategory = .information,
        requestID: String? = nil,
        syncAttemptID: UUID? = nil
    ) {
        notice = MembershipNotice(
            text: text,
            source: source,
            category: category,
            requestID: requestID,
            syncAttemptID: syncAttemptID
        )
        message = text
    }

    private func clearNoticeAfterSuccessfulEntitlementSync() {
        let updated = MembershipNotice.afterSuccessfulEntitlementSync(notice)
        if updated == nil, notice != nil {
            notice = nil
            message = nil
        }
    }

    private static func syncFailureDetails(_ error: Error) -> (requestID: String?, syncAttemptID: UUID?) {
        if let deferred = error as? TransactionSyncDeferredError {
            return (deferred.requestID, deferred.syncAttemptID)
        }
        if let accessError = error as? AccessCredentialError {
            return (accessError.requestID, nil)
        }
        return (nil, nil)
    }

    private static func hashedTransactionID(_ transactionID: UInt64) -> String {
        SHA256.hash(data: Data(String(transactionID).utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func recordMetric(_ eventName: String, productId: String? = nil, outcome: String? = nil) {
        Task {
            await AccessCredentialStore.shared.recordMetric(
                eventName: eventName,
                productId: productId,
                outcome: outcome
            )
        }
    }

    private static func loadCachedEntitlement() -> CachedEntitlement? {
        guard let data = UserDefaults.standard.data(forKey: "membership.cachedEntitlement") else { return nil }
        if let cached = try? JSONDecoder().decode(CachedEntitlement.self, from: data) {
            return cached
        }
        guard let legacy = try? JSONDecoder().decode(EntitlementSummary.self, from: data) else { return nil }
        return CachedEntitlement(entitlement: legacy, savedAt: .distantPast)
    }

#if DEBUG
    private static func localFreeEntitlement() -> EntitlementSummary {
        EntitlementSummary(
            tier: "free", productId: nil, subscriptionState: "none",
            limit: 3, used: 0, reserved: 0, remaining: 3,
            unlimited: false,
            periodStart: nil, resetAt: nil, expiresAt: nil,
            autoRenewEnabled: nil, vocabularyCorrectionEnabled: false
        )
    }

    private func localEntitlement(for transaction: Transaction) async -> EntitlementSummary {
        guard transaction.revocationDate == nil,
              let expiration = transaction.expirationDate,
              expiration > Date() else {
            return Self.localFreeEntitlement()
        }

        let formatter = ISO8601DateFormatter()
        let now = Date()
        let nextMonth = Calendar(identifier: .gregorian).date(byAdding: .month, value: 1, to: now) ?? expiration
        let reset = min(nextMonth, expiration)
        return EntitlementSummary(
            tier: "member", productId: transaction.productID, subscriptionState: "active",
            limit: 100, used: 0, reserved: 0, remaining: 100,
            unlimited: false,
            periodStart: formatter.string(from: now),
            resetAt: formatter.string(from: reset),
            expiresAt: formatter.string(from: expiration),
            autoRenewEnabled: true, vocabularyCorrectionEnabled: true
        )
    }
#endif
}

private struct BootstrapRequest: Encodable {
    let installationId: UUID
    let deviceToken: String
}

private struct CachedEntitlement: Codable {
    let entitlement: EntitlementSummary
    let savedAt: Date
}

private struct BootstrapResponse: Decodable {
    let accessToken: String
    let entitlement: EntitlementSummary
}

private struct EntitlementResponse: Decodable {
    let entitlement: EntitlementSummary
}

private struct StoreSyncResponse: Decodable {
    let entitlement: EntitlementSummary
    let syncedTransactionState: SyncedTransactionState
}

private struct StoreSyncRequest: Encodable {
    let signedTransaction: String
    let signedRenewalInfo: String?
}

private struct MetricRequest: Encodable {
    let eventName: String
    let productId: String?
    let outcome: String?
}

private struct AccessServerError: Decodable {
    let error: String?
    let message: String?
}

protocol KeychainStoring: Sendable {
    func string(for account: String) -> String?
    func set(_ value: String, for account: String) throws
    func delete(_ account: String)
}

struct AppKeychain: KeychainStoring, Sendable {
    let service: String

    func string(for account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func set(_ value: String, for account: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus)) }
        } else if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func delete(_ account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
