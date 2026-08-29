import DeviceCheck
import Foundation
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
    let periodStart: String?
    let resetAt: String?
    let expiresAt: String?
    let autoRenewEnabled: Bool?
    let vocabularyCorrectionEnabled: Bool

    var isMember: Bool {
        tier == "member" && (subscriptionState == "active" || subscriptionState == "grace")
    }

    var resetDate: Date? { resetAt.flatMap(Self.dateFormatter.date(from:)) }
    var expirationDate: Date? { expiresAt.flatMap(Self.dateFormatter.date(from:)) }

    private static let dateFormatter = ISO8601DateFormatter()
}

struct AccessCredentials: Sendable {
    let accessToken: String
    let deviceCheckToken: String
}

enum AccessCredentialError: LocalizedError {
    case deviceUnsupported
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .deviceUnsupported: return "当前设备暂时无法完成安全验证"
        case .invalidResponse: return "服务器返回了无法识别的会员信息"
        case .server(let message): return message
        }
    }
}

actor AccessCredentialStore {
    static let shared = AccessCredentialStore()

    private let baseURL = AppEnvironment.current.apiBaseURL
    private let keychain = AppKeychain(service: "com.kakaword.app.access")
    private var accessToken: String?

    private init() {
        accessToken = keychain.string(for: "access-token")
    }

    func bootstrapIfNeeded(force: Bool = false) async throws -> EntitlementSummary {
        if !force, accessToken != nil {
            do {
                return try await status()
            } catch let error as AccessCredentialError {
                if case .server(let message) = error, message == "UNAUTHORIZED" {
                    clearAccessToken()
                } else {
                    throw error
                }
            }
        }

        let deviceToken = try await freshDeviceToken()
        let installationId = try installationIdentifier()
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/access/bootstrap"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(BootstrapRequest(
            installationId: installationId,
            deviceToken: deviceToken
        ))
        let response: BootstrapResponse = try await send(request)
        accessToken = response.accessToken
        try keychain.set(response.accessToken, for: "access-token")
        return response.entitlement
    }

    func status() async throws -> EntitlementSummary {
        let token = try await authorizationToken()
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/access/status"))
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let response: EntitlementResponse = try await send(request, retryingTransientFailures: 2)
        return response.entitlement
    }

    func syncSubscription(signedTransaction: String, signedRenewalInfo: String?) async throws -> EntitlementSummary {
        let token = try await authorizationToken()
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/store/sync"))
        request.httpMethod = "POST"
        // Apple online verification can take longer on a cold server. The endpoint is
        // idempotent, so retrying the same signed transaction is safe.
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "X-Request-ID")
        request.httpBody = try JSONEncoder().encode(StoreSyncRequest(
            signedTransaction: signedTransaction,
            signedRenewalInfo: signedRenewalInfo
        ))
        let response: EntitlementResponse = try await send(request, retryingTransientFailures: 2)
        return response.entitlement
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
        _ = try? await URLSession.shared.data(for: request)
    }

    func credentialsForAnalyze() async throws -> AccessCredentials {
        AccessCredentials(
            accessToken: try await authorizationToken(),
            deviceCheckToken: try await freshDeviceToken()
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

    private func freshDeviceToken() async throws -> String {
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
        retryingTransientFailures retryCount: Int = 0
    ) async throws -> Response {
        var remainingRetries = max(0, retryCount)
        var retryDelayNanoseconds: UInt64 = 500_000_000
        let data: Data
        let response: URLResponse
        while true {
            do {
                (data, response) = try await URLSession.shared.data(for: request)
                break
            } catch let error as URLError where remainingRetries > 0 && Self.isTransient(error) {
                remainingRetries -= 1
                try await Task.sleep(nanoseconds: retryDelayNanoseconds)
                retryDelayNanoseconds *= 2
            }
        }
        guard let http = response as? HTTPURLResponse else { throw AccessCredentialError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let payload = try? JSONDecoder().decode(AccessServerError.self, from: data)
            if http.statusCode == 401 {
                throw AccessCredentialError.server("UNAUTHORIZED")
            }
            throw AccessCredentialError.server(payload?.message ?? "会员服务暂时不可用")
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw AccessCredentialError.invalidResponse
        }
        return decoded
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
}

@MainActor
final class MembershipStore: ObservableObject {
    static let monthlyProductId = "com.kakaword.app.membership.month"
    static let annualProductId = "com.kakaword.app.membership.annual"

    @Published private(set) var entitlement: EntitlementSummary?
    @Published private(set) var products: [Product] = []
    @Published private(set) var productLoadFailed = false
    @Published private(set) var isLoading = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false
    @Published private(set) var isRefreshingEntitlements = false
    @Published var message: String?

    private var transactionTask: Task<Void, Never>?
    private var entitlementTask: Task<Void, Never>?
    private var didPrepare = false

    init() {
        entitlement = Self.loadCachedEntitlement()
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
    }

    var canStartRecognition: Bool { (entitlement?.remaining ?? 0) > 0 }
    var isMember: Bool { entitlement?.isMember == true }
    var canPurchase: Bool {
        entitlement != nil && !isMember && !isLoading && !isRefreshingEntitlements && !isPurchasing
    }

    var annualProduct: Product? { products.first { $0.id == Self.annualProductId } }
    var monthlyProduct: Product? { products.first { $0.id == Self.monthlyProductId } }

    func prepare() async {
        guard !didPrepare || products.isEmpty else {
            await refreshStatus()
            return
        }
        didPrepare = true
        isLoading = true
        defer { isLoading = false }
        productLoadFailed = false
        async let productRequest = Product.products(for: [Self.monthlyProductId, Self.annualProductId])
        do {
            let initialEntitlement = try await AccessCredentialStore.shared.bootstrapIfNeeded()
            setEntitlement(initialEntitlement)
        } catch {
            message = error.localizedDescription
#if DEBUG
            if entitlement == nil { setEntitlement(Self.localFreeEntitlement()) }
#endif
        }
        do {
            products = sortProducts(try await productRequest)
            productLoadFailed = products.isEmpty
            if productLoadFailed {
                message = "暂时没有找到可用的订阅商品，请确认 App Store 商品配置后重试"
            }
        } catch {
            productLoadFailed = true
            message = error.localizedDescription
        }
        do {
            try await synchronizeCurrentEntitlements()
        } catch {
            message = "会员状态同步失败：\(error.localizedDescription)"
        }
    }

    func retryProducts() async {
        didPrepare = false
        await prepare()
    }

    func refreshStatus() async {
        do {
            setEntitlement(try await loadStatus())
        } catch {
            message = error.localizedDescription
        }
    }

    func refreshCurrentEntitlements() async {
        guard !isRefreshingEntitlements, !isPurchasing else { return }
        isRefreshingEntitlements = true
        defer { isRefreshingEntitlements = false }
        do {
            try await synchronizeCurrentEntitlements()
        } catch {
            message = "会员状态同步失败：\(error.localizedDescription)"
        }
    }

    func purchase(_ product: Product) async -> Bool {
        guard !isPurchasing else { return false }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            // Re-read StoreKit and server state immediately before presenting Apple's
            // purchase sheet. This prevents a stale free cache on a new device from
            // initiating a plan change for an already-active subscriber.
            try await synchronizeCurrentEntitlements()
            guard !isMember else {
                message = "当前已有有效会员，无需重复购买"
                return false
            }
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result else {
                    message = "App Store 无法验证这笔购买，请稍后重试"
                    recordMetric("purchase_result", productId: product.id, outcome: "unverified")
                    return false
                }
                try await deliver(transaction, signedTransaction: result.jwsRepresentation)
                message = "会员已开通"
                recordMetric("purchase_result", productId: product.id, outcome: "success")
                return true
            case .pending:
                message = "购买正在等待批准，批准后会员会自动生效"
                recordMetric("purchase_result", productId: product.id, outcome: "pending")
            case .userCancelled:
                message = nil
                recordMetric("purchase_result", productId: product.id, outcome: "cancelled")
            @unknown default:
                message = "购买状态暂时无法确认"
            }
        } catch {
            message = error.localizedDescription
            recordMetric("purchase_result", productId: product.id, outcome: "failed")
        }
        return false
    }

    func restorePurchases() async -> Bool {
        guard !isPurchasing else { return false }
        isPurchasing = true
        isRestoring = true
        defer {
            isRestoring = false
            isPurchasing = false
        }
        do {
            try await AppStore.sync()
            try await synchronizeCurrentEntitlements()
            message = isMember ? "购买记录已恢复" : "没有找到可恢复的有效会员"
            recordMetric("restore_result", outcome: isMember ? "success" : "not_found")
            return isMember
        } catch {
            message = restoreErrorMessage(error)
            recordMetric("restore_result", outcome: "failed")
            return false
        }
    }

    func showManageSubscriptions() async {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            message = "暂时无法打开订阅管理"
            return
        }
        do {
            try await AppStore.showManageSubscriptions(in: scene)
            await refreshStatus()
        } catch {
            message = error.localizedDescription
        }
    }

    private func synchronizeCurrentEntitlements() async throws {
        var foundMembershipTransaction = false
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                guard transaction.productID == Self.monthlyProductId || transaction.productID == Self.annualProductId else { continue }
                foundMembershipTransaction = true
                try await deliver(transaction, signedTransaction: result.jwsRepresentation)
            case .unverified(let transaction, _):
                guard transaction.productID == Self.monthlyProductId || transaction.productID == Self.annualProductId else { continue }
                throw AccessCredentialError.server("发现一笔无法验证的购买，请稍后重试或联系 Apple 支持")
            }
        }
        if !foundMembershipTransaction {
            setEntitlement(try await loadStatus())
        }
    }

    private func loadStatus() async throws -> EntitlementSummary {
        do {
            return try await AccessCredentialStore.shared.status()
        } catch let error as AccessCredentialError {
            if case .server(let code) = error, code == "UNAUTHORIZED" {
                return try await AccessCredentialStore.shared.bootstrapIfNeeded(force: true)
            }
            throw error
        }
    }

    private func restoreErrorMessage(_ error: Error) -> String {
        if let storeKitError = error as? StoreKitError,
           case .userCancelled = storeKitError {
            return "已取消恢复购买，没有产生任何更改"
        }

        let nsError = error as NSError
        if (nsError.domain == SKErrorDomain && nsError.code == SKError.paymentCancelled.rawValue)
            || (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) {
            return "已取消恢复购买，没有产生任何更改"
        }

        let description = error.localizedDescription.lowercased()
        if description.contains("request canceled")
            || description.contains("request cancelled")
            || description.contains("user canceled")
            || description.contains("user cancelled") {
            return "已取消恢复购买，没有产生任何更改"
        }
        return error.localizedDescription
    }

    private func deliver(_ transaction: Transaction, signedTransaction: String) async throws {
#if DEBUG
        if transaction.environment == .xcode {
            setEntitlement(await localEntitlement(for: transaction))
            await transaction.finish()
            return
        }
#endif
        let renewalInfo = await signedRenewalInfo(for: transaction)
        let updated = try await AccessCredentialStore.shared.syncSubscription(
            signedTransaction: signedTransaction,
            signedRenewalInfo: renewalInfo
        )
        setEntitlement(updated)
        await transaction.finish()
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
                    do {
                        try await self?.deliver(transaction, signedTransaction: result.jwsRepresentation)
                    } catch {
                        self?.message = "购买状态同步失败：\(error.localizedDescription)"
                    }
                case .unverified:
                    self?.message = "App Store 无法验证这笔购买，会员权益尚未生效"
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
        entitlement = value
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: "membership.cachedEntitlement")
        }
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

    private static func loadCachedEntitlement() -> EntitlementSummary? {
        guard let data = UserDefaults.standard.data(forKey: "membership.cachedEntitlement") else { return nil }
        return try? JSONDecoder().decode(EntitlementSummary.self, from: data)
    }

#if DEBUG
    private static func localFreeEntitlement() -> EntitlementSummary {
        EntitlementSummary(
            tier: "free", productId: nil, subscriptionState: "none",
            limit: 3, used: 0, reserved: 0, remaining: 3,
            periodStart: nil, resetAt: nil, expiresAt: nil,
            autoRenewEnabled: nil, vocabularyCorrectionEnabled: false
        )
    }

    private func localEntitlement(for transaction: Transaction) async -> EntitlementSummary {
        guard transaction.revocationDate == nil,
              let product = products.first(where: { $0.id == transaction.productID }),
              let subscription = product.subscription,
              let statuses = try? await subscription.status else {
            return Self.localFreeEntitlement()
        }
        let state = statuses.first { status in
            guard case .verified(let statusTransaction) = status.transaction else { return false }
            return statusTransaction.originalID == transaction.originalID
        }?.state
        let subscriptionState: String
        switch state {
        case .subscribed: subscriptionState = "active"
        case .inGracePeriod: subscriptionState = "grace"
        default: return Self.localFreeEntitlement()
        }

        let formatter = ISO8601DateFormatter()
        let now = Date()
        let reset = Calendar(identifier: .gregorian).date(byAdding: .month, value: 1, to: now) ?? now
        return EntitlementSummary(
            tier: "member", productId: transaction.productID, subscriptionState: subscriptionState,
            limit: 100, used: 0, reserved: 0, remaining: 100,
            periodStart: formatter.string(from: now),
            resetAt: formatter.string(from: reset),
            expiresAt: transaction.expirationDate.map(formatter.string(from:)),
            autoRenewEnabled: true, vocabularyCorrectionEnabled: true
        )
    }
#endif
}

private struct BootstrapRequest: Encodable {
    let installationId: UUID
    let deviceToken: String
}

private struct BootstrapResponse: Decodable {
    let accessToken: String
    let entitlement: EntitlementSummary
}

private struct EntitlementResponse: Decodable {
    let entitlement: EntitlementSummary
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

private struct AppKeychain: Sendable {
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
