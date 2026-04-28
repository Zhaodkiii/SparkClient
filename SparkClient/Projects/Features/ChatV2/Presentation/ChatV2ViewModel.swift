import Combine
import Foundation
import SwiftUI

@MainActor
final class ChatV2ViewModel: ObservableObject {
    struct DisplayMessage: Identifiable, Equatable {
        let id: UUID
        let role: ChatV2Role
        let document: ChatV2MessageDocument
        let isStreaming: Bool
    }

    @Published private(set) var threads: [ChatV2ThreadRecord] = []
    @Published private(set) var messages: [ChatV2MessageRecord] = []
    @Published private(set) var streamingAssistantState: ChatV2StreamingMessageState?
    @Published private(set) var selectedThreadID: UUID?
    @Published private(set) var isBootstrapping = false
    @Published private(set) var isSending = false
    @Published var composerText = ""

    let ownerAccountID: Int64

    private let snapshotStore: any ChatV2SnapshotStore
    private let logger: Logger
    private var bootstrapped = false

    init(
        ownerAccountID: Int64,
        snapshotStore: any ChatV2SnapshotStore,
        logger: Logger
    ) {
        self.ownerAccountID = ownerAccountID
        self.snapshotStore = snapshotStore
        self.logger = logger
    }

    var displayMessages: [DisplayMessage] {
        var result = messages.map {
            DisplayMessage(
                id: $0.id,
                role: $0.role,
                document: $0.document,
                isStreaming: false
            )
        }
        if let streamingAssistantState {
            result.append(
                DisplayMessage(
                    id: streamingAssistantState.id,
                    role: streamingAssistantState.role,
                    document: streamingAssistantState.finalizedDocument(includeResidualToolStates: true),
                    isStreaming: true
                )
            )
        }
        return result
    }

    /// 首次进入 V2 页面时，自动准备一条独立线程。
    func bootstrapIfNeeded() async {
        guard bootstrapped == false else { return }
        bootstrapped = true
        isBootstrapping = true
        defer { isBootstrapping = false }

        logger.info("对话V2 开始启动，准备独立线程与消息列表", module: .general)
        do {
            let loadedThreads = try await snapshotStore.loadThreads(ownerAccountID: ownerAccountID)
            if loadedThreads.isEmpty {
                let newThread = makeThread(title: "V2 新会话")
                try await snapshotStore.insertThread(newThread)
                threads = [newThread]
                selectedThreadID = newThread.id
                messages = []
                logger.info("对话V2 启动时自动创建首个线程 id=\(shortID(newThread.id))", module: .general)
            } else {
                threads = loadedThreads
                selectedThreadID = loadedThreads.first?.id
                if let selectedThreadID {
                    try await loadMessages(threadID: selectedThreadID)
                }
            }
        } catch {
            logger.error("对话V2 启动失败 error=\(error.localizedDescription)", module: .general)
        }
    }

    func createThread() async {
        let title = "V2 会话 \(threads.count + 1)"
        let thread = makeThread(title: title)
        do {
            try await snapshotStore.insertThread(thread)
            threads.insert(thread, at: 0)
            selectedThreadID = thread.id
            messages = []
            logger.info("对话V2 创建新线程成功 id=\(shortID(thread.id)) title=\(title)", module: .general)
        } catch {
            logger.error("对话V2 创建线程失败 error=\(error.localizedDescription)", module: .general)
        }
    }

    func selectThread(_ threadID: UUID) async {
        selectedThreadID = threadID
        do {
            try await loadMessages(threadID: threadID)
            logger.debug("对话V2 切换线程 id=\(shortID(threadID))", module: .general)
        } catch {
            logger.error("对话V2 切换线程失败 error=\(error.localizedDescription)", module: .general)
        }
    }

    func sendCurrentInput() async {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return }
        guard let threadID = selectedThreadID else { return }
        guard isSending == false else { return }

        isSending = true
        composerText = ""
        defer { isSending = false }

        do {
            logger.info("对话V2 开始发送用户消息 thread=\(shortID(threadID)) textLen=\(text.count)", module: .general)
            let now = Date()
            let userMessage = ChatV2MessageRecord(
                threadID: threadID,
                ownerAccountID: ownerAccountID,
                role: .user,
                status: .committed,
                document: ChatV2MessageDocument(nodes: [.text(.init(text: text))]),
                createdAt: now,
                updatedAt: now,
                committedAt: now
            )
            try await snapshotStore.commitMessageSnapshot(userMessage)

            if let index = threads.firstIndex(where: { $0.id == threadID }) {
                let previous = threads[index]
                let updatedThread = ChatV2ThreadRecord(
                    id: previous.id,
                    ownerAccountID: previous.ownerAccountID,
                    title: previous.title,
                    scenario: previous.scenario,
                    memberID: previous.memberID,
                    status: previous.status,
                    createdAt: previous.createdAt,
                    updatedAt: now,
                    lastSyncedAt: previous.lastSyncedAt
                )
                threads[index] = updatedThread
                try await snapshotStore.upsertThread(updatedThread)
            }

            try await loadMessages(threadID: threadID)
            try await runAssistantSleepDemo(threadID: threadID, seedText: text)
        } catch {
            logger.error("对话V2 发送消息失败 error=\(error.localizedDescription)", module: .general)
        }
    }

    /// 这里先接一条最小垂直链路：
    /// 用户文本 -> assistant 流式文本 -> 工具运行状态 -> 睡眠卡 -> 最终消息快照。
    private func runAssistantSleepDemo(threadID: UUID, seedText: String) async throws {
        let startedAt = Date()
        var draftState = ChatV2StreamingMessageState(threadID: threadID, role: .assistant)
        let draftRecord = ChatV2MessageRecord(
            id: draftState.id,
            threadID: threadID,
            ownerAccountID: ownerAccountID,
            clientMessageID: draftState.id,
            role: .assistant,
            status: .streaming,
            document: .empty,
            createdAt: startedAt,
            updatedAt: startedAt
        )
        try await snapshotStore.insertDraftMessage(draftRecord)

        for chunk in makeAssistantTextChunks(for: seedText) {
            try await Task.sleep(nanoseconds: 280_000_000)
            draftState.appendText(chunk)
            streamingAssistantState = draftState
            logger.debug("对话V2 流式追加文本 chunkLen=\(chunk.count)", module: .general)
        }

        let toolID = "sleep-tool-\(draftState.id.uuidString.lowercased())"
        draftState.upsertToolState(
            .init(
                id: toolID,
                toolName: "sleep_analysis",
                state: "running",
                description: "正在分析最近一晚的睡眠结构"
            )
        )
        streamingAssistantState = draftState
        logger.info("对话V2 已插入工具运行状态 tool=\(toolID)", module: .general)

        try await Task.sleep(nanoseconds: 600_000_000)

        draftState.appendBlock(id: toolID, payload: .sleepVisualization(makeSleepPayload()))
        streamingAssistantState = draftState
        logger.info("对话V2 已生成睡眠卡片并插入流式文档", module: .general)

        let committedAt = Date()
        let finalRecord = ChatV2MessageRecord(
            id: draftRecord.id,
            threadID: threadID,
            ownerAccountID: ownerAccountID,
            clientMessageID: draftRecord.clientMessageID,
            serverMessageID: draftRecord.serverMessageID,
            role: .assistant,
            status: .committed,
            document: draftState.finalizedDocument(),
            version: 1,
            createdAt: draftRecord.createdAt,
            updatedAt: committedAt,
            committedAt: committedAt
        )
        try await snapshotStore.commitMessageSnapshot(finalRecord)
        streamingAssistantState = nil
        try await loadMessages(threadID: threadID)
        logger.info("对话V2 assistant 最终快照已落库 id=\(shortID(finalRecord.id))", module: .general)
    }

    private func loadMessages(threadID: UUID) async throws {
        messages = try await snapshotStore.loadMessages(threadID: threadID, limit: nil)
    }

    private func makeThread(title: String) -> ChatV2ThreadRecord {
        ChatV2ThreadRecord(
            ownerAccountID: ownerAccountID,
            title: title,
            scenario: .chat,
            status: .active
        )
    }

    private func makeAssistantTextChunks(for seedText: String) -> [String] {
        [
            "收到你的消息了。",
            "\n\n我先用 V2 独立链路演示一条完整响应：",
            "\n\n下面是一张由最终消息快照承载的睡眠分析卡片。",
            "\n\n本轮输入摘要：\(seedText.prefix(18))"
        ]
    }

    private func makeSleepPayload() -> ChatV2SleepVisualizationPayload {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .hour, value: 0, to: day) ?? day
        let stages: [ChatV2SleepStagePayload] = [
            .init(stage: .core, startAt: start, endAt: start.addingTimeInterval(90 * 60)),
            .init(stage: .deep, startAt: start.addingTimeInterval(90 * 60), endAt: start.addingTimeInterval(150 * 60)),
            .init(stage: .rem, startAt: start.addingTimeInterval(150 * 60), endAt: start.addingTimeInterval(210 * 60)),
            .init(stage: .core, startAt: start.addingTimeInterval(210 * 60), endAt: start.addingTimeInterval(420 * 60)),
            .init(stage: .awake, startAt: start.addingTimeInterval(420 * 60), endAt: start.addingTimeInterval(438 * 60))
        ]
        return ChatV2SleepVisualizationPayload(
            day: day,
            totalSleepMinutes: 420,
            deepSleepMinutes: 60,
            coreSleepMinutes: 300,
            remSleepMinutes: 60,
            awakeMinutes: 18,
            stages: stages
        )
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}
