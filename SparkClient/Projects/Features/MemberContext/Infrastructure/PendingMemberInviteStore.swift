import Foundation

/// 未登录或首页未就绪时暂存成员邀请 ID（按账号隔离、7 天有效，与邀请过期周期对齐）。
enum PendingMemberInviteStore {
    private static let expiryInterval: TimeInterval = 7 * 24 * 60 * 60
    private static var memoryPayload: PendingPayload?

    struct PendingPayload: Codable, Equatable {
        let inviteID: Int
        let createdAt: Date
        let accountID: Int64?
        let source: String
    }

    static func save(inviteID: Int, accountID: Int64? = nil, source: String = "deeplink") {
        let payload = PendingPayload(
            inviteID: inviteID,
            createdAt: Date(),
            accountID: accountID,
            source: source
        )

        if let accountID {
            UserDefaults.standard.set(encode(payload), forKey: storageKey(accountID: accountID))
            memoryPayload = nil
        } else {
            memoryPayload = payload
        }
    }

    static func consume(forAccountID accountID: Int64?) -> Int? {
        if let accountID,
           let data = UserDefaults.standard.data(forKey: storageKey(accountID: accountID)),
           let payload = decode(data) {
            UserDefaults.standard.removeObject(forKey: storageKey(accountID: accountID))
            if isExpired(payload) == false {
                return payload.inviteID
            }
        }

        guard let payload = memoryPayload else { return nil }
        memoryPayload = nil
        guard isExpired(payload) == false else { return nil }
        if let storedAccountID = payload.accountID, let accountID, storedAccountID != accountID {
            return nil
        }
        return payload.inviteID
    }

    static func clearAll() {
        memoryPayload = nil
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(storageKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private static let storageKeyPrefix = "pending.member.invite.v1."

    private static func storageKey(accountID: Int64) -> String {
        "\(storageKeyPrefix)\(accountID)"
    }

    private static func isExpired(_ payload: PendingPayload) -> Bool {
        Date().timeIntervalSince(payload.createdAt) > expiryInterval
    }

    private static func encode(_ payload: PendingPayload) -> Data {
        (try? JSONEncoder().encode(payload)) ?? Data()
    }

    private static func decode(_ data: Data) -> PendingPayload? {
        try? JSONDecoder().decode(PendingPayload.self, from: data)
    }
}
