import Foundation

/// 未登录或首页未就绪时暂存成员分享票据。
enum PendingMemberShareTicketStore {
    private static let key = "pending.member.share.ticket"

    static func save(_ ticket: String) {
        UserDefaults.standard.set(ticket, forKey: key)
    }

    static func consume() -> String? {
        let ticket = UserDefaults.standard.string(forKey: key)
        if ticket != nil {
            UserDefaults.standard.removeObject(forKey: key)
        }
        return ticket
    }
}

enum MemberShareDeepLinkParser {
    static func ticket(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "spark" else { return nil }
        let host = url.host?.lowercased() ?? ""
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        guard host == "member-share" || path == "member-share" else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "ticket" })?
            .value
    }
}
