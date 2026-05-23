import Foundation

/// 未登录或首页未就绪时暂存成员分享票据（按账号隔离、短期有效）。
enum PendingMemberShareTicketStore {
    private static let expiryInterval: TimeInterval = 30 * 60
    private static var memoryPayload: PendingPayload?

    struct PendingPayload: Codable, Equatable {
        let ticket: String
        let createdAt: Date
        let accountID: Int64?
        let source: String
    }

    static func save(_ ticket: String, accountID: Int64? = nil, source: String = "deeplink") {
        let payload = PendingPayload(
            ticket: ticket.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: Date(),
            accountID: accountID,
            source: source
        )
        guard payload.ticket.isEmpty == false else { return }

        if let accountID {
            UserDefaults.standard.set(encode(payload), forKey: storageKey(accountID: accountID))
            memoryPayload = nil
        } else {
            memoryPayload = payload
        }
    }

    static func consume(forAccountID accountID: Int64?) -> String? {
        if let accountID,
           let data = UserDefaults.standard.data(forKey: storageKey(accountID: accountID)),
           let payload = decode(data) {
            UserDefaults.standard.removeObject(forKey: storageKey(accountID: accountID))
            if isExpired(payload) == false {
                return payload.ticket
            }
        }

        guard let payload = memoryPayload else { return nil }
        memoryPayload = nil
        guard isExpired(payload) == false else { return nil }
        if let storedAccountID = payload.accountID, let accountID, storedAccountID != accountID {
            return nil
        }
        return payload.ticket
    }

    static func clearAll() {
        memoryPayload = nil
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(storageKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private static let storageKeyPrefix = "pending.member.share.v2."

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

enum MemberShareDeepLinkParser {
    private static let signedTicketPrefix = "spark_member_share."

    /// 仅接受 `spark://member-share?ticket=...` 深链。
    static func ticket(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "spark" else { return nil }
        let host = url.host?.lowercased() ?? ""
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        guard host == "member-share" || path == "member-share" else { return nil }
        guard let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "ticket" })?
            .value
        else { return nil }
        return normalizeTicket(value)
    }

    /// 扫码/粘贴原始文本：只接受 Spark 成员分享深链或带签名前缀的裸 ticket。
    static func ticket(fromRaw raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        if let url = URL(string: trimmed), let ticket = ticket(from: url) {
            return ticket
        }
        if trimmed.lowercased().hasPrefix("spark://"), let url = URL(string: trimmed), let ticket = ticket(from: url) {
            return ticket
        }
        if trimmed.hasPrefix(signedTicketPrefix) {
            return normalizeTicket(trimmed)
        }
        return nil
    }

    private static func normalizeTicket(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let ticket = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return ticket.isEmpty ? nil : ticket
    }
}
