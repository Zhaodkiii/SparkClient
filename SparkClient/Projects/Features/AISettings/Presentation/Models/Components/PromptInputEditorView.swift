import SwiftUI

struct PromptInputEditorView: View {
    @Binding var text: String
    var isAutoFillInProgress = false
    var isAutoFilled = false
    var isAutoFillDisabled = false
    var showsCurrentDateButton = true
    var onAutoFill: (() -> Void)?
    var onVoiceInput: () -> Void
    var onTextInput: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $text)
                .scrollContentBackgroundIfAvailable(.hidden)
                .frame(minHeight: 150)

            HStack(spacing: 10) {
                if onAutoFill != nil {
                    autoFillButton
                }

                if showsCurrentDateButton {
                    currentDateButton
                }

                Spacer()
                Text(L10n.text("prompt_input.tools", fallback: "Input tools", comment: "Prompt input toolbar label"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(action: onVoiceInput) {
                    Image(systemName: "microphone.circle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 25, height: 25)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("prompt_input.voice.title", fallback: "Voice input", comment: "Voice input sheet title"))

                Button(action: onTextInput) {
                    Image(systemName: "chevron.up.circle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 25, height: 25)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("prompt_input.drawer.title", fallback: "Multiline input", comment: "Prompt drawer title"))
            }
            .foregroundStyle(.tint)
        }
    }

    private var autoFillButton: some View {
        Button {
            onAutoFill?()
        } label: {
            HStack(spacing: 5) {
                if isAutoFillInProgress {
                    ProgressView()
                        .frame(width: 25, height: 25)
                    Text(L10n.text("prompt_input.toolbar.autofilling", fallback: "Filling", comment: "Prompt autofill progress"))
                        .font(.caption)
                } else if isAutoFilled {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 25, height: 25)
                    Text(L10n.text("prompt_input.toolbar.undo_autofill", fallback: "Undo fill", comment: "Undo prompt autofill"))
                        .font(.caption)
                } else {
                    Image(systemName: "pencil.circle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 25, height: 25)
                    Text(L10n.text("prompt_input.toolbar.autofill", fallback: "Auto fill", comment: "Prompt autofill action"))
                        .font(.caption)
                }
            }
            .foregroundStyle(isAutoFillDisabled ? Color(.systemGray) : Color.accentColor)
        }
        .buttonStyle(.plain)
        .disabled(isAutoFillInProgress || isAutoFillDisabled)
    }

    private var currentDateButton: some View {
        Button {
            let enabled = AIPromptKeywords.contains(AIPromptKeywords.currentDate, in: text) == false
            text = AIPromptKeywords.setting(AIPromptKeywords.currentDate, enabled: enabled, in: text)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: AIPromptKeywords.contains(AIPromptKeywords.currentDate, in: text) ? "calendar.badge.checkmark" : "calendar.badge.plus")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 25, height: 25)
                Text(
                    L10n.text(
                        "ai_settings.small_tasks.field.use_current_date",
                        fallback: "Append current date to system prompt",
                        comment: "Use current date keyword action"
                    )
                )
                .font(.caption)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            L10n.text(
                "ai_settings.small_tasks.field.use_current_date",
                fallback: "Append current date to system prompt",
                comment: "Use current date keyword accessibility label"
            )
        )
    }
}
