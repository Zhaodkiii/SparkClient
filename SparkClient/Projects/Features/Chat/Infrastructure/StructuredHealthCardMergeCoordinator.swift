import Foundation

/// 结构化医疗卡片异步合并协调器
/// 核心职责：将后台抽取完成的医疗结构化数据，追加写入同一条助手消息的 `structured_health_cards` 附件中
/// 并同步更新内存状态 `ChatStateStore`，保证 UI 实时刷新
final class StructuredHealthCardMergeCoordinator: @unchecked Sendable {
    /// 聊天数据仓库（负责数据库/持久化操作）
    private let repository: any ChatRepository
    /// 聊天内存状态管理器（弱引用，避免循环持有）
    private weak var stateStore: ChatStateStore?

    /// 初始化
    /// - Parameter repository: 聊天数据操作仓库
    init(repository: any ChatRepository) {
        self.repository = repository
    }

    /// 注册内存状态管理器
    /// - Parameter stateStore: 聊天界面状态 Store
    func register(stateStore: ChatStateStore) {
        self.stateStore = stateStore
    }

    /// 仅写入流式缓存，不触发持久化；用于工具等待态的即时卡片展示。
    func mergeRichAttachmentsIntoStreamingCache(
        threadID: UUID,
        attachments: [ChatAttachment]
    ) async {
        guard attachments.isEmpty == false else { return }
        let store = stateStore
        await MainActor.run {
            store?.mergeStreamingAssistantAttachments(threadID: threadID, attachments: attachments)
        }
    }

    /// 等待助手消息就绪后，再执行合并追加操作
    /// 说明：助手消息在编排结束后才会落库，而工具异步抽取任务可能更早完成
    /// 因此需要轮询等待目标消息存在后，再执行合并逻辑
    /// - Parameters:
    ///   - threadID: 会话 ID
    ///   - assistantClientMessageID: 助手消息客户端唯一 ID
    ///   - delta: 需要合并的结构化医疗卡片增量数据
    ///   - maxWaitSeconds: 最大等待超时时间，默认 25 秒
    func mergeAppendWhenAssistantMessageReady(
        threadID: UUID,
        assistantClientMessageID: UUID,
        delta: StructuredHealthCardsBlob,
        maxWaitSeconds: TimeInterval = 300
    ) async {
        // 计算超时截止时间
        let deadline = Date().addingTimeInterval(maxWaitSeconds)
        // 轮询检查消息是否已落库
        while Date() < deadline {
            // 加载当前会话所有消息
            let messages = await repository.loadMessages(threadID: threadID, limit: nil, before: nil)
            // 判断目标助手消息是否已存在
            if messages.contains(where: { $0.clientMessageID == assistantClientMessageID }) {
                // 消息已就绪，执行合并
                await mergeAppend(
                    threadID: threadID,
                    assistantClientMessageID: assistantClientMessageID,
                    delta: delta
                )
                return
            }
            // 未找到消息，等待 60ms 后重试
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
    }

    /// 执行结构化医疗卡片合并与追加
    /// 将增量数据合并到原有卡片中，并更新消息附件与内存状态
    /// - Parameters:
    ///   - threadID: 会话 ID
    ///   - assistantClientMessageID: 目标助手消息 ID
    ///   - delta: 待合并的增量卡片数据
    func mergeAppend(
        threadID: UUID,
        assistantClientMessageID: UUID,
        delta: StructuredHealthCardsBlob
    ) async {
        // 1. 加载会话消息
        let messages = await repository.loadMessages(threadID: threadID, limit: nil, before: nil)
        // 2. 查找目标助手消息，不存在则直接返回
        guard let msg = messages.first(where: { $0.clientMessageID == assistantClientMessageID }) else {
            return
        }

        // 3. 解码消息中已有的结构化卡片数据，不存在则使用空对象
        var blob = Self.decodeBlob(from: msg) ?? .empty
        // 4. 合并增量数据到现有卡片（药物、处方、检查报告、病历）
        blob.medications.append(contentsOf: delta.medications)
        blob.prescriptions.append(contentsOf: delta.prescriptions)
        blob.examReports.append(contentsOf: delta.examReports)
        blob.medicalCases.append(contentsOf: delta.medicalCases)

        // 5. 将合并后的对象序列化为 JSON 字符串
        guard let data = try? JSONEncoder().encode(blob),
              let json = String(data: data, encoding: .utf8) else {
            return
        }

        // 6. 构建新的附件列表（替换或插入结构化健康卡片附件）
        let newAttachments = Self.replaceOrInsertStructuredHealthCardsAttachment(in: msg.attachments, json: json)
        // 7. 持久化更新消息附件
        await repository.updateMessageAttachments(
            clientMessageID: assistantClientMessageID,
            attachments: newAttachments,
            markPendingForSync: true
        )

        // 8. 主线程更新内存状态，触发 UI 刷新
        let store = stateStore
        await MainActor.run {
            store?.updateMessageAttachments(
                threadID: threadID,
                clientMessageID: assistantClientMessageID,
                attachments: newAttachments
            )
        }
    }

    // MARK: - 知识卡预览

    /// 将单条知识卡预览（标题+正文）编码为 `knowledge_card` 附件，等待助手消息就绪后追加写入。
    func mergeKnowledgeCardPreviewWhenAssistantMessageReady(
        threadID: UUID,
        assistantClientMessageID: UUID,
        title: String,
        content: String,
        maxWaitSeconds: TimeInterval = 300
    ) async {
        struct Row: Codable {
            let title: String
            let content: String
        }
        guard let data = try? JSONEncoder().encode([Row(title: title, content: content)]),
              let json = String(data: data, encoding: .utf8) else { return }
        await mergeAppendRichAttachmentsWhenAssistantMessageReady(
            threadID: threadID,
            assistantClientMessageID: assistantClientMessageID,
            attachments: [ChatAttachment(type: .knowledgeCard, text: json)],
            maxWaitSeconds: maxWaitSeconds
        )
    }

    // MARK: - 富 UI 附件（地图 / 日程 / 睡眠 / 任务卡 / HTML 等）

    /// 等待助手消息就绪后，将一批富 UI 附件追加写入消息
    func mergeAppendRichAttachmentsWhenAssistantMessageReady(
        threadID: UUID,
        assistantClientMessageID: UUID,
        attachments: [ChatAttachment],
        maxWaitSeconds: TimeInterval = 300
    ) async {
        guard attachments.isEmpty == false else { return }
        // 先写入流式缓存，保证“等待消息落库”期间也能立即看到卡片。
        let store = stateStore
        await MainActor.run {
            store?.mergeStreamingAssistantAttachments(threadID: threadID, attachments: attachments)
        }
        let deadline = Date().addingTimeInterval(maxWaitSeconds)
        while Date() < deadline {
            let messages = await repository.loadMessages(threadID: threadID, limit: nil, before: nil)
            if messages.contains(where: { $0.clientMessageID == assistantClientMessageID }) {
                await mergeAppendRichAttachments(
                    threadID: threadID,
                    assistantClientMessageID: assistantClientMessageID,
                    attachments: attachments
                )
                return
            }
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
    }

    private func mergeAppendRichAttachments(
        threadID: UUID,
        assistantClientMessageID: UUID,
        attachments: [ChatAttachment]
    ) async {
        guard attachments.isEmpty == false else { return }
        let messages = await repository.loadMessages(threadID: threadID, limit: nil, before: nil)
        guard let msg = messages.first(where: { $0.clientMessageID == assistantClientMessageID }) else { return }

        var combined = msg.attachments
        combined.append(contentsOf: attachments)

        await repository.updateMessageAttachments(
            clientMessageID: assistantClientMessageID,
            attachments: combined,
            markPendingForSync: true
        )

        let store = stateStore
        await MainActor.run {
            store?.updateMessageAttachments(
                threadID: threadID,
                clientMessageID: assistantClientMessageID,
                attachments: combined
            )
        }
    }

    // MARK: - 睡眠可视化

    /// 等待助手消息就绪后，将 `ChatHealthSleepModel` 编码为 `healthSleepVisualization` 附件写入（不向模型暴露原始 JSON）。
    func insertHealthSleepVisualizationWhenAssistantMessageReady(
        threadID: UUID,
        assistantClientMessageID: UUID,
        model: ChatHealthSleepModel,
        maxWaitSeconds: TimeInterval = 300
    ) async {
        let deadline = Date().addingTimeInterval(maxWaitSeconds)
        while Date() < deadline {
            let messages = await repository.loadMessages(threadID: threadID, limit: nil, before: nil)
            if messages.contains(where: { $0.clientMessageID == assistantClientMessageID }) {
                await insertHealthSleepVisualization(
                    threadID: threadID,
                    assistantClientMessageID: assistantClientMessageID,
                    model: model
                )
                return
            }
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
    }

    private func insertHealthSleepVisualization(
        threadID: UUID,
        assistantClientMessageID: UUID,
        model: ChatHealthSleepModel
    ) async {
        guard let data = try? JSONEncoder().encode(model),
              let json = String(data: data, encoding: .utf8) else { return }

        let messages = await repository.loadMessages(threadID: threadID, limit: nil, before: nil)
        guard let msg = messages.first(where: { $0.clientMessageID == assistantClientMessageID }) else { return }

        var attachments = msg.attachments
        if let i = attachments.firstIndex(where: { $0.type == .healthSleepVisualization }) {
            attachments[i] = attachments[i].replacing(type: .healthSleepVisualization, text: json)
        } else {
            attachments.append(ChatAttachment(type: .healthSleepVisualization, text: json))
        }

        await repository.updateMessageAttachments(
            clientMessageID: assistantClientMessageID,
            attachments: attachments,
            markPendingForSync: true
        )

        let store = stateStore
        await MainActor.run {
            store?.updateMessageAttachments(
                threadID: threadID,
                clientMessageID: assistantClientMessageID,
                attachments: attachments
            )
        }
    }

    // MARK: - Capture Message Card

    /// 等待助手消息就绪后，将拍照/上传卡片附件异步写入消息
    func insertCaptureCardWhenAssistantMessageReady(
        threadID: UUID,
        assistantClientMessageID: UUID,
        payload: ChatCaptureMessageCardPayload,
        maxWaitSeconds: TimeInterval = 300
    ) async {
        let deadline = Date().addingTimeInterval(maxWaitSeconds)
        while Date() < deadline {
            let messages = await repository.loadMessages(threadID: threadID, limit: nil, before: nil)
            if messages.contains(where: { $0.clientMessageID == assistantClientMessageID }) {
                await insertCaptureCard(
                    threadID: threadID,
                    assistantClientMessageID: assistantClientMessageID,
                    payload: payload
                )
                return
            }
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
    }

    private func insertCaptureCard(
        threadID: UUID,
        assistantClientMessageID: UUID,
        payload: ChatCaptureMessageCardPayload
    ) async {
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else { return }

        let messages = await repository.loadMessages(threadID: threadID, limit: nil, before: nil)
        guard let msg = messages.first(where: { $0.clientMessageID == assistantClientMessageID }) else { return }

        var attachments = msg.attachments
        if let i = attachments.firstIndex(where: { $0.type == .captureMessageCard }) {
            attachments[i] = attachments[i].replacing(type: .captureMessageCard, text: json)
        } else {
            attachments.append(ChatAttachment(type: .captureMessageCard, text: json))
        }

        await repository.updateMessageAttachments(
            clientMessageID: assistantClientMessageID,
            attachments: attachments,
            markPendingForSync: true
        )

        let store = stateStore
        await MainActor.run {
            store?.updateMessageAttachments(
                threadID: threadID,
                clientMessageID: assistantClientMessageID,
                attachments: attachments
            )
        }
    }

    // MARK: - Structured Health Cards

    /// 从消息中解码结构化医疗卡片数据
    /// - Parameter message: 聊天消息
    /// - Returns: 解码后的结构化卡片对象，失败返回 nil
    private static func decodeBlob(from message: ChatMessage) -> StructuredHealthCardsBlob? {
        // 查找类型为 structuredHealthCards 的附件
        guard let raw = message.attachments.first(where: { $0.type == .structuredHealthCards })?.text,
              let data = raw.data(using: .utf8) else {
            return nil
        }
        // JSON 解码
        return try? JSONDecoder().decode(StructuredHealthCardsBlob.self, from: data)
    }

    /// 替换或插入结构化医疗卡片附件
    /// 如果已有该类型附件则覆盖，没有则追加
    /// - Parameters:
    ///   - attachments: 原始附件列表
    ///   - json: 新的卡片 JSON 字符串
    /// - Returns: 处理后的新附件列表
    private static func replaceOrInsertStructuredHealthCardsAttachment(
        in attachments: [ChatAttachment],
        json: String
    ) -> [ChatAttachment] {
        var out = attachments
        // 查找已存在的结构化卡片附件索引
        if let i = out.firstIndex(where: { $0.type == .structuredHealthCards }) {
            // 替换原有附件内容
            out[i] = out[i].replacing(type: .structuredHealthCards, text: json)
        } else {
            // 不存在则新增附件
            out.append(ChatAttachment(type: .structuredHealthCards, text: json))
        }
        return out
    }
}
