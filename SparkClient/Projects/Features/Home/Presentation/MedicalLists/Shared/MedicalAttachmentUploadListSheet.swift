import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

extension MedicalDocumentKind: Identifiable {
    var id: String { rawValue }
}

// MARK: - 医疗列表附件上传 Sheet 展示配置

extension MedicalDocumentKind {
    /// 文件上传前缀，用于区分不同类型文件命名
    var attachmentUploadFileNamePrefix: String {
        switch self {
        case .auto:
            return "medical_upload"
        case .caseDocument:
            return "case_document"
        case .healthExamReport:
            return "health_exam_report"
        case .medicalReport:
            return "medical_report"
        case .prescription:
            return "prescription"
        case .medicationPlan:
            return "medication_plan"
        case .medicineBox:
            return "medicine_box"
        }
    }

    /// 单类文档最大可上传文件数量限制
    var attachmentUploadMaxFileCount: Int {
        switch self {
        case .medicalReport:
            return 3
        case .healthExamReport:
            return 6
        case .auto, .caseDocument, .prescription, .medicationPlan, .medicineBox:
            return 5
        }
    }

    /// 连续拍摄类相机单次拍摄最大张数
    var attachmentUploadReportCameraMaxCaptureCount: Int {
        switch self {
        case .medicalReport:
            return 3
        case .healthExamReport:
            return 6
        case .prescription, .medicationPlan, .caseDocument:
            return 5
        default:
            return 1
        }
    }

    /// 报告相机业务上下文，区分检查/体检报告拍摄页面，非报告类返回 nil
    var attachmentUploadExaminationReportCameraContext: ExaminationReportCameraContext? {
        switch self {
        case .medicalReport:
            return .examinationReport
        case .healthExamReport:
            return .healthExamReport
        default:
            return nil
        }
    }

    /// 处方/服药计划相机业务上下文，非对应类型返回 nil
    var attachmentUploadPrescriptionMedicationCameraContext: PrescriptionMedicationCameraContext? {
        switch self {
        case .prescription:
            return .prescription
        case .medicationPlan:
            return .medicationPlan
        default:
            return nil
        }
    }

    var attachmentUploadSheetTitle: String {
        switch self {
        case .auto:
            return L10n.text("medical.upload.kind.auto")
        case .medicineBox:
            return L10n.text("medical.upload.medicine_box.sheet.title")
        case .medicationPlan:
            return L10n.text("medical.upload.medication_plan.sheet.title", fallback: "选择服药计划图片")
        case .prescription:
            return L10n.text("common.prescription")
        case .medicalReport:
            return L10n.text("medical.upload.examination_report.sheet.title", fallback: "选择检查报告图片")
        case .healthExamReport:
            return L10n.text("medical.upload.health_exam_report.sheet.title", fallback: "选择体检报告")
        case .caseDocument:
            return L10n.text("medical.upload.case_document.sheet.title", fallback: "选择病历图片")
        }
    }

    var attachmentUploadSheetHeaderTitle: String {
        switch self {
        case .auto:
            return L10n.text("medical.upload.kind.auto")
        case .medicineBox:
            return L10n.text("medical.upload.medicine_box.sheet.header")
        case .medicationPlan:
            return L10n.text("medical.upload.medication_plan.sheet.header", fallback: "选择上传方式")
        case .prescription:
            return L10n.text("common.prescription")
        case .medicalReport:
            return L10n.text("medical.upload.examination_report.sheet.header", fallback: "选择上传方式")
        case .healthExamReport:
            return L10n.text("medical.upload.health_exam_report.sheet.header", fallback: "选择上传方式")
        case .caseDocument:
            return L10n.text("medical.upload.case_document.sheet.header", fallback: "选择上传方式")
        }
    }

    var attachmentUploadSheetHeaderSubtitle: String {
        switch self {
        case .auto:
            return L10n.text("medical.upload.kind.auto")
        case .medicineBox:
            return L10n.text("medical.upload.medicine_box.sheet.subtitle")
        case .medicationPlan:
            return L10n.text("medical.upload.medication_plan.sheet.subtitle", fallback: "可一次选择多张处方、药品说明或服药计划图片，确认后开始识别。")
        case .prescription:
            return L10n.text("medical.upload.medication_plan.sheet.subtitle", fallback: "可一次选择多张处方、药品说明或服药计划图片，确认后开始识别。")
        case .medicalReport:
            return L10n.text("medical.upload.examination_report.sheet.subtitle", fallback: "可一次选择多张检查、检验或影像报告图片，确认后开始识别。")
        case .healthExamReport:
            return L10n.text("medical.upload.health_exam_report.sheet.subtitle", fallback: "一次仅选择 1 个体检报告文件，确认后开始识别。")
        case .caseDocument:
            return L10n.text("medical.upload.case_document.sheet.subtitle", fallback: "可一次选择最多 5 个门诊病历、出院小结或相关附件，确认后开始识别。")
        }
    }

    var attachmentUploadSheetEmptyTitle: String {
        switch self {
        case .auto:
            return L10n.text("medical.upload.medication_plan.sheet.empty.title", fallback: "尚未选择文件")
        case .medicineBox:
            return L10n.text("medical.upload.medicine_box.sheet.empty_title")
        case .medicationPlan:
            return L10n.text("medical.upload.medication_plan.sheet.empty.title", fallback: "尚未选择文件")
        case .prescription:
            return L10n.text("medical.upload.medication_plan.sheet.empty.title", fallback: "尚未选择文件")
        case .medicalReport:
            return L10n.text("medical.upload.examination_report.sheet.empty.title", fallback: "尚未选择文件")
        case .healthExamReport:
            return L10n.text("medical.upload.health_exam_report.sheet.empty.title", fallback: "尚未选择文件")
        case .caseDocument:
            return L10n.text("medical.upload.case_document.sheet.empty.title", fallback: "尚未选择文件")
        }
    }

    var attachmentUploadSheetEmptySubtitle: String {
        switch self {
        case .auto:
            return L10n.text("medical.upload.medication_plan.sheet.empty.subtitle", fallback: "可拍照、从相册选择或上传 PDF/图片")
        case .medicineBox:
            return L10n.text("medical.upload.medicine_box.sheet.empty_subtitle")
        case .medicationPlan, .prescription:
            return L10n.text("medical.upload.medication_plan.sheet.empty.subtitle", fallback: "可拍照、从相册选择或上传 PDF/图片")
        case .medicalReport:
            return L10n.text("medical.upload.examination_report.sheet.empty.subtitle", fallback: "可拍照、从相册选择或上传 PDF/图片")
        case .healthExamReport:
            return L10n.text("medical.upload.health_exam_report.sheet.empty.subtitle", fallback: "可拍照、从相册选择或上传 PDF/图片")
        case .caseDocument:
            return L10n.text("medical.upload.case_document.sheet.empty.subtitle", fallback: "可拍照、从相册选择或上传 PDF/图片")
        }
    }

    var attachmentUploadCameraCover: MedicalAttachmentUploadCameraCover {
        switch self {
        case .medicineBox:
            return .medicineBoxCustomCamera
        case .medicalReport, .healthExamReport:
            return .examinationReportCustomCamera
        case .prescription:
            return .prescriptionMedicationCustomCamera(.prescription)
        case .medicationPlan:
            return .prescriptionMedicationCustomCamera(.medicationPlan)
        case .caseDocument:
            return .caseDocumentCustomCamera
        case .auto:
            return .systemCamera
        }
    }

    /// 列表页底部是否展示「手动添加」按钮。
    var showsListManualAddButton: Bool {
        switch self {
        case .medicineBox, .healthExamReport, .auto:
            return false
        case .prescription, .medicationPlan, .medicalReport, .caseDocument:
            return true
        }
    }

    /// 列表页底部按钮主题色。
    var listActionTintColor: Color {
        switch self {
        case .medicationPlan, .prescription, .medicineBox:
            return Color(uiColor: .systemPurple)
        case .healthExamReport:
            return Color(uiColor: .systemTeal)
        case .auto, .medicalReport, .caseDocument:
            return Color(uiColor: .systemBlue)
        }
    }

    /// 列表页底部「手动添加」按钮文案；不支持手动添加时为 `nil`。
    var listManualAddActionTitle: String? {
        switch self {
        case .medicalReport:
            return L10n.text("home.medical.list.examination.action.manual_add", fallback: "手动添加")
        case .caseDocument:
            return L10n.text("home.medical.list.medical_cases.action.manual_add", fallback: "手动添加")
        case .medicationPlan, .prescription:
            return L10n.text("home.medical.list.medications.action.manual_add", fallback: "手动添加")
        case .auto, .medicineBox, .healthExamReport:
            return nil
        }
    }

    /// 列表页底部「拍摄添加」按钮文案。
    var listCameraAddActionTitle: String {
        switch self {
        case .auto:
            return L10n.text("medical.upload.kind.auto")
        case .medicineBox:
            return L10n.text("home.medical.medicine_box.camera_add", fallback: "拍照添加药品")
        case .medicationPlan:
            return L10n.text("home.medical.list.medications.action.camera_add_plan", fallback: "拍摄添加计划")
        case .prescription:
            return L10n.text("home.medical.list.medications.action.camera_add_plan", fallback: "拍摄添加计划")
        case .medicalReport:
            return L10n.text("home.medical.list.examination.action.camera_add_report", fallback: "拍摄添加报告")
        case .healthExamReport:
            return L10n.text("home.medical.list.health_exam.action.camera_add_report", fallback: "拍摄添加体检报告")
        case .caseDocument:
            return L10n.text("home.medical.list.medical_cases.action.camera_add_case", fallback: "拍摄添加病历")
        }
    }

    /// Sheet 打开后默认自动弹出的上传入口。
    var attachmentUploadSheetAutoPresentation: MedicalAttachmentUploadAutoPresentation {
        switch self {
        case .healthExamReport:
            return .fileImporter
        case .caseDocument:
            return .photoLibrary
        case .auto, .medicineBox, .prescription, .medicationPlan, .medicalReport:
            return .camera
        }
    }
}

/// Sheet 打开后默认自动弹出的上传方式。
enum MedicalAttachmentUploadAutoPresentation {
    case camera
    case photoLibrary
    case fileImporter
}

/// 医疗列表页统一底部操作栏：按 `documentKind` 展示手动添加 / 拍摄添加，并内置上传 Sheet。
struct MedicalListBottomActionBar: View {
    let documentKind: MedicalDocumentKind
    var isEnabled: Bool = true
    var onManualAdd: (() -> Void)?
    let onUploadConfirmed: ([MedicalUploadLocalFile]) -> Void

    @State private var showingUploadSheet = false

    private var tintColor: Color { documentKind.listActionTintColor }

    var body: some View {
        VStack(spacing: 0) {
            if documentKind.showsListManualAddButton {
                Divider()
                    .background(Color(uiColor: .separator).opacity(0.2))
            }

            VStack(spacing: 12) {
                if documentKind.showsListManualAddButton {
                    dualActionButtons
                } else {
                    cameraOnlyButton
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showingUploadSheet) {
            MedicalAttachmentUploadListSheet(documentKind: documentKind, onConfirm: onUploadConfirmed)
        }
    }

    private var dualActionButtons: some View {
        GeometryReader { proxy in
            HStack(spacing: 12) {
                Button {
                    onManualAdd?()
                } label: {
                    Label(documentKind.listManualAddActionTitle ?? "", systemImage: "plus")
                        .font(.headline)
                        .foregroundStyle(tintColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            tintColor.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(tintColor.opacity(0.22), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isEnabled == false)
                .frame(width: max(112, proxy.size.width * 0.34))

                cameraButton(fullWidth: false)
            }
        }
        .frame(height: 52)
    }

    private var cameraOnlyButton: some View {
        cameraButton(fullWidth: true)
    }

    private func cameraButton(fullWidth: Bool) -> some View {
        Button {
            showingUploadSheet = true
        } label: {
            Label(documentKind.listCameraAddActionTitle, systemImage: "camera.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, maxHeight: fullWidth ? nil : .infinity)
                .padding(.vertical, fullWidth ? 15 : 0)
                .background(
                    tintColor,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(isEnabled == false)
    }
}

enum MedicalAttachmentUploadCameraCover: Identifiable {
    case medicineBoxCustomCamera
    case examinationReportCustomCamera
    case prescriptionMedicationCustomCamera(PrescriptionMedicationCameraContext)
    case caseDocumentCustomCamera
    case systemCamera

    var id: String {
        switch self {
        case .medicineBoxCustomCamera:
            return "medicineBoxCustomCamera"
        case .examinationReportCustomCamera:
            return "examinationReportCustomCamera"
        case .prescriptionMedicationCustomCamera(let context):
            return "prescriptionMedicationCustomCamera:\(context)"
        case .caseDocumentCustomCamera:
            return "caseDocumentCustomCamera"
        case .systemCamera:
            return "systemCamera"
        }
    }
}

struct MedicalAttachmentUploadListSheet: View {
    @Environment(\.dismiss) private var dismiss
    let documentKind: MedicalDocumentKind
    let onConfirm: ([MedicalUploadLocalFile]) -> Void

    @State private var localFiles: [MedicalUploadLocalFile] = []
    @State private var presentedCameraCover: MedicalAttachmentUploadCameraCover?
    @State private var showingPhotoPicker = false
    @State private var showingFileImporter = false
    @State private var showCameraUnavailableAlert = false
    @State private var filePreviewSelection: FilePreviewInput?
    @State private var filePreviewIndex: Int = 0
    @State private var fileLimitMessage: String?
    @State private var pendingConfirmedFiles: [MedicalUploadLocalFile]?
    @State private var hasScheduledDeferredConfirm = false

    private let logger: Logger = ConsoleLogger()

    init(
        documentKind: MedicalDocumentKind,
        onConfirm: @escaping ([MedicalUploadLocalFile]) -> Void
    ) {
        self.documentKind = documentKind
        self.onConfirm = onConfirm
    }

    private var title: String { documentKind.attachmentUploadSheetTitle }
    private var headerTitle: String { documentKind.attachmentUploadSheetHeaderTitle }
    private var headerSubtitle: String { documentKind.attachmentUploadSheetHeaderSubtitle }
    private var emptyTitle: String { documentKind.attachmentUploadSheetEmptyTitle }
    private var emptySubtitle: String { documentKind.attachmentUploadSheetEmptySubtitle }
    private var fileNamePrefix: String { documentKind.attachmentUploadFileNamePrefix }
    private var maxFileCount: Int { max(1, documentKind.attachmentUploadMaxFileCount) }

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
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .task {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    presentDefaultUploadEntry()
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
                    .ignoresSafeArea(.keyboard, edges: .bottom)
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
                        let files = images.compactMap { captured in
                            saveUIImageToTemp(
                                image: captured.image,
                                namePrefix: "\(fileNamePrefix)_camera_\(captured.slot.fileNameSuffix)"
                            )
                        }
                        appendFiles(files)
                    }
                )
            case .examinationReportCustomCamera:
                if let context = documentKind.attachmentUploadExaminationReportCameraContext {
                    ExaminationReportCameraSceneView(
                        context: context,
                        maxCaptureCount: min(documentKind.attachmentUploadReportCameraMaxCaptureCount, remainingFileSlots),
                        onCancel: { presentedCameraCover = nil },
                        onImagesCaptured: { images in
                            presentedCameraCover = nil
                            let files = images.compactMap { captured in
                                saveUIImageToTemp(
                                    image: captured.image,
                                    namePrefix: "\(fileNamePrefix)_camera_page_\(captured.index)"
                                )
                            }
                            appendFiles(files)
                        }
                    )
                }
            case .prescriptionMedicationCustomCamera(let context):
                PrescriptionMedicationCameraSceneView(
                    context: context,
                    maxCaptureCount: min(documentKind.attachmentUploadReportCameraMaxCaptureCount, remainingFileSlots),
                    onCancel: { presentedCameraCover = nil },
                    onImagesCaptured: { images in
                        presentedCameraCover = nil
                        let files = images.compactMap { captured in
                            saveUIImageToTemp(
                                image: captured.image,
                                namePrefix: "\(fileNamePrefix)_camera_page_\(captured.index)"
                            )
                        }
                        appendFiles(files)
                    }
                )
            case .caseDocumentCustomCamera:
                CaseDocumentCameraSceneView(
                    maxCaptureCount: min(documentKind.attachmentUploadReportCameraMaxCaptureCount, remainingFileSlots),
                    onCancel: { presentedCameraCover = nil },
                    onImagesCaptured: { images in
                        presentedCameraCover = nil
                        let files = images.compactMap { captured in
                            saveUIImageToTemp(
                                image: captured.image,
                                namePrefix: "\(fileNamePrefix)_camera_page_\(captured.index)"
                            )
                        }
                        appendFiles(files)
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
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.image, .pdf],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            appendFiles(urls.compactMap(copyToTempFile))
        }
        .overlay {
            MedicalAttachmentPhotosPickerBridge(
                isPresented: $showingPhotoPicker,
                maxSelectionCount: remainingFileSlots,
                fileNamePrefix: fileNamePrefix
            ) { files in
                appendFiles(files)
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
        .unifiedFilePreview(
            isPresented: Binding(
                get: { filePreviewSelection != nil },
                set: { isPresented in
                    if isPresented == false {
                        filePreviewSelection = nil
                    }
                }
            ),
            inputs: localFiles.map(\.previewInput),
            startIndex: filePreviewIndex
        )
        .onDisappear {
            triggerDeferredConfirmIfNeeded()
        }
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
//        .background(RoundedRectangle(cornerRadius: 12).fill(Color.purple.opacity(0.06)))
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .systemGroupedBackground)))
//        .overlay(
//            RoundedRectangle(cornerRadius: 12)
//                .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
//                .foregroundStyle(Color.purple.opacity(0.35))
//        )
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
                        onPreview: {
                            filePreviewSelection = file.previewInput
                            if let index = localFiles.firstIndex(where: { $0.id == file.id }) {
                                filePreviewIndex = index
                            }
                        },
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
                pendingConfirmedFiles = localFiles
                hasScheduledDeferredConfirm = false
                dismiss()
            } label: {
                Label(L10n.text("medical.upload.medicine_box.sheet.start_recognition"), systemImage: "wand.and.stars")
            }
            .buttonStyle(.borderedProminent)
            .disabled(localFiles.isEmpty)
        }
        .padding(10)
        .ignoresSafeArea(.keyboard, edges: .bottom)
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
//        .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.06)))
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .systemGroupedBackground)))
//        .overlay(
//            RoundedRectangle(cornerRadius: 12)
//                .stroke(tint.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [6]))
//        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }

    private func presentDefaultUploadEntry() {
        switch documentKind.attachmentUploadSheetAutoPresentation {
        case .camera:
            presentCamera()
        case .photoLibrary:
            presentPhotoLibrary()
        case .fileImporter:
            presentFileImporter()
        }
    }

    private func presentPhotoLibrary() {
        guard ensureCanAddMoreFiles() else { return }
        showingPhotoPicker = true
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

        presentedCameraCover = documentKind.attachmentUploadCameraCover
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

    private func triggerDeferredConfirmIfNeeded() {
        guard hasScheduledDeferredConfirm == false,
              let files = pendingConfirmedFiles,
              files.isEmpty == false else {
            return
        }

        hasScheduledDeferredConfirm = true
        pendingConfirmedFiles = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onConfirm(files)
        }
    }
}

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
