import Foundation

enum DeepTutorBlockKindConstants: Sendable {
    nonisolated static let envelope = "deepTutorEnvelope"
    nonisolated static let text = "deepTutorText"
    nonisolated static let thinking = "deepTutorThinking"
    nonisolated static let trace = "deepTutorTrace"
    nonisolated static let askUser = "deepTutorAskUser"
    nonisolated static let memberSelection = "deepTutorMemberSelection"
    nonisolated static let generatedFile = "deepTutorGeneratedFile"
    nonisolated static let researchOutline = "deepTutorResearchOutline"
    nonisolated static let quiz = "deepTutorQuiz"
    nonisolated static let quizParseError = "deepTutorQuizParseError"
    nonisolated static let visualization = "deepTutorVisualization"
    nonisolated static let error = "deepTutorError"
}

enum DeepTutorScenarioConstants: Sendable {
    nonisolated static let scenario = "deepTutor"
}

nonisolated enum DeepTutorMessageCodec {
    static let encoder = JSONEncoder.default
    static let decoder = JSONDecoder.default

    // encodePayload / decodePayload / decodeBlockPayload live in DeepTutorMessageCodec+Compatibility.swift

    nonisolated static func decodeErrorSummary(_ error: Error) -> String {
        if let decodingError = error as? DecodingError {
            switch decodingError {
            case let .typeMismatch(type, context):
                return "typeMismatch type=\(type) path=\(codingPath(context.codingPath)) debug=\(context.debugDescription)"
            case let .valueNotFound(type, context):
                return "valueNotFound type=\(type) path=\(codingPath(context.codingPath)) debug=\(context.debugDescription)"
            case let .keyNotFound(key, context):
                return "keyNotFound key=\(key.stringValue) path=\(codingPath(context.codingPath)) debug=\(context.debugDescription)"
            case let .dataCorrupted(context):
                return "dataCorrupted path=\(codingPath(context.codingPath)) debug=\(context.debugDescription)"
            @unknown default:
                return "unknownDecodingError error=\(error.localizedDescription)"
            }
        }
        let nsError = error as NSError
        return "domain=\(nsError.domain) code=\(nsError.code) error=\(error.localizedDescription)"
    }

    nonisolated static func makeEnvelopeBlock(for message: DeepTutorMessage, orderKey: Double) -> DeepTutorMessageBlock {
        DeepTutorMessageBlock(
            id: stableBlockID(messageID: message.id, suffix: "envelope"),
            kind: .envelope,
            payload: .envelope(
                DeepTutorMessageEnvelope(
                    serverID: message.serverID,
                    capability: message.capability,
                    events: message.events,
                    attachments: message.attachments,
                    requestSnapshot: message.requestSnapshot,
                    parentMessageID: message.parentMessageID,
                    status: message.status,
                    updatedAt: message.updatedAt
                )
            ),
            revision: 0,
            orderKey: orderKey,
            createdAt: message.createdAt,
            updatedAt: message.updatedAt
        )
    }

    nonisolated static func makeTextBlock(messageID: UUID, text: String, orderKey: Double) -> DeepTutorMessageBlock {
        DeepTutorMessageBlock(
            id: stableBlockID(messageID: messageID, suffix: "text"),
            kind: .text,
            payload: .text(text),
            revision: 0,
            orderKey: orderKey,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    nonisolated static func entityKind(for blockKind: DeepTutorMessageBlockKind) -> String {
        switch blockKind {
        case .envelope: DeepTutorBlockKindConstants.envelope
        case .text: DeepTutorBlockKindConstants.text
        case .thinking: DeepTutorBlockKindConstants.thinking
        case .trace: DeepTutorBlockKindConstants.trace
        case .askUser: DeepTutorBlockKindConstants.askUser
        case .memberSelection: DeepTutorBlockKindConstants.memberSelection
        case .generatedFile: DeepTutorBlockKindConstants.generatedFile
        case .researchOutline: DeepTutorBlockKindConstants.researchOutline
        case .quiz: DeepTutorBlockKindConstants.quiz
        case .quizParseError: DeepTutorBlockKindConstants.quizParseError
        case .visualization: DeepTutorBlockKindConstants.visualization
        case .error: DeepTutorBlockKindConstants.error
        }
    }

    nonisolated static func blockKind(for entityKind: String) -> DeepTutorMessageBlockKind? {
        switch entityKind {
        case DeepTutorBlockKindConstants.envelope: .envelope
        case DeepTutorBlockKindConstants.text: .text
        case DeepTutorBlockKindConstants.thinking: .thinking
        case DeepTutorBlockKindConstants.trace: .trace
        case DeepTutorBlockKindConstants.askUser: .askUser
        case DeepTutorBlockKindConstants.memberSelection: .memberSelection
        case DeepTutorBlockKindConstants.generatedFile: .generatedFile
        case DeepTutorBlockKindConstants.researchOutline: .researchOutline
        case DeepTutorBlockKindConstants.quiz: .quiz
        case DeepTutorBlockKindConstants.quizParseError: .quizParseError
        case DeepTutorBlockKindConstants.visualization: .visualization
        case DeepTutorBlockKindConstants.error: .error
        default: nil
        }
    }

    nonisolated static func stableBlockID(messageID: UUID, suffix: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        let messageBytes = withUnsafeBytes(of: messageID.uuid) { Array($0) }
        let suffixBytes = Array(suffix.utf8.prefix(16))
        for index in 0..<16 {
            bytes[index] = messageBytes[index] ^ suffixBytes[index % suffixBytes.count]
        }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private nonisolated static func codingPath(_ path: [CodingKey]) -> String {
        guard path.isEmpty == false else { return "-" }
        return path.map(\.stringValue).joined(separator: ".")
    }
}
