import Foundation

actor SessionSnapshotStore {
    private enum Keys {
        static let currentSession = "spark.session.current"
    }

    private let userDefaults: UserDefaults
    private let logger: Logger = ConsoleLogger()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> UserSession? {
        guard let data = userDefaults.data(forKey: Keys.currentSession) else { return nil }
        return try? JSONDecoder.default.decode(UserSession.self, from: data)
//        do {
//            let session = try JSONDecoder.default.decode(UserSession.self, from: data)
////            logger.info("会话快照：读取成功 accountID=\(session.accountID)", module: .auth)
//            return session
//        } catch {
//            logger.error("会话快照：读取失败 error=\(error.localizedDescription)", module: .auth)
//            return nil
//        }
    }

    func save(_ session: UserSession) throws {
        let data: Data
        do {
            data = try JSONEncoder.default.encode(session)
        } catch {
            logger.error("会话快照：编码失败 accountID=\(session.accountID) error=\(error.localizedDescription)", module: .auth)
            throw error
        }
        userDefaults.set(data, forKey: Keys.currentSession)
        logger.info("会话快照：保存成功 accountID=\(session.accountID)", module: .auth)
    }

    func clear() {
        userDefaults.removeObject(forKey: Keys.currentSession)
    }
}
