import PhotosUI
import SwiftUI
import UIKit

/// 专业版输入区（与 `ChatComposerView` 完全分离的实现，不共用 SwiftUI 视图层级）。
struct HanlinChatInputView: View {
    let threadID: UUID
    let modelReasoning: ChatModelReasoningContext
    @ObservedObject var stateStore: ChatStateStore
    let onSend: () -> Void
    let onRequestFileImport: () -> Void

    @State private var inputHeight: CGFloat = 24
    @State private var inputExpandedSheet = false

    private var composerDraft: ChatComposerDraft {
        stateStore.composerDraft(for: threadID)
    }

    private var attachmentMenuOpen: Bool {
        composerDraft.isShowingAttachmentMenu
    }

    private var canOpenCamera: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    private var selectedPreview: ChatComposerAttachmentPreview? {
        guard let previewSelection = composerDraft.previewSelection else { return nil }
        return composerDraft.attachments.first(where: { $0.id == previewSelection })
    }

    private var canSendPayload: Bool {
        composerDraft.trimmedText.isEmpty == false || composerDraft.hasVisualContent
    }

    var body: some View {
        content
            .sheet(isPresented: attachmentMenuBinding) {
                HanlinAttachmentSheet(
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
                        onRequestFileImport()
                    }
                )
            }
            .sheet(isPresented: photoPickerBinding) {
                HanlinPhotoLibraryPicker(
                    onCancel: {
                        stateStore.setPhotoPickerPresented(false, for: threadID)
                    },
                    onImagesPicked: { images in
                        var attachments: [ChatComposerAttachmentPreview] = []
                        for (index, image) in images.enumerated() {
                            guard let imageData = image.jpegData(compressionQuality: 0.88) ?? image.pngData() else {
                                continue
                            }
                            attachments.append(
                                ChatComposerAttachmentPreview(
                                    source: .photoLibrary,
                                    imageData: imageData,
                                    displayName: String(
                                        format: L10n.text("chat.attachments.photo.result"),
                                        locale: Locale.current,
                                        Int64(index + 1)
                                    )
                                )
                            )
                        }
                        stateStore.appendComposerAttachments(attachments, for: threadID)
                        stateStore.setPhotoPickerPresented(false, for: threadID)
                    }
                )
            }
            .fullScreenCover(isPresented: cameraBinding) {
                HanlinCameraPicker(
                    onCancel: {
                        stateStore.setCameraPresented(false, for: threadID)
                    },
                    onImagePicked: { image in
                        guard let imageData = image.jpegData(compressionQuality: 0.88) ?? image.pngData() else {
                            stateStore.setCameraPresented(false, for: threadID)
                            return
                        }
                        stateStore.appendComposerAttachments(
                            [
                                ChatComposerAttachmentPreview(
                                    source: .camera,
                                    imageData: imageData,
                                    displayName: L10n.text("chat.attachments.camera.result")
                                )
                            ],
                            for: threadID
                        )
                        stateStore.setCameraPresented(false, for: threadID)
                    }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: previewPresentedBinding) {
                if let selectedPreview {
                    HanlinPreviewSheet(
                        attachment: selectedPreview,
                        onClose: {
                            stateStore.setPreviewSelection(nil, for: threadID)
                        }
                    )
                }
            }
            .sheet(isPresented: $inputExpandedSheet) {
                hanlinExpandedEditorSheet
            }
    }

    private var content: some View {
        VStack(spacing: 6) {
            if composerDraft.attachments.isEmpty == false {
                attachmentStrip
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
            }

            VStack(spacing: 0) {
                HStack(alignment: .bottom) {
                    ZStack(alignment: .topLeading) {
                        if composerDraft.text.isEmpty {
                            Text(L10n.text("chat.input.placeholder"))
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                        }

                        HanlinChatTextView(
                            text: Binding(
                                get: { stateStore.draft(for: threadID) },
                                set: { stateStore.setDraft($0, for: threadID) }
                            ),
                            measuredHeight: $inputHeight
                        )
                        .frame(height: min(max(inputHeight, 44), 160))
                    }
                    .padding(.leading, 12)

                    Button {
                    } label: {
                        Image(systemName: "microphone")
                            .foregroundStyle(Color(.systemGray))
                            .padding(.trailing, 3)
                    }
                    .disabled(stateStore.isSending)

                    Button {
                        inputExpandedSheet = true
                    } label: {
                        Image(systemName: inputExpandedSheet ? "chevron.down" : "chevron.up")
                            .foregroundStyle(Color(.systemGray))
                            .padding(.trailing, 12)
                    }
                    .disabled(stateStore.isSending)
                }

                HStack(spacing: 6) {
                    plusButton

                    ChatComposerRuntimeTogglesRow(
                        threadID: threadID,
                        modelReasoning: modelReasoning,
                        stateStore: stateStore
                    )

                    Spacer(minLength: 0)

                    trailingSendControl
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.top, composerDraft.attachments.isEmpty ? 12 : 6)
        }
    }

    private var hanlinExpandedEditorSheet: some View {
        NavigationView {
            TextEditor(
                text: Binding(
                    get: { stateStore.draft(for: threadID) },
                    set: { stateStore.setDraft($0, for: threadID) }
                )
            )
            .padding(12)
            .navigationTitle(L10n.text("chat.composer.expanded.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("common.ok")) {
                        inputExpandedSheet = false
                    }
                }
            }
        }
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(composerDraft.attachments) { attachment in
                    HanlinAttachmentThumbnail(
                        attachment: attachment,
                        isSelected: composerDraft.previewSelection == attachment.id,
                        onTap: {
                            stateStore.setPreviewSelection(attachment.id, for: threadID)
                        },
                        onRemove: {
                            stateStore.removeComposerAttachment(id: attachment.id, for: threadID)
                        }
                    )
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var plusButton: some View {
        Button {
            stateStore.setAttachmentMenuPresented(true, for: threadID)
        } label: {
            Image(systemName: "plus.circle")
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .foregroundStyle(plusForeground)
                .rotationEffect(.degrees(attachmentMenuOpen ? 45 : 0))
                .animation(.spring(response: 0.5), value: attachmentMenuOpen)
        }
        .buttonStyle(.plain)
        .disabled(stateStore.isSending || composerDraft.attachments.count > 4)
        .accessibilityLabel(L10n.text("chat.attachments.button"))
    }

    private var plusForeground: Color {
        if stateStore.isSending || composerDraft.attachments.count > 4 {
            return Color(.systemGray)
        }
        if attachmentMenuOpen {
            return Color(uiColor: .systemRed)
        }
        return Color.accentColor
    }

    private var trailingSendControl: some View {
        Group {
            if stateStore.isSending {
                Image(systemName: "stop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .foregroundStyle(Color(uiColor: .systemRed))
            } else if canSendPayload {
                Button(action: onSend) {
                    Image(systemName: "arrowtriangle.up.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "arrowtriangle.up.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .foregroundStyle(Color(.systemGray))
            }
        }
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

    private var previewPresentedBinding: Binding<Bool> {
        Binding(
            get: { selectedPreview != nil },
            set: { isPresented in
                if isPresented == false {
                    stateStore.setPreviewSelection(nil, for: threadID)
                }
            }
        )
    }
}

// MARK: - 专业版专用子视图（与 ChatComposerView 内类型无共享）

private struct HanlinAttachmentThumbnail: View {
    let attachment: ChatComposerAttachmentPreview
    let isSelected: Bool
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onTap) {
                previewImage
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
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
            if let image = UIImage(data: attachment.imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color(uiColor: .secondarySystemFill))
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    )
            }
        }
    }
}

private struct HanlinAttachmentSheet: View {
    let isCameraAvailable: Bool
    let onPhotos: () -> Void
    let onCamera: () -> Void
    let onFiles: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                Text(L10n.text("chat.attachments.title"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(L10n.text("chat.attachments.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                attachmentRow(
                    title: L10n.text("chat.attachments.photos"),
                    subtitle: L10n.text("chat.attachments.photos.subtitle"),
                    systemImage: "photo.on.rectangle.angled",
                    action: onPhotos
                )

                attachmentRow(
                    title: L10n.text("chat.attachments.camera"),
                    subtitle: isCameraAvailable
                        ? L10n.text("chat.attachments.camera.subtitle")
                        : L10n.text("chat.attachments.camera.unavailable"),
                    systemImage: "camera",
                    action: onCamera
                )
                .disabled(isCameraAvailable == false)

                attachmentRow(
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
        .navigationViewStyle(.stack)
    }

    private func attachmentRow(
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

private struct HanlinPreviewSheet: View {
    let attachment: ChatComposerAttachmentPreview
    let onClose: () -> Void

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.opacity(0.95)
                    .ignoresSafeArea()

                if let image = UIImage(data: attachment.imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(20)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo")
                            .font(.system(size: 36))
                        Text(L10n.text("chat.attachments.preview.unavailable"))
                            .font(.body)
                    }
                    .foregroundColor(.white.opacity(0.8))
                }
            }
            .navigationBarTitle(attachment.displayName, displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.text("common.ok"), action: onClose)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

private struct HanlinChatTextView: UIViewRepresentable {
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
        let nextHeight = max(measured, 44)
        if abs(measuredHeight - nextHeight) > 0.5 {
            DispatchQueue.main.async {
                measuredHeight = nextHeight
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: HanlinChatTextView

        init(_ parent: HanlinChatTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.recalculateHeight(for: textView)
        }
    }
}

private struct HanlinPhotoLibraryPicker: UIViewControllerRepresentable {
    let onCancel: () -> Void
    let onImagesPicked: ([UIImage]) -> Void

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
        private let parent: HanlinPhotoLibraryPicker

        init(_ parent: HanlinPhotoLibraryPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard results.isEmpty == false else {
                parent.onCancel()
                return
            }

            let dispatchGroup = DispatchGroup()
            var images: [UIImage] = []

            for result in results {
                dispatchGroup.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    defer { dispatchGroup.leave() }
                    if let image = object as? UIImage {
                        images.append(image)
                    }
                }
            }

            dispatchGroup.notify(queue: .main) {
                self.parent.onImagesPicked(images)
            }
        }
    }
}

private struct HanlinCameraPicker: UIViewControllerRepresentable {
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
        private let parent: HanlinCameraPicker

        init(_ parent: HanlinCameraPicker) {
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
