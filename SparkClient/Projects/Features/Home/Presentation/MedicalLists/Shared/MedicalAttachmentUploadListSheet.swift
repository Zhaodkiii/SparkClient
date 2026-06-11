import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

/// 医疗附件上传列表所支持的识别文档场景。
enum MedicalAttachmentUploadDocumentType: String, Identifiable, CaseIterable {
    case medicineBox
    case medicationPlan
    case examinationReport
    case healthExamReport
    case caseDocument

    var id: String { rawValue }

    var fileNamePrefix: String {
        switch self {
        case .medicineBox:
            return "medicine_box"
        case .medicationPlan:
            return "medication_plan"
        case .examinationReport:
            return "examination_report"
        case .healthExamReport:
            return "health_exam_report"
        case .caseDocument:
            return "case_document"
        }
    }

    var maxFileCount: Int {
        switch self {
        case .healthExamReport:
            return 1
        case .medicineBox, .medicationPlan, .examinationReport, .caseDocument:
            return 5
        }
    }

    var title: String {
        switch self {
        case .medicineBox:
            return L10n.text("medical.upload.medicine_box.sheet.title")
        case .medicationPlan:
            return L10n.text("medical.upload.medication_plan.sheet.title", fallback: "选择服药计划图片")
        case .examinationReport:
            return L10n.text("medical.upload.examination_report.sheet.title", fallback: "选择检查报告图片")
        case .healthExamReport:
            return L10n.text("medical.upload.health_exam_report.sheet.title", fallback: "选择体检报告")
        case .caseDocument:
            return L10n.text("medical.upload.case_document.sheet.title", fallback: "选择病历图片")
        }
    }

    var headerTitle: String {
        switch self {
        case .medicineBox:
            return L10n.text("medical.upload.medicine_box.sheet.header")
        case .medicationPlan:
            return L10n.text("medical.upload.medication_plan.sheet.header", fallback: "选择上传方式")
        case .examinationReport:
            return L10n.text("medical.upload.examination_report.sheet.header", fallback: "选择上传方式")
        case .healthExamReport:
            return L10n.text("medical.upload.health_exam_report.sheet.header", fallback: "选择上传方式")
        case .caseDocument:
            return L10n.text("medical.upload.case_document.sheet.header", fallback: "选择上传方式")
        }
    }

    var headerSubtitle: String {
        switch self {
        case .medicineBox:
            return L10n.text("medical.upload.medicine_box.sheet.subtitle")
        case .medicationPlan:
            return L10n.text("medical.upload.medication_plan.sheet.subtitle", fallback: "可一次选择多张处方、药品说明或服药计划图片，确认后开始识别。")
        case .examinationReport:
            return L10n.text("medical.upload.examination_report.sheet.subtitle", fallback: "可一次选择多张检查、检验或影像报告图片，确认后开始识别。")
        case .healthExamReport:
            return L10n.text("medical.upload.health_exam_report.sheet.subtitle", fallback: "一次仅选择 1 个体检报告文件，确认后开始识别。")
        case .caseDocument:
            return L10n.text("medical.upload.case_document.sheet.subtitle", fallback: "可一次选择最多 5 个门诊病历、出院小结或相关附件，确认后开始识别。")
        }
    }

    var emptyTitle: String {
        switch self {
        case .medicineBox:
            return L10n.text("medical.upload.medicine_box.sheet.empty_title")
        case .medicationPlan:
            return L10n.text("medical.upload.medication_plan.sheet.empty.title", fallback: "尚未选择文件")
        case .examinationReport:
            return L10n.text("medical.upload.examination_report.sheet.empty.title", fallback: "尚未选择文件")
        case .healthExamReport:
            return L10n.text("medical.upload.health_exam_report.sheet.empty.title", fallback: "尚未选择文件")
        case .caseDocument:
            return L10n.text("medical.upload.case_document.sheet.empty.title", fallback: "尚未选择文件")
        }
    }

    var emptySubtitle: String {
        switch self {
        case .medicineBox:
            return L10n.text("medical.upload.medicine_box.sheet.empty_subtitle")
        case .medicationPlan:
            return L10n.text("medical.upload.medication_plan.sheet.empty.subtitle", fallback: "可拍照、从相册选择或上传 PDF/图片")
        case .examinationReport:
            return L10n.text("medical.upload.examination_report.sheet.empty.subtitle", fallback: "可拍照、从相册选择或上传 PDF/图片")
        case .healthExamReport:
            return L10n.text("medical.upload.health_exam_report.sheet.empty.subtitle", fallback: "可拍照、从相册选择或上传 PDF/图片")
        case .caseDocument:
            return L10n.text("medical.upload.case_document.sheet.empty.subtitle", fallback: "可拍照、从相册选择或上传 PDF/图片")
        }
    }

    var cameraCover: MedicalAttachmentUploadCameraCover {
        switch self {
        case .medicineBox:
            return .medicineBoxCustomCamera
        case .medicationPlan, .examinationReport, .healthExamReport, .caseDocument:
            return .systemCamera
        }
    }
}

enum MedicalAttachmentUploadCameraCover: Identifiable {
    case medicineBoxCustomCamera
    case systemCamera

    var id: String {
        switch self {
        case .medicineBoxCustomCamera:
            return "medicineBoxCustomCamera"
        case .systemCamera:
            return "systemCamera"
        }
    }
}

struct MedicalAttachmentUploadListSheet: View {
    @Environment(\.dismiss) private var dismiss
    let documentType: MedicalAttachmentUploadDocumentType
    let onConfirm: ([MedicalUploadLocalFile]) -> Void

    @State private var localFiles: [MedicalUploadLocalFile] = []
    @State private var presentedCameraCover: MedicalAttachmentUploadCameraCover?
    @State private var showingPhotoPicker = false
    @State private var showingPhotoLibrary = false
    @State private var showingFileImporter = false
    @State private var showCameraUnavailableAlert = false
    @State private var filePreviewSelection: FilePreviewInput?
    @State private var fileLimitMessage: String?

    private let logger: Logger = ConsoleLogger()

    init(
        documentType: MedicalAttachmentUploadDocumentType,
        onConfirm: @escaping ([MedicalUploadLocalFile]) -> Void
    ) {
        self.documentType = documentType
        self.onConfirm = onConfirm
    }

    private var title: String { documentType.title }
    private var headerTitle: String { documentType.headerTitle }
    private var headerSubtitle: String { documentType.headerSubtitle }
    private var emptyTitle: String { documentType.emptyTitle }
    private var emptySubtitle: String { documentType.emptySubtitle }
    private var fileNamePrefix: String { documentType.fileNamePrefix }
    private var maxFileCount: Int { max(1, documentType.maxFileCount) }

    var body: some View {
        CompatibleNavigationContainer {
            AdaptiveToolSheetScrollView(bottomContentPadding: 0, extraChromeHeight: 120) {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    Divider()
                    entryTiles
                    if localFiles.isEmpty {
                        placeholder
                    } else {
                        selectionPreview
                    }
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("common.cancel")) {
                        dismiss()
                    }
                }
            }
        }
        .fullScreenCover(item: $presentedCameraCover) { cover in
            switch cover {
            case .medicineBoxCustomCamera:
                MedicineBoxCameraSceneView(
                    onCancel: { presentedCameraCover = nil },
                    onImagesCaptured: { images in
                        presentedCameraCover = nil
                        for captured in images {
                            if let file = saveUIImageToTemp(
                                image: captured.image,
                                namePrefix: "\(fileNamePrefix)_camera_\(captured.slot.fileNameSuffix)"
                            ) {
                                localFiles.append(file)
                            }
                        }
                    }
                )
            case .systemCamera:
                SystemImagePicker(
                    source: .camera,
                    onCancel: { presentedCameraCover = nil },
                    onImagePicked: { image in
                        presentedCameraCover = nil
                        if let file = saveUIImageToTemp(image: image, namePrefix: "\(fileNamePrefix)_camera") {
                            localFiles.append(file)
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showingPhotoLibrary) {
            SystemImagePicker(
                source: .photoLibrary,
                onCancel: { showingPhotoLibrary = false },
                onImagePicked: { image in
                    showingPhotoLibrary = false
                    if let file = saveUIImageToTemp(image: image, namePrefix: "\(fileNamePrefix)_photo") {
                        localFiles.append(file)
                    }
                }
            )
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.image, .pdf],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            appendFiles(urls.compactMap(copyToTempFile))
        }
        .overlay {
            if #available(iOS 16.0, *) {
                MedicalAttachmentPhotosPickerBridge(
                    isPresented: $showingPhotoPicker,
                    maxSelectionCount: remainingFileSlots,
                    fileNamePrefix: fileNamePrefix
                ) { files in
                    appendFiles(files)
                }
            }
        }
        .alert(L10n.text("medical.upload.medicine_box.sheet.camera_unavailable_title"), isPresented: $showCameraUnavailableAlert) {
            Button(L10n.text("common.ok"), role: .cancel) {}
        } message: {
            Text(L10n.text("medical.upload.medicine_box.sheet.camera_unavailable_message"))
        }
        .alert(L10n.text("medical.upload.medicine_box.sheet.file_limit_title"), isPresented: Binding(
            get: { fileLimitMessage != nil },
            set: { if !$0 { fileLimitMessage = nil } }
        )) {
            Button(L10n.text("common.ok"), role: .cancel) {}
        } message: {
            Text(fileLimitMessage ?? "")
        }
        .unifiedFilePreview(selection: $filePreviewSelection)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(headerTitle)
                .font(.system(size: 17, weight: .semibold))
            Text(headerSubtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private var entryTiles: some View {
        HStack(spacing: 12) {
            attachmentUploadTile(
                icon: "camera",
                title: L10n.text("medical.upload.medicine_box.sheet.tile.camera.title"),
                subtitle: L10n.text("medical.upload.medicine_box.sheet.tile.camera.subtitle"),
                tint: .blue
            ) {
                presentCamera()
            }
            attachmentUploadTile(
                icon: "photo.on.rectangle",
                title: L10n.text("medical.upload.medicine_box.sheet.tile.photo.title"),
                subtitle: L10n.text("medical.upload.medicine_box.sheet.tile.photo.subtitle"),
                tint: .purple
            ) {
                presentPhotoLibrary()
            }
            attachmentUploadTile(
                icon: "doc",
                title: L10n.text("medical.upload.medicine_box.sheet.tile.file.title"),
                subtitle: L10n.text("medical.upload.medicine_box.sheet.tile.file.subtitle"),
                tint: .green
            ) {
                presentFileImporter()
            }
        }
        .padding(.top, 6)
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 40))
                .foregroundStyle(.purple.opacity(0.65))
            Text(emptyTitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.purple)
            Text(emptySubtitle)
                .font(.system(size: 12))
                .foregroundStyle(.purple.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.purple.opacity(0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
                .foregroundStyle(Color.purple.opacity(0.35))
        )
        .padding(.top, 6)
    }

    private var selectionPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.text("medical.upload.medicine_box.sheet.selected_label"))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(
                    String(
                        format: L10n.text("medical.upload.medicine_box.sheet.selected_count"),
                        localFiles.count,
                        maxFileCount
                    )
                )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                spacing: 12
            ) {
                ForEach(localFiles) { file in
                    MedicalDocumentFilePreviewSquareCard(
                        item: file.previewInput,
                        onPreview: { filePreviewSelection = file.previewInput },
                        onDelete: { localFiles.removeAll { $0.id == file.id } }
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var bottomBar: some View {
        HStack {
            Button {
                localFiles.removeAll()
            } label: {
                Label(L10n.text("medical.upload.medicine_box.sheet.clear"), systemImage: "trash")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button {
                onConfirm(localFiles)
                dismiss()
            } label: {
                Label(L10n.text("medical.upload.medicine_box.sheet.start_recognition"), systemImage: "wand.and.stars")
            }
            .buttonStyle(.borderedProminent)
            .disabled(localFiles.isEmpty)
        }
        .padding(10)
    }

    private var remainingFileSlots: Int {
        max(0, maxFileCount - localFiles.count)
    }

    private func attachmentUploadTile(
        icon: String,
        title: String,
        subtitle: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(tint.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(tint.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [6]))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }

    private func presentPhotoLibrary() {
        guard ensureCanAddMoreFiles() else { return }
        if #available(iOS 16.0, *) {
            showingPhotoPicker = true
        } else {
            showingPhotoLibrary = true
        }
    }

    private func presentFileImporter() {
        guard ensureCanAddMoreFiles() else { return }
        showingFileImporter = true
    }

    private func presentCamera() {
        guard ensureCanAddMoreFiles() else { return }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showCameraUnavailableAlert = true
            return
        }

        presentedCameraCover = documentType.cameraCover
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
            logger.error("写入医疗附件临时文件失败：\(error.localizedDescription)", module: .medical)
            return nil
        }
    }

    private func copyToTempFile(url: URL) -> MedicalUploadLocalFile? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        let ext = url.pathExtension.isEmpty ? "pdf" : url.pathExtension
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileNamePrefix)_upload_\(UUID().uuidString).\(ext)")
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
            logger.error("复制医疗附件文件失败：\(error.localizedDescription)", module: .medical)
            return nil
        }
    }

    private func appendFiles(_ files: [MedicalUploadLocalFile]) {
        guard files.isEmpty == false else { return }
        let slots = remainingFileSlots
        guard slots > 0 else {
            showFileLimitMessage()
            return
        }

        localFiles.append(contentsOf: files.prefix(slots))
        if files.count > slots {
            showFileLimitMessage()
        }
    }

    private func ensureCanAddMoreFiles() -> Bool {
        guard remainingFileSlots > 0 else {
            showFileLimitMessage()
            return false
        }
        return true
    }

    private func showFileLimitMessage() {
        fileLimitMessage = String(
            format: L10n.text("medical.upload.medicine_box.sheet.file_limit_message"),
            maxFileCount
        )
    }
}

@available(iOS 16.0, *)
private struct MedicalAttachmentPhotosPickerBridge: View {
    @Binding var isPresented: Bool
    let maxSelectionCount: Int
    let fileNamePrefix: String
    let onFilesSelected: ([MedicalUploadLocalFile]) -> Void

    @State private var selectedItems: [PhotosPickerItem] = []

    private let logger: Logger = ConsoleLogger()

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .photosPicker(
                isPresented: $isPresented,
                selection: $selectedItems,
                maxSelectionCount: max(1, maxSelectionCount),
                matching: .images
            )
            .onChange(of: selectedItems) { newItems in
                guard newItems.isEmpty == false else { return }
                Task {
                    let files = await convertPhotoItems(newItems)
                    await MainActor.run {
                        if files.isEmpty == false {
                            onFilesSelected(files)
                        }
                        selectedItems = []
                    }
                }
            }
    }

    private func convertPhotoItems(_ items: [PhotosPickerItem]) async -> [MedicalUploadLocalFile] {
        var files: [MedicalUploadLocalFile] = []
        for item in items {
            do {
                if let data = try await item.loadTransferable(type: Data.self),
                   let file = saveDataToTemp(data: data, preferredExtension: "jpg", namePrefix: "\(fileNamePrefix)_photo") {
                    files.append(file)
                }
            } catch {
                logger.error("读取相册图片失败：\(error.localizedDescription)", module: .medical)
            }
        }
        return files
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
            logger.error("写入相册临时文件失败：\(error.localizedDescription)", module: .medical)
            return nil
        }
    }
}
