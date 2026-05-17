import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

struct MedicineBoxListPage: View {
    let medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    let memberID: Int?
    let workflowAPI: SparkMedicalWorkflowAPI
    let medicalQueryAPI: SparkMedicalQueryAPI
    let fileTransferService: FileTransferService
    @ObservedObject var viewModel: MedicalDocumentUploadViewModel
    let notificationClient: any NotificationClient
    let logger: Logger
    let onMedicineBoxesChanged: ([SparkMedicalSyncAPI.RemoteMedicineBox]) -> Void

    @State private var localMedicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    @State private var sheetDestination: MedicineBoxSheetDestination?
    @State private var showingUploadSheet = false
    @State private var showingUploadHost = false

    init(
        medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox],
        memberID: Int?,
        workflowAPI: SparkMedicalWorkflowAPI,
        medicalQueryAPI: SparkMedicalQueryAPI,
        fileTransferService: FileTransferService,
        viewModel: MedicalDocumentUploadViewModel,
        notificationClient: any NotificationClient,
        logger: Logger,
        onMedicineBoxesChanged: @escaping ([SparkMedicalSyncAPI.RemoteMedicineBox]) -> Void
    ) {
        self.medicineBoxes = medicineBoxes
        self.memberID = memberID
        self.workflowAPI = workflowAPI
        self.medicalQueryAPI = medicalQueryAPI
        self.fileTransferService = fileTransferService
        self.viewModel = viewModel
        self.notificationClient = notificationClient
        self.logger = logger
        self.onMedicineBoxesChanged = onMedicineBoxesChanged
        _localMedicineBoxes = State(initialValue: medicineBoxes)
    }

    private var sortedBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox] {
        localMedicineBoxes.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var medicineTypeOptions: [String] {
        MedicineBoxTypeCatalog.options(in: localMedicineBoxes)
    }

    var body: some View {
        List {
            if sortedBoxes.isEmpty {
                Text("暂无药箱药品")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedBoxes, id: \.id) { box in
                    NavigationLink {
                        MedicineBoxDetailPage(
                            box: box,
                            typeOptions: medicineTypeOptions,
                            specOptionBoxes: localMedicineBoxes,
                            workflowAPI: workflowAPI,
                            fileTransferService: fileTransferService,
                            onSaved: upsertMedicineBox,
                            onDeleted: removeMedicineBox
                        )
                    } label: {
                        MedicineBoxRow(box: box, fileTransferService: fileTransferService)
                    }
                }
            }
        }
        .refreshable {
            await refreshMedicineBoxes()
        }
        .navigationTitle("药箱")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                showingUploadSheet = true
            } label: {
                Label("拍照添加药品", systemImage: "camera.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color(uiColor: .systemPurple), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(memberID == nil)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    sheetDestination = .create
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                }
                .disabled(memberID == nil)
                .accessibilityLabel("添加药品")
            }
        }
        .sheet(item: $sheetDestination) { destination in
            if let memberID {
                MedicineBoxFormView(
                    mode: destination.formMode,
                    memberID: memberID,
                    workflowAPI: workflowAPI,
                    fileTransferService: fileTransferService,
                    typeOptions: medicineTypeOptions,
                    specOptionBoxes: localMedicineBoxes,
                    onServerSaved: upsertMedicineBox
                )
            } else {
                missingMemberSheet
            }
        }
        .onChange(of: medicineBoxes) { newValue in
            localMedicineBoxes = newValue
        }
        .sheet(isPresented: $showingUploadSheet) {
            MedicineBoxUploadSheet { files in
                startMedicineBoxRecognition(files: files)
            }
        }
        .fullScreenCover(isPresented: $showingUploadHost) {
            CompatibleNavigationContainer {
                MedicalDocumentUploadHostView(viewModel: viewModel)
            }
        }
    }

    private func upsertMedicineBox(_ box: SparkMedicalSyncAPI.RemoteMedicineBox) {
        if let index = localMedicineBoxes.firstIndex(where: { $0.id == box.id }) {
            localMedicineBoxes[index] = box
        } else {
            localMedicineBoxes.insert(box, at: 0)
        }
        onMedicineBoxesChanged(localMedicineBoxes)
        sheetDestination = nil
    }

    private func removeMedicineBox(id: Int) {
        localMedicineBoxes.removeAll { $0.id == id }
        onMedicineBoxesChanged(localMedicineBoxes)
    }

    @MainActor
    private func refreshMedicineBoxes() async {
        guard let memberID else {
            logger.warning("药箱下拉刷新跳过：缺少成员 ID", module: .home)
            return
        }

        let startedAt = Date()
        logger.info("药箱下拉刷新开始 memberID=\(memberID)", module: .home)

        do {
            // 下拉刷新只拉取药箱列表，并只回写首页 completeData.medicineBoxes 缓存字段。
            let boxes = try await medicalQueryAPI.listMedicineBoxes(memberID: memberID)
            localMedicineBoxes = boxes
            onMedicineBoxesChanged(boxes)
            logger.info(
                "药箱下拉刷新完成 memberID=\(memberID) count=\(boxes.count) cost=\(String(format: "%.3f", Date().timeIntervalSince(startedAt)))s",
                module: .home
            )
        } catch {
            notificationClient.error(error.localizedDescription, title: L10n.text("common.error"), source: "home.medicine_boxes.refresh")
            logger.warning("药箱下拉刷新失败 memberID=\(memberID) error=\(error.localizedDescription)", module: .home)
        }
    }

    @MainActor
    private func startMedicineBoxRecognition(files: [MedicalUploadLocalFile]) {
        viewModel.prepareAndStart(files: files, kind: .medicineBox)
        showingUploadHost = true
    }

    @ViewBuilder
    private var missingMemberSheet: some View {
        let content = Text("请先选择成员")
            .font(.headline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        if #available(iOS 16.0, *) {
            content.presentationDetents([.height(180)])
        } else {
            content
        }
    }
}

enum MedicineBoxSheetDestination: Identifiable {
    case create
    case serverEdit(SparkMedicalSyncAPI.RemoteMedicineBox)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .serverEdit(let box):
            return "server_\(box.id)"
        }
    }

    var formMode: MedicineBoxFormView.Mode {
        switch self {
        case .create:
            return .create
        case .serverEdit(let box):
            return .serverEdit(existing: box)
        }
    }
}

private struct MedicineBoxRow: View {
    let box: SparkMedicalSyncAPI.RemoteMedicineBox
    let fileTransferService: FileTransferService

    private var imageAttachment: SparkMedicalSyncAPI.RemoteManagedFile? {
        box.attachments?.first(where: \.isMedicationImageLike)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MedicationImageGlyph(
                seed: box.id,
                attachment: imageAttachment,
                fileTransferService: fileTransferService
            )
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(box.medicineName.nilIfBlank ?? "未命名药品")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(medicineBoxStockText(box))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text([medicineStrengthText(box.strength), box.dosageForm.nilIfBlank, medicineTypeText(box.medicineType)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let expireDate = box.expireDate {
                    Text("有效期 \(expireDate.formatted(date: .numeric, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct MedicineBoxDetailPage: View {
    let box: SparkMedicalSyncAPI.RemoteMedicineBox
    let typeOptions: [String]
    let specOptionBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    let workflowAPI: SparkMedicalWorkflowAPI
    let fileTransferService: FileTransferService
    let onSaved: (SparkMedicalSyncAPI.RemoteMedicineBox) -> Void
    let onDeleted: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentBox: SparkMedicalSyncAPI.RemoteMedicineBox
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirm = false
    @State private var alertMessage: String?
    @State private var isDeleting = false

    init(
        box: SparkMedicalSyncAPI.RemoteMedicineBox,
        typeOptions: [String],
        specOptionBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox],
        workflowAPI: SparkMedicalWorkflowAPI,
        fileTransferService: FileTransferService,
        onSaved: @escaping (SparkMedicalSyncAPI.RemoteMedicineBox) -> Void,
        onDeleted: @escaping (Int) -> Void
    ) {
        self.box = box
        self.typeOptions = typeOptions
        self.specOptionBoxes = specOptionBoxes
        self.workflowAPI = workflowAPI
        self.fileTransferService = fileTransferService
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        _currentBox = State(initialValue: box)
    }

    var body: some View {
        List {
            Section("药品信息") {
                MedicineBoxDetailRow(title: "药品名称", value: currentBox.medicineName)
                MedicineBoxDetailRow(title: "药品类型", value: medicineTypeText(currentBox.medicineType) ?? "")
                MedicineBoxDetailRow(title: "品牌名", value: currentBox.brandName)
                MedicineBoxDetailRow(title: "剂型", value: currentBox.dosageForm)
                MedicineBoxDetailRow(title: "规格", value: medicineStrengthDetailValue(currentBox.strength))
            }

            Section("库存信息") {
                MedicineBoxDetailRow(title: "总数量", value: medicineBoxStockText(currentBox))
                if let expireDate = currentBox.expireDate {
                    MedicineBoxDetailRow(title: "有效期", value: expireDate.formatted(date: .numeric, time: .omitted))
                }
            }

            if currentBox.notes.nilIfBlank != nil {
                Section("备注") {
                    Text(currentBox.notes)
                        .font(.body)
                        .foregroundStyle(.primary)
                }
            }

            if let attachments = currentBox.attachments, attachments.isEmpty == false {
                Section("附件") {
                    MedicalAttachmentGridPreview(
                        attachments: attachments,
                        fileTransferService: fileTransferService
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
        }
        .navigationTitle(currentBox.medicineName.nilIfBlank ?? "药品详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(isDeleting)
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            MedicineBoxFormView(
                mode: .serverEdit(existing: currentBox),
                memberID: currentBox.member,
                workflowAPI: workflowAPI,
                fileTransferService: fileTransferService,
                typeOptions: typeOptions,
                specOptionBoxes: specOptionBoxes,
                onServerSaved: { saved in
                    currentBox = saved
                    onSaved(saved)
                    showingEditSheet = false
                }
            )
        }
        .alert("确认删除", isPresented: $showingDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task { await deleteCurrentBox() }
            }
        } message: {
            Text("删除后该药品将从药箱中移除。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .onChange(of: box) { newValue in
            currentBox = newValue
        }
    }

    @MainActor
    private func deleteCurrentBox() async {
        guard isDeleting == false else { return }
        isDeleting = true
        defer { isDeleting = false }

        do {
            try await workflowAPI.delete(kind: .medicineBoxes, id: currentBox.id)
            onDeleted(currentBox.id)
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

struct MedicineBoxUploadSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let headerTitle: String
    let headerSubtitle: String
    let emptyTitle: String
    let emptySubtitle: String
    let fileNamePrefix: String
    let maxFileCount: Int
    let onConfirm: ([MedicalUploadLocalFile]) -> Void

    @State private var localFiles: [MedicalUploadLocalFile] = []
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    @State private var showingPhotoLibrary = false
    @State private var showingFileImporter = false
    @State private var showCameraUnavailableAlert = false
    @State private var filePreviewSelection: FilePreviewInput?
    @State private var fileLimitMessage: String?

    private let logger: Logger = ConsoleLogger()

    init(
        title: String = L10n.text("medical.upload.medicine_box.sheet.title", fallback: "选择药品图片"),
        headerTitle: String = L10n.text("medical.upload.medicine_box.sheet.header", fallback: "选择上传方式"),
        headerSubtitle: String = L10n.text("medical.upload.medicine_box.sheet.subtitle", fallback: "可一次选择多张药盒、药瓶或说明书图片，确认后开始识别。"),
        emptyTitle: String = "尚未选择文件",
        emptySubtitle: String = "可拍照、从相册选择或上传 PDF/图片",
        fileNamePrefix: String = "medicine_box",
        maxFileCount: Int = 5,
        onConfirm: @escaping ([MedicalUploadLocalFile]) -> Void
    ) {
        self.title = title
        self.headerTitle = headerTitle
        self.headerSubtitle = headerSubtitle
        self.emptyTitle = emptyTitle
        self.emptySubtitle = emptySubtitle
        self.fileNamePrefix = fileNamePrefix
        self.maxFileCount = max(1, maxFileCount)
        self.onConfirm = onConfirm
    }

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
        .sheet(isPresented: $showingCamera) {
            KnowledgeImagePicker(
                source: .camera,
                onCancel: { showingCamera = false },
                onImagePicked: { image in
                    showingCamera = false
                    if let file = saveUIImageToTemp(image: image, namePrefix: "\(fileNamePrefix)_camera") {
                        localFiles.append(file)
                    }
                }
            )
        }
        .sheet(isPresented: $showingPhotoLibrary) {
            KnowledgeImagePicker(
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
                MedicineBoxPhotosPickerBridge(
                    isPresented: $showingPhotoPicker,
                    maxSelectionCount: remainingFileSlots,
                    fileNamePrefix: fileNamePrefix
                ) { files in
                    appendFiles(files)
                }
            }
        }
        .alert("无法打开相机", isPresented: $showCameraUnavailableAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text("当前设备不支持相机。")
        }
        .alert("文件数量已达上限", isPresented: Binding(
            get: { fileLimitMessage != nil },
            set: { if !$0 { fileLimitMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
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
            medicineUploadTile(icon: "camera", title: "拍照上传", subtitle: "即时拍摄", tint: .blue) {
                presentCamera()
            }
            medicineUploadTile(icon: "photo.on.rectangle", title: "照片上传", subtitle: "选择相册", tint: .purple) {
                presentPhotoLibrary()
            }
            medicineUploadTile(icon: "doc", title: "文件上传", subtitle: "PDF/图片", tint: .green) {
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
                Text("已选择")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(localFiles.count)/\(maxFileCount) 个文件")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                spacing: 12
            ) {
                ForEach(BuildMedicalDocumentPreviewItemsUseCase().execute(files: localFiles)) { item in
                    MedicalDocumentFilePreviewSquareCard(
                        item: item,
                        onPreview: { filePreviewSelection = item },
                        onDelete: { localFiles.removeAll { $0.id == item.id } }
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
                Label("清空", systemImage: "trash")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button {
                onConfirm(localFiles)
                dismiss()
            } label: {
                Label("开始识别", systemImage: "wand.and.stars")
            }
            .buttonStyle(.borderedProminent)
            .disabled(localFiles.isEmpty)
        }
        .padding( 10)
    }

    private var remainingFileSlots: Int {
        max(0, maxFileCount - localFiles.count)
    }

    private func medicineUploadTile(icon: String, title: String, subtitle: String, tint: Color, action: @escaping () -> Void) -> some View {
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
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            showingCamera = true
        } else {
            showCameraUnavailableAlert = true
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
            logger.error("写入药箱识别临时文件失败：\(error.localizedDescription)", module: .medical)
            return nil
        }
    }

    private func copyToTempFile(url: URL) -> MedicalUploadLocalFile? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        let ext = url.pathExtension.isEmpty ? "pdf" : url.pathExtension
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("medicine_box_upload_\(UUID().uuidString).\(ext)")
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
            logger.error("复制药箱识别文件失败：\(error.localizedDescription)", module: .medical)
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
        fileLimitMessage = "最多可选择 \(maxFileCount) 个文件。"
    }
}

@available(iOS 16.0, *)
private struct MedicineBoxPhotosPickerBridge: View {
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
                logger.error("读取药箱相册图片失败：\(error.localizedDescription)", module: .medical)
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
            logger.error("写入药箱相册临时文件失败：\(error.localizedDescription)", module: .medical)
            return nil
        }
    }
}

struct MedicineBoxFormView: View {
    enum Mode {
        case create
        case serverEdit(existing: SparkMedicalSyncAPI.RemoteMedicineBox)
        case localEdit(existing: MedicineBoxDraft, onSubmit: (MedicineBoxDraft) -> Void)
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let memberID: Int
    let workflowAPI: SparkMedicalWorkflowAPI
    let fileTransferService: FileTransferService?
    let typeOptions: [String]
    let specOptionBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    let onServerSaved: ((SparkMedicalSyncAPI.RemoteMedicineBox) -> Void)?

    @State private var draft: MedicineBoxDraft
    @State private var isSubmitting = false
    @State private var alertMessage: String?
    @State private var sheetKeyboardVisible = false
    @State private var showDosageFormSheet = false
    @State private var showSpecificationSheet = false
    @State private var pendingAttachmentFiles: [MedicalUploadLocalFile] = []
    @State private var localAttachmentPreview: FilePreviewInput?

    private let formLog: Logger = ConsoleLogger()
    private let formLogModule: LogModule = .medical

    /// Chrome outside the measured scroll content (inline nav + `sparkFormBottomBar`), aligned with `MedicineBoxSpecificationSheet` detent math.
    private static let formSheetNavChromeHeight: CGFloat = 72
    private static let formSheetBottomBarChromeHeight: CGFloat = 88

    init(
        mode: Mode,
        memberID: Int,
        workflowAPI: SparkMedicalWorkflowAPI,
        fileTransferService: FileTransferService? = nil,
        typeOptions: [String] = MedicineBoxTypeCatalog.defaultStoredOptions,
        specOptionBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox] = [],
        onServerSaved: ((SparkMedicalSyncAPI.RemoteMedicineBox) -> Void)? = nil
    ) {
        self.mode = mode
        self.memberID = memberID
        self.workflowAPI = workflowAPI
        self.fileTransferService = fileTransferService
        self.typeOptions = MedicineBoxTypeCatalog.mergedOptions(typeOptions)
        self.specOptionBoxes = specOptionBoxes
        self.onServerSaved = onServerSaved

        switch mode {
        case .create:
            _draft = State(initialValue: MedicineBoxDraft())
        case .serverEdit(let existing):
            _draft = State(initialValue: MedicineBoxDraft(existing: existing))
        case .localEdit(let existing, _):
            _draft = State(initialValue: existing)
        }
    }

    private var canSubmit: Bool {
        isSubmitting == false
        && draft.medicineName.nilIfBlank != nil
    }

    private var navigationTitle: String {
        switch mode {
        case .create:
            return "添加药品"
        case .serverEdit, .localEdit:
            return "编辑药品"
        }
    }

    var body: some View {
        CompatibleNavigationContainer {
            formContent
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .sparkFormBottomBar(
                    canSubmit: canSubmit,
                    cancelTitle: L10n.text("common.cancel"),
                    saveTitle: L10n.text("common.done"),
                    saveSystemImage: "checkmark.circle.fill",
                    keyboardVisible: $sheetKeyboardVisible,
                    onCancel: {
                        formLog.info("MedicineBoxFormView: cancel tapped mode=\(modeLogLabel)", module: formLogModule)
                        dismiss()
                    },
                    onSave: {
                        guard canSubmit else { return }
                        submitDraft()
                    }
                )
        }
        .interactiveDismissDisabled(isSubmitting)
//        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(uiColor: .systemBackground)))
        .background(Color(uiColor: .systemBackground))
        .unifiedFilePreview(selection: $localAttachmentPreview)


        .alert("保存失败", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .sheet(isPresented: $showSpecificationSheet) {
            MedicineBoxSpecificationSheet(
                specification: $draft.specification,
                specOptionBoxes: specOptionBoxes
            )

        }
        .sheet(isPresented: $showDosageFormSheet) {
            MedicineBoxDosageFormPickerSheet(selection: $draft.dosageForm)
        }
    }

    private var formContent: some View {
        AdaptiveToolSheetScrollView(
            bottomContentPadding: 24,
            extraChromeHeight: Self.formSheetNavChromeHeight + Self.formSheetBottomBarChromeHeight
        ) {
            VStack(spacing: 14) {
      
                SparkFormCard(title: "药品信息", titleSystemImage: "pills.fill") {
                    VStack(spacing: 12) {
                        SparkFormTextRow(title: "药品名称", text: $draft.medicineName, placeholder: "如 对乙酰氨基酚或泰诺林", required: true, keyboardVisible: $sheetKeyboardVisible)
                        
                        VStack{
                            Toggle("设置有效期", isOn: $draft.hasExpireDate)
                                .font(.subheadline.weight(.medium))
                            if draft.hasExpireDate {
                                DatePicker("有效期", selection: $draft.expireDate, displayedComponents: .date)
                                    .font(.subheadline.weight(.medium))
//                                    .padding(.horizontal, 12)
//                                    .frame(height: 44)
                                    .sparkFormTextFieldChrome(isFocused: false, isError: false)
//                                    .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                        
                        SparkFormMenuCustomRow(
                            title: "药品类型",
                            required: false,
                            sections: [(nil, MedicineBoxTypeCatalog.displayOptions(for: typeOptions))],
                            text: medicineTypeBinding,
                            customMenuTitle: L10n.text("medical_record.forms.lab_item.unit_custom_menu"),
                            customPlaceholder: "输入药品类型",
                            keyboardVisible: $sheetKeyboardVisible,
                            optionSystemImage: MedicineBoxTypeCatalog.systemImage(for:),
                            customAutofocus: false
                        )
                        SparkFormSheetPickerRow(
                            title: L10n.text("medical_record.forms.field.dosage_form", fallback: "剂型"),
                            displayValue: MedicineBoxDosageFormCatalog.displayString(stored: draft.dosageForm),
                            placeholder: L10n.text("medical_record.medicine_box.dosage_form_sheet.placeholder", fallback: "请选择剂型")
                        ) {
                            showDosageFormSheet.toggle()
                        }

                        SparkFormSheetPickerRow(
                            title: L10n.text("medical_record.forms.field.strength"),
                            displayValue: draft.specification.displayString(prefersEnglish: SparkFormCatalogMenuLocale.prefersEnglish)
                                .trimmingCharacters(in: .whitespacesAndNewlines),
                            placeholder: L10n.text("medical_record.medicine_box.strength_sheet.placeholder")
                        ) {
                            showSpecificationSheet.toggle()
                        }
                        
                        SparkFormTextRow(title: "总数量", text: $draft.totalQuantity, placeholder: "如 24", keyboardVisible: $sheetKeyboardVisible)
                            .keyboardType(.decimalPad)
                    }
                }
                
                SparkFormCard(title: "更多信息", titleSystemImage: "shippingbox.fill") {
                    
                    SparkFormTextRow(title: "品牌名", text: $draft.brandName, placeholder: "可选", keyboardVisible: $sheetKeyboardVisible)
                    
                    SparkFormTextAreaRow(title: "备注", text: $draft.notes, minHeight: 80, maxHeight: 160, placeholder: "用法、存放位置或注意事项", keyboardVisible: $sheetKeyboardVisible)
                }

                if fileTransferService != nil {
                    attachmentFormCard
                }

            }
        }
    }

    private var attachmentFormCard: some View {
        SparkFormCard(title: "附件", titleSystemImage: "paperclip") {
            VStack(alignment: .leading, spacing: 12) {
                if let fileTransferService, draft.attachments.isEmpty == false {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("已保存附件")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)

                        MedicalAttachmentListView(
                            attachments: draft.attachments,
                            fileTransferService: fileTransferService
                        )
                    }
                }

                if pendingAttachmentFiles.isEmpty == false {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("待上传附件")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                            spacing: 12
                        ) {
                            ForEach(BuildMedicalDocumentPreviewItemsUseCase().execute(files: pendingAttachmentFiles)) { item in
                                MedicalDocumentFilePreviewSquareCard(
                                    item: item,
                                    onPreview: { localAttachmentPreview = item },
                                    onDelete: { pendingAttachmentFiles.removeAll { $0.id == item.id } }
                                )
                            }
                        }
                    }
                }

                attachmentPickerButton
            }
        }
    }

    @ViewBuilder
    private var attachmentPickerButton: some View {
        if #available(iOS 16.0, *) {
            MedicalDocumentFilePickerMenu(
                buttonContent: { addAttachmentButtonLabel },
                onFilesSelected: appendAttachmentFiles
            )
        } else {
            MedicalDocumentLegacyFilePickerMenu(
                buttonContent: { addAttachmentButtonLabel },
                onFilesSelected: appendAttachmentFiles
            )
        }
    }

    private var addAttachmentButtonLabel: some View {
        Label("添加附件", systemImage: "plus.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [5]))
            )
    }

    private func appendAttachmentFiles(_ files: [MedicalUploadLocalFile]) {
        pendingAttachmentFiles.append(contentsOf: files)
    }

    private var medicineTypeBinding: Binding<String> {
        Binding(
            get: { MedicineBoxTypeCatalog.displayString(stored: draft.medicineType) },
            set: { draft.medicineType = MedicineBoxTypeCatalog.storedValue(fromDisplay: $0) }
        )
    }

    private func submitDraft() {
        switch mode {
        case .localEdit(_, let onSubmit):
            guard validateDraft() else { return }
            onSubmit(draft)
            dismiss()
        case .create, .serverEdit:
            Task { await submitToServer() }
        }
    }

    @MainActor
    private func submitToServer() async {
        guard validateDraft() else { return }
        guard isSubmitting == false else { return }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let uploadedFileIDs = try await uploadPendingAttachmentsIfNeeded()
            let fileIDs = draft.attachments.map(\.id) + uploadedFileIDs
            let payload = try draft.payload(memberID: memberID, fileIds: fileIDs)
            let saved: SparkMedicalSyncAPI.RemoteMedicineBox
            switch mode {
            case .create:
                saved = try await workflowAPI.create(
                    SparkMedicalSyncAPI.RemoteMedicineBox.self,
                    kind: .medicineBoxes,
                    body: payload
                )
            case .serverEdit(let existing):
                saved = try await workflowAPI.update(
                    SparkMedicalSyncAPI.RemoteMedicineBox.self,
                    kind: .medicineBoxes,
                    id: existing.id,
                    body: payload
                )
            case .localEdit:
                return
            }
            onServerSaved?(saved)
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func validateDraft() -> Bool {
        guard canSubmit else {
            alertMessage = "请填写药品名称"
            return false
        }
        return true
    }

    private func uploadPendingAttachmentsIfNeeded() async throws -> [Int] {
        guard pendingAttachmentFiles.isEmpty == false else { return [] }
        guard let fileTransferService else { return [] }

        let uploader = UploadMedicalDocumentFilesUseCase(fileTransferService: fileTransferService)
        let uploaded = try await uploader.execute(memberID: memberID, files: pendingAttachmentFiles)
        return uploaded.compactMap { $0.remoteFile?.id }
    }

    private var modeLogLabel: String {
        switch mode {
        case .create:
            return "create"
        case .serverEdit:
            return "serverEdit"
        case .localEdit:
            return "localEdit"
        }
    }
}

// MARK: - Specification sheet (structured fields; `SparkFormSheetPickerRow` lives in `MedicalRecordFormSupport`)

private struct MedicineBoxDosageFormPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String

    var body: some View {
        CompatibleNavigationContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    MedicineBoxDosageFormHeaderIcon()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)

                    Text(L10n.text("medical_record.medicine_box.dosage_form_sheet.title", fallback: "选取药品类型"))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 20)

                    dosageFormSection(
                        title: L10n.text("medical_record.medicine_box.dosage_form_sheet.common_section", fallback: "常见形式"),
                        items: MedicineBoxDosageFormCatalog.commonForms
                    )
                    dosageFormSection(
                        title: L10n.text("medical_record.medicine_box.dosage_form_sheet.more_section", fallback: "更多形式"),
                        items: MedicineBoxDosageFormCatalog.moreForms
                    )
                }
                .padding(.bottom, 40)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.text("common.cancel")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func dosageFormSection(title: String, items: [MedicineBoxDosageFormCatalog.Item]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Section(L10n.text(title)) {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.storedValue) { index, item in
                        Button {
                            select(item)
                        } label: {
                            HStack(spacing: 12) {
                                Text(item.displayName)
                                    .font(.title3)
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if normalizedSelection == item.storedValue {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < items.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .font(.title3.bold())
            .foregroundColor(.primary)
            .padding(.horizontal, 20)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: normalizedSelection)
    }

    private func select(_ item: MedicineBoxDosageFormCatalog.Item) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            selection = item.storedValue
        }
        dismiss()
    }

    private var normalizedSelection: String {
        selection.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum MedicineBoxDosageFormCatalog {
    struct Item: Hashable {
        let storedValue: String
        let localizationKey: String
        let fallback: String

        var displayName: String {
            L10n.text(localizationKey, fallback: fallback)
        }
    }

    static let commonForms: [Item] = [
        item("胶囊", key: "capsule", fallback: "胶囊"),
        item("药片", key: "tablet", fallback: "药片"),
        item("液体", key: "liquid", fallback: "液体"),
        item("外用", key: "topical", fallback: "外用")
    ]

    static let moreForms: [Item] = [
        item("乳液", key: "lotion", fallback: "乳液"),
        item("乳霜", key: "cream", fallback: "乳霜"),
        item("凝胶", key: "gel", fallback: "凝胶"),
        item("吸入剂", key: "inhaler", fallback: "吸入剂"),
        item("喷剂", key: "spray", fallback: "喷剂"),
        item("栓剂", key: "suppository", fallback: "栓剂"),
        item("泡沫", key: "foam", fallback: "泡沫"),
        item("注射", key: "injection", fallback: "注射"),
        item("滴剂", key: "drops", fallback: "滴剂"),
        item("粉末", key: "powder", fallback: "粉末"),
        item("设备", key: "device", fallback: "设备"),
        item("贴剂", key: "patch", fallback: "贴剂"),
        item("软膏", key: "ointment", fallback: "软膏")
    ]

    static func displayString(stored: String) -> String {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }
        return allForms.first { $0.storedValue == trimmed }?.displayName ?? trimmed
    }

    static func storedValue(fromAny raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }
        if let item = allForms.first(where: { $0.storedValue == trimmed || $0.displayName == trimmed }) {
            return item.storedValue
        }
        return trimmed
    }

    private static var allForms: [Item] {
        commonForms + moreForms
    }

    private static func item(_ storedValue: String, key: String, fallback: String) -> Item {
        Item(
            storedValue: storedValue,
            localizationKey: "medical_record.medicine_box.dosage_form.\(key)",
            fallback: fallback
        )
    }
}

private struct MedicineBoxDosageFormHeaderIcon: View {
    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "pills.fill")
                .font(.largeTitle)
                .symbolRenderingMode(.multicolor)

            Image(systemName: "cross.case.fill")
                .font(.title)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(uiColor: .systemTeal))

            Image(systemName: "drop.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(uiColor: .systemBlue))

            Image(systemName: "bandage.fill")
                .font(.title)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(uiColor: .systemPink))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct MedicineBoxSpecificationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var specification: MedicineSpecification
    let specOptionBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]

    @State private var tempSpec: MedicineSpecification
    @FocusState private var doseValueFocused: Bool
    @FocusState private var packageCountFocused: Bool

    private static let selectedChip = Color(red: 79 / 255, green: 70 / 255, blue: 229 / 255)
    private static let sheetHeaderChromeHeight: CGFloat = 72
    private static let sheetFooterChromeHeight: CGFloat = 88

    init(
        specification: Binding<MedicineSpecification>,
        specOptionBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    ) {
        _specification = specification
        self.specOptionBoxes = specOptionBoxes
        _tempSpec = State(initialValue: specification.wrappedValue)
    }

    private var doseUnitLabels: [String] {
        MedicineSpecificationCatalog.doseUnitMenuOptions(boxes: specOptionBoxes)
    }

    private var innerUnitLabels: [String] {
        MedicineSpecificationCatalog.innerPackageMenuOptions(boxes: specOptionBoxes)
    }

    private var outerUnitLabels: [String] {
        MedicineSpecificationCatalog.outerPackageMenuOptions(boxes: specOptionBoxes)
    }

    private var prefersEnglish: Bool {
        SparkFormCatalogMenuLocale.prefersEnglish
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
    }

    private var previewLine: String {
        let t = tempSpec.displayString(prefersEnglish: prefersEnglish)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? L10n.text("medical_record.medicine_box.spec.preview_empty") : t
    }

    private var trimmedTempDoseUnit: String {
        tempSpec.doseUnit.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        CompatibleNavigationContainer {
            AdaptiveToolSheetScrollView(
                bottomContentPadding: 12,
                extraChromeHeight: Self.sheetHeaderChromeHeight + Self.sheetFooterChromeHeight
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    legacyFreeformBlock
                    
                    sheetFieldBlock(title: L10n.text("medical_record.medicine_box.spec.dose_value")) {
                        HStack(spacing: prefersEnglish ? 6 : 0) {
                            TextField("5", text: doseValueBinding)
                                .textFieldStyle(.plain)
                                .focused($doseValueFocused)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 16))
                                .foregroundColor(.primary)

                            if trimmedTempDoseUnit.isEmpty == false {
                                Text(MedicineSpecificationCatalog.displayUnit(stored: trimmedTempDoseUnit, prefersEnglish: prefersEnglish))
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.secondary)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Color(uiColor: .systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    
                    unitChipBlock(
                        title: L10n.text("medical_record.medicine_box.spec.dose_unit"),
                        labels: doseUnitLabels,
                        isSelected: { label in
                            MedicineSpecificationCatalog.storedDoseUnit(fromDisplay: label)
                            == MedicineSpecificationCatalog.storedDoseUnit(fromAny: tempSpec.doseUnit)
                        },
                        onSelect: { label in
                            tempSpec.rawLegacyStrength = nil
                            let doseUnit = MedicineSpecificationCatalog.storedDoseUnit(fromDisplay: label)
                            tempSpec.doseUnit = doseUnit
                        }
                    )
                    
                    sheetFieldBlock(title: L10n.text("medical_record.medicine_box.spec.package_count")) {
                        TextField("28", text: packageCountBinding)
                            .textFieldStyle(.plain)
                            .focused($packageCountFocused)
                            .keyboardType(.numberPad)
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(Color(uiColor: .systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    
                    unitChipBlock(
                        title: L10n.text("medical_record.medicine_box.spec.package_unit"),
                        labels: innerUnitLabels,
                        isSelected: { label in
                            MedicineSpecificationCatalog.storedInnerPackage(fromDisplay: label)
                            == MedicineSpecificationCatalog.storedInnerPackage(fromAny: tempSpec.packageUnit)
                        },
                        onSelect: { label in
                            tempSpec.rawLegacyStrength = nil
                            tempSpec.packageUnit = MedicineSpecificationCatalog.storedInnerPackage(fromDisplay: label)
                        }
                    )
                    
                    unitChipBlock(
                        title: L10n.text("medical_record.medicine_box.spec.outer_unit"),
                        labels: outerUnitLabels,
                        isSelected: { label in
                            MedicineSpecificationCatalog.storedOuterPackage(fromDisplay: label)
                            == MedicineSpecificationCatalog.storedOuterPackage(fromAny: tempSpec.outerPackageUnit)
                        },
                        onSelect: { label in
                            tempSpec.rawLegacyStrength = nil
                            tempSpec.outerPackageUnit = MedicineSpecificationCatalog.storedOuterPackage(fromDisplay: label)
                        }
                    )
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("medical_record.medicine_box.spec.preview"))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                        Text(previewLine)
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .navigationTitle(L10n.text("medical_record.medicine_box.strength_sheet.title"))
            .sparkKeyboardDoneToolbar {
                SparkKeyboardDismiss.endEditing()
            }
            .sparkFormBottomBar(
                canSubmit: true,
                cancelTitle: L10n.text("common.cancel"),
                saveTitle: L10n.text("common.done"),
                saveSystemImage: "checkmark.circle.fill",
                onCancel: {
                    dismiss()
                },
                onSave: {
                    specification = tempSpec
                    dismiss()
                }
            )
        }
        .ignoresSafeArea()
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear {
            tempSpec = specification
        }
    }

    @ViewBuilder
    private var legacyFreeformBlock: some View {
        if tempSpec.rawLegacyStrength != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("medical_record.medicine_box.strength_sheet.custom_section"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                TextField(
                    L10n.text("medical_record.medicine_box.strength_sheet.placeholder"),
                    text: Binding(
                        get: { tempSpec.rawLegacyStrength ?? "" },
                        set: { newValue in
                            let t = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            tempSpec.rawLegacyStrength = t.isEmpty ? nil : t
                        }
                    )
                )
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(uiColor: .separator).opacity(0.35))
            }
        }
    }

    private var doseValueBinding: Binding<String> {
        Binding(
            get: { tempSpec.doseValue },
            set: {
                tempSpec.doseValue = $0
                tempSpec.rawLegacyStrength = nil
            }
        )
    }

    private var packageCountBinding: Binding<String> {
        Binding(
            get: { tempSpec.packageCount },
            set: {
                tempSpec.packageCount = $0
                tempSpec.rawLegacyStrength = nil
            }
        )
    }

    private func sheetFieldBlock(title: String, @ViewBuilder field: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
            field()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(uiColor: .separator).opacity(0.35))
        }
    }

    private func unitChipBlock(
        title: String,
        labels: [String],
        isSelected: @escaping (String) -> Bool,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
                .padding(.top, 16)

            LazyVGrid(columns: gridColumns, spacing: 10) {
                ForEach(labels, id: \.self) { label in
                    let selected = isSelected(label)
                    Button {
                        onSelect(label)
                    } label: {
                        Text(label)
                            .font(.system(size: 14))
                            .foregroundColor(selected ? .white : Color.primary.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 4)
                            .background(selected ? Self.selectedChip : Color(uiColor: .secondarySystemBackground))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(uiColor: .separator).opacity(0.35))
        }
    }
}

struct MedicineBoxDraft {
    var medicineName = ""
    var medicineType = MedicineBoxTypeCatalog.defaultStoredValue
    var brandName = ""
    var dosageForm = ""
    /// Structured specification; encoded to API `strength` via ``MedicineSpecification/storedStrengthString``.
    var specification = MedicineSpecification()
    var totalQuantity = ""
    var hasExpireDate = false
    var expireDate = Date()
    var notes = ""
    var attachments: [SparkMedicalSyncAPI.RemoteManagedFile] = []

    init() {}

    init(recognition: MedicineBoxRecognitionDraft) {
        medicineName = recognition.medicineName?.trimmed ?? ""
        medicineType = MedicineBoxTypeCatalog.storedValue(fromAny: recognition.medicineType)
        brandName = recognition.brandName?.trimmed ?? ""
        dosageForm = MedicineBoxDosageFormCatalog.storedValue(fromAny: recognition.dosageForm ?? "")
        let rawStrength = recognition.strength?.trimmed ?? ""
        let parsed = MedicineSpecification.parse(fromAPIStrength: rawStrength)
        if parsed.hasStructuredContent {
            specification = parsed
        } else if rawStrength.isEmpty == false {
            specification = MedicineSpecification(rawLegacyOnly: rawStrength)
        }
        totalQuantity = recognition.totalQuantity?.trimmed ?? ""
        if let expire = recognition.expireDate?.nilIfBlank {
            hasExpireDate = true
            expireDate = Date.parseOrNow(expire)
        }
        notes = recognition.notes?.trimmed ?? ""
        MedicineSpecification.mergeDoseUnitFromAPI(recognition.doseUnit, into: &specification)
    }

    init(existing: SparkMedicalSyncAPI.RemoteMedicineBox) {
        medicineName = existing.medicineName
        medicineType = MedicineBoxTypeCatalog.storedValue(fromAny: existing.medicineType)
        brandName = existing.brandName
        dosageForm = existing.dosageForm
        let parsed = MedicineSpecification.parse(fromAPIStrength: existing.strength)
        if parsed.hasStructuredContent {
            specification = parsed
        } else if existing.strength.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            specification = MedicineSpecification(rawLegacyOnly: existing.strength)
        } else {
            specification = MedicineSpecification()
        }
        MedicineSpecification.mergeDoseUnitFromAPI(existing.doseUnit, into: &specification)
        if let q = existing.totalQuantity {
            totalQuantity = MedicineBoxDraft.formatQuantity(q)
        } else {
            totalQuantity = ""
        }
        if let expireDate = existing.expireDate {
            hasExpireDate = true
            self.expireDate = expireDate
        }
        notes = existing.notes
        attachments = existing.attachments ?? []
    }

    var totalQuantityValue: Double? {
        Double(totalQuantity.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    fileprivate func payload(memberID: Int, fileIds: [Int] = []) throws -> MedicineBoxPayload {
        let trimmedQty = totalQuantity.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTotal: Double?
        if trimmedQty.isEmpty {
            resolvedTotal = nil
        } else if let v = Double(trimmedQty) {
            resolvedTotal = v
        } else {
            throw MedicineBoxFormError.invalidQuantity
        }
        return MedicineBoxPayload(
            member: memberID,
            medicineName: medicineName.trimmed,
            medicineType: medicineType.nilIfBlank,
            brandName: brandName.nilIfBlank ?? "",
            dosageForm: dosageForm.nilIfBlank ?? "",
            strength: specification.storedStrengthString.nilIfBlank ?? "",
            doseUnit: specification.backendDoseUnitField,
            totalQuantity: resolvedTotal,
            expireDate: hasExpireDate ? MedicalDateCoding.encodeDateOnly(expireDate) : nil,
            notes: notes.nilIfBlank ?? "",
            extra: [:],
            fileIds: fileIds
        )
    }

    private static func formatQuantity(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    func recognitionDraft(sortOrder: String? = nil) -> MedicineBoxRecognitionDraft {
        MedicineBoxRecognitionDraft(
            medicineName: medicineName.nilIfBlank,
            medicineType: medicineType.nilIfBlank,
            brandName: brandName.nilIfBlank,
            dosageForm: dosageForm.nilIfBlank,
            strength: specification.storedStrengthString.nilIfBlank,
            doseUnit: specification.backendDoseUnitField.nilIfBlank,
            totalQuantity: totalQuantity.nilIfBlank,
            expireDate: hasExpireDate ? MedicalDateCoding.encodeDateOnly(expireDate) : nil,
            notes: notes.nilIfBlank,
            extra: nil,
            sortOrder: sortOrder
        )
    }
}

private struct MedicineBoxPayload: Encodable {
    let member: Int
    let medicineName: String
    let medicineType: String?
    let brandName: String
    let dosageForm: String
    let strength: String
    let doseUnit: String
    let totalQuantity: Double?
    let expireDate: String?
    let notes: String
    let extra: [String: String]
    let fileIds: [Int]

    enum CodingKeys: String, CodingKey {
        case member
        case medicineName = "medicine_name"
        case medicineType = "medicine_type"
        case brandName = "brand_name"
        case dosageForm = "dosage_form"
        case strength
        case doseUnit = "dose_unit"
        case totalQuantity = "total_quantity"
        case expireDate = "expire_date"
        case notes
        case extra
        case fileIds = "file_ids"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(member, forKey: .member)
        try c.encode(medicineName, forKey: .medicineName)
        try c.encodeIfPresent(medicineType, forKey: .medicineType)
        try c.encode(brandName, forKey: .brandName)
        try c.encode(dosageForm, forKey: .dosageForm)
        try c.encode(strength, forKey: .strength)
        try c.encode(doseUnit, forKey: .doseUnit)
        try c.encodeIfPresent(totalQuantity, forKey: .totalQuantity)
        try c.encodeIfPresent(expireDate, forKey: .expireDate)
        try c.encode(notes, forKey: .notes)
        try c.encode(extra, forKey: .extra)
        try c.encode(fileIds, forKey: .fileIds)
    }
}

private enum MedicineBoxFormError: LocalizedError {
    case invalidQuantity

    var errorDescription: String? {
        switch self {
        case .invalidQuantity:
            return "数量格式不正确"
        }
    }
}

private struct MedicineBoxDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value.isEmpty ? "未填写" : value)
                .multilineTextAlignment(.trailing)
        }
    }
}

enum MedicineBoxTypeCatalog {
    nonisolated static let defaultStoredValue = ""

    nonisolated static let defaults: [SparkBilingualItem] = [
        .init(cn: "感冒发烧", en: "Cold & Fever"),
        .init(cn: "胃肠消化", en: "GI & Digestion"),
        .init(cn: "咳嗽咽痛", en: "Cough & Throat"),
        .init(cn: "皮肤骨痛", en: "Skin, Bone & Pain"),
        .init(cn: "慢病用药", en: "Chronic Medication"),
        .init(cn: "儿童用药", en: "Pediatric")
    ]

    nonisolated static let defaultStoredOptions: [String] = defaults.map(\.cn)

    nonisolated private static let legacyCodeMap: [String: String] = [
        "cold_fever": "感冒发烧",
        "gi_digestion": "胃肠消化",
        "cough_throat": "咳嗽咽痛",
        "skin_bone": "皮肤骨痛",
        "chronic": "慢病用药",
        "pediatric": "儿童用药",
        "uncategorized": ""
    ]

    nonisolated private static var prefersEnglish: Bool {
        if #available(iOS 16, *) {
            let code = Locale.current.language.languageCode?.identifier ?? ""
            return code.hasPrefix("zh") == false
        }
        return Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == false
    }

    nonisolated static func options(in boxes: [SparkMedicalSyncAPI.RemoteMedicineBox]) -> [String] {
        let custom = boxes.compactMap { blankToNil(storedValue(fromAny: $0.medicineType)) }
        return mergedOptions(defaultStoredOptions + custom)
    }

    nonisolated static func mergedOptions(_ values: [String]) -> [String] {
        uniqued(values.map(storedValue(fromAny:)))
    }

    nonisolated static func displayOptions(for values: [String]) -> [String] {
        uniqued(values).map(displayString(stored:))
    }

    nonisolated static func displayString(stored: String?) -> String {
        let stored = storedValue(fromAny: stored)
        guard let item = defaults.first(where: { $0.cn == stored || $0.en == stored }) else {
            return blankToNil(stored) ?? defaultStoredValue
        }
        return prefersEnglish ? item.en : item.cn
    }

    nonisolated static func storedValue(fromDisplay display: String) -> String {
        let text = display.trimmingCharacters(in: .whitespacesAndNewlines)
        if let item = defaults.first(where: { $0.cn == text || $0.en == text }) {
            return item.cn
        }
        return text
    }

    nonisolated static func storedValue(fromAny raw: String?) -> String {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), raw.isEmpty == false else {
            return defaultStoredValue
        }
        if let mapped = legacyCodeMap[raw] {
            return mapped
        }
        if let item = defaults.first(where: { $0.cn == raw || $0.en == raw }) {
            return item.cn
        }
        return raw
    }

    nonisolated static func systemImage(for display: String) -> String? {
        switch storedValue(fromDisplay: display) {
        case "感冒发烧":
            return "thermometer.medium"
        case "胃肠消化":
            return "cross.case"
        case "咳嗽咽痛":
            return "lungs"
        case "皮肤骨痛":
            return "figure.walk"
        case "慢病用药":
            return "calendar.badge.clock"
        case "儿童用药":
            return "person.crop.circle"
        default:
            return "tag"
        }
    }

    nonisolated private static func uniqued(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { continue }
            let key = storedValue(fromAny: trimmed)
            if seen.insert(key).inserted {
                result.append(key)
            }
        }
        return result
    }

    nonisolated private static func blankToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private func medicineBoxStockText(_ box: SparkMedicalSyncAPI.RemoteMedicineBox) -> String {
    guard let q = box.totalQuantity else { return "未填写" }
    return q.formatted(.number.precision(.fractionLength(0...2)))
}

private func medicineStrengthText(_ strength: String?) -> String? {
    guard let raw = strength?.trimmingCharacters(in: .whitespacesAndNewlines), raw.isEmpty == false else { return nil }
    let spec = MedicineSpecification.parse(fromAPIStrength: raw)
    if spec.hasStructuredContent {
        return spec.displayString(prefersEnglish: SparkFormCatalogMenuLocale.prefersEnglish)
    }
    return raw
}

private func medicineStrengthDetailValue(_ strength: String) -> String {
    let raw = strength.trimmingCharacters(in: .whitespacesAndNewlines)
    guard raw.isEmpty == false else { return "" }
    let spec = MedicineSpecification.parse(fromAPIStrength: raw)
    if spec.hasStructuredContent {
        return spec.displayString(prefersEnglish: SparkFormCatalogMenuLocale.prefersEnglish)
    }
    return raw
}

private func medicineTypeText(_ type: String?) -> String? {
    guard let type, !type.isEmpty else { return nil }
    return MedicineBoxTypeCatalog.displayString(stored: type)
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
