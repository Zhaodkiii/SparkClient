import Foundation

enum NearbyShareAuthorizationState: Equatable {
    case unknown
    case unauthorized
    case poweredOff
    case ready
}

enum NearbyShareConnectionState: Equatable {
    case discovered
    case connecting
    case connected
    case failed
}

enum NearbyShareSendState: Equatable {
    case sending
    case sent
    case failed(String)
}

enum NearbyShareReceiveState: Equatable {
    case idle
    case advertising
    case received
    case failed(String)
}

/// 广播包：仅会话信息，不含成员/票据。
struct NearbyShareBeacon: Codable, Equatable {
    let v: Int
    let mode: String
    let sessionId: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case v
        case mode
        case sessionId = "session_id"
        case displayName = "display_name"
    }
}

struct NearbyShareMemberSnippet: Codable, Equatable {
    let id: Int
    let name: String
    let gender: String
    let birthDate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case gender
        case birthDate = "birth_date"
    }
}

struct NearbyShareInviterSnippet: Codable, Equatable {
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

/// BLE 写入的分享载荷。
struct NearbyShareOutboundPayload: Codable, Equatable {
    let v: Int
    let type: String
    let ticket: String
    let member: NearbyShareMemberSnippet
    let inviter: NearbyShareInviterSnippet
    let sentAt: String
    let nonce: String

    enum CodingKeys: String, CodingKey {
        case v
        case type
        case ticket
        case member
        case inviter
        case sentAt = "sent_at"
        case nonce
    }
}

struct NearbyShareInboundPayload: Equatable {
    let ticket: String
    let member: NearbyShareMemberSnippet
    let inviter: NearbyShareInviterSnippet
}
