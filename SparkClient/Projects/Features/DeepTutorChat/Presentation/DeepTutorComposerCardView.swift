import SwiftUI
import UniformTypeIdentifiers

struct DeepTutorComposerCardView: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var capability: DeepTutorCapability
    @Binding var selectedModelName: String?
    let modelRows: [AIScenarioRemoteModelRow]
    let modelDisplayTitle: String?
    let modelIconName: String
    let isModelPickerDisabled: Bool
    let boundMemberDisplayModel: DeepTutorBoundMemberDisplayModel
    let members: [Member]
    let onPersistSelectedModel: (String?) -> Void
    let hasMessages: Bool
    let isStreaming: Bool
    let references: [DeepTutorContextReference]
    let attachmentDrafts: [DeepTutorComposerAttachmentDraft]
    let onAttachmentsPicked: ([MedicalUploadLocalFile]) -> Void
    let onUploadAttachment: (UUID) -> Void
    let onRetryAttachmentUpload: (UUID) -> Void
    let onRemoveAttachment: (UUID) -> Void
    let onPreviewAttachment: (UUID) -> Void
    let onSetMemberBinding: (Int?) -> Void
    let onSend: () -> Void
    let onStop: () -> Void

    @State private var isDragging = false

    private var selectedModelBinding: Binding<String?> {
        Binding(
            get: { selectedModelName },
            set: { newValue in
                selectedModelName = newValue
                onPersistSelectedModel(newValue)
            }
        )
    }

    private var minInputHeight: CGFloat {
        hasMessages ? DeepTutorPalette.composerFilledMinHeight : DeepTutorPalette.composerEmptyMinHeight
    }

    private var canSend: Bool {
        let hasText = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasUploadedAttachment = attachmentDrafts.contains { $0.phase == .uploaded }
        let hasBlockingAttachment = attachmentDrafts.contains(where: \.isBlockingSend)
        return isStreaming == false
            && hasBlockingAttachment == false
            && (hasText || hasUploadedAttachment)
    }

    private var canPickAttachments: Bool {
        isStreaming == false && attachmentDrafts.count < DeepTutorAttachmentMapper.maxComposerAttachments
    }

    private func sendWithKeyboardDismiss() {
        guard canSend else { return }
        DeepTutorChatLog.keyboardDismiss(source: "composer_send")
        KeyboardDismissHelper.dismissKeyboard()
        isFocused = false
        onSend()
    }

    var body: some View {
        VStack(spacing: 4) {
            DeepTutorComposerAttachmentPreviewBandView(
                drafts: attachmentDrafts,
                onUpload: onUploadAttachment,
                onRetry: onRetryAttachmentUpload,
                onRemove: onRemoveAttachment,
                onPreview: onPreviewAttachment
            )

            DeepTutorComposerReferenceBandView(
                attachments: [],
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
                selectedModelName: selectedModelBinding,
                modelRows: modelRows,
                modelDisplayTitle: modelDisplayTitle,
                modelIconName: modelIconName,
                isModelPickerDisabled: isModelPickerDisabled,
                boundMemberDisplayModel: boundMemberDisplayModel,
                members: members,
                isStreaming: isStreaming,
                canSend: canSend,
                canPickAttachments: canPickAttachments,
                onSetMemberBinding: onSetMemberBinding,
                onAttachmentsPicked: onAttachmentsPicked,
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
