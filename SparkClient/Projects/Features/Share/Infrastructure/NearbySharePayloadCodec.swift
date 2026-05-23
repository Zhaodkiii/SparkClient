import Foundation

enum NearbySharePayloadCodec {
    enum CodecError: LocalizedError {
        case payloadTooLarge
        case invalidFormat
        case missingTicket

        var errorDescription: String? {
            switch self {
            case .payloadTooLarge:
                return L10n.text("home.members.share.nearby.payload_too_large")
            case .invalidFormat:
                return L10n.text("home.members.share.nearby.payload_invalid")
            case .missingTicket:
                return L10n.text("home.members.share.ticket_invalid")
            }
        }
    }

    static func encodeBeacon(_ beacon: NearbyShareBeacon) throws -> Data {
        try encode(beacon)
    }

    static func decodeBeacon(_ data: Data) throws -> NearbyShareBeacon {
        try decode(NearbyShareBeacon.self, from: data)
    }

    static func encodeOutbound(_ payload: NearbyShareOutboundPayload) throws -> Data {
        let data = try encode(payload)
        guard data.count <= NearbyShareBLE.maxPayloadBytes else {
            throw CodecError.payloadTooLarge
        }
        return data
    }

    static func decodeInbound(_ data: Data) throws -> NearbyShareInboundPayload {
        struct Raw: Decodable {
            let v: Int
            let type: String
            let ticket: String
            let member: NearbyShareMemberSnippet
            let inviter: NearbyShareInviterSnippet
        }
        let raw = try decode(Raw.self, from: data)
        guard raw.v == 1, raw.type == NearbyShareBLE.shareType else {
            throw CodecError.invalidFormat
        }
        guard raw.ticket.isEmpty == false else {
            throw CodecError.missingTicket
        }
        return NearbyShareInboundPayload(ticket: raw.ticket, member: raw.member, inviter: raw.inviter)
    }

    static func makeOutboundPayload(
        ticket: String,
        member: Member,
        inviterDisplayName: String
    ) -> NearbyShareOutboundPayload {
        let birthDate = member.birthDate.map { MedicalDateCoding.encodeDateOnly($0) }
        return NearbyShareOutboundPayload(
            v: 1,
            type: NearbyShareBLE.shareType,
            ticket: ticket,
            member: NearbyShareMemberSnippet(
                id: member.id,
                name: member.name,
                gender: member.gender,
                birthDate: birthDate
            ),
            inviter: NearbyShareInviterSnippet(displayName: inviterDisplayName),
            sentAt: MedicalDateCoding.encodeISO8601(Date()),
            nonce: UUID().uuidString
        )
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }
}
