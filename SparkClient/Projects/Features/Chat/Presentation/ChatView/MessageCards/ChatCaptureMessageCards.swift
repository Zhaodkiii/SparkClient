import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct ChatCaptureTypeMessageCard: View {
    let payload: ChatCaptureMessageCardPayload
    let onAttachmentsPicked: ([ChatComposerAttachmentPreview]) -> Void
    let onCancel: () -> Void

    @State private var showPhotoLibrary = false
    @State private var showCamera = false
    @State private var showFiles = false
    @State private var showUnifiedFilePreview = false
    @State private var previewInputs: [FilePreviewInput] = []
    @State private var previewStartIndex = 0

    var body: some View {
        let spec = CaptureCardSpec(payload.cardType)
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: statusIcon)
                        .foregroundStyle(spec.tint)
                    Text(spec.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    statusBadge(spec: spec)
                }
                Text(statusText(spec: spec))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if payload.selectedAttachments.isEmpty == false {
                attachmentList(spec: spec)
            } else if spec.examples.isEmpty == false {
                HStack(spacing: 12) {
                    ForEach(spec.examples) { example in
                        exampleItem(title: example.title, icon: example.icon, tint: spec.tint)
                    }
                }
            }

            if payload.status == .pending || payload.status == .failed || payload.status == .selected {
                HStack(spacing: 10) {
                    actionButton(icon: "camera.fill", title: L10n.text("chat.capture_card.action.camera"), color: spec.tint) {
                        showCamera = true
                    }
                    actionButton(icon: "photo.on.rectangle", title: L10n.text("chat.capture_card.action.photo_library"), color: spec.tint) {
                        showPhotoLibrary = true
                    }
                    if spec.supportsFiles {
                        actionButton(icon: "doc.fill", title: L10n.text("chat.capture_card.action.files"), color: spec.tint) {
                            showFiles = true
                        }
                    }
                }
            } else if payload.status == .uploading || payload.status == .processing {
                Button(action: onCancel) {
                    Label(L10n.text("common.cancel"), systemImage: "xmark.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(spec.tint)
            }

            if let error = payload.errorMessage, error.isEmpty == false {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .systemRed))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let disclaimer = spec.disclaimer {
                Text(disclaimer)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
        .unifiedFilePreview(
            isPresented: $showUnifiedFilePreview,
            inputs: previewInputs,
            startIndex: previewStartIndex
        )
        .sheet(isPresented: $showPhotoLibrary) {
            ChatCapturePhotoLibraryPicker(
                onCancel: {
                    showPhotoLibrary = false
                },
                onPhotosPicked: { photos in
                    let attachments = photos.map {
                        ChatComposerAttachmentPreview(
                            source: .photoLibrary,
                            data: $0.imageData,
                            displayName: $0.suggestedFileName
                        )
                    }
                    showPhotoLibrary = false
                    onAttachmentsPicked(attachments)
                }
            )
        }
        .fullScreenCover(isPresented: $showCamera) {
            ChatCaptureCameraPicker(
                onCancel: {
                    showCamera = false
                },
                onImagePicked: { image in
                    defer { showCamera = false }
                    guard let data = image.jpegData(compressionQuality: 0.88) ?? image.pngData() else {
                        return
                    }
                    let attachments = [
                        ChatComposerAttachmentPreview(
                            source: .camera,
                            data: data,
                            displayName: L10n.text("chat.attachments.camera.result")
                        )
                    ]
                    onAttachmentsPicked(attachments)
                }
            )
            .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $showFiles,
            allowedContentTypes: [.pdf, .plainText, .image, .jpeg, .png],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task {
                    let attachments = await ChatComposerAttachmentImporter.importFiles(urls: urls)
                    await MainActor.run {
                        onAttachmentsPicked(attachments)
                    }
                }
            case .failure:
                break
            }
        }
    }

    private func exampleItem(title: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(tint)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(height: 60)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionButton(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(color)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background(color.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var statusIcon: String {
        switch payload.status {
        case .pending, .selected: return "square.and.arrow.up"
        case .uploading: return "arrow.up.circle.fill"
        case .uploaded, .processing: return "doc.text.magnifyingglass"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }

    @ViewBuilder
    private func statusBadge(spec: CaptureCardSpec) -> some View {
        let text: String? = switch payload.status {
        case .pending: nil
        case .selected: L10n.text("chat.capture_card.status.selected", fallback: "已选择")
        case .uploading: L10n.text("chat.capture_card.status.uploading", fallback: "上传中")
        case .uploaded: L10n.text("chat.capture_card.status.uploaded", fallback: "已上传")
        case .processing: L10n.text("chat.capture_card.status.processing", fallback: "处理中")
        case .completed: L10n.text("chat.capture_card.status.completed", fallback: "已完成")
        case .failed: L10n.text("chat.capture_card.status.failed", fallback: "失败")
        case .cancelled: L10n.text("chat.capture_card.status.cancelled", fallback: "已取消")
        }
        if let text {
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(spec.tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(spec.tint.opacity(0.1), in: Capsule())
        }
    }

    private func statusText(spec: CaptureCardSpec) -> String {
        switch payload.status {
        case .pending:
            return spec.subtitle
        case .selected:
            return L10n.text("chat.capture_card.status_text.selected", fallback: "已选择材料，准备上传。")
        case .uploading:
            return L10n.text("chat.capture_card.status_text.uploading", fallback: "正在上传到安全文件存储，请稍候。")
        case .uploaded:
            return L10n.text("chat.capture_card.status_text.uploaded", fallback: "文件已上传，正在准备给 AI 使用的材料。")
        case .processing:
            return L10n.text("chat.capture_card.status_text.processing", fallback: "正在压缩图片并提取文字，对话稍后会自动继续。")
        case .completed:
            return payload.resultSummary ?? L10n.text("chat.capture_card.status_text.completed", fallback: "材料已处理完成，对话将继续。")
        case .failed:
            return L10n.text("chat.capture_card.status_text.failed", fallback: "上传或处理失败，可以重新选择材料。")
        case .cancelled:
            return payload.resultSummary ?? L10n.text("chat.capture_card.status_text.cancelled", fallback: "已取消上传。")
        }
    }

    private func attachmentList(spec: CaptureCardSpec) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(payload.selectedAttachments.enumerated()), id: \.element.id) { index, attachment in
                Button {
                    openPreview(startIndex: index)
                } label: {
                    attachmentRow(attachment, spec: spec)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func attachmentRow(_ attachment: ChatInlineCapturedAttachment, spec: CaptureCardSpec) -> some View {
        HStack(spacing: 10) {
            attachmentThumbnail(attachment, tint: spec.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(attachment.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(byteText(attachment.byteCount))
                    if payload.status == .uploading {
                        Text("\(Int((attachment.uploadProgress * 100).rounded()))%")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                if payload.status == .uploading {
                    ProgressView(value: attachment.uploadProgress)
                        .tint(spec.tint)
                }
            }
            Spacer(minLength: 0)
            trailingStatusIcon(for: attachment, tint: spec.tint)
        }
        .padding(10)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func attachmentThumbnail(_ attachment: ChatInlineCapturedAttachment, tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemFill))
            if attachment.kind == .image,
               let url = attachment.localPreviewURL,
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if attachment.kind == .image, let url = attachment.publicURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty:
                        ProgressView()
                    case .failure:
                        Image(systemName: "photo.fill").foregroundStyle(tint)
                    @unknown default:
                        Image(systemName: "photo.fill").foregroundStyle(tint)
                    }
                }
            } else {
                Image(systemName: attachment.kind == .pdf ? "doc.richtext.fill" : "doc.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
            }
            if payload.status == .uploading {
                Color.black.opacity(0.08)
                ProgressView(value: attachment.uploadProgress)
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .controlSize(.small)
            }
        }
        .frame(width: 46, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func trailingStatusIcon(for attachment: ChatInlineCapturedAttachment, tint: Color) -> some View {
        if attachment.fileID != nil {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(tint)
        } else if payload.status == .uploading {
            Image(systemName: "arrow.up.circle")
                .foregroundStyle(.secondary)
        } else {
            Image(systemName: "eye")
                .foregroundStyle(.secondary)
        }
    }

    private func openPreview(startIndex: Int) {
        let inputs = payload.selectedAttachments.compactMap(previewInput(for:))
        guard inputs.isEmpty == false else { return }
        previewInputs = inputs
        previewStartIndex = min(max(0, startIndex), inputs.count - 1)
        showUnifiedFilePreview = true
    }

    private func previewInput(for attachment: ChatInlineCapturedAttachment) -> FilePreviewInput? {
        if let url = attachment.localPreviewURL {
            return FilePreviewInput(
                id: attachment.id,
                fileURL: url,
                displayName: attachment.displayName,
                mimeType: attachment.mimeType
            )
        }
        if let url = attachment.publicURL {
            return FilePreviewInput(
                id: attachment.id,
                fileURL: url,
                displayName: attachment.displayName,
                mimeType: attachment.mimeType
            )
        }
        return nil
    }

    private func byteText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

private struct CaptureCardSpec {
    let title: String
    let subtitle: String
    let disclaimer: String?
    let tint: Color
    let examples: [CaptureCardExample]
    let supportsFiles: Bool

    init(_ type: ChatCaptureCardType) {
        switch type {
        case .reportPhoto:
            title = L10n.text("chat.capture_card.report.title")
            subtitle = L10n.text("chat.capture_card.report.subtitle")
            disclaimer = L10n.text("chat.capture_card.report.disclaimer")
            tint = .blue
            examples = [
                CaptureCardExample(title: L10n.text("chat.capture_card.report.example.flat"), icon: "doc.text.fill"),
                CaptureCardExample(title: L10n.text("chat.capture_card.report.example.complete"), icon: "iphone")
            ]
            supportsFiles = true
        case .medicineBoxPhoto:
            title = L10n.text("chat.capture_card.medicine_box.title")
            subtitle = L10n.text("chat.capture_card.medicine_box.subtitle")
            disclaimer = nil
            tint = .purple
            examples = [
                CaptureCardExample(title: L10n.text("chat.capture_card.medicine_box.example.flat"), icon: "shippingbox"),
                CaptureCardExample(title: L10n.text("chat.capture_card.medicine_box.example.front"), icon: "iphone")
            ]
            supportsFiles = false
        case .skinPhoto:
            title = L10n.text("chat.capture_card.skin.title")
            subtitle = L10n.text("chat.capture_card.skin.subtitle")
            disclaimer = nil
            tint = .green
            examples = []
            supportsFiles = false
        }
    }
}

private struct CaptureCardExample: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
}

private struct ChatCapturePhotoLibraryPicker: UIViewControllerRepresentable {
    let onCancel: () -> Void
    let onPhotosPicked: ([ChatComposerPickedPhoto]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

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
        private let parent: ChatCapturePhotoLibraryPicker

        init(_ parent: ChatCapturePhotoLibraryPicker) {
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

private struct ChatCaptureCameraPicker: UIViewControllerRepresentable {
    let onCancel: () -> Void
    let onImagePicked: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

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
        private let parent: ChatCaptureCameraPicker

        init(_ parent: ChatCaptureCameraPicker) {
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
