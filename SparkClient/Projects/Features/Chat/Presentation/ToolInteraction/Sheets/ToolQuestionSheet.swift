import SwiftUI

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
