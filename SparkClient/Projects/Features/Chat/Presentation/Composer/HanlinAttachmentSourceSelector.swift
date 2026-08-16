import SwiftUI

/// 翰林 AI 风格附件来源横排（对标 `ChatViewBottom.sourceSelector` 三按钮区域）。
struct HanlinAttachmentSourceSelector: View {
    let showsMediaSources: Bool
    let attachmentCount: Int
    let isSending: Bool
    let isVisible: Bool
    let showCameraPicker: Bool
    let showImagePicker: Bool
    let showDocumentPicker: Bool
    let onCamera: () -> Void
    let onPhotos: () -> Void
    let onFiles: () -> Void

    @State private var feedbackTrigger = false

    private var accentForeground: Color {
        Color.accentColor
    }

    private var accentBackground: Color {
        Color.accentColor.opacity(0.1)
    }

    private var filesDisabled: Bool {
        attachmentCount >= 5 || isSending
    }

    var body: some View {
        HStack(spacing: 6) {
            if showsMediaSources {
                sourceButton(
                    icon: "camera.circle",
                    title: L10n.text("chat.attachments.camera.result"),
                    isDisabled: isSending,
                    bounceTrigger: showCameraPicker,
                    action: onCamera
                )

                sourceButton(
                    icon: "photo.circle",
                    title: L10n.text("chat.attachments.source.photos"),
                    isDisabled: isSending,
                    bounceTrigger: showImagePicker,
                    action: onPhotos
                )
            }

            sourceButton(
                icon: "document.circle",
                title: L10n.text("chat.attachments.source.files"),
                isDisabled: filesDisabled,
                bounceTrigger: showDocumentPicker,
                action: onFiles
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isVisible)
    }

    private func sourceButton(
        icon: String,
        title: String,
        isDisabled: Bool,
        bounceTrigger: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            feedbackTrigger.toggle()
            action()
        } label: {
            VStack(spacing: 0) {
                Image(systemName: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .foregroundStyle(isDisabled ? Color(.systemGray) : accentForeground)
                    .symbolEffect(.bounce, value: bounceTrigger)

                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(isDisabled ? Color(.systemGray) : accentForeground)
                    .padding(.top, 3)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                isDisabled ? Color.gray.opacity(0.2) : accentBackground
            )
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .sensoryFeedback(.impact, trigger: feedbackTrigger)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isVisible)
    }
}
