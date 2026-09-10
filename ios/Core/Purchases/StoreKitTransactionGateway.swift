import CryptoKit
import Foundation
import StoreKit
import UIKit

enum StoreTransactionSource: String, Hashable, Sendable {
    case currentEntitlement
    case unfinished
    case update
    case purchase
}

struct StoreTransactionFingerprint: Hashable, Sendable {
    let transactionID: UInt64
    let signedTransactionHash: String

    init(transactionID: UInt64, signedTransaction: String) {
        self.transactionID = transactionID
        signedTransactionHash = SHA256.hash(data: Data(signedTransaction.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    var logHash: String {
        String(signedTransactionHash.prefix(16))
    }
}

struct StoreTransactionObservation: @unchecked Sendable {
    let id: UInt64
    let originalID: UInt64
    let productID: String
    let purchaseDate: Date
    let expirationDate: Date?
    let revocationDate: Date?
    let isUpgraded: Bool
    let isXcodeEnvironment: Bool
    let signedTransaction: String
    let source: StoreTransactionSource
    let requiresFinish: Bool

    private let finishOperation: @Sendable () async -> Void

    init(
        id: UInt64,
        originalID: UInt64,
        productID: String,
        purchaseDate: Date,
        expirationDate: Date?,
        revocationDate: Date?,
        isUpgraded: Bool,
        isXcodeEnvironment: Bool,
        signedTransaction: String,
        source: StoreTransactionSource,
        requiresFinish: Bool,
        finishOperation: @escaping @Sendable () async -> Void = {}
    ) {
        self.id = id
        self.originalID = originalID
        self.productID = productID
        self.purchaseDate = purchaseDate
        self.expirationDate = expirationDate
        self.revocationDate = revocationDate
        self.isUpgraded = isUpgraded
        self.isXcodeEnvironment = isXcodeEnvironment
        self.signedTransaction = signedTransaction
        self.source = source
        self.requiresFinish = requiresFinish
        self.finishOperation = finishOperation
    }

    init(
        transaction: Transaction,
        signedTransaction: String,
        source: StoreTransactionSource
    ) {
        self.init(
            id: transaction.id,
            originalID: transaction.originalID,
            productID: transaction.productID,
            purchaseDate: transaction.purchaseDate,
            expirationDate: transaction.expirationDate,
            revocationDate: transaction.revocationDate,
            isUpgraded: transaction.isUpgraded,
            isXcodeEnvironment: transaction.environment == .xcode,
            signedTransaction: signedTransaction,
            source: source,
            requiresFinish: source != .currentEntitlement,
            finishOperation: { await transaction.finish() }
        )
    }

    var fingerprint: StoreTransactionFingerprint {
        StoreTransactionFingerprint(
            transactionID: id,
            signedTransaction: signedTransaction
        )
    }

    func finish() async {
        guard requiresFinish else { return }
        await finishOperation()
    }
}

struct UnverifiedStoreTransaction: Sendable {
    let transactionID: UInt64
    let productID: String
    let source: StoreTransactionSource
}

enum StoreTransactionEvent: Sendable {
    case verified(StoreTransactionObservation)
    case unverified(UnverifiedStoreTransaction)
}

struct StoreTransactionSnapshot: Sendable {
    let observations: [StoreTransactionObservation]
    let unverified: [UnverifiedStoreTransaction]
    let currentCount: Int
    let unfinishedCount: Int
}

protocol StoreKitTransactionProviding: Sendable {
    func snapshot(supportedProductIDs: Set<String>) async -> StoreTransactionSnapshot
    func updates(supportedProductIDs: Set<String>) async -> AsyncStream<StoreTransactionEvent>
    func signedRenewalInfo(for observation: StoreTransactionObservation) async -> String?
    func register(products: [Product]) async
    func beginRefundRequest() async throws
}

extension StoreKitTransactionProviding {
    func beginRefundRequest() async throws {
        throw StoreKitRefundError.noActiveSubscription
    }
}

actor LiveStoreKitTransactionGateway: StoreKitTransactionProviding {
    private var productsByID: [String: Product] = [:]

    func register(products: [Product]) {
        for product in products {
            productsByID[product.id] = product
        }
    }

    func beginRefundRequest() async throws {
        guard let scene = await MainActor.run(body: {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
        }) else {
            throw StoreKitRefundError.noActiveScene
        }
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  ["com.kakaword.app.membership.month", "com.kakaword.app.membership.annual"].contains(transaction.productID) else { continue }
            try await transaction.beginRefundRequest(in: scene)
            return
        }
        throw StoreKitRefundError.noActiveSubscription
    }

    func snapshot(supportedProductIDs: Set<String>) async -> StoreTransactionSnapshot {
        var observations: [StoreTransactionObservation] = []
        var unverified: [UnverifiedStoreTransaction] = []
        var currentCount = 0
        var unfinishedCount = 0

        for await result in Transaction.currentEntitlements {
            guard let event = Self.event(
                from: result,
                source: .currentEntitlement,
                supportedProductIDs: supportedProductIDs
            ) else { continue }
            currentCount += 1
            Self.append(event, observations: &observations, unverified: &unverified)
        }

        for await result in Transaction.unfinished {
            guard let event = Self.event(
                from: result,
                source: .unfinished,
                supportedProductIDs: supportedProductIDs
            ) else { continue }
            unfinishedCount += 1
            Self.append(event, observations: &observations, unverified: &unverified)
        }

        return StoreTransactionSnapshot(
            observations: observations,
            unverified: unverified,
            currentCount: currentCount,
            unfinishedCount: unfinishedCount
        )
    }

    func updates(supportedProductIDs: Set<String>) -> AsyncStream<StoreTransactionEvent> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    guard !Task.isCancelled else { break }
                    guard let event = Self.event(
                        from: result,
                        source: .update,
                        supportedProductIDs: supportedProductIDs
                    ) else { continue }
                    continuation.yield(event)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func signedRenewalInfo(for observation: StoreTransactionObservation) async -> String? {
        let product: Product?
        if let cached = productsByID[observation.productID] {
            product = cached
        } else {
            product = (try? await Product.products(for: [observation.productID]))?.first
            if let product {
                productsByID[product.id] = product
            }
        }
        guard let subscription = product?.subscription,
              let statuses = try? await subscription.status else { return nil }
        for status in statuses {
            guard case .verified(let transaction) = status.transaction,
                  transaction.originalID == observation.originalID,
                  case .verified = status.renewalInfo else { continue }
            return status.renewalInfo.jwsRepresentation
        }
        return nil
    }

    private nonisolated static func event(
        from result: VerificationResult<Transaction>,
        source: StoreTransactionSource,
        supportedProductIDs: Set<String>
    ) -> StoreTransactionEvent? {
        switch result {
        case .verified(let transaction):
            guard supportedProductIDs.contains(transaction.productID) else { return nil }
            return .verified(StoreTransactionObservation(
                transaction: transaction,
                signedTransaction: result.jwsRepresentation,
                source: source
            ))
        case .unverified(let transaction, _):
            guard supportedProductIDs.contains(transaction.productID) else { return nil }
            return .unverified(UnverifiedStoreTransaction(
                transactionID: transaction.id,
                productID: transaction.productID,
                source: source
            ))
        }
    }

    private nonisolated static func append(
        _ event: StoreTransactionEvent,
        observations: inout [StoreTransactionObservation],
        unverified: inout [UnverifiedStoreTransaction]
    ) {
        switch event {
        case .verified(let observation):
            observations.append(observation)
        case .unverified(let transaction):
            unverified.append(transaction)
        }
    }
}

enum StoreKitRefundError: LocalizedError {
    case noActiveScene
    case noActiveSubscription

    var errorDescription: String? {
        switch self {
        case .noActiveScene: return "暂时无法打开退款页面"
        case .noActiveSubscription: return "没有找到可申请退款的会员交易"
        }
    }
}
