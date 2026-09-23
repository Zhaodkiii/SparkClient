import Foundation

@MainActor
final class SubscriptionSummaryStore {
    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func save(_ summary: SparkSubscriptionAPI.Summary, accountID: Int64) {
        guard let data = try? encoder.encode(summary) else { return }
        defaults.set(data, forKey: key(accountID: accountID))
    }

    func load(accountID: Int64) -> SparkSubscriptionAPI.Summary? {
        guard let data = defaults.data(forKey: key(accountID: accountID)) else { return nil }
        return try? decoder.decode(SparkSubscriptionAPI.Summary.self, from: data)
    }

    func remove(accountID: Int64) {
        defaults.removeObject(forKey: key(accountID: accountID))
    }

    private func key(accountID: Int64) -> String {
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        return "subscription-summary/\(environment)/\(accountID)"
    }
}
