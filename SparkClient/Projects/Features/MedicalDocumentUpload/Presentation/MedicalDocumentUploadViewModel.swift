import Combine
import Foundation

/// 医疗单据上传与「Typed」识别流程的界面状态：选文件 → 上传/OCR/类型/抽取 → 展示结果 → 保存并绑定附件。
///
/// - 依赖用例完成 I/O 与领域逻辑，本类型只编排 `stage`、`progress` 与用户可写状态。
/// - 步骤 ID（`upload` / `ocr` / `type_recognition` / `extract` / `save`）需与界面展示顺序一致。
/// - 实现 `MedicalDocumentUploadStepReporter` 协议，用于上报步骤状态。
@MainActor
final class MedicalDocumentUploadViewModel: ObservableObject {
    // MARK: - Types

    /// 上传页所处大阶段：挑选文件、流水线处理中、已有识别结果。
    enum Stage: Equatable {
        case picking
        case processing
        case result
    }

    // MARK: - Published state

    /// 当前所处大阶段
    @Published var stage: Stage = .picking
    @Published private(set) var selectedMemberName: String?
    @Published private(set) var selectedFiles: [MedicalUploadLocalFile] = []
    @Published private(set) var previewItems: [FilePreviewInput] = []
    
    /// 新的进度模型，用于完整进度管理
    @Published var progress: MedicalDocumentUploadProgress?
    /// 是否需要手动选择文档类型
    @Published var needsManualModeSelection: Bool = false

    @Published private(set) var typedOutput: MedicalDocumentTypedExtractionOutput?
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?
    @Published var saveReceipt: MedicalDocumentSaveReceipt?
    /// 用户选择的文书类型；`.auto` 时由服务端/模型推断。
    @Published var selectedKind: MedicalDocumentKind = .auto

    // MARK: - Dependencies

    private let patientContextStore: PatientContextStore
    private let uploadFilesUseCase: UploadMedicalDocumentFilesUseCase
    private let extractUseCase: ExtractTypedMedicalDocumentUseCase
    private let saveUseCase: SaveTypedMedicalDocumentUseCase
    private let bindUseCase: BindUploadedFilesToMedicalBusinessUseCase
    private let buildPreviewUseCase: BuildMedicalDocumentPreviewItemsUseCase
    private let logger: Logger
    /// 最近一次识别流程中已上传的文件，供保存成功后与业务单据绑定。
    private var uploadedFiles: [UploadedMedicalDocumentFile] = []

    // MARK: - Initialization

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

    // MARK: - Derived state

    /// 是否允许开始识别：已选文件且就诊人上下文中有当前选中成员。
    var canStartRecognition: Bool {
        selectedFiles.isEmpty == false && patientContextStore.context.selectedMember != nil
    }

    // MARK: - File selection

    /// 替换当前待识别列表并刷新预览；会清除之前的错误提示。
    func setSelectedFiles(_ files: [MedicalUploadLocalFile]) {
        selectedFiles = files
        previewItems = buildPreviewUseCase.execute(files: files)
        errorMessage = nil
        logger.info("已更新待识别文件，数量=\(files.count)", category: "medical_upload")
    }

    /// 按本地文件 ID 移除一项并同步预览。
    func removeFile(id: UUID) {
        selectedFiles.removeAll { $0.id == id }
        previewItems = buildPreviewUseCase.execute(files: selectedFiles)
        logger.info("已移除文件，剩余数量=\(selectedFiles.count)", category: "medical_upload")
    }

    // MARK: - Recognition pipeline

    /// 执行上传 + Typed 抽取；成功则进入 `.result`，失败时标记当前步骤为 `.failed` 并写入 `errorMessage`。
    func startRecognition() async {
        guard let member = patientContextStore.context.selectedMember else {
            errorMessage = L10n.text("medical.upload.error.no_member")
            logger.warning("开始识别失败：未选择就诊成员", category: "medical_upload")
            return
        }
        selectedMemberName = member.name
        errorMessage = nil
        typedOutput = nil
        saveReceipt = nil
        stage = .processing
        
        // 创建新的进度模型
        progress = createProgress()
        needsManualModeSelection = false

        logger.info(
            "开始识别流程 memberID=\(member.id) 文件数=\(selectedFiles.count) selectedKind=\(selectedKind.rawValue)",
            category: "medical_upload"
        )
        do {
            uploadedFiles = try await uploadFilesUseCase.execute(memberID: member.id, files: selectedFiles)
            logger.info("文件上传完成，远端文件数=\(uploadedFiles.count)", category: "medical_upload")
            
            complete(.upload, outcome: .success)
            start(.ocr, variant: kindToVariant(selectedKind))

            let output = try await extractUseCase.execute(
                memberID: member.id,
                files: selectedFiles,
                selectedKind: selectedKind
            )

            complete(.ocr, outcome: .success)
            complete(.typeRecognition, outcome: .success)
            complete(.extract, outcome: .success)

            typedOutput = output
            stage = .result
            logger.info(
                "Typed 识别流程完成，resolvedKind=\(output.envelope.typeResolution.kind.rawValue)",
                category: "medical_upload"
            )
        } catch {
            fail(.extract)
            errorMessage = error.localizedDescription
            logger.error("Typed 识别流程失败：\(error.localizedDescription)", category: "medical_upload")
        }
    }

    // MARK: - Save & bind

    /// 将当前 `typedOutput` 持久化，并在成功后把已上传附件与业务单据绑定。
    /// - Returns: 保存且绑定流程是否全部成功。
    func saveResult() async -> Bool {
        guard isSaving == false else {
            logger.debug("忽略保存请求：仍在保存中", category: "medical_upload")
            return false
        }
        guard let typedOutput else {
            errorMessage = L10n.text("medical.upload.error.no_result")
            logger.warning("保存失败：无识别结果 typedOutput=nil", category: "medical_upload")
            return false
        }
        isSaving = true
        start(.save, variant: kindToVariant(typedOutput.envelope.typeResolution.kind))
        defer { isSaving = false }

        logger.info(
            "开始保存识别结果 kind=\(typedOutput.envelope.typeResolution.kind.rawValue)",
            category: "medical_upload"
        )
        do {
            let receipt = try await saveUseCase.execute(output: typedOutput)
            saveReceipt = receipt
            complete(.save, outcome: .success)
            logger.info(
                "保存成功 recordID=\(receipt.recordID) success=\(receipt.isSuccess)",
                category: "medical_upload"
            )
            await bindUseCase.execute(
                uploadedFiles: uploadedFiles,
                kind: typedOutput.envelope.typeResolution.kind,
                receipt: receipt
            )
            logger.info(
                "附件绑定完成 uploaded=\(uploadedFiles.count) recordID=\(receipt.recordID)",
                category: "medical_upload"
            )
            return true
        } catch {
            fail(.save)
            errorMessage = localizedSaveErrorMessage(from: error)
            logger.error("保存或绑定失败：\(error.localizedDescription)", category: "medical_upload")
            return false
        }
    }

    /// 将界面与中间态恢复为初始：清空文件、结果、进度与上传缓存，就诊人名称回读当前上下文。
    func reset() {
        stage = .picking
        selectedFiles = []
        previewItems = []
        progress = nil
        needsManualModeSelection = false
        typedOutput = nil
        saveReceipt = nil
        errorMessage = nil
        selectedKind = .auto
        uploadedFiles = []
        selectedMemberName = patientContextStore.context.selectedMember?.name
        logger.info("已重置医疗上传流程", category: "medical_upload")
    }
    
    /// 仅重置识别状态，保留已选择的文件
    /// 用于用户选择重新识别时，不需要重新选择文件
    func resetRecognitionState() {
        typedOutput = nil
        saveReceipt = nil
        progress = nil
        needsManualModeSelection = false
        errorMessage = nil
        // 注意：不重置 selectedFiles、previewItems 和 uploadedFiles，保留用户选择的文件
        logger.info("已重置识别状态（保留已选文件）", category: "medical_upload")
    }

    // MARK: - Progress management
    
    /// 创建初始进度模型
    /// 根据 selectedKind 确定步骤变体和预估时间
    func createProgress() -> MedicalDocumentUploadProgress {
        let variant = kindToVariant(selectedKind)
        let estimatedSeconds = estimatedRecognitionSeconds()
        
        // 创建初始步骤（upload 为 running，其余为 idle）
        let initialSteps: [MedicalDocumentUploadStep] = [
            .init(
                id: MedicalDocumentUploadFlowStep.upload.rawValue,
                title: MedicalDocumentUploadFlowStep.upload.runningPresentation(variant: variant).title,
                subtitle: MedicalDocumentUploadFlowStep.upload.runningPresentation(variant: variant).subtitle,
                state: .running,
                estimatedSeconds: nil
            ),
            .init(
                id: MedicalDocumentUploadFlowStep.ocr.rawValue,
                title: MedicalDocumentUploadFlowStep.ocr.runningPresentation(variant: variant).title,
                subtitle: MedicalDocumentUploadFlowStep.ocr.runningPresentation(variant: variant).subtitle,
                state: .idle,
                estimatedSeconds: nil
            ),
            .init(
                id: MedicalDocumentUploadFlowStep.typeRecognition.rawValue,
                title: MedicalDocumentUploadFlowStep.typeRecognition.runningPresentation(variant: variant).title,
                subtitle: MedicalDocumentUploadFlowStep.typeRecognition.runningPresentation(variant: variant).subtitle,
                state: .idle,
                estimatedSeconds: nil
            ),
            .init(
                id: MedicalDocumentUploadFlowStep.extract.rawValue,
                title: MedicalDocumentUploadFlowStep.extract.runningPresentation(variant: variant).title,
                subtitle: MedicalDocumentUploadFlowStep.extract.runningPresentation(variant: variant).subtitle,
                state: .idle,
                estimatedSeconds: nil
            ),
            .init(
                id: MedicalDocumentUploadFlowStep.save.rawValue,
                title: MedicalDocumentUploadFlowStep.save.runningPresentation(variant: variant).title,
                subtitle: MedicalDocumentUploadFlowStep.save.runningPresentation(variant: variant).subtitle,
                state: .idle,
                estimatedSeconds: nil
            )
        ]
        
        return MedicalDocumentUploadProgress(
            title: L10n.text("medical.upload.processing.title"),
            statusLabel: L10n.text("medical.upload.status.processing"),
            elapsedSeconds: 0,
            estimatedSeconds: estimatedSeconds,
            steps: initialSteps
        )
    }
    
    /// 将 MedicalDocumentKind 转换为 StartVariant
    private func kindToVariant(_ kind: MedicalDocumentKind) -> MedicalDocumentUploadFlowStep.StartVariant {
        switch kind {
        case .auto:
            return .default
        case .caseDocument:
            return .caseDocument
        case .healthExamReport:
            return .healthExamReport
        case .medicalReport:
            return .medicalReport
        case .prescription:
            return .prescription
        case .medication:
            return .medication
        }
    }
    
    /// 估算识别流程所需时间（秒）
    /// 基于文件总大小和数量计算
    func estimatedRecognitionSeconds() -> Int {
        let fileCount = selectedFiles.count
        guard fileCount > 0 else { return 60 }
        
        // 计算总字节数
        var totalBytes: Int64 = 0
        for file in selectedFiles {
            if let fileSize = try? FileManager.default.attributesOfItem(atPath: file.url.path)[.size] as? Int64 {
                totalBytes += fileSize
            } else {
                // 无法获取大小，按 500KB 估算
                totalBytes += 512_000
            }
        }
        
        let mb = Double(max(totalBytes, 1)) / 1_048_576.0
        let fromSize = Int(ceil(mb * 28))
        let fromFiles = fileCount * 20
        let base = 35
        let seconds = base + fromSize + fromFiles
        
        // 限制范围 48-900 秒
        return min(max(seconds, 48), 900)
    }

    // MARK: - Errors

    /// 统一保存失败提示：若有 HTTP 后端文案则拼接本地化模板，否则退回 `localizedDescription`。
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

// MARK: - StepReporter 协议实现

extension MedicalDocumentUploadViewModel: MedicalDocumentUploadStepReporter {
    func start(_ step: MedicalDocumentUploadFlowStep, variant: MedicalDocumentUploadFlowStep.StartVariant) {
        guard var currentProgress = progress else { return }
        
        let presentation = step.runningPresentation(variant: variant)
        let newStep = MedicalDocumentUploadStep(
            id: step.rawValue,
            title: presentation.title,
            subtitle: presentation.subtitle,
            state: .running,
            estimatedSeconds: nil
        )
        
        // 查找或添加步骤
        if let idx = currentProgress.steps.firstIndex(where: { $0.id == step.rawValue }) {
            // 更新已有步骤
            currentProgress.steps[idx] = newStep
            // 将之前的步骤标记为 done
            for prevIdx in 0..<idx {
                if currentProgress.steps[prevIdx].state != .done && currentProgress.steps[prevIdx].state != .failed {
                    currentProgress.steps[prevIdx].state = .done
                }
            }
        } else {
            // 添加新步骤
            currentProgress.steps.append(newStep)
        }
        
        progress = currentProgress
        logger.debug("开始步骤: \(step.rawValue)", category: "medical_upload")
    }
    
    func complete(_ step: MedicalDocumentUploadFlowStep, outcome: MedicalDocumentUploadFlowStep.CompletionOutcome) {
        guard var currentProgress = progress else { return }
        
        let presentation = step.completionPresentation(outcome: outcome)
        
        if let idx = currentProgress.steps.firstIndex(where: { $0.id == step.rawValue }) {
            currentProgress.steps[idx].state = .done
            currentProgress.steps[idx].title = presentation.title
            currentProgress.steps[idx].subtitle = presentation.subtitle
        } else {
            // 步骤不存在，添加为已完成
            let completedStep = MedicalDocumentUploadStep(
                id: step.rawValue,
                title: presentation.title,
                subtitle: presentation.subtitle,
                state: .done,
                estimatedSeconds: nil
            )
            currentProgress.steps.append(completedStep)
        }
        
        progress = currentProgress
        logger.debug("完成步骤: \(step.rawValue), 结果: \(outcome)", category: "medical_upload")
    }
    
    func fail(_ step: MedicalDocumentUploadFlowStep) {
        guard var currentProgress = progress else { return }
        
        if let idx = currentProgress.steps.firstIndex(where: { $0.id == step.rawValue }) {
            currentProgress.steps[idx].state = .failed
        } else {
            // 步骤不存在，添加为失败
            let presentation = step.runningPresentation()
            let failedStep = MedicalDocumentUploadStep(
                id: step.rawValue,
                title: presentation.title,
                subtitle: presentation.subtitle,
                state: .failed,
                estimatedSeconds: nil
            )
            currentProgress.steps.append(failedStep)
        }
        
        progress = currentProgress
        logger.debug("步骤失败: \(step.rawValue)", category: "medical_upload")
    }
}

#if DEBUG
/// SwiftUI 预览用：返回固定 JSON 的本地 AI Runtime，避免真网路与真实模型。
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
    /// 构造可用于 Canvas 预览的 ViewModel（假网络、假 Runtime）。
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
        let dummyOSSAPI = SparkOSSAPI(configuration: SparkBackendConfiguration(engine: previewEngine))
        let dummyOSSStore = SparkOSSConfigurationStore()
        let dummyOSSClient = OSSClientWrapper()
        let binder = DefaultMedicalDocumentAttachmentBinder(fileAPI: dummyFileAPI)
        let dummyFileTransfer = FileTransferService(
            api: dummyFileAPI,
            ossAPI: dummyOSSAPI,
            ossClient: dummyOSSClient,
            ossConfigurationStore: dummyOSSStore,
            cacheManager: FileCacheManager()
        )
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
