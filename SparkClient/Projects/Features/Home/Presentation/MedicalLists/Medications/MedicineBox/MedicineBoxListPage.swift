import SwiftUI
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
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    let notificationClient: any NotificationClient
    let logger: Logger
    let onMedicineBoxesChanged: ([SparkMedicalSyncAPI.RemoteMedicineBox]) -> Void

    @State private var localMedicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    @State private var sheetDestination: MedicineBoxSheetDestination?
    @State private var showingUploadSheet = false
    @State private var showingMedicineBoxCamera = false
    @State private var showCameraUnavailableAlert = false

    init(
        medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox],
        memberID: Int?,
        workflowAPI: SparkMedicalWorkflowAPI,
        medicalQueryAPI: SparkMedicalQueryAPI,
        fileTransferService: FileTransferService,
        viewModel: MedicalDocumentUploadViewModel,
        aiSettingsViewModel: AISettingsViewModel,
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
        self.aiSettingsViewModel = aiSettingsViewModel
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
                Text(L10n.text("home.medical.medicine_box.empty"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedBoxes, id: \.id) { box in
                    MainNavigationLink {
                        MedicineBoxDetailPage(
                            box: box,
                            entryMemberID: memberID,
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
        .navigationTitle(L10n.text("home.medical.medicine_box.title"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                presentMedicineBoxCamera()
            } label: {
                Label(L10n.text("home.medical.medicine_box.camera_add"), systemImage: "camera.fill")
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
                .accessibilityLabel(L10n.text("home.medical.medicine_box.add_a11y"))
            }
        }
        .sheet(item: $sheetDestination) { destination in
            if let memberID {
                MedicineBoxFormView(
                    mode: destination.formMode,
                    entryMemberID: memberID,
                    defaultBindingMemberID: memberID,
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
        .onChange(of: viewModel.saveSucceededRevision) { _ in
            Task { await refreshMedicineBoxes() }
        }
        .sheet(isPresented: $showingUploadSheet) {
            MedicalAttachmentUploadListSheet(documentType: .medicineBox) { files in
                startMedicineBoxRecognition(files: files)
            }
        }
        .fullScreenCover(isPresented: $showingMedicineBoxCamera) {
            MedicineBoxCameraSceneView(
                onCancel: { showingMedicineBoxCamera = false },
                onImagesCaptured: { images in
                    showingMedicineBoxCamera = false
                    handleCapturedMedicineBoxImages(images)
                }
            )
        }
        .alert(L10n.text("medical.upload.medicine_box.sheet.camera_unavailable_title"), isPresented: $showCameraUnavailableAlert) {
            Button(L10n.text("common.ok"), role: .cancel) {}
        } message: {
            Text(L10n.text("medical.upload.medicine_box.sheet.camera_unavailable_message"))
        }
        .fullScreenCover(isPresented: $viewModel.isUploadPresented) {
            CompatibleNavigationContainer {
                MedicalDocumentUploadHostView(
                    viewModel: viewModel,
                    aiSettingsViewModel: aiSettingsViewModel
                )
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
    }

    private func presentMedicineBoxCamera() {
        guard memberID != nil else { return }
        #if canImport(UIKit)
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            showingMedicineBoxCamera = true
        } else {
            showCameraUnavailableAlert = true
        }
        #else
        showCameraUnavailableAlert = true
        #endif
    }

    private func handleCapturedMedicineBoxImages(_ images: [MedicineBoxCapturedImage]) {
        let files = MedicineBoxLocalFileSupport.saveCapturedImages(images, logger: logger)
        guard !files.isEmpty else {
            notificationClient.error(
                L10n.text(
                    "medical.upload.medicine_box.sheet.save_failed_message",
                    fallback: "图片保存失败，请重试"
                ),
                title: L10n.text("common.error"),
                source: "home.medicine_box.camera"
            )
            return
        }
        if files.count < images.count {
            notificationClient.error(
                L10n.text(
                    "medical.upload.medicine_box.sheet.save_failed_message",
                    fallback: "部分图片保存失败，请重试"
                ),
                title: L10n.text("common.error"),
                source: "home.medicine_box.camera"
            )
        }
        startMedicineBoxRecognition(files: files)
    }

    @ViewBuilder
    private var missingMemberSheet: some View {
        let content = Text(L10n.text("home.medical.medicine_box.select_member_first"))
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
