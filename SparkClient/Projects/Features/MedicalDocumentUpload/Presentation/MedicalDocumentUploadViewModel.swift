import Combine
import Foundation

@MainActor
final class MedicalDocumentUploadViewModel: ObservableObject {
    enum Stage: Equatable {
        case picking
        case processing
        case result
    }

    struct ProgressStep: Identifiable, Equatable {
        enum State: Equatable { case waiting, running, done, failed }
        let id: String
        let title: String
        var state: State
    }

    @Published private(set) var stage: Stage = .picking
    @Published private(set) var selectedMemberName: String?
    @Published private(set) var selectedFiles: [MedicalUploadLocalFile] = []
    @Published private(set) var previewItems: [FilePreviewInput] = []
    @Published private(set) var progressSteps: [ProgressStep] = []
    @Published private(set) var typedOutput: MedicalDocumentTypedExtractionOutput?
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?
    @Published var saveReceipt: MedicalDocumentSaveReceipt?
    @Published var selectedKind: MedicalDocumentKind = .auto

    private let patientContextStore: PatientContextStore
    private let uploadFilesUseCase: UploadMedicalDocumentFilesUseCase
    private let extractUseCase: ExtractTypedMedicalDocumentUseCase
    private let saveUseCase: SaveTypedMedicalDocumentUseCase
    private let bindUseCase: BindUploadedFilesToMedicalBusinessUseCase
    private let buildPreviewUseCase: BuildMedicalDocumentPreviewItemsUseCase
    private let logger: Logger
    private var uploadedFiles: [UploadedMedicalDocumentFile] = []

    init(
        patientContextStore: PatientContextStore,
        uploadFilesUseCase: UploadMedicalDocumentFilesUseCase,
        extractUseCase: ExtractTypedMedicalDocumentUseCase,
        saveUseCase: SaveTypedMedicalDocumentUseCase,
        bindUseCase: BindUploadedFilesToMedicalBusinessUseCase,
        buildPreviewUseCase: BuildMedicalDocumentPreviewItemsUseCase = BuildMedicalDocumentPreviewItemsUseCase(),
        logger: Logger = ConsoleLogger()
    ) {
        self.patientContextStore = patientContextStore
        self.uploadFilesUseCase = uploadFilesUseCase
        self.extractUseCase = extractUseCase
        self.saveUseCase = saveUseCase
        self.bindUseCase = bindUseCase
        self.buildPreviewUseCase = buildPreviewUseCase
        self.logger = logger
        self.selectedMemberName = patientContextStore.context.selectedMember?.name
    }

    var canStartRecognition: Bool {
        selectedFiles.isEmpty == false && patientContextStore.context.selectedMember != nil
    }

    func setSelectedFiles(_ files: [MedicalUploadLocalFile]) {
        selectedFiles = files
        previewItems = buildPreviewUseCase.execute(files: files)
        errorMessage = nil
        logger.info("已更新待识别文件，数量=\(files.count)", category: "medical_upload")
    }

    func removeFile(id: UUID) {
        selectedFiles.removeAll { $0.id == id }
        previewItems = buildPreviewUseCase.execute(files: selectedFiles)
        logger.info("已移除文件，剩余数量=\(selectedFiles.count)", category: "medical_upload")
    }

    func startRecognition() async {
        guard let member = patientContextStore.context.selectedMember else {
            errorMessage = L10n.text("medical.upload.error.no_member")
            return
        }
        selectedMemberName = member.name
        errorMessage = nil
        typedOutput = nil
        saveReceipt = nil
        stage = .processing
        progressSteps = [
            .init(id: "upload", title: "Upload", state: .running),
            .init(id: "ocr", title: "OCR", state: .waiting),
            .init(id: "type", title: "Type", state: .waiting),
            .init(id: "extract", title: "Extract", state: .waiting),
            .init(id: "save", title: "Save", state: .waiting)
        ]
        do {
            uploadedFiles = try await uploadFilesUseCase.execute(memberID: member.id, files: selectedFiles)
            markDone("upload")
            markRunning("ocr")
            let output = try await extractUseCase.execute(
                memberID: member.id,
                files: selectedFiles,
                selectedKind: selectedKind
            )
            markDone("ocr")
            markDone("type")
            markDone("extract")
            typedOutput = output
            stage = .result
            logger.info("typed 识别流程完成，kind=\(output.envelope.typeResolution.kind.rawValue)", category: "medical_upload")
        } catch {
            markFailedCurrent()
            errorMessage = error.localizedDescription
            logger.error("typed 识别流程失败：\(error.localizedDescription)", category: "medical_upload")
        }
    }

    func saveResult() async -> Bool {
        guard isSaving == false else { return false }
        guard let typedOutput else {
            errorMessage = "暂无可保存的识别结果。"
            return false
        }
        isSaving = true
        markRunning("save")
        defer { isSaving = false }

        do {
            let receipt = try await saveUseCase.execute(output: typedOutput)
            saveReceipt = receipt
            markDone("save")
            await bindUseCase.execute(
                uploadedFiles: uploadedFiles,
                kind: typedOutput.envelope.typeResolution.kind,
                receipt: receipt
            )
            return true
        } catch {
            markFailedCurrent()
            errorMessage = localizedSaveErrorMessage(from: error)
            return false
        }
    }

    func reset() {
        stage = .picking
        selectedFiles = []
        previewItems = []
        progressSteps = []
        typedOutput = nil
        saveReceipt = nil
        errorMessage = nil
        selectedKind = .auto
        uploadedFiles = []
        selectedMemberName = patientContextStore.context.selectedMember?.name
    }

    private func markRunning(_ id: String) { update(id) { $0.state = .running } }
    private func markDone(_ id: String) { update(id) { $0.state = .done } }

    private func markFailedCurrent() {
        guard let running = progressSteps.first(where: { $0.state == .running }) else { return }
        update(running.id) { $0.state = .failed }
    }

    private func update(_ id: String, transform: (inout ProgressStep) -> Void) {
        guard let idx = progressSteps.firstIndex(where: { $0.id == id }) else { return }
        var next = progressSteps[idx]
        transform(&next)
        progressSteps[idx] = next
    }

    /// 统一保存失败提示：本地化前缀 + 服务端错误内容。
    private func localizedSaveErrorMessage(from error: Error) -> String {
        let serverMessage: String?
        if let networkError = error as? SparkNetworkError,
           case .httpError(_, let backend, _) = networkError {
            let text = backend?.msg.trimmingCharacters(in: .whitespacesAndNewlines)
            serverMessage = (text?.isEmpty == false) ? text : nil
        } else {
            serverMessage = nil
        }

        guard let serverMessage else {
            return error.localizedDescription
        }
        return String(
            format: L10n.text("medical.upload.submit_failed_with_server_error"),
            serverMessage
        )
    }
}

#if DEBUG
private struct PreviewMedicalRuntimeService: AIRuntimeServing {
    func generateTextStream(
        request _: AIRuntimeTextRequest
    ) async throws -> AsyncThrowingStream<AIRuntimeStreamEvent, Error> {
        let response = AIRuntimeTextResponse(
            text: """
            {"title":"门诊复查记录","summary":"患者主诉咽痛三天，体温正常。","diagnosis":"上呼吸道感染","occurredAt":"2026-04-01"}
            """,
            reasoningText: nil,
            model: "preview",
            promptTokens: nil,
            completionTokens: nil,
            toolCalls: [],
            finishReason: "stop"
        )
        return AsyncThrowingStream { continuation in
            continuation.yield(.textDelta(response.text))
            continuation.yield(.completed(response))
            continuation.finish()
        }
    }
}

extension MedicalDocumentUploadViewModel {
    static func preview() -> MedicalDocumentUploadViewModel {
        let patientStore = PatientContextStore()
        let member = Member(id: 1, name: "本人", relationship: "self", isPrimary: true)
        patientStore.update(members: [member], selectedMemberID: member.id)

        let promptFactory = MedicalPromptFactory()
        let typeResolver = DefaultMedicalDocumentTypeResolver(
            runtimeService: PreviewMedicalRuntimeService(),
            promptFactory: promptFactory
        )
        let extractor = DefaultTypedMedicalDocumentExtractor(
            ocrOrchestrator: OCROrchestrator(config: OCRConfiguration()),
            typeResolver: typeResolver,
            promptFactory: promptFactory,
            runtimeService: PreviewMedicalRuntimeService()
        )
        let previewEngine = SparkNetworkEngine(baseURL: URL(string: "https://preview.sparkclient.local")!)
        let previewWorkflowAPI = SparkMedicalWorkflowAPI(configuration: SparkBackendConfiguration(engine: previewEngine))
        let saver = DefaultTypedMedicalDocumentSaver(workflowAPI: previewWorkflowAPI)
        let dummyFileAPI = SparkFileAPI(engine: previewEngine)
        let binder = DefaultMedicalDocumentAttachmentBinder(fileAPI: dummyFileAPI)
        let dummyFileTransfer = FileTransferService(api: dummyFileAPI, cacheManager: FileCacheManager())
        return MedicalDocumentUploadViewModel(
            patientContextStore: patientStore,
            uploadFilesUseCase: UploadMedicalDocumentFilesUseCase(fileTransferService: dummyFileTransfer),
            extractUseCase: ExtractTypedMedicalDocumentUseCase(extractor: extractor),
            saveUseCase: SaveTypedMedicalDocumentUseCase(saver: saver),
            bindUseCase: BindUploadedFilesToMedicalBusinessUseCase(binder: binder)
        )
    }
}
#endif
