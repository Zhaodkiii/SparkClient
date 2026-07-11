import Foundation

nonisolated enum NearbyShareAuthorizationState: Equatable, Sendable {
    case unknown
    case unauthorized
    case poweredOff
    case ready
}

nonisolated enum NearbyShareConnectionState: Equatable, Sendable {
    case discovered
    case connecting
    case connected
    case failed
}

nonisolated enum NearbyShareSendState: Equatable, Sendable {
    case sending
    case sent
    case failed(String)
}

nonisolated enum NearbyShareReceiveState: Equatable, Sendable {
    case idle
    case advertising
    case received
    case failed(String)
}

/// 广播包：仅会话信息，不含成员/票据。
nonisolated struct NearbyShareBeacon: Codable, Equatable, Sendable {
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

nonisolated struct NearbyShareMemberSnippet: Codable, Equatable, Sendable {
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

nonisolated struct NearbyShareInviterSnippet: Codable, Equatable, Sendable {
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

/// BLE 写入的分享载荷。
nonisolated struct NearbyShareOutboundPayload: Codable, Equatable, Sendable {
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

nonisolated struct NearbyShareInboundPayload: Equatable, Sendable {
    let ticket: String
    let member: NearbyShareMemberSnippet
    let inviter: NearbyShareInviterSnippet
}
