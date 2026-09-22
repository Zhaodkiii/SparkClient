import Foundation
import RevenueCat

/// The single RevenueCat entry point for the app.
///
/// Purchases and entitlement checks should be added here instead of being spread
/// across SwiftUI views. The backend remains the business entitlement authority.
@MainActor
final class RevenueCatClient {
    static let shared = RevenueCatClient()

    private(set) var isConfigured = false

    private init() {}

    func configure() {
        guard !isConfigured else { return }

        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .warn
        #endif
        Purchases.configure(withAPIKey: RevenueCatConfiguration.apiKey)
        isConfigured = true
    }

    /// Call after SparkService session restoration/login succeeds.
    func identify(accountID: Int64) async throws {
        guard isConfigured else { return }
        _ = try await Purchases.shared.logIn(String(accountID))
    }

    /// Call when the app signs out of the SparkService account.
    func resetIdentity() async throws {
        guard isConfigured else { return }
        guard Purchases.shared.isAnonymous == false else { return }
        _ = try await Purchases.shared.logOut()
    }
}
