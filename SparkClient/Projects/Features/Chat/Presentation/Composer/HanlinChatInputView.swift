import PhotosUI
import SwiftUI
import UIKit

/// 专业版输入区（与 `ChatComposerView` 完全分离的实现，不共用 SwiftUI 视图层级）。
struct HanlinChatInputView: View {
    let threadID: UUID
    let modelReasoning: ChatModelReasoningContext
    @ObservedObject var stateStore: ChatStateStore
    @ObservedObject var memberContextStore: MemberContextStore
    let boundMemberID: Int?
    let medicalQueryAPI: SparkMedicalQueryAPI
    let initialCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    let memberCompleteDataFetcher: any MemberCompleteDataFetching
    let fileTransferService: FileTransferService
    let onSend: () -> Void
    let onCancel: () -> Void
    let onRequestFileImport: () -> Void
    let onAttachmentsPicked: ([ChatComposerAttachmentPreview]) -> Void
    let onRemoveAttachment: (UUID) -> Void
    let onSetMemberBinding: (Int?) -> Void
    let onRemoveHealthResourceRef: (HealthResourceRef) -> Void
    let onClearHealthResourceRefs: () -> Void

    @State private var inputHeight: CGFloat = 24
    @State private var voiceInputSheet = false
    @State private var showUnifiedFilePreview = false
    @State private var unifiedFilePreviewStartIndex = 0
    @State private var healthResourcePreviewRef: HealthResourceRef?

    private var composerDraft: ChatComposerDraft {
        stateStore.composerDraft(for: threadID)
    }

    private var attachmentMenuOpen: Bool {
        composerDraft.isShowingAttachmentMenu
    }

    private var canOpenCamera: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    private var canSendPayload: Bool {
        (composerDraft.trimmedText.isEmpty == false || composerDraft.hasVisualContent)
            && stateStore.hasBlockingPreparedAttachmentWork(for: threadID) == false
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
                HanlinCameraPicker(
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
                            ]
                        )
                        stateStore.setCameraPresented(false, for: threadID)
                    }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $voiceInputSheet) {
                SparkVoiceInputSheet(
                    text: draftBinding,
                    isPresented: $voiceInputSheet
                )
                .sparkInputPresentationChromeIfAvailable()
            }
            .unifiedFilePreview(
                isPresented: $showUnifiedFilePreview,
                inputs: composerDraft.attachments.map(\.previewInput),
                startIndex: unifiedFilePreviewStartIndex
            )
            .sheet(item: $healthResourcePreviewRef) { ref in
                ChatHealthResourcePreviewSheet(
                    ref: ref,
                    memberContextStore: memberContextStore,
                    medicalQueryAPI: medicalQueryAPI,
                    initialCompleteData: initialCompleteData,
                    memberCompleteDataFetcher: memberCompleteDataFetcher,
                    fileTransferService: fileTransferService
                )
            }
            .onChange(of: boundMemberID) { newValue in
                stateStore.pruneHealthResourceRefs(matchingMemberID: newValue, for: threadID)
            }
    }

    private var composerAttachmentAreaHasContent: Bool {
        composerDraft.attachments.isEmpty == false
            || composerDraft.pendingHealthResourceRefs.isEmpty == false
    }

    private var content: some View {
        VStack(spacing: 6) {
            if composerAttachmentAreaHasContent {
                composerAttachmentArea
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
                            text: draftBinding,
                            measuredHeight: $inputHeight,
                            minimumHeight: 44,
                            maximumHeight: 160,
                            isSending: stateStore.isSending
                        )
                        .frame(height: inputHeight)
                    }
                    .padding(.leading, 12)

                    // 语音目前先隐藏 后期介入电话
//                    Button {
//                        voiceInputSheet = true
//                    } label: {
//                        Image(systemName: "microphone.circle")
//                            .foregroundStyle(Color(.systemGray))
//                            .padding(.trailing, 3)
//                    }
//                    .disabled(stateStore.isSending)
                }

                HStack(spacing: 6) {
                    plusButton

                    ChatComposerRuntimeTogglesRow(
                        threadID: threadID,
                        modelReasoning: modelReasoning,
                        stateStore: stateStore,
                        memberContextStore: memberContextStore,
                        boundMemberID: boundMemberID,
                        onSetMemberBinding: onSetMemberBinding
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
//            .padding(.top, composerAttachmentAreaHasContent ? 6 : 12)
        }
    }

    @ViewBuilder
    private var composerAttachmentArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            if composerDraft.attachments.isEmpty == false {
                attachmentStrip
            }
            if composerDraft.pendingHealthResourceRefs.isEmpty == false {
                healthResourcePreviewStrip
            }
        }
    }

    private var healthResourcePreviewStrip: some View {
        let refs = composerDraft.pendingHealthResourceRefs
        return HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(refs.enumerated()), id: \.element.id) { index, ref in
                        HanlinHealthResourceThumbnail(
                            ref: ref,
                            index: index + 1,
                            total: refs.count,
                            onTap: { healthResourcePreviewRef = ref },
                            onRemove: { onRemoveHealthResourceRef(ref) }
                        )
                    }
                }
                .padding(.horizontal, 2)
            }
            if refs.count > 1 {
                Button(action: onClearHealthResourceRefs) {
                    Text(L10n.text("chat.ask_report.strip.clear_all"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
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
                        uploadProgress: stateStore.composerAttachmentUploadProgress[attachment.id],
                        isSelected: composerDraft.previewSelection == attachment.id,
                        onTap: {
                            stateStore.setPreviewSelection(attachment.id, for: threadID)
                            if let index = composerDraft.attachments.firstIndex(where: { $0.id == attachment.id }) {
                                unifiedFilePreviewStartIndex = index
                                showUnifiedFilePreview = true
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
                Button(action: onCancel) {
                    Image(systemName: "stop.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .foregroundStyle(Color(uiColor: .systemRed))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("chat.input.stop"))
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

    private var draftBinding: Binding<String> {
        Binding(
            get: { stateStore.draft(for: threadID) },
            set: { stateStore.setDraft($0, for: threadID) }
        )
    }

}

// MARK: - 专业版专用子视图（与 ChatComposerView 内类型无共享）

private struct HanlinAttachmentThumbnail: View {
    let attachment: ChatComposerAttachmentPreview
    var uploadProgress: Double?
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
                    .overlay {
                        if let p = uploadProgress, p < 1.0 - 0.001 {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
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

private struct HanlinAttachmentSheet: View {
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

private struct HanlinChatTextView: View {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    let minimumHeight: CGFloat
    let maximumHeight: CGFloat
    let isSending: Bool

    @State private var inputExpandedSheet = false
    @State private var reachedScrollThreshold = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            HanlinChatTextUIKitView(
                text: $text,
                measuredHeight: $measuredHeight,
                minimumHeight: minimumHeight,
                maximumHeight: maximumHeight,
                onScrollThresholdChange: { reachedThreshold in
                    if reachedScrollThreshold != reachedThreshold {
                        reachedScrollThreshold = reachedThreshold
                    }
                }
            )
            .frame(maxWidth: .infinity)

            if reachedScrollThreshold {
                Button {
                    inputExpandedSheet = true
                } label: {
                    Image(systemName: inputExpandedSheet ? "chevron.down" : "chevron.up")
                        .foregroundStyle(Color(.systemGray))
                        .padding(.trailing, 12)
                }
                .disabled(isSending)
                .padding(.top)
            }
                
        }
        .sheet(isPresented: $inputExpandedSheet) {
            SparkPromptInputDrawerSheet(
                text: $text,
                isPresented: $inputExpandedSheet
            )
            .sparkInputPresentationChromeIfAvailable()
        }
    }
}

private struct HanlinChatTextUIKitView: UIViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    let minimumHeight: CGFloat
    let maximumHeight: CGFloat
    let onScrollThresholdChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.showsVerticalScrollIndicator = true
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
        let fittingSize = CGSize(width: max(textView.bounds.width, 1), height: .greatestFiniteMagnitude)
        let measured = textView.sizeThatFits(fittingSize).height
        let nextHeight = min(max(measured, minimumHeight), maximumHeight)
        let shouldScroll = measured > maximumHeight

        if textView.isScrollEnabled != shouldScroll {
            textView.isScrollEnabled = shouldScroll
        }
        DispatchQueue.main.async {
            onScrollThresholdChange(shouldScroll)
        }
        if shouldScroll == false && textView.contentOffset != .zero {
            textView.setContentOffset(.zero, animated: false)
        }
        if abs(measuredHeight - nextHeight) > 0.5 {
            DispatchQueue.main.async {
                measuredHeight = nextHeight
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: HanlinChatTextUIKitView

        init(_ parent: HanlinChatTextUIKitView) {
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
        private let parent: HanlinPhotoLibraryPicker

        init(_ parent: HanlinPhotoLibraryPicker) {
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
