import Foundation

/// 结构化健康卡片合并协调器
/// 负责统一处理健康卡片、睡眠/运动可视化、知识卡片、任务卡片等富内容块的流式合并、数据库持久化与状态同步
/// 线程安全，遵循 @unchecked Sendable 协议，可在多任务/异步环境中安全使用
final class StructuredHealthCardMergeCoordinator: @unchecked Sendable {
    // MARK: - 内部数据结构
    /// 展示层补丁：用于封装待合并的消息块，统一处理空值判断与数据库合并条件判断
    private struct PresentationPatch: Sendable {
        /// 待合并的聊天消息块列表
        let blocks: [ChatMessageBlock]

        /// 是否为空补丁（无消息块）
        var isEmpty: Bool {
            blocks.isEmpty
        }

        /// 是否需要执行数据库合并
        /// 健康卡片、睡眠可视化、运动可视化需要落库，其他类型仅做流式展示
        var requiresDatabaseMerge: Bool {
            blocks.contains { block in
                switch block.kind {
                case .structuredHealthCards,
                        .sleepVisualization,
                        .workoutVisualization:
                    return true
                default:
                    return false
                }
            }
        }
    }

    // MARK: - 依赖属性
    /// 聊天数据仓库，负责消息数据的加载、更新、持久化
    private let repository: any ChatRepository
    /// 聊天状态存储，弱引用避免循环引用，负责UI层状态刷新
    private weak var stateStore: ChatStateStore?

    // MARK: - 初始化
    /// 构造方法
    /// - Parameter repository: 聊天数据仓库实例
    init(repository: any ChatRepository) {
        self.repository = repository
    }

    /// 注册状态存储
    /// - Parameter stateStore: 聊天状态存储实例
    func register(stateStore: ChatStateStore) {
        self.stateStore = stateStore
    }

    // MARK: - Public streaming / async entry points
    /// 公开入口：将富展示内容合并到流式缓存
    /// - Parameters:
    ///   - threadID: 会话ID
    ///   - blocks: 待合并的消息块
    func mergeRichPresentationIntoStreamingCache(
        threadID: UUID,
        blocks: [ChatMessageBlock]
    ) async {
        await mergeRichPresentationIntoStreamingCache(
            threadID: threadID,
            patch: PresentationPatch(blocks: blocks)
        )
    }

    /// 公开入口：等待助手消息就绪后，追加合并富展示内容
    /// - Parameters:
    ///   - threadID: 会话ID
    ///   - assistantClientMessageID: 助手客户端消息ID
    ///   - blocks: 待合并的消息块
    ///   - maxWaitSeconds: 最大等待时间，默认300秒
    func mergeAppendRichPresentationWhenAssistantMessageReady(
        threadID: UUID,
        assistantClientMessageID: UUID,
        blocks: [ChatMessageBlock],
        maxWaitSeconds: TimeInterval = 300
    ) async {
        await mergeAppendRichPresentationWhenAssistantMessageReady(
            threadID: threadID,
            assistantClientMessageID: assistantClientMessageID,
            patch: PresentationPatch(blocks: blocks),
            maxWaitSeconds: maxWaitSeconds
        )
    }

    /// 公开入口：等待助手消息就绪后，追加合并结构化健康卡片数据
    /// - Parameters:
    ///   - threadID: 会话ID
    ///   - assistantClientMessageID: 助手客户端消息ID
    ///   - delta: 增量健康卡片数据
    ///   - maxWaitSeconds: 最大等待时间
    func mergeAppendWhenAssistantMessageReady(
        threadID: UUID,
        assistantClientMessageID: UUID,
        delta: StructuredHealthCardsBlob,
        maxWaitSeconds: TimeInterval = 300
    ) async {
        await waitUntilMessageReady(
            threadID: threadID,
            assistantClientMessageID: assistantClientMessageID,
            maxWaitSeconds: maxWaitSeconds
        ) { message in
            // 解码已有健康卡片数据，不存在则使用空实例
            var blob = Self.decodeStructuredHealthBlob(from: message) ?? .empty
            // 追加增量数据：药物、处方、检查报告、病历
            blob.medications.append(contentsOf: delta.medications)
            blob.prescriptions.append(contentsOf: delta.prescriptions)
            blob.examReports.append(contentsOf: delta.examReports)
            blob.medicalCases.append(contentsOf: delta.medicalCases)
            
            // 校验JSON编码合法性，非法则返回空
            guard (try? JSONEncoder.default.encode(blob)) != nil else {
                return nil
            }
            
            // 构建结构化健康卡片补丁
            return PresentationPatch(
                blocks: [
                    ChatMessageBlock(
                        kind: .structuredHealthCards,
                        structuredHealthCards: blob,
                        createdAt: message.createdAt,
                        updatedAt: Date()
                    )
                ]
            )
        }
    }

    /// 插入结构化健康卡片（等待助手消息就绪）
    /// 与睡眠/运动可视化卡同构：生成一块带工具调用锚点的结构化健康卡片，并走统一富卡片合并入口。
    /// - Parameters:
    ///   - threadID: 会话ID
    ///   - assistantClientMessageID: 助手消息ID
    ///   - delta: 健康卡片数据
    ///   - anchorToolCallID: 工具调用锚点ID，用于UI对齐
    ///   - maxWaitSeconds: 最大等待时间
    func insertStructuredHealthCardsWhenAssistantMessageReady(
        threadID: UUID,
        assistantClientMessageID: UUID,
        delta: StructuredHealthCardsBlob,
        anchorToolCallID: String? = nil,
        maxWaitSeconds: TimeInterval = 300
    ) async {
        // 校验数据可序列化
        guard (try? JSONEncoder.default.encode(delta)) != nil else { return }

        // 构建带锚点的健康卡片消息块补丁
        let patch = PresentationPatch(
            blocks: [
                ChatMessageBlock(
                    anchor: anchorToolCallID.map(ChatBlockAnchor.toolCall),
                    kind: .structuredHealthCards,
                    toolCallID: anchorToolCallID,
                    structuredHealthCards: delta
                )
            ]
        )

        await mergeAppendRichPresentationWhenAssistantMessageReady(
            threadID: threadID,
            assistantClientMessageID: assistantClientMessageID,
            patch: patch,
            maxWaitSeconds: maxWaitSeconds
        )
    }

    /// 直接追加合并结构化健康卡片数据（无需等待消息就绪）
    /// - Parameters:
    ///   - threadID: 会话ID
    ///   - assistantClientMessageID: 助手消息ID
    ///   - delta: 增量健康数据
    func mergeAppend(
        threadID: UUID,
        assistantClientMessageID: UUID,
        delta: StructuredHealthCardsBlob
    ) async {
        // 加载会话消息
        let messages = await repository.loadMessages(threadID: threadID, limit: nil, before: nil)
        // 查找目标助手消息
        guard let message = messages.first(where: { $0.clientMessageID == assistantClientMessageID }) else { return }

        // 合并增量健康数据
        var blob = Self.decodeStructuredHealthBlob(from: message) ?? .empty
        blob.medications.append(contentsOf: delta.medications)
        blob.prescriptions.append(contentsOf: delta.prescriptions)
        blob.examReports.append(contentsOf: delta.examReports)
        blob.medicalCases.append(contentsOf: delta.medicalCases)
        
        guard (try? JSONEncoder.default.encode(blob)) != nil else { return }

        // 构建消息块补丁
        let patch = PresentationPatch(
            blocks: [
                ChatMessageBlock(
                    kind: .structuredHealthCards,
                    structuredHealthCards: blob,
                    createdAt: message.createdAt,
                    updatedAt: Date()
                )
            ]
        )
        
        // 提交合并到数据库与UI状态
        await commitPatch(
            threadID: threadID,
            assistantClientMessageID: assistantClientMessageID,
            message: message,
            patch: patch
        )
    }

    /// 插入知识卡片预览（等待助手消息就绪）
    /// - Parameters:
    ///   - threadID: 会话ID
    ///   - assistantClientMessageID: 助手消息ID
    ///   - title: 卡片标题
    ///   - content: 卡片内容
    func mergeKnowledgeCardPreviewWhenAssistantMessageReady(
        threadID: UUID,
        assistantClientMessageID: UUID,
        title: String,
        content: String
    ) async {
        await insertKnowledgeCardsWhenAssistantMessageReady(
            threadID: threadID,
            assistantClientMessageID: assistantClientMessageID,
            cards: [ChatKnowledgeCard(title: title, content: content)],
            anchorToolCallID: nil
        )
    }

    /// 批量插入知识卡片（等待助手消息就绪）
    /// 与 `insertHealthSleepVisualizationWhenAssistantMessageReady` 同构：先合入流式缓存，带工具调用锚点以便与工具行对齐。
    /// - Parameters:
    ///   - threadID: 会话ID
    ///   - assistantClientMessageID: 助手消息ID
    ///   - cards: 知识卡片列表
    ///   - anchorToolCallID: 工具锚点ID
    func insertKnowledgeCardsWhenAssistantMessageReady(
        threadID: UUID,
        assistantClientMessageID: UUID,
        cards: [ChatKnowledgeCard],
        anchorToolCallID: String? = nil
    ) async {
        guard cards.isEmpty == false else { return }
        guard (try? JSONEncoder.default.encode(cards)) != nil else { return }

        // 构建知识卡片消息块补丁
        let patch = PresentationPatch(
            blocks: [
                ChatMessageBlock(
                    anchor: anchorToolCallID.map(ChatBlockAnchor.toolCall),
                    kind: .knowledgeCards,
                    toolCallID: anchorToolCallID,
                    knowledgeCards: cards
                )
            ]
        )

        // 合并到流式缓存
        await mergeRichPresentationIntoStreamingCache(threadID: threadID, patch: patch)
    }

    /// 插入健康运动可视化卡片（等待助手消息就绪）
    /// - Parameters:
    ///   - threadID: 会话ID
    ///   - assistantClientMessageID: 助手消息ID
    ///   - model: 运动可视化数据模型
    ///   - anchorToolCallID: 工具锚点ID
    ///   - maxWaitSeconds: 最大等待时间
    func insertHealthWorkoutVisualizationWhenAssistantMessageReady(
        threadID: UUID,
        assistantClientMessageID: UUID,
        model: ChatHealthWorkoutModel,
        anchorToolCallID: String? = nil,
        maxWaitSeconds: TimeInterval = 300
    ) async {
        guard (try? JSONEncoder.default.encode(model)) != nil else { return }

        let patch = PresentationPatch(
            blocks: [
                ChatMessageBlock(
                    anchor: anchorToolCallID.map(ChatBlockAnchor.toolCall),
                    kind: .workoutVisualization,
                    toolCallID: anchorToolCallID,
                    workoutVisualization: model
                )
            ]
        )

        await mergeAppendRichPresentationWhenAssistantMessageReady(
            threadID: threadID,
            assistantClientMessageID: assistantClientMessageID,
            patch: patch,
            maxWaitSeconds: maxWaitSeconds
        )
    }

    /// 插入健康睡眠可视化卡片（等待助手消息就绪）
    /// - Parameters:
    ///   - threadID: 会话ID
    ///   - assistantClientMessageID: 助手消息ID
    ///   - model: 睡眠可视化数据模型
    ///   - anchorToolCallID: 工具锚点ID
    ///   - maxWaitSeconds: 最大等待时间
    func insertHealthSleepVisualizationWhenAssistantMessageReady(
        threadID: UUID,
        assistantClientMessageID: UUID,
        model: ChatHealthSleepModel,
        anchorToolCallID: String? = nil,
        maxWaitSeconds: TimeInterval = 300
    ) async {
        guard (try? JSONEncoder.default.encode(model)) != nil else { return }

        let patch = PresentationPatch(
            blocks: [
                ChatMessageBlock(
                    anchor: anchorToolCallID.map(ChatBlockAnchor.toolCall),
                    kind: .sleepVisualization,
                    toolCallID: anchorToolCallID,
                    sleepVisualization: model
                )
            ]
        )

        await mergeAppendRichPresentationWhenAssistantMessageReady(
            threadID: threadID,
            assistantClientMessageID: assistantClientMessageID,
            patch: patch,
            maxWaitSeconds: maxWaitSeconds
        )
    }

    /// 插入任务卡片（等待助手消息就绪）
    /// 与 `insertHealthSleepVisualizationWhenAssistantMessageReady` 同构：先合入流式缓存，再在助手消息已落库且锚点工具行存在时写入持久化与待同步。
    /// - Parameters:
    ///   - threadID: 会话ID
    ///   - assistantClientMessageID: 助手消息ID
    ///   - taskCards: 任务卡片列表
    ///   - anchorToolCallID: 工具锚点ID
    ///   - maxWaitSeconds: 最大等待时间
    func insertTaskCardsWhenAssistantMessageReady(
        threadID: UUID,
        assistantClientMessageID: UUID,
        taskCards: [TaskCard],
        anchorToolCallID: String? = nil,
        maxWaitSeconds: TimeInterval = 300
    ) async {
        guard taskCards.isEmpty == false else { return }
        let patch = PresentationPatch(
            blocks: [
                ChatMessageBlock(
                    anchor: anchorToolCallID.map(ChatBlockAnchor.toolCall),
                    kind: .taskCards,
                    toolCallID: anchorToolCallID,
                    taskCards: taskCards
                )
            ]
        )

        await mergeRichPresentationIntoStreamingCache(threadID: threadID, patch: patch)
    }

    /// 插入采集卡片（等待助手消息就绪）
    /// - Parameters:
    ///   - threadID: 会话ID
    ///   - assistantClientMessageID: 助手消息ID
    ///   - payload: 采集卡片数据
    func insertCaptureCardWhenAssistantMessageReady(
        threadID: UUID,
        assistantClientMessageID: UUID,
        payload: ChatCaptureMessageCardPayload
    ) async {
        guard (try? JSONEncoder.default.encode(payload)) != nil else { return }
        await mergeRichPresentationIntoStreamingCache(
            threadID: threadID,
            patch: PresentationPatch(
                blocks: [
                    ChatMessageBlock(
                        kind: .captureCard,
                        captureMessageCard: payload
                    )
                ]
            )
        )
    }

    // MARK: - Core pipeline
    /// 核心管道：将富展示补丁合并到流式缓存
    /// - Parameters:
    ///   - threadID: 会话ID
    ///   - patch: 展示补丁
    private func mergeRichPresentationIntoStreamingCache(
        threadID: UUID,
        patch: PresentationPatch
    ) async {
        guard patch.isEmpty == false else { return }
        let store = stateStore
        // 主线程更新UI流式展示状态
        await MainActor.run {
            store?.mergeStreamingAssistantPresentation(
                threadID: threadID,
                incomingBlocks: patch.blocks
            )
        }
    }

    /// 核心管道：等待消息就绪后合并富展示补丁
    /// - Parameters:
    ///   - threadID: 会话ID
    ///   - assistantClientMessageID: 助手消息ID
    ///   - patch: 展示补丁
    ///   - maxWaitSeconds: 最大等待时间
    private func mergeAppendRichPresentationWhenAssistantMessageReady(
        threadID: UUID,
        assistantClientMessageID: UUID,
        patch: PresentationPatch,
        maxWaitSeconds: TimeInterval
    ) async {
        guard patch.isEmpty == false else { return }
        // 先更新流式缓存
        await mergeRichPresentationIntoStreamingCache(threadID: threadID, patch: patch)
        // 仅需要落库的类型执行数据库合并
        guard patch.requiresDatabaseMerge else { return }
//        // 等待消息就绪后提交补丁
//        await waitUntilMessageReady(
//            threadID: threadID,
//            assistantClientMessageID: assistantClientMessageID,
//            maxWaitSeconds: maxWaitSeconds
//        ) { _ in patch }
    }

    /// 核心管道：循环等待消息就绪，就绪后执行补丁构建与提交
    /// - Parameters:
    ///   - threadID: 会话ID
    ///   - assistantClientMessageID: 目标消息ID
    ///   - maxWaitSeconds: 最大等待时间
    ///   - makePatch: 补丁构建闭包
    private func waitUntilMessageReady(
        threadID: UUID,
        assistantClientMessageID: UUID,
        maxWaitSeconds: TimeInterval,
        makePatch: (ChatMessage) -> PresentationPatch?
    ) async {
        let deadline = Date().addingTimeInterval(maxWaitSeconds)
        // 超时轮询等待消息就绪
        while Date() < deadline {
            let messages = await repository.loadMessages(threadID: threadID, limit: nil, before: nil)
            if let message = messages.first(where: { $0.clientMessageID == assistantClientMessageID }),
               let patch = makePatch(message) {
                // 消息就绪，提交合并补丁
                await commitPatch(
                    threadID: threadID,
                    assistantClientMessageID: assistantClientMessageID,
                    message: message,
                    patch: patch
                )
                return
            }
            // 每次轮询间隔60ms
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
    }

    /// 核心管道：提交补丁，合并消息块并持久化+同步UI
    /// - Parameters:
    ///   - threadID: 会话ID
    ///   - assistantClientMessageID: 助手消息ID
    ///   - message: 目标消息
    ///   - patch: 待合并补丁
    private func commitPatch(
        threadID: UUID,
        assistantClientMessageID: UUID,
        message: ChatMessage,
        patch: PresentationPatch
    ) async {
        guard patch.isEmpty == false else { return }
        // 合并原有消息块与新消息块
        let combinedBlocks = ChatMessageBlockBuilder.mergeRichBlocks(
            existingBlocks: message.blocks,
            incomingBlocks: patch.blocks
        )

        // 更新数据库消息块，标记为待同步
        await repository.updateMessageBlocks(
            clientMessageID: assistantClientMessageID,
            blocks: combinedBlocks,
            markPendingForSync: true
        )

        // 主线程更新UI状态快照
        let store = stateStore
        await MainActor.run {
            store?.updateMessageBlocksSnapshot(
                threadID: threadID,
                clientMessageID: assistantClientMessageID,
                blocks: combinedBlocks
            )
        }
    }

    /// 工具方法：从消息中解码结构化健康卡片数据
    /// - Parameter message: 聊天消息
    /// - Returns: 健康卡片数据（可选）
    private static func decodeStructuredHealthBlob(from message: ChatMessage) -> StructuredHealthCardsBlob? {
        message.blocks.last(where: { $0.kind == .structuredHealthCards })?.structuredHealthCards
    }
}
