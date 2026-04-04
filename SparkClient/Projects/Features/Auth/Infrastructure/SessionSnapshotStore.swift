import Foundation

actor SessionSnapshotStore {
    private enum Keys {
        static let currentSession = "spark.session.current"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> UserSession? {
        guard let data = userDefaults.data(forKey: Keys.currentSession) else { return nil }
        return try? JSONDecoder().decode(UserSession.self, from: data)
    }

    func save(_ session: UserSession) throws {
        let data = try JSONEncoder().encode(session)
        userDefaults.set(data, forKey: Keys.currentSession)
    }

    func clear() {
        userDefaults.removeObject(forKey: Keys.currentSession)
    }
}
