import SwiftUI
import UniformTypeIdentifiers

/// 统一文件选择入口（iOS 15 兼容版）：
/// 使用 `UIImagePickerController` 处理相册，不依赖 `PhotosPicker`。
struct MedicalDocumentLegacyFilePickerMenu<ButtonContent: View>: View {
    let buttonContent: () -> ButtonContent
    let onFilesSelected: ([MedicalUploadLocalFile]) -> Void
    private let logger: Logger

    @State private var showDocPicker = false
    @State private var showCameraPicker = false
    @State private var showPhotoLibraryPicker = false
    @State private var showCameraUnavailableAlert = false

    init(
        logger: Logger = ConsoleLogger(),
        @ViewBuilder buttonContent: @escaping () -> ButtonContent,
        onFilesSelected: @escaping ([MedicalUploadLocalFile]) -> Void
    ) {
        self.logger = logger
        self.buttonContent = buttonContent
        self.onFilesSelected = onFilesSelected
    }

    var body: some View {
        Menu {
            Button {
                presentCamera()
            } label: {
                Label("拍摄", systemImage: "camera.fill")
            }

            Button {
                showPhotoLibraryPicker = true
            } label: {
                Label("照片", systemImage: "photo.on.rectangle")
            }

            Button {
                showDocPicker = true
            } label: {
                Label("文件", systemImage: "doc.text.fill")
            }
        } label: {
            buttonContent()
        }
        .fileImporter(
            isPresented: $showDocPicker,
            allowedContentTypes: [.image, .pdf],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else {
                logger.warning("文件选择器取消或失败。", category: "medical_upload")
                return
            }
            let files = urls.compactMap(copyToTempFile)
            if files.isEmpty == false {
                logger.info("文档导入成功，数量=\(files.count)", category: "medical_upload")
                onFilesSelected(files)
            } else {
                logger.warning("文档导入完成，但未生成临时文件。", category: "medical_upload")
            }
        }
        .sheet(isPresented: $showCameraPicker) {
            KnowledgeImagePicker(
                source: .camera,
                onCancel: { showCameraPicker = false },
                onImagePicked: { image in
                    showCameraPicker = false
                    if let file = saveUIImageToTemp(image: image, namePrefix: "camera") {
                        logger.info("相机拍照导入成功。", category: "medical_upload")
                        onFilesSelected([file])
                    } else {
                        logger.error("相机拍照后保存临时文件失败。", category: "medical_upload")
                    }
                }
            )
        }
        .sheet(isPresented: $showPhotoLibraryPicker) {
            KnowledgeImagePicker(
                source: .photoLibrary,
                onCancel: { showPhotoLibraryPicker = false },
                onImagePicked: { image in
                    showPhotoLibraryPicker = false
                    if let file = saveUIImageToTemp(image: image, namePrefix: "photo_library") {
                        logger.info("iOS15 相册导入成功。", category: "medical_upload")
                        onFilesSelected([file])
                    } else {
                        logger.error("iOS15 相册导入后保存临时文件失败。", category: "medical_upload")
                    }
                }
            )
        }
        .alert("无法打开相机", isPresented: $showCameraUnavailableAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text("当前设备不支持相机。")
        }
    }

    private func presentCamera() {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            logger.info("准备打开相机。", category: "medical_upload")
            showCameraPicker = true
        } else {
            logger.warning("设备不支持相机。", category: "medical_upload")
            showCameraUnavailableAlert = true
        }
    }

    private func copyToTempFile(url: URL) -> MedicalUploadLocalFile? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let ext = url.pathExtension.isEmpty ? "pdf" : url.pathExtension
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("medical_upload_\(UUID().uuidString).\(ext)")
        do {
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.copyItem(at: url, to: target)
            return MedicalUploadLocalFile(
                url: target,
                displayName: url.lastPathComponent,
                mimeType: UTType(filenameExtension: ext)?.preferredMIMEType
            )
        } catch {
            logger.error("复制文件到临时目录失败：\(error.localizedDescription)", category: "medical_upload")
            return nil
        }
    }

    private func saveUIImageToTemp(image: UIImage, namePrefix: String) -> MedicalUploadLocalFile? {
        guard let data = image.jpegData(compressionQuality: 0.95) else { return nil }
        return saveDataToTemp(data: data, preferredExtension: "jpg", namePrefix: namePrefix)
    }

    private func saveDataToTemp(data: Data, preferredExtension: String, namePrefix: String) -> MedicalUploadLocalFile? {
        let filename = "\(namePrefix)_\(UUID().uuidString).\(preferredExtension)"
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: target, options: .atomic)
            return MedicalUploadLocalFile(
                url: target,
                displayName: filename,
                mimeType: UTType(filenameExtension: preferredExtension)?.preferredMIMEType
            )
        } catch {
            logger.error("写入临时文件失败：\(error.localizedDescription)", category: "medical_upload")
            return nil
        }
    }
}
