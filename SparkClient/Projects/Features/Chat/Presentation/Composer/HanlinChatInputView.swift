import PhotosUI
import SwiftUI
import UIKit

/// 专业版输入区（与 `ChatComposerView` 完全分离的实现，不共用 SwiftUI 视图层级）。
struct HanlinChatInputView: View {
    let threadID: UUID
    let modelReasoning: ChatModelReasoningContext
    @ObservedObject var stateStore: ChatStateStore
    @ObservedObject var memberContextStore: MemberContextStore
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    let boundMemberID: Int?
    let modelRows: [AIScenarioRemoteModelRow]
    let medicalQueryAPI: SparkMedicalQueryAPI
    let initialCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    let memberCompleteDataFetcher: any MemberCompleteDataFetching
    let fileTransferService: FileTransferService
    let onSend: () -> Void
    let onCancel: () -> Void
    let onAttachmentsPicked: ([ChatComposerAttachmentPreview]) -> Void
    let onRemoveAttachment: (UUID) -> Void
    let onSetMemberBinding: (Int?) -> Void
    let onRemoveHealthResourceRef: (HealthResourceRef) -> Void
    let onClearHealthResourceRefs: () -> Void

    @State private var inputHeight: CGFloat = 52
    @State private var voiceInputSheet = false
    @State private var attachmentPreviewRoute: ChatAttachmentPreviewRoute?
    @State private var healthResourcePreviewRef: HealthResourceRef?

    private var composerDraft: ChatComposerDraft {
        stateStore.composerDraft(for: threadID)
    }

    private var attachmentMenuOpen: Bool {
        composerDraft.isShowingAttachmentMenu
    }

    private var canSendPayload: Bool {
        (composerDraft.trimmedText.isEmpty == false || composerDraft.hasVisualContent)
            && stateStore.hasBlockingPreparedAttachmentWork(for: threadID) == false
    }

    var body: some View {
        content
            .sheet(isPresented: photoPickerBinding, onDismiss: {
                stateStore.setAttachmentMenuPresented(false, for: threadID)
            }) {
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
            .fullScreenCover(isPresented: cameraBinding, onDismiss: {
                stateStore.setAttachmentMenuPresented(false, for: threadID)
            }) {
                CustomCameraFullScreenView(
                    onMediaBatchCaptured: { mediaItems in
                        SparkLogger.log(
                            level: .info,
                            module: .camera,
                            message: "HanlinChatInputView onMediaBatchCaptured closing camera count=\(mediaItems.count)"
                        )
                        handleCameraMediaBatch(mediaItems)
                        stateStore.setCameraPresented(false, for: threadID)
                    },
                    onImageCaptured: { image in
                        SparkLogger.log(
                            level: .info,
                            module: .camera,
                            message: "HanlinChatInputView onImageCaptured closing camera"
                        )
                        if let attachment = makeCameraAttachment(from: image) {
                            let remaining = remainingComposerAttachmentCapacity
                            if remaining > 0 {
                                onAttachmentsPicked([attachment])
                            } else {
                                SparkLogger.log(
                                    level: .warning,
                                    module: .camera,
                                    message: "HanlinChatInputView onImageCaptured skipped: attachment limit reached"
                                )
                            }
                        }
                        stateStore.setCameraPresented(false, for: threadID)
                    },
                    onVideoCaptured: { _, _ in
                        SparkLogger.log(
                            level: .info,
                            module: .camera,
                            message: "HanlinChatInputView onVideoCaptured closing camera; chat attachments do not import video yet"
                        )
                        stateStore.setCameraPresented(false, for: threadID)
                    },
                    onDismiss: {
                        SparkLogger.log(
                            level: .info,
                            module: .camera,
                            message: "HanlinChatInputView onDismiss closing camera"
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
            .fullScreenCover(item: imagePreviewRequestBinding) { request in
                SecondCameraPublicMediaPreview(
                    inputs: request.inputs,
                    selectedID: request.selectedID,
                    mode: .readOnly,
                    onClose: { attachmentPreviewRoute = nil }
                )
            }
            .sheet(item: quickLookRequestBinding) { request in
                UnifiedFilePreview(
                    inputs: request.inputs,
                    startIndex: request.startIndex,
                    onClose: { attachmentPreviewRoute = nil }
                )
            }
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
                            minimumHeight: 52,
                            maximumHeight: 160,
                            isSending: stateStore.isSending
                        )
                        .frame(height: inputHeight)
                    }
                    .padding(.leading, 12)

                    // 语音目前先隐藏 后期介入电话
#if DEBUG
                    Button {
                        voiceInputSheet = true
                    } label: {
                        Image(systemName: "microphone.circle")
                            .foregroundStyle(Color(.systemGray))
                            .padding(.trailing, 3)
                    }
                    .disabled(stateStore.isSending)
#endif

                }

                HStack(spacing: 6) {
                    plusButton

                    ChatComposerRuntimeTogglesRow(
                        threadID: threadID,
                        modelReasoning: modelReasoning,
                        stateStore: stateStore,
                        memberContextStore: memberContextStore,
                        aiSettingsViewModel: aiSettingsViewModel,
                        boundMemberID: boundMemberID,
                        modelRows: modelRows,
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
                            openAttachmentPreview(
                                attachmentID: attachment.id,
                                attachments: composerDraft.attachments
                            )
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
            stateStore.setAttachmentMenuPresented(!attachmentMenuOpen, for: threadID)
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

    private var imagePreviewRequestBinding: Binding<ChatAttachmentPreviewRoute.ImageRequest?> {
        Binding(
            get: {
                guard case .images(let request) = attachmentPreviewRoute else { return nil }
                return request
            },
            set: { request in
                if request == nil {
                    attachmentPreviewRoute = nil
                }
            }
        )
    }

    private var quickLookRequestBinding: Binding<ChatAttachmentPreviewRoute.QuickLookRequest?> {
        Binding(
            get: {
                guard case .quickLook(let request) = attachmentPreviewRoute else { return nil }
                return request
            },
            set: { request in
                if request == nil {
                    attachmentPreviewRoute = nil
                }
            }
        )
    }

    private func openAttachmentPreview(
        attachmentID: UUID,
        attachments: [ChatComposerAttachmentPreview]
    ) {
        guard attachmentPreviewRoute == nil else { return }
        attachmentPreviewRoute = ChatAttachmentPreviewRequestFactory.makeRoute(
            attachments: attachments,
            tappedID: attachmentID
        )
    }

    /// 与加号按钮禁用条件 `attachments.count > 4` 对齐：最多 5 个附件。
    private var maxComposerAttachments: Int { 5 }

    private var remainingComposerAttachmentCapacity: Int {
        max(0, maxComposerAttachments - composerDraft.attachments.count)
    }

    private func handleCameraMediaBatch(_ mediaItems: [CustomCameraMedia]) {
        let videoCount = mediaItems.filter { $0.getVideo() != nil }.count
        if videoCount > 0 {
            SparkLogger.log(
                level: .info,
                module: .camera,
                message: "HanlinChatInputView batch contains \(videoCount) video(s); chat attachments do not import video yet"
            )
        }

        let attachments = makeCameraAttachments(from: mediaItems)
        if attachments.isEmpty {
            let imageCount = mediaItems.compactMap { $0.getImage() }.count
            if imageCount > 0 {
                SparkLogger.log(
                    level: .error,
                    module: .camera,
                    message: "HanlinChatInputView onMediaBatchCaptured produced no attachments from \(imageCount) image(s)"
                )
            }
            return
        }
        onAttachmentsPicked(attachments)
    }

    private func makeCameraAttachments(from mediaItems: [CustomCameraMedia]) -> [ChatComposerAttachmentPreview] {
        let remaining = remainingComposerAttachmentCapacity
        guard remaining > 0 else {
            SparkLogger.log(
                level: .warning,
                module: .camera,
                message: "HanlinChatInputView batch skipped: attachment limit reached"
            )
            return []
        }
        return Array(
            mediaItems
                .compactMap { $0.getImage() }
                .compactMap { makeCameraAttachment(from: $0) }
                .prefix(remaining)
        )
    }

    private func makeCameraAttachment(from image: UIImage) -> ChatComposerAttachmentPreview? {
        guard let imageData = image.jpegData(compressionQuality: 0.88) ?? image.pngData() else {
            SparkLogger.log(
                level: .error,
                module: .camera,
                message: "HanlinChatInputView failed to encode camera image"
            )
            return nil
        }
        return ChatComposerAttachmentPreview(
            source: .camera,
            data: imageData,
            displayName: L10n.text("chat.attachments.camera.result"),
            mimeType: "image/jpeg",
            utTypeIdentifier: "public.jpeg"
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
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byCharWrapping
        textView.textContainer.widthTracksTextView = true
        textView.textContainer.maximumNumberOfLines = 0
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // CHAT-000035：ChatView 在详情页内切换 Thread 时 SwiftUI 可能复用
        // UITextView/Coordinator；必须先把当前 Thread 的 Binding 同步给代理，
        // 否则输入会继续写入旧 Thread，并被当前 Thread 的草稿回刷覆盖。
        context.coordinator.parent = self
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
        var parent: HanlinChatTextUIKitView

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
