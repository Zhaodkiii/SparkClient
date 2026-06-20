import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 统一文件选择入口：保留拍照、相册、文件三入口能力。
/// 相册入口使用 `PhotosPicker` 多选。
struct MedicalDocumentFilePickerMenu<ButtonContent: View>: View {
    let buttonContent: () -> ButtonContent
    let onFilesSelected: ([MedicalUploadLocalFile]) -> Void
    private let logger: Logger

    @State private var showDocPicker = false
    @State private var showCameraPicker = false
    @State private var showCameraUnavailableAlert = false
    @State private var showPhotoPicker = false
    @State private var photoItems: [PhotosPickerItem] = []

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
                showPhotoPicker = true
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
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $photoItems,
            maxSelectionCount: 10,
            matching: .images
        )
        .onChange(of: photoItems) { items in
            Task {
                let files = await convertPhotoItems(items)
                if files.isEmpty == false {
                    logger.info("相册导入成功，数量=\(files.count)", module: .medical)
                    onFilesSelected(files)
                } else {
                    logger.warning("相册导入完成，但未获取到可用文件。", module: .medical)
                }
                photoItems = []
            }
        }
        .fileImporter(
            isPresented: $showDocPicker,
            allowedContentTypes: [.image, .pdf],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else {
                logger.warning("文件选择器取消或失败。", module: .medical)
                return
            }
            let files = urls.compactMap { url in
                MedicalUploadLocalFileImportSupport.copyToTempFile(from: url, logger: logger)
            }
            if files.isEmpty == false {
                logger.info("文档导入成功，数量=\(files.count)", module: .medical)
                onFilesSelected(files)
            } else {
                logger.warning("文档导入完成，但未生成临时文件。", module: .medical)
            }
        }
        .sheet(isPresented: $showCameraPicker) {
            SystemImagePicker(
                source: .camera,
                onCancel: { showCameraPicker = false },
                onImagePicked: { image in
                    showCameraPicker = false
                    if let file = saveUIImageToTemp(image: image, namePrefix: "camera") {
                        logger.info("相机拍照导入成功。", module: .medical)
                        onFilesSelected([file])
                    } else {
                        logger.error("相机拍照后保存临时文件失败。", module: .medical)
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
            logger.info("准备打开相机。", module: .medical)
            showCameraPicker = true
        } else {
            logger.warning("设备不支持相机。", module: .medical)
            showCameraUnavailableAlert = true
        }
    }

    private func convertPhotoItems(_ items: [PhotosPickerItem]) async -> [MedicalUploadLocalFile] {
        var files: [MedicalUploadLocalFile] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let file = saveDataToTemp(data: data, preferredExtension: "jpg", namePrefix: "photo") else {
                continue
            }
            files.append(file)
        }
        return files
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
            logger.error("写入临时文件失败：\(error.localizedDescription)", module: .medical)
            return nil
        }
    }
}
