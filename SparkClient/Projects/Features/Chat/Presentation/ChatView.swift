import SwiftUI
import AVFoundation
import UIKit
import Combine

struct ChatView: View {
    let threadID: UUID
    @ObservedObject var stateStore: ChatStateStore
    @ObservedObject var listViewModel: ChatListViewModel
    @ObservedObject var detailViewModel: ChatDetailViewModel

    @State private var hasLoaded = false
    @State private var lastStreamingAutoScrollGeneration: UInt64 = 0
    @State private var deletedMessageIDs: Set<UUID> = []
    @State private var translatedTexts: [UUID: String] = [:]
    @State private var isTranslatingMessageIDs: Set<UUID> = []
    @State private var mathModeMessageIDs: Set<UUID> = []
    /// 用户在本地“生成预览”得到的知识卡（尚未入库）。
    /// key = message.id，value = 该消息生成出的知识卡列表。
    @State private var generatedKnowledgeCards: [UUID: [ChatKnowledgeCard]] = [:]
    /// 正在保存中的知识卡 id，用于控制按钮 loading 与防重复点击。
    @State private var savingKnowledgeCardIDs: Set<UUID> = []
    /// 已保存成功的知识卡 id，用于展示“已保存”状态并禁用按钮。
    @State private var savedKnowledgeCardIDs: Set<UUID> = []
    @State private var selectedTextSheet: SelectableTextPayload?
    @StateObject private var speechHelper = ChatSpeechHelper()
    @State private var isSavingMessageIDs: Set<UUID> = []
    @State private var savedMessageIDs: Set<UUID> = []
    @State private var taskCardLoadingIDs: Set<Int> = []
    @State private var ignoredTaskCardIDs: Set<Int> = []
    @State private var createdTaskCardIDs: Set<Int> = []
    @AppStorage(ChatComposerStyle.appStorageKey) private var composerStyleRaw = ChatComposerStyle.signal.rawValue
    @StateObject private var taskManager = TaskManager.shared
    private let logger: Logger = ConsoleLogger()

    private var reasoningRefreshId: String {
        let name = stateStore.composerDraft(for: threadID).runtimeFlags.selectedChatModelName ?? "-"
        return "\(threadID.uuidString)|\(name)"
    }

    private var composerStyle: ChatComposerStyle {
        ChatComposerStyle(rawValue: composerStyleRaw) ?? .signal
    }

    private var visibleMessages: [ChatMessage] {
        stateStore.selectedMessages.filter { deletedMessageIDs.contains($0.id) == false }
    }

    private var hasMoreMessages: Bool {
        stateStore.hasMoreMessages(for: threadID)
    }

    private var isLoadingMoreMessages: Bool {
        stateStore.isLoadingMoreMessages(for: threadID)
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList

            Group {
                switch composerStyle {
                case .signal:
                    ChatComposerView(
                        threadID: threadID,
                        stateStore: stateStore,
                        onSend: {
                            KeyboardDismissHelper.dismissKeyboard()
                            Task { await detailViewModel.sendCurrentDraft() }
                        }
                    )
                case .hanlin:
                    HanlinChatComposerView(
                        threadID: threadID,
                        modelReasoning: detailViewModel.reasoningToolbarContext,
                        stateStore: stateStore,
                        modelRows: detailViewModel.chatScenarioModels,
                        onSend: {
                            KeyboardDismissHelper.dismissKeyboard()
                            Task { await detailViewModel.sendCurrentDraft() }
                        }
                    )
                }
            }
        }
        .navigationTitle(stateStore.selectedThread?.listDisplayTitle ?? L10n.text("chat.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker(L10n.text("chat.composer.style.title"), selection: $composerStyleRaw) {
                        Text(L10n.text("chat.composer.style.signal")).tag(ChatComposerStyle.signal.rawValue)
                        Text(L10n.text("chat.composer.style.hanlin")).tag(ChatComposerStyle.hanlin.rawValue)
                    }
                } label: {
                    Label(L10n.text("chat.composer.style.title"), systemImage: "rectangle.split.2x1")
                }
            }
        }
        .task {
            guard hasLoaded == false else { return }
            hasLoaded = true
            listViewModel.selectThread(threadID)
            await detailViewModel.loadMessagesIfNeeded(for: threadID)
        }
        .task(id: threadID) {
            await detailViewModel.refreshChatModelPicker()
        }
        .task(id: reasoningRefreshId) {
            await detailViewModel.refreshReasoningToolbarContext(for: threadID)
        }
        .sheet(item: $selectedTextSheet) { payload in
            NavigationView {
                ScrollView {
                    Text(payload.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle(payload.title)
            }
            .navigationViewStyle(.stack)
        }
        .onAppear {
            Task { await detailViewModel.chatPageDidAppear() }
        }
        .onDisappear {
            Task { await detailViewModel.chatPageDidDisappear() }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if hasMoreMessages {
                        HStack {
                            Spacer()
                            if isLoadingMoreMessages {
                                ProgressView()
                            } else {
                                Text(L10n.text("chat.history.load_more"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .onAppear {
                            Task {
                                await detailViewModel.loadMoreMessages(for: threadID)
                            }
                        }
                    }

                    ForEach(visibleMessages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }
                    if stateStore.isSending {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }
                }
                .padding(.vertical, 16)
            }
            .chatScrollDismissesKeyboardInteractively()
            .onAppear {
                scrollToLastMessage(proxy: proxy, animated: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    scrollToLastMessage(proxy: proxy, animated: false)
                }
            }
            .onChange(of: visibleMessages.last?.id) { _ in
                scrollToLastMessage(proxy: proxy, animated: true)
            }
            .onChange(of: stateStore.streamingContentGeneration) { generation in
                let minGenerationStep: UInt64 = 4
                guard generation >= lastStreamingAutoScrollGeneration + minGenerationStep else { return }
                lastStreamingAutoScrollGeneration = generation
                scrollToLastMessage(proxy: proxy, animated: false)
            }
            .refreshable {
                await detailViewModel.sync()
                await detailViewModel.loadMessagesIfNeeded(for: threadID)
                await listViewModel.refreshThreads()
            }
        }
    }

    private func scrollToLastMessage(proxy: ScrollViewProxy, animated: Bool) {
        if let lastID = visibleMessages.last?.id {
            if animated {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }

    /// 对齐 AI_HLY 的 `isLastAssistantGroup` 语义：
    /// 仅最后一条助手消息在“流式思考中”时展示三行动态推理预览。
    private func isLastAssistantMessage(_ message: ChatMessage) -> Bool {
        guard message.role == .assistant else { return false }
        return visibleMessages.last(where: { $0.role == .assistant })?.id == message.id
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .assistant || message.role == .system {
                bubbleContent(message)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 40)
                bubbleContent(message)
            }
        }
        .padding(.trailing, 16)
    }

    /// 渲染单条聊天消息的气泡内容（根据消息角色和类型展示不同组件）
    /// - Parameter message: 聊天消息模型
    /// - Returns: 消息气泡视图
    private func bubbleContent(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // 从消息中解析出通用元数据
            let metadata = ChatMessageMetadata(message: message)
            
            // ============== 1. 助手消息：图片展示区域 ==============
            if message.role == .assistant {
                let imagePayloads = imagePayloads(from: message)
                // 如果有图片，渲染图片画廊
                if !imagePayloads.isEmpty {
                    ChatImageGalleryBlockView(images: imagePayloads)
                }
            }

            // ============== 2. 助手消息：思考过程（推理内容）展示 ==============
            if message.role == .assistant,
               let reasoning = message.reasoningContent?.trimmingCharacters(in: .whitespacesAndNewlines),
               !reasoning.isEmpty {
                ChatReasoningBlockView(
                    text: reasoning,                // 推理文本
                    timeText: formatReasoningTime(message.reasoningDurationMs),  // 推理耗时
                    isStreaming: message.deliveryState == .sending,              // 是否正在流式输出
                    isLastAssistantMessage: isLastAssistantMessage(message)      // 是否是最后一条助手消息
                )
            }

            // ============== 3. 助手消息：操作状态展示 ==============
            if message.role == .assistant,
               let operational = operationalMeta(from: message, metadata: metadata),
               isLastAssistantMessage(message) {
                ChatOperationalStatusBlockView(
                    operationalState: operational.state,         // 操作状态
                    operationalDescription: operational.description // 状态描述
                )
            }

            // ============== 4. 助手消息：工具调用内容展示 ==============
            if message.role == .assistant,
               let tool = toolMeta(from: message, metadata: metadata),
               shouldShowToolContentBlock(metadata: metadata) {
                ChatToolContentBlockView(
                    toolName: tool.name,             // 工具名称
                    toolContent: tool.content,       // 工具返回内容
                    isStreaming: message.deliveryState == .sending  // 是否正在流式输出
                )
            }


            // ============== 6. 助手消息：知识卡片展示 ==============
            if message.role == .assistant {
                // 知识卡渲染优先：展示“消息附件中的卡 + 本地临时生成卡”的合并结果
                let cards = combinedKnowledgeCards(for: message, metadata: metadata)
                if !cards.isEmpty {
                    ChatKnowledgeCardListView(
                        cards: cards,
                        onSave: { card in
                            saveKnowledgeCard(card, from: message)  // 保存知识卡片
                        },
                        isSaving: { card in
                            savingKnowledgeCardIDs.contains(card.id)  // 是否正在保存
                        },
                        isSaved: { card in
                            savedKnowledgeCardIDs.contains(card.id)   // 是否已保存
                        }
                    )
                }
            }

            // ============== 7. 助手消息：翻译结果展示 ==============
            if message.role == .assistant,
               let translated = translatedText(for: message, metadata: metadata),
               !translated.isEmpty {
                ChatTranslatedBlockView(text: translated)
            }

            // ============== 8. 助手消息：地图/路线展示 ==============
            if message.role == .assistant {
                let locations = metadata.locations
                let routes = metadata.routes
                // 有地点或路线时展示地图
                if !locations.isEmpty || !routes.isEmpty {
                    ChatMapRouteBlockView(locations: locations, routes: routes)
                }
            }

            // ============== 9. 助手消息：日程/事件卡片展示 ==============
            if message.role == .assistant {
                let events = metadata.events
                if !events.isEmpty {
                    ChatEventsCardListView(events: events)
                }
            }

            // ============== 10. 助手消息：健康卡片 + 睡眠可视化 ==============
            if message.role == .assistant {
                let cards = metadata.healthCards
                if !cards.isEmpty {
                    ChatHealthCardListView(cards: cards)
                }
                // 睡眠数据图表
                if let sleep = metadata.sleepVisualization {
                    ChatSleepCardView(model: sleep)
                }
            }

            // ============== 11. 助手消息：HTML 内容预览 ==============
            if message.role == .assistant,
               let htmlContent = metadata.htmlContent,
               !htmlContent.isEmpty {
                ChatHTMLPreviewBlockView(htmlContent: htmlContent)
            }

            // ============== 12. 主文本内容（Markdown / 纯文本） ==============
            if shouldRenderMainMarkdown(for: message, metadata: metadata) {
                // 数学公式模式：等宽纯文本展示
                if mathModeMessageIDs.contains(message.id) {
                    Text(message.content)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // 普通模式：Markdown 渲染
                    Markdown(message.content)
                        .markdownTheme(.chatBubble(foreground: message.role == .user ? .white : .primary))
                }
            }

            // ============== 13. 消息发送失败：重试按钮 ==============
            if message.deliveryState == .failed {
                Button {
                    Task {
                        await detailViewModel.retryFailedMessage(clientMessageID: message.clientMessageID)
                    }
                } label: {
                    Text(L10n.text("common.retry"))
                        .font(.caption)
                }
            }

            // ============== 14. 消息操作按钮（复制/转发/删除等） ==============
            messageActions(message)
            
            
            // ============== 5. 助手消息：任务卡片展示 ==============
            if message.role == .assistant {
                // 过滤掉已忽略、已创建的任务卡片
                let taskCards = metadata.taskCards.filter { card in
                    !ignoredTaskCardIDs.contains(card.id) && !createdTaskCardIDs.contains(card.id)
                }
                // 渲染任务卡片列表
                if !taskCards.isEmpty {
                    ForEach(taskCards) { card in
                        TaskCardCell(
                            card: card,
                            onConfirm: { confirmTaskCard(card) },    // 确认任务
                            onIgnore: { ignoreTaskCard(card) },      // 忽略任务
                            isLoading: taskCardLoadingIDs.contains(card.id)  // 是否加载中
                        )
                    }
                }
            }
            
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            // 气泡背景：用户消息使用主题色，助手消息使用系统背景色
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(message.role == .user ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func toolMeta(from message: ChatMessage, metadata: ChatMessageMetadata) -> (name: String, content: String)? {
        let name = metadata.toolName ?? ""
        let rawContent = metadata.toolContent ?? ""
        guard rawContent.isEmpty == false else { return nil }
        return (name.isEmpty ? L10n.text("chat.bubble.tool.default_name") : name, rawContent)
    }

    private func shouldShowToolContentBlock(metadata: ChatMessageMetadata) -> Bool {
        true
    }

    /// 对齐 AI_HLY 的 operationalState / operationalDescription：
    /// - operationalState：当前工具执行状态（例如“正在使用工具：xxx”）
    /// - operationalDescription：工具过程描述（多行，UI 仅展示最近三行）
    private func operationalMeta(from message: ChatMessage, metadata: ChatMessageMetadata) -> (state: String, description: String)? {
        guard message.deliveryState == .sending else { return nil }
        let storedState = metadata.operationalState ?? ""
        let storedDesc = metadata.operationalDescription ?? ""
        if storedState.isEmpty == false || storedDesc.isEmpty == false {
            return (storedState, storedDesc)
        }
        guard let tool = toolMeta(from: message, metadata: metadata) else { return nil }
        let lines = tool.content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        let state: String
        if let first = lines.first, first.hasPrefix("使用工具：") {
            state = first
        } else {
            state = L10n.text("chat.bubble.tool.operating_prefix") + tool.name
        }
        let description = lines.dropFirst().joined(separator: "\n")
        return (state, description)
    }

    private func knowledgeCards(from message: ChatMessage) -> [ChatKnowledgeCard] {
        ChatMessageMetadata(message: message).knowledgeCards
    }

    private func combinedKnowledgeCards(for message: ChatMessage, metadata: ChatMessageMetadata? = nil) -> [ChatKnowledgeCard] {
        // 合并“持久化卡片 + 本地临时卡片”，并按 title+content 做去重。
        // 这样可以兼容：服务器返回卡片 + 用户手动点击“生成知识卡预览”。
        let persisted = metadata?.knowledgeCards ?? knowledgeCards(from: message)
        let generated = generatedKnowledgeCards[message.id] ?? []
        var dedup: Set<String> = []
        var merged: [ChatKnowledgeCard] = []
        for card in persisted + generated {
            let normalizedTitle = card.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedContent = card.content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let key = "\(normalizedTitle)|\(normalizedContent)"
            guard dedup.insert(key).inserted else { continue }
            merged.append(card)
        }
        return merged
    }

    private func formatReasoningTime(_ durationMs: Int64?) -> String? {
        guard let durationMs, durationMs > 0 else { return nil }
        let seconds = Double(durationMs) / 1_000
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let minutes = Int(seconds) / 60
        let remainSeconds = seconds.truncatingRemainder(dividingBy: 60)
        return String(format: "%dm %.1fs", minutes, remainSeconds)
    }

    private func shouldRenderMainMarkdown(for message: ChatMessage, metadata: ChatMessageMetadata? = nil) -> Bool {
        guard message.role == .assistant else { return true }
        guard message.kind == .tool else { return true }
        let resolvedMeta = metadata ?? ChatMessageMetadata(message: message)
        let trimmedContent = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedContent.isEmpty == false else { return false }
        let toolContent = resolvedMeta.toolContent ?? ""
        if toolContent.isEmpty {
            return true
        }
        return trimmedContent != toolContent
    }

    @ViewBuilder
    private func messageActions(_ message: ChatMessage) -> some View {
        if message.id == visibleMessages.last?.id {
            // 与 AI_HLY 交互一致：助手流式回复中隐藏底部操作栏，避免误触与视觉干扰。
            if message.role == .assistant, message.deliveryState == .sending {
                EmptyView()
            } else {
                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = message.content
                    } label: {
                        Image(systemName: "square.on.square")
                    }
                    .font(.caption)

                    Button(role: .destructive) {
                        deletedMessageIDs.insert(message.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .font(.caption)

                    if message.role == .assistant {
                        Button {
                            speechHelper.toggle(text: message.content, id: message.id)
                        } label: {
                            Image(systemName: speechHelper.isSpeaking(message.id) ? "pause.circle" : "waveform")
                        }
                        .font(.caption)

                        Button {
                            toggleTranslate(message)
                        } label: {
                            if isTranslatingMessageIDs.contains(message.id) {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: translatedText(for: message)?.isEmpty == false ? "trash" : "globe")
                            }
                        }
                        .font(.caption)

                        Button {
                            openNetworkSearch(with: message.content)
                        } label: {
                            Image(systemName: "network")
                        }
                        .font(.caption)

                        Button {
                            saveMessageToKnowledge(message)
                        } label: {
                            if isSavingMessageIDs.contains(message.id) {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: savedMessageIDs.contains(message.id) ? "checkmark.circle.fill" : "square.and.arrow.down")
                            }
                        }
                        .font(.caption)

                        Button {
                            generateKnowledgeCardsPreview(for: message)
                        } label: {
                            Image(systemName: combinedKnowledgeCards(for: message).isEmpty ? "backpack" : "backpack.fill")
                        }
                        .font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private func openNetworkSearch(with text: String) {
        let keyword = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard keyword.isEmpty == false else { return }
        let escaped = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        guard let url = URL(string: "https://www.bing.com/search?q=\(escaped)") else { return }
        UIApplication.shared.open(url)
    }

    private func saveMessageToKnowledge(_ message: ChatMessage) {
        guard isSavingMessageIDs.contains(message.id) == false else { return }
        guard savedMessageIDs.contains(message.id) == false else { return }
        isSavingMessageIDs.insert(message.id)
        Task {
            defer { isSavingMessageIDs.remove(message.id) }
            do {
                _ = try await detailViewModel.saveMessageAsKnowledge(
                    content: message.content,
                    suggestedTitle: nil
                )
                savedMessageIDs.insert(message.id)
            } catch {
                logger.error("保存消息到知识库失败：\(error.localizedDescription)", module: .general)
            }
        }
    }

    private func toggleTranslate(_ message: ChatMessage) {
        if translatedTexts[message.id]?.isEmpty == false {
            translatedTexts[message.id] = nil
            return
        }
        guard isTranslatingMessageIDs.contains(message.id) == false else { return }
        isTranslatingMessageIDs.insert(message.id)
        Task {
            defer { isTranslatingMessageIDs.remove(message.id) }
            do {
                let translated = try await detailViewModel.translateMessageText(message.content)
                translatedTexts[message.id] = translated.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                translatedTexts[message.id] = nil
            }
        }
    }

    /// 点击“创建任务”：直接创建 Task 总表与子任务，不再走 TaskCard 服务端接口。
    private func confirmTaskCard(_ card: TaskCard) {
        guard taskCardLoadingIDs.contains(card.id) == false else { return }
        taskCardLoadingIDs.insert(card.id)
        Task {
            defer { taskCardLoadingIDs.remove(card.id) }
            do {
                let payload = buildCreatePayload(from: card)
                try await taskManager.createTask(payload: payload)
                createdTaskCardIDs.insert(card.id)
                logger.info("任务卡片直接创建任务成功 card_id=\(card.id)", module: .general)
            } catch {
                logger.error("任务卡片直接创建任务失败 card_id=\(card.id) error=\(error.localizedDescription)", module: .general)
            }
        }
    }

    private func ignoreTaskCard(_ card: TaskCard) {
        ignoredTaskCardIDs.insert(card.id)
        logger.info("任务卡片本地忽略 card_id=\(card.id)", module: .general)
    }

    private func buildCreatePayload(from card: TaskCard) -> TaskCreatePayload {
        let base = parseJSONObject(card.taskPayload["task"]) ?? [:]
        let subMedical = parseJSONObject(card.taskPayload["task_medical"])
        let subExercise = parseJSONObject(card.taskPayload["task_exercise"])
        let subDiet = parseJSONObject(card.taskPayload["task_diet"])

        let startText = stringValue(base["start_time"]) ?? card.startTime.map(iso8601)
        let dueText = stringValue(base["due_time"]) ?? card.dueTime.map(iso8601)
        let repeatTypeRaw = intValue(base["repeat_type"]) ?? card.repeatType.rawValue
        let priorityRaw = intValue(base["priority"]) ?? card.priority.rawValue

        return TaskCreatePayload(
            member: intValue(base["member"]) ?? intValue(base["member_id"]) ?? card.member,
            title: stringValue(base["title"]) ?? card.title,
            description: stringValue(base["description"]) ?? card.description,
            type: card.type,
            status: .pending,
            startTime: startText,
            dueTime: dueText,
            repeatType: HealthTask.RepeatType(rawValue: repeatTypeRaw) ?? .none,
            priority: HealthTask.Priority(rawValue: priorityRaw) ?? .medium,
            businessType: stringValue(base["business_type"]) ?? card.businessType,
            businessID: stringValue(base["business_id"]) ?? card.businessID,
            extra: [:],
            taskMedical: buildMedicalPayload(from: subMedical, fallback: card),
            taskExercise: buildExercisePayload(from: subExercise, fallback: card),
            taskDiet: buildDietPayload(from: subDiet, fallback: card)
        )
    }

    private func buildMedicalPayload(from json: [String: Any], fallback card: TaskCard) -> TaskMedicalPayload? {
        guard card.type == .medical else { return nil }
        return TaskMedicalPayload(
            reminderTime: stringValue(json["reminder_time"]) ?? card.startTime.map(iso8601),
            medicalTaskType: stringValue(json["medical_task_type"]) ?? card.title,
            description: stringValue(json["description"]) ?? card.description,
            source: "ai",
            extra: [:]
        )
    }

    private func buildExercisePayload(from json: [String: Any], fallback card: TaskCard) -> TaskExercisePayload? {
        guard card.type == .exercise else { return nil }
        return TaskExercisePayload(
            exerciseType: stringValue(json["exercise_type"]) ?? card.title,
            durationMin: intValue(json["duration_min"]) ?? 30,
            intensity: stringValue(json["intensity"]) ?? "medium",
            description: stringValue(json["description"]) ?? card.description,
            source: "ai",
            extra: [:]
        )
    }

    /// Diet 卡片直接创建 Task + task_diet 子表。
    private func buildDietPayload(from json: [String: Any], fallback card: TaskCard) -> TaskDietPayload? {
        guard card.type == .diet else { return nil }
        var foodRecommend = [String]()
        if let array = json["food_recommend"] as? [String] {
            foodRecommend = array
        } else if let text = stringValue(json["food_recommend"]), text.isEmpty == false {
            foodRecommend = [text]
        }
        if foodRecommend.isEmpty {
            foodRecommend = [card.description]
        }
        return TaskDietPayload(
            mealType: stringValue(json["meal_type"]) ?? "dinner",
            calorieTarget: intValue(json["calorie_target"]) ?? 1800,
            foodRecommend: foodRecommend,
            description: stringValue(json["description"]) ?? card.description,
            source: "ai",
            extra: [:]
        )
    }

    private func parseJSONObject(_ text: String?) -> [String: Any] {
        guard let text, let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            return [:]
        }
        return dict
    }

    private func intValue(_ value: Any?) -> Int? {
        if let intValue = value as? Int { return intValue }
        if let doubleValue = value as? Double { return Int(doubleValue) }
        if let stringValue = value as? String { return Int(stringValue) }
        return nil
    }

    private func stringValue(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let intValue = value as? Int { return "\(intValue)" }
        if let doubleValue = value as? Double { return "\(doubleValue)" }
        return nil
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func generateKnowledgeCardsPreview(for message: ChatMessage) {
        guard message.role == .assistant else { return }
        guard combinedKnowledgeCards(for: message).isEmpty else {
            // 该消息已经存在可展示卡片，不重复生成，避免 UI 重复。
            logger.debug("知识卡预览已存在，跳过重新生成，message=\(message.id.uuidString)", module: .general)
            return
        }
        // 仅生成预览，不直接落库。
        let card = buildKnowledgePreviewCard(from: message)
        generatedKnowledgeCards[message.id] = [card]
        logger.info("知识卡预览已生成，message=\(message.id.uuidString), title=\(card.title)", module: .general)
    }

    /// 使用轻量本地规则先生成可预览知识卡，再由用户决定是否保存到知识库。
    private func buildKnowledgePreviewCard(from message: ChatMessage) -> ChatKnowledgeCard {
        // 优先使用工具输出作为知识卡正文来源；若没有工具输出，则退回主回复正文。
        let toolContent = ChatMessageMetadata(message: message).toolContent ?? ""
        let primary = toolContent.isEmpty ? message.content : toolContent
        // 文本预处理：压缩空行、去首尾空白，避免卡片展示噪音。
        let normalized = primary
            .replacingOccurrences(of: "\n\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // 预览控制长度，避免气泡中出现超长卡片影响可读性。
        let previewBody = String(normalized.prefix(320))
        // 标题优先取首个非空行，再截断到固定长度；兜底走本地化默认标题。
        let titleSeed = normalized.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { $0.isEmpty == false }) ?? ""
        let title = titleSeed.isEmpty
            ? L10n.text("chat.bubble.knowledge.default_title")
            : String(titleSeed.prefix(20))
        return ChatKnowledgeCard(title: title, content: previewBody)
    }

    private func saveKnowledgeCard(_ card: ChatKnowledgeCard, from message: ChatMessage) {
        // 幂等保护：保存中或已保存都直接返回，避免重复请求。
        guard savingKnowledgeCardIDs.contains(card.id) == false else { return }
        guard savedKnowledgeCardIDs.contains(card.id) == false else { return }
        savingKnowledgeCardIDs.insert(card.id)
        Task { @MainActor in
            // 无论成功失败，都要清理 saving 状态，避免按钮一直卡住。
            defer { savingKnowledgeCardIDs.remove(card.id) }
            do {
                _ = try await detailViewModel.saveKnowledgeCard(title: card.title, content: card.content)
                savedKnowledgeCardIDs.insert(card.id)
                logger.info("知识卡保存成功，message=\(message.id.uuidString), card=\(card.id.uuidString)", module: .general)
            } catch {
                logger.error("知识卡保存失败：\(error.localizedDescription)", module: .general)
            }
        }
    }

    private func translatedText(for message: ChatMessage, metadata: ChatMessageMetadata? = nil) -> String? {
        if let local = translatedTexts[message.id], local.isEmpty == false {
            return local
        }
        let attachment = metadata?.translatedText ?? ChatMessageMetadata(message: message).translatedText
        return attachment?.isEmpty == false ? attachment : nil
    }

    private func htmlContent(from message: ChatMessage) -> String? {
        ChatMessageMetadata(message: message).htmlContent
    }

    private func imagePayloads(from message: ChatMessage) -> [ChatImagePayload] {
        var payloads: [ChatImagePayload] = []
        for attachment in message.attachments where attachment.type == "image_url" || attachment.type == "image_base64" {
            let raw = attachment.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard raw.isEmpty == false else { continue }
            if let image = decodeImage(from: raw) {
                payloads.append(ChatImagePayload(id: attachment.id, url: nil, image: image))
            } else if let url = URL(string: raw) {
                payloads.append(ChatImagePayload(id: attachment.id, url: url, image: nil))
            }
        }
        return payloads
    }

    private func decodeImage(from text: String) -> UIImage? {
        if text.hasPrefix("data:image"),
           let base64 = text.components(separatedBy: ",").last,
           let data = Data(base64Encoded: base64) {
            return UIImage(data: data)
        }
        if let data = Data(base64Encoded: text) {
            return UIImage(data: data)
        }
        return nil
    }

    private func mapLocations(from message: ChatMessage) -> [ChatMapLocationPayload] {
        ChatMessageMetadata(message: message).locations
    }

    private func mapRoutes(from message: ChatMessage) -> [ChatRoutePayload] {
        ChatMessageMetadata(message: message).routes
    }

    private func eventPayloads(from message: ChatMessage) -> [ChatEventPayload] {
        ChatMessageMetadata(message: message).events
    }

    private func healthCardPayloads(from message: ChatMessage) -> [ChatHealthCardPayload] {
        ChatMessageMetadata(message: message).healthCards
    }
}

private struct SelectableTextPayload: Identifiable {
    let id: UUID = UUID()
    let title: String
    let text: String
}

private final class ChatSpeechHelper: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    @Published private var speakingMessageID: UUID?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(text: String, id: UUID) {
        if speakingMessageID == id {
            synthesizer.stopSpeaking(at: .immediate)
            speakingMessageID = nil
            return
        }
        speakingMessageID = id
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func isSpeaking(_ id: UUID) -> Bool {
        speakingMessageID == id && synthesizer.isSpeaking
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        speakingMessageID = nil
    }
}
