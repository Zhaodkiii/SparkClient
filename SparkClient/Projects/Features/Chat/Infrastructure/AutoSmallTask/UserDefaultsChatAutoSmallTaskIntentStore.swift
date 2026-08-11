import Foundation

final class UserDefaultsChatAutoSmallTaskIntentStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load(threadID: UUID) -> ChatAutoSmallTaskIntent? {
        guard let data = defaults.data(forKey: storageKey(threadID: threadID)) else {
            return nil
        }
        return try? decoder.decode(ChatAutoSmallTaskIntent.self, from: data)
    }

    func save(_ intent: ChatAutoSmallTaskIntent) {
        guard let data = try? encoder.encode(intent) else { return }
        defaults.set(data, forKey: storageKey(threadID: intent.threadID))
    }

    private func storageKey(threadID: UUID) -> String {
        "chat.autoSmallTask.intent.\(threadID.uuidString)"
    }
}

