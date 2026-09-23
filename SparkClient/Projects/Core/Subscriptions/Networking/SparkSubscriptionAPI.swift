import Foundation

/// SparkService 是最终 Pro 权限事实源；RevenueCat CustomerInfo 仅用于本地购买界面反馈。
struct SparkSubscriptionAPI {
    let configuration: SparkBackendConfiguration

    struct Source: Codable, Sendable {
        let type: String
        let active: Bool
        let status: String?
        let billingStatus: String?
        let environment: String?
        let entitlement: String?
        let productId: String?
        let pendingProductId: String?
        let startedAt: Date?
        let expiresAt: Date?
        let willRenew: Bool?
        let periodType: String?
        let store: String?
        let lastSyncedAt: Date?
    }

    struct Summary: Codable, Sendable {
        let isPro: Bool
        let effectiveSource: String
        let syncState: String
        let lastSyncedAt: Date?
        let sources: [Source]
    }

    func current() async throws -> Summary {
        let operation = CacheableSparkNetworkOperation(
            name: "Subscription.Current",
            apiName: "SubscriptionAPI",
            request: SparkNetworkRequest(
                method: .get,
                path: "/api/v1/subscriptions/me/",
                headers: [:],
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "subscription.current",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .high
                )
            )
        )
        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedData(Summary.self, from: response)
    }

    func synchronize() async throws -> Summary {
        let operation = CacheableSparkNetworkOperation(
            name: "Subscription.Synchronize",
            apiName: "SubscriptionAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/subscriptions/revenuecat/sync/",
                headers: ["Idempotency-Key": UUID().uuidString],
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "subscription.sync",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .high
                )
            )
        )
        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedData(Summary.self, from: response)
    }
}
