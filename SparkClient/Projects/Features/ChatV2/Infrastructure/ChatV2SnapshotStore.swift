import Foundation

protocol ChatV2SnapshotStore: Sendable {
    func loadThreads(ownerAccountID: Int64) async throws -> [ChatV2ThreadRecord]
    func loadMessages(threadID: UUID, limit: Int?) async throws -> [ChatV2MessageRecord]

    func insertThread(_ thread: ChatV2ThreadRecord) async throws
    func upsertThread(_ thread: ChatV2ThreadRecord) async throws

    func insertDraftMessage(_ message: ChatV2MessageRecord) async throws
    func commitMessageSnapshot(_ message: ChatV2MessageRecord) async throws
    func replaceRemoteSnapshot(_ message: ChatV2MessageRecord) async throws
    func markMessageFailed(messageID: UUID, errorText: String?) async throws
    func tombstoneMessage(messageID: UUID, updatedAt: Date) async throws

    func enqueueOutbox(_ record: ChatV2OutboxRecord) async throws
    func updateOutbox(_ record: ChatV2OutboxRecord) async throws
    func loadPendingOutbox(limit: Int?) async throws -> [ChatV2OutboxRecord]

    func saveCheckpoint(_ checkpoint: ChatV2SyncCheckpoint) async throws
    func loadCheckpoint(scopeKey: String) async throws -> ChatV2SyncCheckpoint?
}

struct ChatV2MessageDocumentCodec: Sendable {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.encoder = encoder
        self.decoder = decoder
    }

    func encode(_ document: ChatV2MessageDocument) throws -> Data {
        try encoder.encode(document)
    }

    func decode(_ data: Data) throws -> ChatV2MessageDocument {
        try decoder.decode(ChatV2MessageDocument.self, from: data)
    }
}

struct ChatV2AssistantMessageBuilder: Sendable {
    enum Step: Equatable, Sendable {
        case text(String)
        case block(id: String, payload: ChatV2BlockPayload)
    }

    func build(steps: [Step]) -> ChatV2MessageDocument {
        var state = ChatV2StreamingMessageState(threadID: UUID())
        for step in steps {
            switch step {
            case .text(let text):
                state.appendText(text)
            case .block(let id, let payload):
                state.appendBlock(id: id, payload: payload)
            }
        }
        return state.finalizedDocument()
    }
}
