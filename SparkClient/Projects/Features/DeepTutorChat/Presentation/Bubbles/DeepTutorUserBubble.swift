import SwiftUI

struct DeepTutorUserBubble: View {
    let message: DeepTutorMessage
    let branchInfo: (index: Int, count: Int)?
    let onCopy: () -> Void
    let onEdit: (String) -> Void
    let onSelectPreviousBranch: () -> Void
    let onSelectNextBranch: () -> Void

    @State private var isEditing = false
    @State private var isEditingFocused = false
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(message.capability.badgeLabel.uppercased())
                .font(.system(size: DeepTutorPalette.badgeFontSize, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(.secondary)

            if isEditing {
                editingCard
            } else {
                messageBubble
            }

            if let branchInfo {
                branchControls(branchInfo)
            }

            DeepTutorContextReferenceTreeView(
                attachments: message.attachments,
                references: message.requestSnapshot?.references ?? []
            )
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var messageBubble: some View {
        Text(message.content)
            .font(.system(size: DeepTutorPalette.bodyFontSize))
            .lineSpacing(DeepTutorPalette.bodyLineSpacing)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, DeepTutorPalette.bubbleHorizontalPadding)
            .padding(.vertical, DeepTutorPalette.bubbleVerticalPadding)
            .background(DeepTutorPalette.secondarySurface, in: bubbleShape)
            .deepTutorBubbleShadow()
            .contextMenu {
                Button {
                    onCopy()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                Button {
                    draft = message.content
                    isEditing = true
                    isEditingFocused = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
    }

    private var editingCard: some View {
        VStack(alignment: .trailing, spacing: 10) {
            DeepTutorComposerTextView(
                text: $draft,
                isFocused: $isEditingFocused,
                placeholder: "Edit message",
                minHeight: 80,
                maxHeight: 160,
                onSubmit: {
                    isEditing = false
                    onEdit(draft)
                }
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(DeepTutorPalette.secondarySurface, in: bubbleShape)
            .overlay {
                RoundedRectangle(cornerRadius: DeepTutorPalette.bubbleCornerRadius, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
            }

            HStack(spacing: 10) {
                Button("Cancel") {
                    isEditing = false
                    draft = message.content
                }
                .font(.system(size: 13, weight: .medium))
                Button("Send") {
                    isEditing = false
                    onEdit(draft)
                }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func branchControls(_ branchInfo: (index: Int, count: Int)) -> some View {
        HStack(spacing: 12) {
            Button(action: onSelectPreviousBranch) {
                Image(systemName: "chevron.left")
            }
            .disabled(branchInfo.index == 0)
            Text("\(branchInfo.index + 1) / \(branchInfo.count)")
                .font(.caption.weight(.semibold))
            Button(action: onSelectNextBranch) {
                Image(systemName: "chevron.right")
            }
            .disabled(branchInfo.index >= branchInfo.count - 1)
        }
        .foregroundStyle(.secondary)
    }

    private var bubbleShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DeepTutorPalette.bubbleCornerRadius, style: .continuous)
    }
}
