import SwiftUI

struct DeepTutorComposerToolbarView: View {
    @Binding var capability: DeepTutorCapability
    let modelDisplayTitle: String?
    let modelIconName: String
    let isStreaming: Bool
    let canSend: Bool
    let canPickAttachments: Bool
    let onAttachmentsPicked: ([MedicalUploadLocalFile]) -> Void
    let onSend: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            capabilityMenu
            modelChip
            Spacer(minLength: 0)
            attachmentButton
            placeholderButton(systemName: "mic")
            sendStopButton
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .padding(.top, 4)
    }

    private var attachmentButton: some View {
        MedicalDocumentFilePickerMenu(
            maxPhotoSelectionCount: DeepTutorAttachmentMapper.maxComposerAttachments,
            buttonContent: {
                Image(systemName: "paperclip")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(canPickAttachments ? Color.secondary : Color.secondary.opacity(0.45))
                    .frame(width: 32, height: 32)
            },
            onFilesSelected: onAttachmentsPicked
        )
        .disabled(isStreaming || canPickAttachments == false)
        .opacity(isStreaming || canPickAttachments == false ? 0.55 : 1)
    }

    private var capabilityMenu: some View {
        Menu {
            ForEach(DeepTutorCapability.allCases, id: \.self) { item in
                Button {
                    capability = item
                } label: {
                    if capability == item {
                        Label(item.badgeLabel, systemImage: "checkmark")
                    } else {
                        Text(item.badgeLabel)
                    }
                }
            }
        } label: {
            toolbarChip(title: capability.badgeLabel, systemImage: "sparkles")
        }
    }

    private var modelChip: some View {
        toolbarChip(
            title: modelDisplayTitle ?? L10n.text("chat.composer.model.default"),
            systemImage: modelIconName
        )
    }

    private func placeholderButton(systemName: String) -> some View {
        Button {} label: {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .disabled(true)
        .opacity(0.55)
    }

    private var sendStopButton: some View {
        Button(action: isStreaming ? onStop : onSend) {
            ZStack {
                if isStreaming {
                    Circle()
                        .stroke(Color.accentColor.opacity(0.35), lineWidth: 2)
                        .frame(width: 32, height: 32)
                }
                Circle()
                    .fill(canSend || isStreaming ? Color.accentColor : Color(.tertiarySystemFill))
                    .frame(width: 32, height: 32)
                Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(canSend || isStreaming ? Color.white : Color.secondary)
                    .opacity(isStreaming ? 1 : (canSend ? 1 : 0.6))
                    .scaleEffect(isStreaming ? 0.82 : 1)
                    .animation(.easeInOut(duration: 0.18), value: isStreaming)
            }
        }
        .buttonStyle(.plain)
        .disabled(isStreaming == false && canSend == false)
    }

    private func toolbarChip(title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(.tertiarySystemFill), in: Capsule())
    }
}
