import SwiftUI

private enum ExternalToolConsentSheetDisplayLimits {
    static let maxResultChars = 32_000
    static let maxArgumentChars = 12_000
}

struct ExternalToolDataConsentSheet: View {
    let prompt: ExternalToolDataSharePrompt
    let onAllow: () -> Void
    let onDeny: () -> Void

    var body: some View {
        CompatibleNavigationContainer(legacyStackStyle: true) {
            ScrollView {
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
            Form {
                ForEach(prompt.questions) { question in
                    Section {
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
                                    Spacer()
                                }
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
                        }
                    }
                }
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
            Form {
                Section {
                    Text(L10n.text("chat.member_selection_tool.message"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if prompt.reason.isEmpty == false {
                        Text(prompt.reason)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
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
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
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

/// 当前队列中的工具交互（全局 sheet，不写入消息流）。
struct ToolInteractionPresentationSheet: View {
    let active: ToolInteractionCoordinator.ActivePresentation
    @ObservedObject var coordinator: ToolInteractionCoordinator
    @ObservedObject var memberContextStore: MemberContextStore

    var body: some View {
        switch active.snapshot {
        case .consent(let prompt):
            ExternalToolDataConsentSheet(
                prompt: prompt,
                onAllow: { coordinator.completeConsent(allowed: true) },
                onDeny: { coordinator.completeConsent(allowed: false) }
            )
        case .question(let prompt):
            ToolQuestionSheet(
                prompt: prompt,
                onSubmit: { coordinator.completeQuestion(answer: ToolQuestionAnswer(responses: $0)) },
                onCancel: { coordinator.completeQuestionCancelled() }
            )
        case .member(let prompt):
            MemberSelectionToolSheet(
                prompt: prompt,
                memberContextStore: memberContextStore,
                onSubmit: { coordinator.completeMemberSelection(memberID: $0) },
                onCancel: { coordinator.completeMemberCancelled() }
            )
        }
    }
}
