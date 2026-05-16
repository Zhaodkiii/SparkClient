import Combine
import Foundation

private enum RecognitionPipelineError: LocalizedError {
    case missingCheckpoint(String)

    var errorDescription: String? {
        switch self {
        case .missingCheckpoint(let name):
            return "缺少\(name)检查点，请从上一步重新识别"
        }
    }
}

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

    struct RecognitionModelOption: Identifiable, Equatable {
        let name: String
        let displayName: String

        var id: String { name }
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
    @Published private(set) var pipelineOCRText: String?
    @Published private(set) var typeResolution: MedicalDocumentTypeResolution?
    @Published private(set) var failedStep: MedicalDocumentUploadFlowStep?
    @Published private(set) var extractModelOptions: [RecognitionModelOption] = []
    @Published var overrideDocumentKindForRetry: MedicalDocumentKind?
    @Published var preferredExtractModelName: String?

    // MARK: - Dependencies

    private let memberContextStore: MemberContextStore
    private let uploadFilesUseCase: UploadMedicalDocumentFilesUseCase
    private let extractUseCase: ExtractTypedMedicalDocumentUseCase
    private let saveUseCase: SaveTypedMedicalDocumentUseCase
    private let bindUseCase: BindUploadedFilesToMedicalBusinessUseCase
    private let buildPreviewUseCase: BuildMedicalDocumentPreviewItemsUseCase
    private let loadEffectiveScenarioBundles: (@Sendable () async throws -> AIScenarioRemoteBundlesCollection)?
    private let logger: Logger
    /// 最近一次识别流程中已上传的文件，供保存成功后与业务单据绑定。
    private var uploadedFiles: [UploadedMedicalDocumentFile] = []
    /// 当前上传/OCR/AI 抽取任务；取消时同时中断外层 Task 与 Runtime 取消令牌。
    private var recognitionTask: Task<Void, Never>?
    private var recognitionCancellationToken: AIRuntimeCancellationToken?

    // MARK: - Initialization

    init(
        memberContextStore: MemberContextStore,
        uploadFilesUseCase: UploadMedicalDocumentFilesUseCase,
        extractUseCase: ExtractTypedMedicalDocumentUseCase,
        saveUseCase: SaveTypedMedicalDocumentUseCase,
        bindUseCase: BindUploadedFilesToMedicalBusinessUseCase,
        buildPreviewUseCase: BuildMedicalDocumentPreviewItemsUseCase = BuildMedicalDocumentPreviewItemsUseCase(),
        loadEffectiveScenarioBundles: (@Sendable () async throws -> AIScenarioRemoteBundlesCollection)? = nil,
        logger: Logger = ConsoleLogger()
    ) {
        self.memberContextStore = memberContextStore
        self.uploadFilesUseCase = uploadFilesUseCase
        self.extractUseCase = extractUseCase
        self.saveUseCase = saveUseCase
        self.bindUseCase = bindUseCase
        self.buildPreviewUseCase = buildPreviewUseCase
        self.loadEffectiveScenarioBundles = loadEffectiveScenarioBundles
        self.logger = logger
        self.selectedMemberName = memberContextStore.context.selectedMember?.name
    }

    // MARK: - Derived state

    /// 是否允许开始识别：已选文件且成员上下文中有当前选中成员。
    var canStartRecognition: Bool {
        selectedFiles.isEmpty == false && memberContextStore.context.selectedMember != nil
    }

    // MARK: - File selection

    /// 替换当前待识别列表并刷新预览；会清除之前的错误提示。
    func setSelectedFiles(_ files: [MedicalUploadLocalFile]) {
        selectedFiles = files
        previewItems = buildPreviewUseCase.execute(files: files)
        clearPipelineCheckpoints()
        errorMessage = nil
        logger.info("已更新待识别文件，数量=\(files.count)", module: .medical)
    }

    /// 按本地文件 ID 移除一项并同步预览。
    func removeFile(id: UUID) {
        selectedFiles.removeAll { $0.id == id }
        previewItems = buildPreviewUseCase.execute(files: selectedFiles)
        clearPipelineCheckpoints()
        logger.info("已移除文件，剩余数量=\(selectedFiles.count)", module: .medical)
    }

    // MARK: - Recognition pipeline

    /// 从 UI 启动识别流程，并保存任务句柄以支持真正取消后台抽取。
    func startRecognitionTask() {
        guard recognitionTask == nil else {
            logger.debug("忽略重复识别请求：已有识别任务运行中", module: .medical)
            return
        }

        recognitionTask = Task { [weak self] in
            await self?.startRecognition()
        }
    }

    func resumeRecognitionTask() {
        guard recognitionTask == nil else {
            logger.debug("忽略重复续跑请求：已有识别任务运行中", module: .medical)
            return
        }

        recognitionTask = Task { [weak self] in
            await self?.resumeRecognition()
        }
    }

    /// 用户主动取消识别：停止外层任务、通知 AI Runtime 结束流式生成，并回到文件选择页。
    func cancelRecognition() {
        logger.info("用户取消医疗识别流程", module: .medical)
        recognitionCancellationToken?.cancel()
        recognitionCancellationToken = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        resetRecognitionState()
        stage = .picking
    }

    /// 执行上传 + Typed 抽取；成功则进入 `.result`，失败时标记当前步骤为 `.failed` 并写入 `errorMessage`。
    /// 开始【医疗文档上传 + OCR + AI 抽取】全流程
    /// 作用：触发整个上传识别流水线（上传文件 → OCR → 类型判定 → AI 抽取 → 展示结果）
    func startRecognition() async {
        await runRecognitionPipeline(startingAt: .upload, resetForFreshRun: true)
    }

    func resumeRecognition() async {
        await runRecognitionPipeline(startingAt: failedStep ?? .upload, resetForFreshRun: false)
    }

    private func runRecognitionPipeline(startingAt requestedStartStep: MedicalDocumentUploadFlowStep, resetForFreshRun: Bool) async {
        // MARK: 1. 前置校验：必须选择就诊成员（患者）
        // 从全局状态中获取当前选中的患者，没有则直接报错返回
        guard let member = memberContextStore.context.selectedMember else {
            // 给 UI 展示错误文案（国际化 L10n）
            errorMessage = L10n.text("medical.upload.error.no_member")
            // 打印警告日志
            logger.warning("开始识别失败：未选择就诊成员", module: .medical)
            return
        }

        // 保存患者姓名，用于 UI 展示
        selectedMemberName = member.name
        // 清空之前的错误信息
        errorMessage = nil
        typedOutput = nil
        saveReceipt = nil
        stage = .processing

        // MARK: 2. 初始化进度条模型（用于 UI 展示进度）
        if resetForFreshRun || progress == nil {
            clearPipelineCheckpoints()
            progress = createProgress()
        } else {
            prepareProgressForRetry(from: requestedStartStep)
        }
        // 关闭“手动选择模式”标记
        needsManualModeSelection = false
        failedStep = nil
        let cancellationToken = AIRuntimeCancellationToken()
        recognitionCancellationToken = cancellationToken
        defer {
            if recognitionCancellationToken === cancellationToken {
                recognitionCancellationToken = nil
                recognitionTask = nil
            }
        }

        // MARK: 3. 打印关键日志：开始流程
        logger.info(
            "开始识别流程 memberID=\(member.id) 文件数=\(selectedFiles.count) selectedKind=\(selectedKind.rawValue)",
            module: .medical
        )

        // MARK: 4. 执行核心流程（try 捕获所有异常）
        var currentStep = requestedStartStep
        do {
            if shouldRun(.upload, from: requestedStartStep) {
                currentStep = .upload
                start(.upload, variant: kindToVariant(selectedKind))
                uploadedFiles = try await uploadFilesUseCase.execute(
                    memberID: member.id,
                    files: selectedFiles
                )
                try cancellationToken.checkCancellation()
                logger.info("文件上传完成，远端文件数=\(uploadedFiles.count)", module: .medical)
                complete(.upload, outcome: .success, resultSummary: "已上传 \(uploadedFiles.count) 个文件")
            } else if uploadedFiles.isEmpty == false {
                complete(.upload, outcome: .skipped, resultSummary: "沿用 \(uploadedFiles.count) 个已上传文件")
            }

            if shouldRun(.ocr, from: requestedStartStep) {
                currentStep = .ocr
                start(.ocr, variant: kindToVariant(selectedKind))
                let ocrText = try await extractUseCase.mergeOCRText(
                    files: selectedFiles,
                    cancellationToken: cancellationToken
                )
                try cancellationToken.checkCancellation()
                pipelineOCRText = ocrText
                complete(
                    .ocr,
                    outcome: .success,
                    resultSummary: "约 \(ocrText.count) 字",
                    detailKind: .ocrFullText
                )
            } else if let ocrText = pipelineOCRText {
                complete(
                    .ocr,
                    outcome: .skipped,
                    resultSummary: "沿用约 \(ocrText.count) 字",
                    detailKind: .ocrFullText
                )
            }

            guard let mergedOCRText = pipelineOCRText else {
                throw RecognitionPipelineError.missingCheckpoint("OCR")
            }

            if shouldRun(.typeRecognition, from: requestedStartStep) {
                currentStep = .typeRecognition
                start(.typeRecognition, variant: kindToVariant(selectedKind))
                let kindForRetry = overrideDocumentKindForRetry ?? selectedKind
                let resolution = try await extractUseCase.resolveType(
                    selectedKind: kindForRetry,
                    mergedOCRText: mergedOCRText,
                    cancellationToken: cancellationToken
                )
                try cancellationToken.checkCancellation()
                typeResolution = resolution
                if kindForRetry != .auto {
                    selectedKind = kindForRetry
                }
                complete(
                    .typeRecognition,
                    outcome: .success,
                    resultSummary: "\(resolution.kind.localizedUploadLabel) · \(resolution.source.localizedUploadLabel)"
                )
            } else if let resolution = typeResolution {
                complete(
                    .typeRecognition,
                    outcome: .skipped,
                    resultSummary: "\(resolution.kind.localizedUploadLabel) · 沿用"
                )
            }

            guard let resolution = typeResolution else {
                throw RecognitionPipelineError.missingCheckpoint("类型识别")
            }

            currentStep = .extract
            let extractScenario = scenario(for: resolution.kind)
            await refreshExtractModelOptions(for: extractScenario)
            let modelSummary = modelDisplayName(for: preferredExtractModelName) ?? "默认模型"
            start(.extract, variant: kindToVariant(resolution.kind))
            updateStepResultSummary(.extract, resultSummary: "\(scenarioLabel(for: extractScenario)) · \(modelSummary)")
            let output = try await extractUseCase.extractStructured(
                memberID: member.id,
                files: selectedFiles,
                mergedOCRText: mergedOCRText,
                resolution: resolution,
                preferredModelName: preferredExtractModelName,
                cancellationToken: cancellationToken
            )
            try cancellationToken.checkCancellation()
            complete(
                .extract,
                outcome: .success,
                resultSummary: "\(scenarioLabel(for: extractScenario)) · \(modelSummary)"
            )

            typedOutput = output
            stage = .result
            logger.info(
                "Typed 识别流程完成，resolvedKind=\(output.envelope.typeResolution.kind.rawValue)",
                module: .medical
            )
        } catch is CancellationError {
            if recognitionCancellationToken === cancellationToken {
                resetRecognitionState()
                stage = .picking
            }
            logger.info("Typed 识别流程已取消", module: .medical)
        } catch {
            if recognitionCancellationToken !== cancellationToken {
                logger.debug("忽略过期识别任务错误：\(error.localizedDescription)", module: .medical)
                return
            }
            failedStep = currentStep
            fail(currentStep)
            errorMessage = error.localizedDescription
            logger.error("Typed 识别流程失败 step=\(currentStep.rawValue)：\(error)", module: .medical)
        }
    }

    // MARK: - 保存 & 绑定

    /// 将当前识别结果持久化保存，成功后将已上传的附件与业务单据进行绑定
    /// - Returns: 保存和绑定流程是否全部成功
    func saveResult() async -> Bool {
        // 若正在保存中，直接忽略本次请求
        guard isSaving == false else {
            logger.debug("忽略保存请求：仍在保存中", module: .medical)
            return false
        }
        
        // 无识别结果时，提示错误并返回失败
        guard let typedOutput else {
            errorMessage = L10n.text("medical.upload.error.no_result")
            logger.warning("保存失败：无识别结果 typedOutput=nil", module: .medical)
            return false
        }
        
        // 标记开始保存
        isSaving = true
        // 触发保存状态更新
        start(.save, variant: kindToVariant(typedOutput.envelope.typeResolution.kind))
        // 代码块执行完毕后，自动重置保存状态为false
        defer { isSaving = false }

        logger.info(
            "开始保存识别结果 kind=\(typedOutput.envelope.typeResolution.kind.rawValue)",
            module: .medical
        )
        
        do {
            // 执行保存用例，获取保存回执
            let receipt = try await saveUseCase.execute(output: typedOutput)
            // 缓存保存回执
            saveReceipt = receipt
            // 标记保存流程完成（成功）
            complete(.save, outcome: .success)
            
            logger.info(
                "保存成功 recordID=\(receipt.recordID) success=\(receipt.isSuccess)",
                module: .medical
            )
            
            // 执行附件绑定：将已上传文件与单据关联
            await bindUseCase.execute(
                uploadedFiles: uploadedFiles,
                kind: typedOutput.envelope.typeResolution.kind,
                receipt: receipt
            )
            
            logger.info(
                "附件绑定完成 已上传文件数=\(uploadedFiles.count) recordID=\(receipt.recordID)",
                module: .medical
            )
            
            // 保存+绑定全部成功
            return true
        } catch {
            // 标记保存流程失败
            fail(.save)
            // 设置错误提示信息
            errorMessage = localizedSaveErrorMessage(from: error)
            logger.error("保存或绑定失败：\(error.localizedDescription)", module: .medical)
            
            // 流程异常，返回失败
            return false
        }
    }

    func updateResultMemberID(_ memberID: Int?) {
        guard let output = typedOutput else { return }
        typedOutput = MedicalDocumentTypedExtractionOutput(
            envelope: MedicalDocumentRecognitionEnvelope(
                memberID: memberID,
                sourceFiles: output.envelope.sourceFiles,
                rawOCRText: output.envelope.rawOCRText,
                typeResolution: output.envelope.typeResolution
            ),
            typedResult: output.typedResult,
            extractedJSON: output.extractedJSON,
            payloadPreview: output.payloadPreview
        )
        selectedMemberName = memberID.flatMap { id in
            memberContextStore.context.members.first(where: { $0.id == id })?.name
        }
    }

    func updateTypedResult(_ typedResult: MedicalDocumentTypedResult) {
        guard let output = typedOutput else { return }
        typedOutput = MedicalDocumentTypedExtractionOutput(
            envelope: output.envelope,
            typedResult: typedResult,
            extractedJSON: output.extractedJSON,
            payloadPreview: output.payloadPreview
        )
    }

    func prepareAndStart(files: [MedicalUploadLocalFile], kind: MedicalDocumentKind) {
        reset()
        selectedKind = kind
        setSelectedFiles(files)
        stage = .processing
        startRecognitionTask()
    }


    /// 将界面与中间态恢复为初始：清空文件、结果、进度与上传缓存，就诊人名称回读当前上下文。
    func reset() {
        recognitionCancellationToken?.cancel()
        recognitionCancellationToken = nil
        recognitionTask?.cancel()
        recognitionTask = nil
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
        clearPipelineCheckpoints()
        selectedMemberName = memberContextStore.context.selectedMember?.name
        logger.info("已重置医疗上传流程", module: .medical)
    }
    
    /// 仅重置识别状态，保留已选择的文件
    /// 用于用户选择重新识别时，不需要重新选择文件
    func resetRecognitionState() {
        typedOutput = nil
        saveReceipt = nil
        progress = nil
        needsManualModeSelection = false
        errorMessage = nil
        failedStep = nil
        // 注意：不重置 selectedFiles、previewItems 和 uploadedFiles，保留用户选择的文件
        logger.info("已重置识别状态（保留已选文件）", module: .medical)
    }

    // MARK: - Progress management
    
    /// 创建初始进度模型
    /// 根据 selectedKind 确定步骤变体和预估时间
    func createProgress() -> MedicalDocumentUploadProgress {
        let variant = kindToVariant(selectedKind)
        let estimatedSeconds = estimatedRecognitionSeconds()
        
        // 创建初始步骤（upload 为 running，其余为 idle）
        let initialSteps: [MedicalDocumentUploadStep] = [
//            .init(
//                id: MedicalDocumentUploadFlowStep.upload.rawValue,
//                title: MedicalDocumentUploadFlowStep.upload.runningPresentation(variant: variant).title,
//                subtitle: MedicalDocumentUploadFlowStep.upload.runningPresentation(variant: variant).subtitle,
//                state: .running,
//                estimatedSeconds: nil
//            ),
//            .init(
//                id: MedicalDocumentUploadFlowStep.ocr.rawValue,
//                title: MedicalDocumentUploadFlowStep.ocr.runningPresentation(variant: variant).title,
//                subtitle: MedicalDocumentUploadFlowStep.ocr.runningPresentation(variant: variant).subtitle,
//                state: .idle,
//                estimatedSeconds: nil
//            ),
//            .init(
//                id: MedicalDocumentUploadFlowStep.typeRecognition.rawValue,
//                title: MedicalDocumentUploadFlowStep.typeRecognition.runningPresentation(variant: variant).title,
//                subtitle: MedicalDocumentUploadFlowStep.typeRecognition.runningPresentation(variant: variant).subtitle,
//                state: .idle,
//                estimatedSeconds: nil
//            ),
//            .init(
//                id: MedicalDocumentUploadFlowStep.extract.rawValue,
//                title: MedicalDocumentUploadFlowStep.extract.runningPresentation(variant: variant).title,
//                subtitle: MedicalDocumentUploadFlowStep.extract.runningPresentation(variant: variant).subtitle,
//                state: .idle,
//                estimatedSeconds: nil
//            ),
//            .init(
//                id: MedicalDocumentUploadFlowStep.save.rawValue,
//                title: MedicalDocumentUploadFlowStep.save.runningPresentation(variant: variant).title,
//                subtitle: MedicalDocumentUploadFlowStep.save.runningPresentation(variant: variant).subtitle,
//                state: .idle,
//                estimatedSeconds: nil
//            )
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
        case .medicationPlan:
            return .medicationPlan
        case .medicineBox:
            return .medicineBox
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

    private func clearPipelineCheckpoints() {
        uploadedFiles = []
        pipelineOCRText = nil
        typeResolution = nil
        failedStep = nil
        overrideDocumentKindForRetry = nil
        preferredExtractModelName = nil
        extractModelOptions = []
    }

    private func shouldRun(_ step: MedicalDocumentUploadFlowStep, from startStep: MedicalDocumentUploadFlowStep) -> Bool {
        step.pipelineOrder >= startStep.pipelineOrder
    }

    private func prepareProgressForRetry(from step: MedicalDocumentUploadFlowStep) {
        guard var currentProgress = progress else { return }
        for idx in currentProgress.steps.indices {
            guard let flowStep = MedicalDocumentUploadFlowStep(rawValue: currentProgress.steps[idx].id) else { continue }
            if flowStep.pipelineOrder < step.pipelineOrder {
                currentProgress.steps[idx].state = .done
            } else {
                currentProgress.steps[idx].state = .idle
            }
        }
        currentProgress.statusLabel = L10n.text("medical.upload.status.processing")
        progress = currentProgress
    }

    private func updateStepResultSummary(
        _ step: MedicalDocumentUploadFlowStep,
        resultSummary: String?,
        detailKind: MedicalDocumentUploadStepDetailKind? = nil
    ) {
        guard var currentProgress = progress,
              let idx = currentProgress.steps.firstIndex(where: { $0.id == step.rawValue })
        else { return }
        currentProgress.steps[idx].resultSummary = resultSummary
        currentProgress.steps[idx].detailKind = detailKind
        progress = currentProgress
    }

    private func refreshExtractModelOptions(for scenario: AIScenario) async {
        guard let loadEffectiveScenarioBundles else {
            extractModelOptions = []
            return
        }
        do {
            let bundles = try await loadEffectiveScenarioBundles()
            extractModelOptions = bundles.bundle(for: scenario).models.map {
                RecognitionModelOption(name: $0.name, displayName: $0.displayName.isEmpty ? $0.name : $0.displayName)
            }
        } catch {
            extractModelOptions = []
            logger.warning("加载抽取模型列表失败：\(error.localizedDescription)", module: .medical)
        }
    }

    private func modelDisplayName(for preferredModelName: String?) -> String? {
        if let preferredModelName,
           let option = extractModelOptions.first(where: { $0.name == preferredModelName })
        {
            return option.displayName
        }
        return extractModelOptions.first?.displayName
    }

    private func scenario(for kind: MedicalDocumentKind) -> AIScenario {
        switch kind {
        case .caseDocument:
            return .medicalCaseExtraction
        case .healthExamReport:
            return .healthExamExtraction
        case .medicalReport, .auto:
            return .medicalReportExtraction
        case .prescription:
            return .prescriptionExtraction
        case .medicationPlan, .medicineBox:
            return .medicationExtraction
        }
    }

    private func scenarioLabel(for scenario: AIScenario) -> String {
        switch scenario {
        case .medicalCaseExtraction:
            return "病历抽取"
        case .healthExamExtraction:
            return "体检抽取"
        case .medicalReportExtraction:
            return "报告抽取"
        case .prescriptionExtraction:
            return "处方抽取"
        case .medicationExtraction:
            return "用药抽取"
        default:
            return "结构化抽取"
        }
    }

    // MARK: - Errors

    /// 统一保存失败提示：若有 HTTP 后端文案则拼接本地化模板，否则退回 `localizedDescription`。
    private func localizedSaveErrorMessage(from error: Error) -> String {
        let serverMessage: String?
        if let networkError = error as? SparkNetworkError,
           case .httpError(_, let backend, _) = networkError {
            let text = BackendErrorLocalizer.message(for: backend).trimmingCharacters(in: .whitespacesAndNewlines)
            serverMessage = text.isEmpty == false ? text : nil
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
        logger.debug("开始步骤: \(step.rawValue)", module: .medical)
    }
    
    func complete(
        _ step: MedicalDocumentUploadFlowStep,
        outcome: MedicalDocumentUploadFlowStep.CompletionOutcome,
        resultSummary: String? = nil,
        detailKind: MedicalDocumentUploadStepDetailKind? = nil
    ) {
        guard var currentProgress = progress else { return }
        
        let presentation = step.completionPresentation(outcome: outcome)
        
        if let idx = currentProgress.steps.firstIndex(where: { $0.id == step.rawValue }) {
            currentProgress.steps[idx].state = .done
            currentProgress.steps[idx].title = presentation.title
            currentProgress.steps[idx].subtitle = presentation.subtitle
            currentProgress.steps[idx].resultSummary = resultSummary
            currentProgress.steps[idx].detailKind = detailKind
        } else {
            // 步骤不存在，添加为已完成
            let completedStep = MedicalDocumentUploadStep(
                id: step.rawValue,
                title: presentation.title,
                subtitle: presentation.subtitle,
                state: .done,
                estimatedSeconds: nil,
                resultSummary: resultSummary,
                detailKind: detailKind
            )
            currentProgress.steps.append(completedStep)
        }
        
        progress = currentProgress
        logger.debug("完成步骤 step=\(step.rawValue)", module: .medical)
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
        currentProgress.statusLabel = L10n.text("medical.upload.status.failed")
        
        progress = currentProgress
        logger.debug("步骤失败: \(step.rawValue)", module: .medical)
    }
}

extension MedicalDocumentKind {
    var localizedUploadLabel: String {
        switch self {
        case .auto:
            return L10n.text("medical.upload.kind.auto")
        case .caseDocument:
            return L10n.text("medical.upload.kind.case")
        case .healthExamReport:
            return L10n.text("medical.upload.kind.health_exam")
        case .medicalReport:
            return L10n.text("medical.upload.kind.medical_report")
        case .prescription:
            return L10n.text("common.prescription")
        case .medicationPlan:
            return L10n.text("common.medicationPlan")
        case .medicineBox:
            return L10n.text("home.medical.list.medicine_box.title", fallback: "药品")
        }
    }
}

private extension MedicalDocumentTypeResolution.Source {
    var localizedUploadLabel: String {
        switch self {
        case .manual:
            return "手动"
        case .localRules:
            return "规则"
        case .ai:
            return "AI"
        }
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
        let previewMemberContextStore = MemberContextStore()
        let member = Member(id: 1, name: "本人", relationship: "self", isPrimary: true)
        previewMemberContextStore.update(members: [member], selectedMemberID: member.id)

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
        let previewBackendConfig = SparkBackendConfiguration(engine: previewEngine)
        let previewWorkflowAPI = SparkMedicalWorkflowAPI(configuration: previewBackendConfig)
        let previewCombinedAPI = SparkCombinedMedicalCreateAPI(configuration: previewBackendConfig)
        let saver = DefaultTypedMedicalDocumentSaver(workflowAPI: previewWorkflowAPI, combinedAPI: previewCombinedAPI)
        let dummyFileAPI = SparkFileAPI(engine: previewEngine)
        let binder = DefaultMedicalDocumentAttachmentBinder(fileAPI: dummyFileAPI)
        let dummyFileTransfer = AppContainer.preview.fileTransferService
        return MedicalDocumentUploadViewModel(
            memberContextStore: previewMemberContextStore,
            uploadFilesUseCase: UploadMedicalDocumentFilesUseCase(fileTransferService: dummyFileTransfer),
            extractUseCase: ExtractTypedMedicalDocumentUseCase(extractor: extractor),
            saveUseCase: SaveTypedMedicalDocumentUseCase(saver: saver),
            bindUseCase: BindUploadedFilesToMedicalBusinessUseCase(binder: binder)
        )
    }
}
#endif
