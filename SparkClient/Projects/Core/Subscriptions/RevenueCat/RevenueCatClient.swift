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
        Purchases.configure(with:
                .init(withAPIKey: RevenueCatConfiguration.apiKey)
                .with(usesStoreKit2IfAvailable:  true))
        isConfigured = true
    }

    /// Call after SparkService session restoration/login succeeds.
    func identify(accountID: Int64) async throws {
        guard isConfigured else { return }
        _ = try await Purchases.shared.logIn(String(accountID))
        guard Purchases.shared.appUserID == String(accountID) else {
            throw NSError(
                domain: "RevenueCatIdentity",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "RevenueCat identity did not match the signed-in account"]
            )
        }
    }

    var currentAppUserID: String? {
        guard isConfigured else { return nil }
        return Purchases.shared.appUserID
    }

    /// Call when the app signs out of the SparkService account.
    func resetIdentity() async throws {
        guard isConfigured else { return }
        guard Purchases.shared.isAnonymous == false else { return }
        _ = try await Purchases.shared.logOut()
    }
}
