import SwiftUI
import UniformTypeIdentifiers

struct DeepTutorComposerCardView: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var capability: DeepTutorCapability
    let modelName: String?
    let hasMessages: Bool
    let isStreaming: Bool
    let attachments: [DeepTutorAttachment]
    let references: [DeepTutorContextReference]
    let onSend: () -> Void
    let onStop: () -> Void

    @State private var isDragging = false

    private var minInputHeight: CGFloat {
        hasMessages ? DeepTutorPalette.composerFilledMinHeight : DeepTutorPalette.composerEmptyMinHeight
    }

    private var canSend: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func sendWithKeyboardDismiss() {
        guard canSend else { return }
        DeepTutorChatLog.keyboardDismiss(source: "composer_send")
        KeyboardDismissHelper.dismissKeyboard()
        isFocused = false
        onSend()
    }

    var body: some View {
        VStack(spacing: 0) {
            DeepTutorComposerReferenceBandView(
                attachments: attachments,
                references: references
            )

            DeepTutorComposerTextView(
                text: $text,
                isFocused: $isFocused,
                placeholder: "Message DeepTutor",
                minHeight: minInputHeight,
                maxHeight: DeepTutorPalette.composerMaxHeight,
                onSubmit: sendWithKeyboardDismiss
            )
            .frame(minHeight: minInputHeight)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            DeepTutorComposerToolbarView(
                capability: $capability,
                modelName: modelName,
                isStreaming: isStreaming,
                canSend: canSend,
                onSend: sendWithKeyboardDismiss,
                onStop: onStop
            )
        }
        .background(
            RoundedRectangle(cornerRadius: DeepTutorPalette.composerCornerRadius, style: .continuous)
                .fill(DeepTutorPalette.cardBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DeepTutorPalette.composerCornerRadius, style: .continuous)
                .strokeBorder(
                    isDragging ? Color.accentColor.opacity(0.5) : DeepTutorPalette.borderColor,
                    style: isDragging ? StrokeStyle(lineWidth: 2, dash: [6, 4]) : StrokeStyle(lineWidth: 1)
                )
        }
        .overlay {
            if isDragging {
                RoundedRectangle(cornerRadius: DeepTutorPalette.composerCornerRadius, style: .continuous)
                    .fill(Color.accentColor.opacity(0.04))
            }
        }
        .deepTutorComposerCardShadow()
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { _ in false }
    }
}
