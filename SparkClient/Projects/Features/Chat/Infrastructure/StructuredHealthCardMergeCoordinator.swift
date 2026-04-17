import Foundation

/// 结构化医疗卡片异步合并：将抽取结果追加写入同一条助手消息的 `structured_health_cards` 附件，并同步内存态 `ChatStateStore`。
final class StructuredHealthCardMergeCoordinator: @unchecked Sendable {
    private let repository: CoreDataChatRepository
    private weak var stateStore: ChatStateStore?

    init(repository: CoreDataChatRepository) {
        self.repository = repository
    }

    func register(stateStore: ChatStateStore) {
        self.stateStore = stateStore
    }

    /// 助手消息在编排结束后才落库；工具异步任务可能更早结束，因此轮询直至消息存在再合并。
    func mergeAppendWhenAssistantMessageReady(
        threadID: UUID,
        assistantClientMessageID: UUID,
        delta: StructuredHealthCardsBlob,
        maxWaitSeconds: TimeInterval = 25
    ) async {
        let deadline = Date().addingTimeInterval(maxWaitSeconds)
        while Date() < deadline {
            let messages = await repository.loadMessages(threadID: threadID, limit: nil, before: nil)
            if messages.contains(where: { $0.clientMessageID == assistantClientMessageID }) {
                await mergeAppend(
                    threadID: threadID,
                    assistantClientMessageID: assistantClientMessageID,
                    delta: delta
                )
                return
            }
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
    }

    func mergeAppend(
        threadID: UUID,
        assistantClientMessageID: UUID,
        delta: StructuredHealthCardsBlob
    ) async {
        let messages = await repository.loadMessages(threadID: threadID, limit: nil, before: nil)
        guard let msg = messages.first(where: { $0.clientMessageID == assistantClientMessageID }) else {
            return
        }

        var blob = Self.decodeBlob(from: msg) ?? .empty
        blob.medications.append(contentsOf: delta.medications)
        blob.prescriptions.append(contentsOf: delta.prescriptions)
        blob.examReports.append(contentsOf: delta.examReports)
        blob.medicalCases.append(contentsOf: delta.medicalCases)

        guard let data = try? JSONEncoder().encode(blob),
              let json = String(data: data, encoding: .utf8) else {
            return
        }

        let newAttachments = Self.replaceOrInsertStructuredHealthCardsAttachment(in: msg.attachments, json: json)
        await repository.updateMessageAttachments(
            clientMessageID: assistantClientMessageID,
            attachments: newAttachments,
            markPendingForSync: true
        )

        let store = stateStore
        await MainActor.run {
            store?.updateMessageAttachments(
                threadID: threadID,
                clientMessageID: assistantClientMessageID,
                attachments: newAttachments
            )
        }
    }

    private static func decodeBlob(from message: ChatMessage) -> StructuredHealthCardsBlob? {
        guard let raw = message.attachments.first(where: { $0.type == ChatStreamFieldKey.structuredHealthCards })?.text,
              let data = raw.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(StructuredHealthCardsBlob.self, from: data)
    }

    private static func replaceOrInsertStructuredHealthCardsAttachment(
        in attachments: [ChatAttachment],
        json: String
    ) -> [ChatAttachment] {
        var out = attachments
        if let i = out.firstIndex(where: { $0.type == ChatStreamFieldKey.structuredHealthCards }) {
            out[i] = ChatAttachment(
                id: out[i].id,
                type: ChatStreamFieldKey.structuredHealthCards,
                url: out[i].url,
                text: json
            )
        } else {
            out.append(ChatAttachment(type: ChatStreamFieldKey.structuredHealthCards, text: json))
        }
        return out
    }
}
