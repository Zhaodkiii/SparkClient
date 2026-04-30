import SwiftUI

private enum ExternalToolConsentSheetDisplayLimits {
    static let maxResultChars = 32_000
    static let maxArgumentChars = 12_000
}

private struct AdaptiveToolSheetScrollView<Content: View>: View {
    private let content: Content
    private let bottomContentPadding: CGFloat = 80

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            scrollView
                .modifier(AdaptiveToolSheetHeightModifier())
        } else {
            scrollView
        }
    }

    private var scrollView: some View {
        ScrollView {
            content
                .padding(.bottom, bottomContentPadding)
                .readAdaptiveSheetHeight()
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

@available(iOS 16.0, *)
private struct AdaptiveToolSheetHeightModifier: ViewModifier {
    @State private var measuredHeight: CGFloat = AdaptiveSheetHeightPreferenceKey.defaultValue
    @State private var selectedDetent: PresentationDetent = .height(AdaptiveSheetHeightPreferenceKey.defaultValue)

    private let navigationChromeHeight: CGFloat = 64

    private var maxFittedHeight: CGFloat {
        UIScreen.main.bounds.height * 0.72
    }

    private var fittedHeight: CGFloat {
        min(measuredHeight, maxFittedHeight)
    }

    private var canScroll: Bool {
        measuredHeight > maxFittedHeight && selectedDetent == .large
    }

    func body(content: Content) -> some View {
        content
            .scrollDisabled(canScroll == false)
            .onPreferenceChange(AdaptiveSheetHeightPreferenceKey.self) { height in
                guard height > 0 else { return }
                let nextHeight = height + navigationChromeHeight
                measuredHeight = nextHeight
                if selectedDetent != .large || nextHeight <= maxFittedHeight {
                    selectedDetent = .height(min(nextHeight, maxFittedHeight))
                }
            }
            .presentationDetents(detents, selection: $selectedDetent)
            .presentationDragIndicator(.visible)
    }

    private var detents: Set<PresentationDetent> {
        measuredHeight > maxFittedHeight ? [.height(fittedHeight), .large] : [.height(measuredHeight)]
    }
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
                            Text(prompt.toolContent.isEmpty ? "—" : prompt.toolContent)
                                .font(.caption.monospaced())
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
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

/// 当前队列中的工具交互（全局 sheet，不写入消息流）。
struct ToolInteractionPresentationSheet: View {
    let active: ToolInteractionCoordinator.ActivePresentation
    @ObservedObject var coordinator: ToolInteractionCoordinator
    @ObservedObject var memberContextStore: MemberContextStore
    @ObservedObject var stateStore: ChatStateStore
    let toolPreviewRenderContext: ChatRenderContext?
    let onClearToolPreviewRenderContext: () -> Void

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
        }
    }
}
