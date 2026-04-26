import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 简洁（Compact）输入栏，仅用于 `ChatComposerStyle.signal`；专业版使用 `HanlinChatComposerView`。
struct ChatComposerView: View {
    let threadID: UUID
    @ObservedObject var stateStore: ChatStateStore
    let onSend: () -> Void
    let onCancel: () -> Void
    let onAttachmentsPicked: ([ChatComposerAttachmentPreview]) -> Void
    let onRemoveAttachment: (UUID) -> Void
    let smallTasks: [SmallTask]
    let onSmallTaskTapped: (SmallTask) -> Void

    @State private var inputHeight: CGFloat = 24
    @State private var showFileImporter = false
    @State private var unifiedFilePreview: FilePreviewInput?

    private var composerDraft: ChatComposerDraft {
        stateStore.composerDraft(for: threadID)
    }

    private var canSendText: Bool {
        (composerDraft.trimmedText.isEmpty == false || composerDraft.hasVisualContent)
            && stateStore.hasBlockingPreparedAttachmentWork(for: threadID) == false
    }

    private var canOpenCamera: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        signalComposerContent
        .sheet(isPresented: attachmentMenuBinding) {
            ChatComposerAttachmentSheet(
                isCameraAvailable: canOpenCamera,
                onPhotos: {
                    stateStore.setAttachmentMenuPresented(false, for: threadID)
                    stateStore.setPhotoPickerPresented(true, for: threadID)
                },
                onCamera: {
                    stateStore.setAttachmentMenuPresented(false, for: threadID)
                    stateStore.setCameraPresented(true, for: threadID)
                },
                onFiles: {
                    stateStore.setAttachmentMenuPresented(false, for: threadID)
                    showFileImporter = true
                }
            )
        }
        .sheet(isPresented: photoPickerBinding) {
            ChatPhotoLibraryPicker(
                onCancel: {
                    stateStore.setPhotoPickerPresented(false, for: threadID)
                },
                onPhotosPicked: { photos in
                    let attachments = photos.map {
                        ChatComposerAttachmentPreview(
                            source: .photoLibrary,
                            data: $0.imageData,
                            displayName: $0.suggestedFileName
                        )
                    }
                    onAttachmentsPicked(attachments)
                    stateStore.setPhotoPickerPresented(false, for: threadID)
                }
            )
        }
        .fullScreenCover(isPresented: cameraBinding) {
            ChatCameraPicker(
                onCancel: {
                    stateStore.setCameraPresented(false, for: threadID)
                },
                onImagePicked: { image in
                    guard let imageData = image.jpegData(compressionQuality: 0.88) ?? image.pngData() else {
                        stateStore.setCameraPresented(false, for: threadID)
                        return
                    }
                    onAttachmentsPicked(
                        [
                            ChatComposerAttachmentPreview(
                                source: .camera,
                                data: imageData,
                                displayName: L10n.text("chat.attachments.camera.result")
                            )
                        ],
                    )
                    stateStore.setCameraPresented(false, for: threadID)
                }
            )
            .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .image, .jpeg, .png],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            Task {
                let attachments = await ChatComposerAttachmentImporter.importFiles(urls: urls)
                await MainActor.run {
                    onAttachmentsPicked(attachments)
                }
            }
        }
        .unifiedFilePreview(selection: $unifiedFilePreview)
    }

    private var signalComposerContent: some View {
        VStack(spacing: 8) {
            ChatComposerContextTaskBar(
                smallTasks: smallTasks,
                onSmallTaskTapped: onSmallTaskTapped
            )

            if composerDraft.attachments.isEmpty == false {
                attachmentStrip
            }

            HStack(alignment: .bottom, spacing: 12) {
                attachmentButton
                messageInputContainer
                sendButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.bar)
    }

    private var attachmentButton: some View {
        Button {
            stateStore.setAttachmentMenuPresented(true, for: threadID)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 42, height: 42)
                .background(Circle().fill(.ultraThinMaterial))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel(L10n.text("chat.attachments.button"))
    }

    private var messageInputContainer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if composerDraft.attachments.isEmpty == false {
                Text(
                    String(
                        format: L10n.text("chat.attachments.selected_count"),
                        locale: Locale.current,
                        Int64(composerDraft.attachments.count)
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            ZStack(alignment: .topLeading) {
                if composerDraft.text.isEmpty {
                    Text(L10n.text("chat.input.placeholder"))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                }

                ChatComposerTextView(
                    text: Binding(
                        get: { stateStore.draft(for: threadID) },
                        set: { stateStore.setDraft($0, for: threadID) }
                    ),
                    measuredHeight: $inputHeight
                )
                .frame(height: min(max(inputHeight, 24), 110))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var sendButton: some View {
        Button(action: stateStore.isSending ? onCancel : onSend) {
            Image(systemName: stateStore.isSending ? "stop.circle.fill" : "paperplane.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(sendButtonForegroundColor)
                .frame(width: 42, height: 42)
                .background(Circle().fill(sendButtonBackgroundColor))
        }
        .buttonStyle(.plain)
        .disabled(stateStore.isSending == false && canSendText == false)
        .accessibilityLabel(stateStore.isSending ? L10n.text("chat.input.stop") : L10n.text("chat.input.send"))
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(composerDraft.attachments) { attachment in
                    ChatComposerAttachmentThumbnail(
                        attachment: attachment,
                        uploadProgress: stateStore.composerAttachmentUploadProgress[attachment.id],
                        isSelected: composerDraft.previewSelection == attachment.id,
                        onTap: {
                            stateStore.setPreviewSelection(attachment.id, for: threadID)
                            if let input = Self.makeComposerPreviewInput(attachment) {
                                unifiedFilePreview = input
                            }
                        },
                        onRemove: {
                            onRemoveAttachment(attachment.id)
                        }
                    )
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var sendButtonBackgroundColor: Color {
        if stateStore.isSending {
            return Color(uiColor: .systemRed)
        }
        if canSendText {
            return .accentColor
        }
        if composerDraft.hasVisualContent {
            return Color.accentColor.opacity(0.3)
        }
        return Color(uiColor: .secondarySystemFill)
    }

    private var sendButtonForegroundColor: Color {
        if stateStore.isSending || canSendText {
            return .white
        }
        return .secondary
    }

    private var attachmentMenuBinding: Binding<Bool> {
        Binding(
            get: { composerDraft.isShowingAttachmentMenu },
            set: { stateStore.setAttachmentMenuPresented($0, for: threadID) }
        )
    }

    private var photoPickerBinding: Binding<Bool> {
        Binding(
            get: { composerDraft.isShowingPhotoPicker },
            set: { stateStore.setPhotoPickerPresented($0, for: threadID) }
        )
    }

    private var cameraBinding: Binding<Bool> {
        Binding(
            get: { composerDraft.isShowingCamera },
            set: { stateStore.setCameraPresented($0, for: threadID) }
        )
    }

    private static func makeComposerPreviewInput(_ attachment: ChatComposerAttachmentPreview) -> FilePreviewInput? {
        let ext = (attachment.displayName as NSString).pathExtension
        let suffix = ext.isEmpty ? (attachment.isImage ? "jpg" : "bin") : ext
        let fileName = attachment.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "chat-attachment.\(suffix)"
            : attachment.displayName
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-composer-\(attachment.id.uuidString).\(suffix)")
        do {
            try attachment.data.write(to: tmp, options: [.atomic])
            return FilePreviewInput(
                fileURL: tmp,
                displayName: fileName,
                mimeType: attachment.mimeType,
                utTypeIdentifier: attachment.utTypeIdentifier
            )
        } catch {
            return nil
        }
    }

}

private struct ChatComposerAttachmentThumbnail: View {
    let attachment: ChatComposerAttachmentPreview
    var uploadProgress: Double?
    let isSelected: Bool
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onTap) {
                previewImage
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                    .overlay {
                        if let p = uploadProgress, p < 1.0 - 0.001 {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.black.opacity(0.45))
                            ProgressView(value: p, total: 1.0)
                                .tint(.white)
                                .padding(12)
                        }
                    }
            }
            .buttonStyle(.plain)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Circle().fill(Color.black.opacity(0.72)))
            }
            .buttonStyle(.plain)
            .padding(6)
        }
    }

    private var previewImage: some View {
        Group {
            if attachment.isImage, let image = UIImage(data: attachment.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle()
                        .fill(Color(uiColor: .secondarySystemFill))
                    VStack(spacing: 6) {
                        Image(systemName: attachment.isPDF ? "doc.richtext.fill" : "doc.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text(attachment.isPDF ? "PDF" : "FILE")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct ChatComposerAttachmentSheet: View {
    let isCameraAvailable: Bool
    let onPhotos: () -> Void
    let onCamera: () -> Void
    let onFiles: () -> Void

    var body: some View {
        CompatibleNavigationContainer(legacyStackStyle: true) {
            VStack(spacing: 12) {
                Text(L10n.text("chat.attachments.title"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(L10n.text("chat.attachments.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                attachmentAction(
                    title: L10n.text("chat.attachments.photos"),
                    subtitle: L10n.text("chat.attachments.photos.subtitle"),
                    systemImage: "photo.on.rectangle.angled",
                    action: onPhotos
                )

                attachmentAction(
                    title: L10n.text("chat.attachments.camera"),
                    subtitle: isCameraAvailable
                        ? L10n.text("chat.attachments.camera.subtitle")
                        : L10n.text("chat.attachments.camera.unavailable"),
                    systemImage: "camera",
                    action: onCamera
                )
                .disabled(isCameraAvailable == false)

                attachmentAction(
                    title: L10n.text("chat.attachments.files"),
                    subtitle: L10n.text("chat.attachments.files.subtitle"),
                    systemImage: "doc",
                    action: onFiles
                )

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationBarHidden(true)
        }
    }

    private func attachmentAction(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.accentColor.opacity(0.12)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ChatComposerTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        recalculateHeight(for: uiView)
    }

    private func recalculateHeight(for textView: UITextView) {
        let fittingSize = CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)
        let measured = textView.sizeThatFits(fittingSize).height
        let nextHeight = max(measured, 24)
        if abs(measuredHeight - nextHeight) > 0.5 {
            DispatchQueue.main.async {
                measuredHeight = nextHeight
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: ChatComposerTextView

        init(_ parent: ChatComposerTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.recalculateHeight(for: textView)
        }
    }
}

private struct ChatPhotoLibraryPicker: UIViewControllerRepresentable {
    let onCancel: () -> Void
    let onPhotosPicked: ([ChatComposerPickedPhoto]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 6

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: ChatPhotoLibraryPicker

        init(_ parent: ChatPhotoLibraryPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard results.isEmpty == false else {
                parent.onCancel()
                return
            }

            ChatComposerPhotoLibraryLoader.load(from: results) { photos in
                self.parent.onPhotosPicked(photos)
            }
        }
    }
}

private struct ChatCameraPicker: UIViewControllerRepresentable {
    let onCancel: () -> Void
    let onImagePicked: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: ChatCameraPicker

        init(_ parent: ChatCameraPicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            } else {
                parent.onCancel()
            }
        }
    }
}
