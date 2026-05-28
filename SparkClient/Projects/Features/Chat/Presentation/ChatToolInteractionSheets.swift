import SwiftUI
import UIKit

private enum ExternalToolConsentSheetDisplayLimits {
    static let maxResultChars = 32_000
    static let maxArgumentChars = 12_000
    static let maxToolPreviewChars = 32_000
}

private struct ToolSheetSection<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ExternalToolDataConsentSheet: View {
    let prompt: ExternalToolDataSharePrompt
    let onAllow: () -> Void
    let onAllowAlways: () -> Void
    let onDeny: () -> Void

    var body: some View {
        CompatibleNavigationContainer(legacyStackStyle: true) {
            AdaptiveToolSheetScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("chat.tool_consent.intro"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        providerGrid
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("chat.tool_consent.data_title"))
                            .font(.headline)
                        ForEach(prompt.dataLines, id: \.self) { line in
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ForEach(prompt.payloadBlocks) { block in
                        payloadBlockView(block)
                    }

                    if let url = prompt.privacyPolicyURL {
                        Link(destination: url) {
                            Label(L10n.text("chat.tool_consent.privacy"), systemImage: "lock.shield")
                        }
                    }

                    Text(L10n.text("chat.tool_consent.footer"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button(action: onAllowAlways) {
                        Label(L10n.text("chat.tool_consent.allow_always"), systemImage: "checkmark.shield")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle(L10n.text("chat.tool_consent.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("chat.tool_consent.deny"), role: .cancel, action: onDeny)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("chat.tool_consent.allow"), action: onAllow)
                }
            }
        }
    }

    private var providerGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            providerRow(title: "Provider", value: prompt.providerCompany)
            providerRow(title: "Endpoint", value: prompt.endpointLine)
            providerRow(title: "Model", value: prompt.modelLine)
        }
        .font(.caption)
    }

    private func providerRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func payloadBlockView(_ block: ExternalToolDataSharePayloadBlock) -> some View {
        let maxA = ExternalToolConsentSheetDisplayLimits.maxArgumentChars
        let maxR = ExternalToolConsentSheetDisplayLimits.maxResultChars
        let argsTruncated = block.argumentsText.count > maxA
        let resultTruncated = block.resultText.count > maxR
        let argsDisplay = argsTruncated ? String(block.argumentsText.prefix(maxA)) : block.argumentsText
        let resultDisplay = resultTruncated ? String(block.resultText.prefix(maxR)) : block.resultText
        return VStack(alignment: .leading, spacing: 8) {
            Text(block.friendlyTitle)
                .font(.subheadline.weight(.semibold))
            Text(block.toolAPIName)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            DisclosureGroup(L10n.text("chat.tool_consent.arguments")) {
                Text(argsDisplay.isEmpty ? "-" : argsDisplay)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            DisclosureGroup(L10n.text("chat.tool_consent.result")) {
                Text(resultDisplay)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if resultTruncated {
                    Text(L10n.text("chat.tool_consent.truncated"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ToolQuestionSheet: View {
    let prompt: ToolQuestionPrompt
    let onSubmit: ([ToolQuestionResponse]) -> Void
    let onCancel: () -> Void

    @State private var selectedIDsByQuestion: [String: Set<String>] = [:]
    @State private var otherTextByQuestion: [String: String] = [:]

    private var canSubmit: Bool {
        prompt.questions.allSatisfy { question in
            (selectedIDsByQuestion[question.id]?.isEmpty == false)
                || (otherTextByQuestion[question.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    var body: some View {
        CompatibleNavigationContainer(legacyStackStyle: true) {
            AdaptiveToolSheetScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(prompt.questions) { question in
                        ToolSheetSection {
                            Text(question.question)
                                .font(.body.weight(.semibold))
                            ForEach(question.options) { option in
                                Button {
                                    toggle(option.id, for: question)
                                } label: {
                                    HStack {
                                        Image(systemName: selectedIDs(for: question).contains(option.id) ? selectedIcon(for: question) : unselectedIcon(for: question))
                                            .foregroundStyle(Color.accentColor)
                                        Text(option.text)
                                            .foregroundStyle(.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            if question.allowsOther {
                                TextField(
                                    L10n.text("chat.tool_question.other"),
                                    text: Binding(
                                        get: { otherTextByQuestion[question.id] ?? "" },
                                        set: { otherTextByQuestion[question.id] = $0 }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(L10n.text("chat.tool_question.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("common.cancel"), role: .cancel, action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("chat.tool_question.submit")) {
                        onSubmit(responses())
                    }
                    .disabled(canSubmit == false)
                }
            }
        }
    }

    private func selectedIcon(for question: ToolQuestionItem) -> String {
        question.selectionMode == .single ? "largecircle.fill.circle" : "checkmark.square.fill"
    }

    private func unselectedIcon(for question: ToolQuestionItem) -> String {
        question.selectionMode == .single ? "circle" : "square"
    }

    private func selectedIDs(for question: ToolQuestionItem) -> Set<String> {
        selectedIDsByQuestion[question.id] ?? []
    }

    private func toggle(_ id: String, for question: ToolQuestionItem) {
        var ids = selectedIDsByQuestion[question.id] ?? []
        switch question.selectionMode {
        case .single:
            ids = [id]
        case .multiple:
            if ids.contains(id) {
                ids.remove(id)
            } else {
                ids.insert(id)
            }
        }
        selectedIDsByQuestion[question.id] = ids
    }

    private func responses() -> [ToolQuestionResponse] {
        prompt.questions.map { question in
            ToolQuestionResponse(
                questionID: question.id,
                selectedOptionIDs: Array(selectedIDsByQuestion[question.id] ?? []),
                otherText: nonEmpty(otherTextByQuestion[question.id])
            )
        }
    }

    private func nonEmpty(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct MemberSelectionToolSheet: View {
    let prompt: ToolMemberSelectionPrompt
    @ObservedObject var memberContextStore: MemberContextStore
    let onSubmit: (Int) -> Void
    let onCancel: () -> Void

    @State private var selectedMemberID: Int?

    private var members: [Member] {
        memberContextStore.context.members
    }

    var body: some View {
        CompatibleNavigationContainer(legacyStackStyle: true) {
            AdaptiveToolSheetScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ToolSheetSection {
                        Text(L10n.text("chat.member_selection_tool.message"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if prompt.reason.isEmpty == false {
                            Text(prompt.reason)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }

                    ToolSheetSection {
                        if members.isEmpty {
                            Text(L10n.text("chat.member_selection_tool.empty"))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(members) { member in
                                Button {
                                    selectedMemberID = member.id
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: selectedMemberID == member.id ? "largecircle.fill.circle" : "circle")
                                            .foregroundStyle(Color.accentColor)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(member.name)
                                                .foregroundStyle(.primary)
                                            Text(member.relationship)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(L10n.text("chat.member_selection_tool.title"))
            .onAppear {
                selectedMemberID = selectedMemberID ?? memberContextStore.context.selectedMemberID
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("common.cancel"), role: .cancel, action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("chat.member_selection_tool.submit")) {
                        if let selectedMemberID {
                            onSubmit(selectedMemberID)
                        }
                    }
                    .disabled(selectedMemberID == nil)
                }
            }
        }
    }
}

/// 工具输出详情（只读 + 关联业务卡片，与 ask/consent 共用全局 Sheet 入口）。
struct ToolPreviewSheet: View {
    let prompt: ToolPreviewPrompt
    let renderContext: ChatRenderContext?
    @ObservedObject var coordinator: ToolInteractionCoordinator
    @ObservedObject var stateStore: ChatStateStore
    let onClearRenderContext: () -> Void

    private var resolvedMessage: ChatMessage? {
        stateStore.conversationListItems(for: prompt.threadID)
            .first { $0.clientMessageID == prompt.sourceClientMessageID }
    }

    private var orderedRelatedBlocks: [ChatMessageBlock] {
        let msg = resolvedMessage ?? renderContext?.message
        guard let msg else { return [] }
        let byId = Dictionary(uniqueKeysWithValues: msg.blocks.map { ($0.id, $0) })
        return prompt.relatedBlockIDs.compactMap { byId[$0] }
    }

    private var contextForCards: ChatRenderContext? {
        guard let base = renderContext else { return nil }
        guard let msg = resolvedMessage else { return base }
        return base.replacingMessage(msg)
    }

    private var toolArgumentsDisplay: ToolLargeTextDisplay? {
        guard let args = prompt.toolArguments, args.isEmpty == false else {
            return nil
        }
        let text = ToolPreviewPrompt.displayText(for: args)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return nil }
        return ToolLargeTextDisplay(
            text: text,
            emptyPlaceholder: "-",
            limit: ExternalToolConsentSheetDisplayLimits.maxToolPreviewChars
        )
    }

    private var toolContentDisplay: ToolLargeTextDisplay {
        ToolLargeTextDisplay(
            text: prompt.toolContent,
            emptyPlaceholder: "-",
            limit: ExternalToolConsentSheetDisplayLimits.maxToolPreviewChars
        )
    }

    var body: some View {
        CompatibleNavigationContainer(legacyStackStyle: true) {
            AdaptiveToolSheetScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ToolSheetSection {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(prompt.toolName)
                                .font(.headline)
                            if let tid = prompt.toolCallID, tid.isEmpty == false {
                                Text("tool_call_id: \(tid)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    if let argsDisplay = toolArgumentsDisplay {
                        ToolSheetSection {
                            Text(L10n.text("chat.bubble.tool.arguments", fallback: "调用参数"))
                                .font(.subheadline.weight(.semibold))
                            ToolLargeTextPreview(display: argsDisplay)
                        }
                    }

                    ToolSheetSection {
                        Text(L10n.text("chat.bubble.tool.output", fallback: "输出"))
                            .font(.subheadline.weight(.semibold))
                        ToolLargeTextPreview(display: toolContentDisplay)
                    }

                    if orderedRelatedBlocks.isEmpty == false, let ctx = contextForCards {
                        ToolSheetSection {
                            Text(L10n.text("chat.tool_preview.related", fallback: "关联内容"))
                                .font(.subheadline.weight(.semibold))
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(orderedRelatedBlocks) { block in
                                    block.render(context: ctx)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(L10n.text("chat.tool_preview.title", fallback: "工具详情"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("common.done")) {
                        onClearRenderContext()
                        coordinator.dismissToolPreview(id: prompt.id)
                    }
                }
            }
        }
    }
}

private struct ToolLargeTextDisplay {
    let fullText: String
    let displayText: String
    let isTruncated: Bool
    let fullCharacterCount: Int
    let visibleCharacterCount: Int

    init(text: String, emptyPlaceholder: String, limit: Int) {
        fullText = text
        fullCharacterCount = text.count
        isTruncated = text.count > limit
        visibleCharacterCount = isTruncated ? limit : text.count

        if text.isEmpty {
            displayText = emptyPlaceholder
        } else if isTruncated {
            displayText = String(text.prefix(limit))
        } else {
            displayText = text
        }
    }
}

private struct ToolLargeTextPreview: View {
    let display: ToolLargeTextDisplay
    @State private var didCopyFullText = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(display.displayText)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if display.isTruncated {
                HStack(spacing: 10) {
                    Label(
                        String(
                            format: L10n.text(
                                "chat.tool_preview.truncated_count",
                                fallback: "仅显示前 %d / %d 个字符"
                            ),
                            display.visibleCharacterCount,
                            display.fullCharacterCount
                        ),
                        systemImage: "scissors"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    Button {
                        UIPasteboard.general.string = display.fullText
                        didCopyFullText = true
                    } label: {
                        Label(
                            didCopyFullText
                                ? L10n.text("common.copied", fallback: "已复制")
                                : L10n.text("common.copy_all", fallback: "复制全部"),
                            systemImage: didCopyFullText ? "checkmark" : "doc.on.doc"
                        )
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .disabled(display.fullText.isEmpty)
                }
            }
        }
    }
}

struct SystemMessageSettingsSheet: View {
    let prompt: SystemMessageSettingsPrompt
    let onSave: (String) -> Void
    let onClose: () -> Void

    @State private var useDefaultSystemMessage: Bool
    @State private var systemMessage: String
    @State private var showTextInputDrawer = false
    @State private var showVoiceInput = false

    init(
        prompt: SystemMessageSettingsPrompt,
        onSave: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.prompt = prompt
        self.onSave = onSave
        self.onClose = onClose

        let session = prompt.sessionPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultPrompt = prompt.defaultPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        _useDefaultSystemMessage = State(initialValue: session.isEmpty || session == defaultPrompt)
        _systemMessage = State(initialValue: session.isEmpty ? prompt.defaultPrompt : prompt.sessionPrompt)
    }

    var body: some View {
        CompatibleNavigationContainer(legacyStackStyle: true) {
            Form {
                Section(L10n.text("chat.system_message.section.current_model")) {
                    Label(prompt.modelDisplayName, systemImage: prompt.isAgentModel ? "person.crop.circle" : "cpu")
                    if prompt.isAgentModel {
                        Text(L10n.text("chat.system_message.agent_model_hint"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(L10n.text("chat.system_message.session_hint"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if prompt.isAgentModel {
                    Section(L10n.text("chat.system_message.section.agent_prompt")) {
                        Text(agentPromptText)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if prompt.sessionPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                        Section(L10n.text("chat.system_message.section.session_prompt")) {
                            Text(prompt.sessionPrompt)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                } else {
                    Section(L10n.text("chat.system_message.section.selection")) {
                        Picker(L10n.text("chat.system_message.picker.title"), selection: $useDefaultSystemMessage) {
                            Text(L10n.text("chat.system_message.option.default")).tag(true)
                            Text(L10n.text("chat.system_message.option.custom")).tag(false)
                        }
                        .pickerStyle(.segmented)
                    }

                    if useDefaultSystemMessage {
                        Section(L10n.text("chat.system_message.section.default_prompt")) {
                            Text(prompt.defaultPrompt)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    } else {
                        Section(L10n.text("chat.system_message.section.edit_system_role")) {
                            PromptInputEditorView(
                                text: $systemMessage,
                                promptTemplates: prompt.promptTemplates,
                                onVoiceInput: { showVoiceInput = true },
                                onTextInput: { showTextInputDrawer = true }
                            )
                        }
                    }
                }

                Section(L10n.text("chat.system_message.section.description")) {
                    Text(L10n.text("chat.system_message.description"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(L10n.text("chat.system_message.nav_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(prompt.isAgentModel ? L10n.text("common.done") : L10n.text("common.cancel"), action: onClose)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("common.save")) {
                        onSave(useDefaultSystemMessage ? prompt.defaultPrompt : systemMessage)
                    }
                    .disabled(prompt.isAgentModel)
                }
            }
        }
        .sheet(isPresented: $showTextInputDrawer) {
            SparkPromptInputDrawerSheet(
                text: $systemMessage,
                isPresented: $showTextInputDrawer
            )
            .sparkInputPresentationChromeIfAvailable()
        }
        .sheet(isPresented: $showVoiceInput) {
            SparkVoiceInputSheet(
                text: $systemMessage,
                isPresented: $showVoiceInput
            )
            .sparkInputPresentationChromeIfAvailable()
        }
    }

    private var agentPromptText: String {
        let text = prompt.agentPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? L10n.text("chat.system_message.agent_prompt_empty") : text
    }
}

/// 当前队列中的工具交互（全局 sheet，不写入消息流）。
struct ToolInteractionPresentationSheet: View {
    let active: ToolInteractionCoordinator.ActivePresentation
    @ObservedObject var coordinator: ToolInteractionCoordinator
    @ObservedObject var memberContextStore: MemberContextStore
    @ObservedObject var stateStore: ChatStateStore
    let toolPreviewRenderContext: ChatRenderContext?
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    let initialCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    let fetchMemberCompleteData: (Int) async throws -> SparkMedicalSyncAPI.RemoteMemberCompleteData
    let onClearToolPreviewRenderContext: () -> Void
    let onSaveSystemMessage: (SystemMessageSettingsPrompt, String) -> Void
    let onAskReportAppend: (UUID, [HealthResourceRef]) -> Void
    let onAskReportSetMemberBinding: (Int?) -> Void
    let onAskReportMaxRefsReached: () -> Void

    var body: some View {
        switch active.snapshot {
        case .consent(let prompt):
            ExternalToolDataConsentSheet(
                prompt: prompt,
                onAllow: { coordinator.completeConsent(id: active.id, allowed: true) },
                onAllowAlways: { coordinator.completeConsent(id: active.id, allowed: true, rememberTool: true) },
                onDeny: { coordinator.completeConsent(id: active.id, allowed: false) }
            )
        case .question(let prompt):
            ToolQuestionSheet(
                prompt: prompt,
                onSubmit: { coordinator.completeQuestion(id: active.id, answer: ToolQuestionAnswer(responses: $0)) },
                onCancel: { coordinator.completeQuestionCancelled(id: active.id) }
            )
        case .member(let prompt):
            MemberSelectionToolSheet(
                prompt: prompt,
                memberContextStore: memberContextStore,
                onSubmit: { coordinator.completeMemberSelection(id: active.id, memberID: $0) },
                onCancel: { coordinator.completeMemberCancelled(id: active.id) }
            )
        case .toolPreview(let prompt):
            ToolPreviewSheet(
                prompt: prompt,
                renderContext: toolPreviewRenderContext,
                coordinator: coordinator,
                stateStore: stateStore,
                onClearRenderContext: onClearToolPreviewRenderContext
            )
        case .systemMessageSettings(let prompt):
            SystemMessageSettingsSheet(
                prompt: prompt,
                onSave: { value in
                    onSaveSystemMessage(prompt, value)
                    coordinator.dismissSystemMessageSettings(id: active.id)
                },
                onClose: { coordinator.dismissSystemMessageSettings(id: active.id) }
            )
        case .healthResourceCandidates(let prompt):
            let pendingCount = stateStore.composerDraft(for: prompt.threadID).pendingHealthResourceRefs.count
            let remaining = max(0, min(prompt.maxSelectable, HealthResourceSendValidator.maxRefs - pendingCount))
            ChatHealthSourceCandidateSheet(
                candidates: prompt.candidates,
                maxSelectable: max(1, remaining),
                onConfirm: { picked in
                    coordinator.completeHealthResourceCandidates(id: active.id, selected: picked)
                },
                onCancel: {
                    coordinator.completeHealthResourceCandidatesCancelled(id: active.id)
                }
            )
        case .askReportPicker(let prompt):
            ChatAskReportSheet(
                memberContextStore: memberContextStore,
                boundMemberID: prompt.memberID,
                pendingRefs: stateStore.composerDraft(for: prompt.threadID).pendingHealthResourceRefs,
                initialCompleteData: initialCompleteData,
                fetchCompleteData: fetchMemberCompleteData,
                onAppendToPreview: { refs in
                    onAskReportAppend(active.id, refs)
                },
                onSetMemberBinding: onAskReportSetMemberBinding,
                onMaxRefsReached: onAskReportMaxRefsReached
            )
        case .apiKeysSettings:
            CompatibleNavigationContainer(legacyStackStyle: true) {
                APIKeysSettingsView(viewModel: aiSettingsViewModel)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L10n.text("common.done")) {
                                coordinator.dismissAPIKeysSettings(id: active.id)
                            }
                        }
                    }
            }
        }
    }
}
