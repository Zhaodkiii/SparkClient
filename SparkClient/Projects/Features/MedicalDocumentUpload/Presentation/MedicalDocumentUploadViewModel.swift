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
    // MARK: - 内部类型定义

    /// 上传页面整体所处的大阶段
    /// 用于控制页面整体切换：选择文件 → 处理中 → 展示结果
    enum Stage: Equatable {
        case picking      // 挑选文件阶段（初始状态）
        case processing   // 流水线处理阶段（上传/OCR/识别/提取）
        case result       // 处理完成，展示识别结果阶段
    }

    /// AI 识别模型选项
    /// 用于信息提取步骤，支持切换不同识别模型
    struct RecognitionModelOption: Identifiable, Equatable {
        let name: String        // 模型唯一标识名称
        let displayName: String // 页面显示名称

        // 唯一标识
        var id: String { name }
    }

    // MARK: - 可观测状态（页面驱动数据源）

    /// 当前页面所处的整体大阶段
    @Published var stage: Stage = .picking

    /// 上传页面弹层展示开关，由 ViewModel 统一驱动入口展示与保存后的关闭。
    @Published var isUploadPresented = false

    /// 当前选中的家庭成员名称
    @Published private(set) var selectedMemberName: String?

    /// 本地选择待上传的文件列表
    @Published private(set) var selectedFiles: [MedicalUploadLocalFile] = []

    /// 上传流程进度模型（包含当前步骤、状态、进度值）
    @Published var progress: MedicalDocumentUploadProgress?

    /// 是否需要手动选择文档类型（自动识别失败时为 true）
    @Published var needsManualModeSelection: Bool = false

    /// 文档结构化提取结果（类型+字段数据）
    @Published private(set) var typedOutput: MedicalDocumentTypedExtractionOutput?

    /// 是否正在执行保存操作
    @Published private(set) var isSaving = false

    /// 错误提示信息
    @Published var errorMessage: String?

    /// 保存成功后的回执信息
    @Published var saveReceipt: MedicalDocumentSaveReceipt?

    /// 保存成功事件版本号，供首页等宿主页面监听后刷新最新数据。
    @Published private(set) var saveSucceededRevision = 0

    /// 用户手动指定的文档类型
    /// 为 .auto 时表示由服务端/AI 自动推断类型
    @Published var selectedKind: MedicalDocumentKind = .auto

    /// 流水线处理得到的 OCR 纯文本内容
    @Published private(set) var pipelineOCRText: String?

    /// 文档类型识别结果
    @Published private(set) var typeResolution: MedicalDocumentTypeResolution?

    /// 执行失败的步骤（用于失败重试）
    @Published private(set) var failedStep: MedicalDocumentUploadFlowStep.Kind?

    /// 可切换的信息提取模型列表
    @Published private(set) var extractModelOptions: [RecognitionModelOption] = []

    /// 重试时手动覆盖的文档类型（类型识别失败时使用）
    @Published var overrideDocumentKindForRetry: MedicalDocumentKind?

    /// 用户偏好选择的信息提取模型名称
    @Published var preferredExtractModelName: String?

    private var extractModelOptionsRefreshTask: Task<Void, Never>?

    // MARK: - 依赖注入（业务用例/数据仓库）

    /// 家庭成员上下文仓库
    private let memberContextStore: MemberContextStore

    /// 上传医疗文档文件用例
    private let uploadFilesUseCase: UploadMedicalDocumentFilesUseCase

    /// 医疗文档结构化信息提取用例
    private let extractUseCase: ExtractTypedMedicalDocumentUseCase

    /// 保存结构化医疗文档用例
    private let saveUseCase: SaveTypedMedicalDocumentUseCase

    /// 绑定已上传文件到业务单据用例
    private let bindUseCase: BindUploadedFilesToMedicalBusinessUseCase

    /// AI 配置中心（场景 bundle、模型列表等）
    private let aiConfigCenter: AIConfigCenter

    /// 公共通知客户端，用于保存成功后的统一提示。
    private let notificationClient: (any NotificationClient)?

    /// 本地表单编辑复用首页表单组件所需的工作流 API。
    private let workflowAPIForLocalForms: SparkMedicalWorkflowAPI?
    
    /// 日志记录器
    private let logger: Logger

    /// 当前正在执行的 上传/OCR/AI识别 任务
    /// 取消时会中断任务并触发取消令牌
    private var recognitionTask: Task<Void, Never>?

    /// AI 运行时取消令牌（用于中断模型推理）
    private var recognitionCancellationToken: AIRuntimeCancellationToken?

    /// 进度模拟/轮询定时器（可选）
    private var progressTimerCancellable: AnyCancellable?

    /// 各步骤开始时刻，用于在步骤完成时写入实际墙钟耗时（毫秒）
    private var stepStartedAt: [MedicalDocumentUploadFlowStep.Kind: Date] = [:]

    // MARK: - Initialization

    init(
        memberContextStore: MemberContextStore,
        uploadFilesUseCase: UploadMedicalDocumentFilesUseCase,
        extractUseCase: ExtractTypedMedicalDocumentUseCase,
        saveUseCase: SaveTypedMedicalDocumentUseCase,
        bindUseCase: BindUploadedFilesToMedicalBusinessUseCase,
        aiConfigCenter: AIConfigCenter,
        workflowAPIForLocalForms: SparkMedicalWorkflowAPI? = nil,
        notificationClient: (any NotificationClient)? = nil,
        logger: Logger = ConsoleLogger()
    ) {
        self.memberContextStore = memberContextStore
        self.uploadFilesUseCase = uploadFilesUseCase
        self.extractUseCase = extractUseCase
        self.saveUseCase = saveUseCase
        self.bindUseCase = bindUseCase
        self.aiConfigCenter = aiConfigCenter
        self.workflowAPIForLocalForms = workflowAPIForLocalForms
        self.notificationClient = notificationClient
        self.logger = logger
        self.selectedMemberName = memberContextStore.context.selectedMember?.name
    }

    // MARK: - Derived state

    /// 是否允许开始识别：已选文件且成员上下文中有当前选中成员。
    var canStartRecognition: Bool {
        selectedFiles.isEmpty == false && memberContextStore.context.selectedMember != nil
    }

    var memberContextStoreForLocalForms: MemberContextStore {
        memberContextStore
    }

    var workflowAPIForCaseLocalForms: SparkMedicalWorkflowAPI? {
        workflowAPIForLocalForms
    }

    var notificationClientForLocalForms: (any NotificationClient)? {
        notificationClient
    }

    var fileTransferServiceForResultDetails: FileTransferService {
        uploadFilesUseCase.fileTransferService
    }

    // MARK: - File selection

    /// 替换当前待识别列表；会清除之前的错误提示。
    func setSelectedFiles(_ files: [MedicalUploadLocalFile]) {
        selectedFiles = files
        clearPipelineCheckpoints()
        errorMessage = nil
        logger.info("已更新待识别文件，数量=\(files.count)", module: .medical)
    }

    /// 按本地文件 ID 移除一项。
    func removeFile(id: UUID) {
        selectedFiles.removeAll { $0.id == id }
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

    /// 执行上传 + Typed 抽取；成功则进入 `.result`，失败时将当前步骤标记为失败并写入 `errorMessage`。
    /// 开始【医疗文档上传 + OCR + AI 抽取】全流程
    /// 作用：触发整个上传识别流水线（上传文件 → OCR → 类型判定 → AI 抽取 → 展示结果）
    func startRecognition() async {
        await runRecognitionPipeline(startingAt: .upload, resetForFreshRun: true)
    }

    func resumeRecognition() async {
        await runRecognitionPipeline(startingAt: failedStep ?? .upload, resetForFreshRun: false)
    }

    /// 医疗单据识别流水线总执行方法
    /// - Parameters:
    ///   - requestedStartStep: 指定从哪个步骤开始执行流水线
    ///   - resetForFreshRun: 是否重置为全新运行（true=清空所有缓存从头开始，false=断点重试）
    private func runRecognitionPipeline(startingAt requestedStartStep: MedicalDocumentUploadFlowStep.Kind, resetForFreshRun: Bool) async {
        // MARK: 1. 前置校验：必须选择就诊成员（患者）
        // 从全局状态中获取当前选中的患者，没有则直接报错返回
        guard let member = memberContextStore.context.selectedMember else {
            // 给 UI 展示国际化错误文案
            errorMessage = L10n.text("medical.upload.error.no_member")
            // 打印警告日志
            logger.warning("开始识别失败：未选择就诊成员", module: .medical)
            return
        }

        // 保存患者姓名用于 UI 展示
        selectedMemberName = member.name
        // 清空历史错误、识别结果等数据，避免脏数据干扰
        errorMessage = nil
        typedOutput = nil
        saveReceipt = nil
        // 将页面状态切换为处理中
        stage = .processing

        // MARK: 2. 初始化进度条模型（用于 UI 展示进度）
        // 如果是全新运行 或 进度对象为空，则清空检查点并创建新进度
        if resetForFreshRun || progress == nil {
            clearPipelineCheckpoints()
            progress = createProgress()
        } else {
            // 否则从指定断点步骤准备重试进度
            prepareProgressForRetry(from: requestedStartStep)
        }
        // 启动进度条计时动画
        startProgressTimer()
        // 关闭手动选择模式标记
        needsManualModeSelection = false
        // 清空失败步骤记录
        failedStep = nil
        
        // 创建任务取消令牌，用于中断识别流程
        let cancellationToken = AIRuntimeCancellationToken()
        recognitionCancellationToken = cancellationToken
        
        // 函数退出时统一清理令牌和任务，避免内存泄漏
        defer {
            if recognitionCancellationToken === cancellationToken {
                recognitionCancellationToken = nil
                recognitionTask = nil
            }
        }

        // MARK: 3. 打印流程启动日志，记录关键信息
        logger.info(
            "开始识别流程 memberID=\(member.id) 文件数=\(selectedFiles.count) selectedKind=\(selectedKind.rawValue)",
            module: .medical
        )

        // MARK: 4. 执行核心识别流程，统一捕获所有异常
        // 当前执行到的步骤
        var currentStep: MedicalDocumentUploadFlowStep.Kind = requestedStartStep
        do {
            // ====================== 步骤1：文件上传 ======================
            if shouldRun(.upload, from: requestedStartStep) {
                currentStep = .upload
                // 标记步骤开始
                start(.upload)
                // 执行文件上传（断点续跑时沿用已有 remoteFile，全新运行则全部重新上传）
                let uploadedFiles = try await uploadFilesUseCase.execute(
                    memberID: member.id,
                    files: selectedFiles,
                    reuploadAll: false
                )
                selectedFiles = uploadedFiles
                // 检查是否触发了任务取消
                try cancellationToken.checkCancellation()
                logger.info("文件上传完成，远端文件数=\(uploadedFiles.count)", module: .medical)
                // 标记步骤完成
                complete(.upload, outcome: .success, resultSummary: "已上传 \(uploadedFiles.count) 个文件")
            } else if selectedFiles.contains(where: { $0.remoteFile != nil }) {
                // 已有上传文件，直接沿用
                let uploadedCount = selectedFiles.filter { $0.remoteFile != nil }.count
                complete(.upload, outcome: .skipped, resultSummary: "沿用 \(uploadedCount) 个已上传文件")
            }

            // ====================== 步骤2：OCR 文字提取 ======================
            if shouldRun(.ocr, from: requestedStartStep) {
                currentStep = .ocr
                start(.ocr)
                // 执行 OCR 识别，写回每个本地文件后再合并文本（断点续跑时沿用已有 ocrText）
                let ocrFiles = try await extractUseCase.recognizeOCRFiles(
                    files: selectedFiles,
                    reRecognizeAll: false,
                    cancellationToken: cancellationToken
                )
                selectedFiles = ocrFiles
                let ocrText = try await extractUseCase.mergeOCRText(
                    files: ocrFiles,
                    reRecognizeAll: false,
                    cancellationToken: cancellationToken
                )
                try cancellationToken.checkCancellation()
                // 缓存 OCR 结果
                pipelineOCRText = ocrText
                complete(
                    .ocr,
                    outcome: .success,
                    resultSummary: "约 \(ocrText.count) 字"
                )
            } else if let ocrText = pipelineOCRText {
                // 已有 OCR 结果，直接沿用
                complete(
                    .ocr,
                    outcome: .skipped,
                    resultSummary: "沿用约 \(ocrText.count) 字"
                )
            }

            // 校验 OCR 结果不能为空
            guard let mergedOCRText = pipelineOCRText else {
                throw RecognitionPipelineError.missingCheckpoint("OCR")
            }

            // ====================== 步骤3：单据类型识别 ======================
            if shouldRun(.typeRecognition, from: requestedStartStep) {
                currentStep = .typeRecognition
                start(.typeRecognition)
                // 获取识别类型（重试时使用指定类型，否则使用用户选择类型）
                let kindForRetry = overrideDocumentKindForRetry ?? selectedKind
                // 执行 AI 类型识别
                let resolution = try await extractUseCase.resolveType(
                    selectedKind: kindForRetry,
                    mergedOCRText: mergedOCRText,
                    cancellationToken: cancellationToken
                )
                try cancellationToken.checkCancellation()
                // 缓存识别结果
                typeResolution = resolution
                // 如果不是自动识别，则更新为用户指定的类型
                if kindForRetry != .auto {
                    selectedKind = kindForRetry
                }
                overrideDocumentKindForRetry = resolution.kind
                complete(
                    .typeRecognition,
                    outcome: .success,
                    resultSummary: "\(resolution.kind.localizedUploadLabel) · \(resolution.source.localizedUploadLabel)"
                )
            } else if let resolution = typeResolution {
                // 已有类型识别结果，直接沿用
                complete(
                    .typeRecognition,
                    outcome: .skipped,
                    resultSummary: "\(resolution.kind.localizedUploadLabel) · 沿用"
                )
            }

            // 校验类型识别结果不能为空
            guard let resolution = typeResolution else {
                throw RecognitionPipelineError.missingCheckpoint("类型识别")
            }

            // ====================== 步骤4：结构化信息提取 ======================
            currentStep = .extract
            // 根据单据类型获取对应的提取场景
            let extractScenario = scenario(for: resolution.kind)
            // 刷新当前场景可用的模型选项
            await refreshExtractModelOptions(for: extractScenario)
            let modelSummary = modelDisplayName(for: preferredExtractModelName) ?? "默认模型"
            
            preferredExtractModelName = modelSummary

            start(.extract)
            updateStepResultSummary(.extract, resultSummary: "\(scenarioLabel(for: extractScenario)) · \(modelSummary)")
            
            // 执行核心结构化数据提取
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

            // ====================== 步骤5：业务附件匹配 ======================
            currentStep = .attachmentBinding
            start(.attachmentBinding)
            let matchedOutput = MedicalDocumentAttachmentBusinessMatcher.matchAndUpdate(
                files: selectedFiles,
                output: output
            )
            complete(
                .attachmentBinding,
                outcome: .success,
                resultSummary: "已匹配 \(selectedFiles.compactMap { $0.remoteFile?.id }.count) 个附件"
            )

            // 保存最终识别结果
            typedOutput = matchedOutput
            // 停止进度条动画
            stopProgressTimer()
            // 切换到结果展示状态
            stage = .result
            logger.info(
                "Typed 识别流程完成，resolvedKind=\(matchedOutput.envelope.typeResolution.kind.rawValue)",
                module: .medical
            )

        } catch is CancellationError {
            // 处理用户主动取消任务的情况
            if recognitionCancellationToken === cancellationToken {
                // 重置识别状态，返回选择页面
                resetRecognitionState()
                stage = .picking
            }
            logger.info("Typed 识别流程已取消", module: .medical)
            
        } catch {
            // 处理其他所有异常错误
            // 忽略已过期的旧任务错误
            if recognitionCancellationToken !== cancellationToken {
                logger.debug("忽略过期识别任务错误：\(error.localizedDescription)", module: .medical)
                return
            }
            // 记录失败步骤并更新 UI 错误信息
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
        start(.save)
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

            reset()
            dismissUploadPage()
            notificationClient?.success(
                L10n.text("medical.upload.saved.message"),
                title: L10n.text("medical.upload.saved.title"),
                source: "medical.upload.save"
            )
            saveSucceededRevision += 1

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

    /// 更新医疗文档结果中的会员ID
    /// - Parameter memberID: 待设置的会员ID（可选值）
    func updateResultMemberID(_ memberID: Int?) {
        // 安全解包当前输出对象，为空则直接返回
        guard let output = typedOutput else { return }
        
        // 重新构建输出对象：仅更新信封中的 memberID，其他数据保持不变
        typedOutput = MedicalDocumentTypedExtractionOutput(
            // 重建信封信息：仅更新会员ID，保留源文件、OCR文本、类型解析结果
            envelope: MedicalDocumentRecognitionEnvelope(
                memberID: memberID,                // 更新为新的会员ID
                sourceFiles: output.envelope.sourceFiles,  // 保留原文件源
                rawOCRText: output.envelope.rawOCRText,    // 保留原OCR原始文本
                typeResolution: output.envelope.typeResolution // 保留原类型解析结果
            ),
            typedResult: output.typedResult,      // 保留原识别结果
            extractedJSON: output.extractedJSON,  // 保留原提取的JSON数据
            payloadPreview: output.payloadPreview // 保留原载荷预览
        )
        
        // 根据会员ID查询并设置选中的会员名称（无ID则清空）
        selectedMemberName = memberID.flatMap { id in
            // 从会员上下文存储中，根据ID匹配对应的会员并获取名称
            memberContextStore.context.members.first(where: { $0.id == id })?.name
        }
    }

    /// 更新已识别的文档结果
    /// - Parameter typedResult: 新的医疗文档识别结果
    func updateTypedResult(_ typedResult: MedicalDocumentTypedResult) {
        // 安全解包当前输出对象，为空则直接返回
        guard let output = typedOutput else { return }
        
        // 使用原有输出数据 + 新识别结果，重新构建并赋值输出对象
        typedOutput = MedicalDocumentTypedExtractionOutput(
            envelope: output.envelope,            // 保留原信封信息
            typedResult: typedResult,             // 替换为新的识别结果
            extractedJSON: output.extractedJSON,  // 保留原提取的JSON数据
            payloadPreview: output.payloadPreview // 保留原载荷预览信息
        )
    }

    func prepareAndStart(files: [MedicalUploadLocalFile], kind: MedicalDocumentKind) {
        reset()
        selectedKind = kind
        setSelectedFiles(files)
        stage = .processing
        presentUploadPage()
        startRecognitionTask()
    }

    func presentUploadPage() {
        isUploadPresented = true
    }

    func dismissUploadPage() {
        isUploadPresented = false
    }


    /// 将界面与中间态恢复为初始：清空文件、结果、进度与上传缓存，就诊人名称回读当前上下文。
    /// - Parameter keepAttachments: 是否保留附件，默认 false（不保留，清空）
    func reset(keepAttachments: Bool = false) {
        recognitionCancellationToken?.cancel()
        recognitionCancellationToken = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        stage = .picking
        // 只有不保留附件时，才清空文件。
        if !keepAttachments {
            selectedFiles = []
        }
        progress = nil
        stopProgressTimer(resetElapsedSeconds: true)
        needsManualModeSelection = false
        typedOutput = nil
        saveReceipt = nil
        errorMessage = nil
        selectedKind = .auto
        clearPipelineCheckpoints()
        selectedMemberName = memberContextStore.context.selectedMember?.name
        logger.info("已重置医疗上传流程，是否保留附件：\(keepAttachments)", module: .medical)
    }

    /// 仅重置识别状态，保留已选择的文件
    /// 用于用户选择重新识别时，不需要重新选择文件
    func resetRecognitionState() {
        typedOutput = nil
        saveReceipt = nil
        progress = nil
        stopProgressTimer(resetElapsedSeconds: true)
        needsManualModeSelection = false
        errorMessage = nil
        failedStep = nil
        stepStartedAt = [:]
        // 注意：不重置 selectedFiles，保留用户选择的文件及其中的上传/OCR结果
        logger.info("已重置识别状态（保留已选文件）", module: .medical)
    }

    // MARK: - Progress management

    /// 创建初始进度模型
    /// 根据 selectedKind 确定步骤变体和预估时间
    func createProgress() -> MedicalDocumentUploadProgress {
        let estimatedSeconds = estimatedRecognitionSeconds()
//        let initialSteps: [MedicalDocumentUploadStep] = []
        let initialSteps = MedicalDocumentUploadFlowStep.Kind.pipelineSteps.map {
            MedicalDocumentUploadStep(kind: $0)
        }

        return MedicalDocumentUploadProgress(
            title: L10n.text("medical.upload.processing.title"),
            statusLabel: L10n.text("medical.upload.status.processing"),
            elapsedSeconds: 0,
            estimatedSeconds: estimatedSeconds,
            steps: initialSteps
        )
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
        pipelineOCRText = nil
        typeResolution = nil
        failedStep = nil
        overrideDocumentKindForRetry = nil
        preferredExtractModelName = nil
        extractModelOptions = []
        stepStartedAt = [:]
    }

    private func shouldRun(_ step: MedicalDocumentUploadFlowStep.Kind, from startStep: MedicalDocumentUploadFlowStep.Kind) -> Bool {
        step.pipelineOrder >= startStep.pipelineOrder
    }

    private func prepareProgressForRetry(from step: MedicalDocumentUploadFlowStep.Kind) {
        guard var currentProgress = progress else { return }
        ensurePipelineSteps(in: &currentProgress)
        for idx in currentProgress.steps.indices {
            let kind = currentProgress.steps[idx].flowStep.kind
            if kind.pipelineOrder < step.pipelineOrder {
                if currentProgress.steps[idx].flowStep.outcome.isTerminalSuccess == false {
                    currentProgress.steps[idx].flowStep.outcome = .skipped
                }
            } else {
                currentProgress.steps[idx].flowStep.outcome = .pending
                currentProgress.steps[idx].resultSummary = nil
                if kind.pipelineOrder > step.pipelineOrder {
                    currentProgress.steps[idx].elapsedMilliseconds = 0
                    stepStartedAt.removeValue(forKey: kind)
                }
            }
        }
        stepStartedAt.removeValue(forKey: step)
        currentProgress.statusLabel = L10n.text("medical.upload.status.processing")
        progress = currentProgress
    }

    private func recordStepStart(_ step: MedicalDocumentUploadFlowStep.Kind) {
        stepStartedAt[step] = Date()
    }

    private func finalizeStepElapsed(
        _ step: MedicalDocumentUploadFlowStep.Kind,
        in currentProgress: inout MedicalDocumentUploadProgress
    ) {
        guard let startedAt = stepStartedAt.removeValue(forKey: step),
              let idx = currentProgress.steps.firstIndex(where: { $0.flowStep.kind == step })
        else { return }
        let measured = Int(ceil(Date().timeIntervalSince(startedAt) * 1000))
        currentProgress.steps[idx].elapsedMilliseconds = max(currentProgress.steps[idx].elapsedMilliseconds, measured)
    }

    private func updateStepResultSummary(
        _ step: MedicalDocumentUploadFlowStep.Kind,
        resultSummary: String?
    ) {
        guard var currentProgress = progress,
              let idx = currentProgress.steps.firstIndex(where: { $0.flowStep.kind == step })
        else { return }
        currentProgress.steps[idx].resultSummary = resultSummary
        progress = currentProgress
    }

    private func startProgressTimer() {
        guard progressTimerCancellable == nil else { return }
        progressTimerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.stage == .processing, var currentProgress = self.progress else { return }
                currentProgress.elapsedSeconds += 1
                if let runningStep = currentProgress.runningStep,
                   let idx = currentProgress.steps.firstIndex(where: { $0.flowStep.kind == runningStep })
                {
                    currentProgress.steps[idx].elapsedMilliseconds += 1000
                }
                self.progress = currentProgress
            }
    }

    private func stopProgressTimer(resetElapsedSeconds: Bool = false) {
        progressTimerCancellable?.cancel()
        progressTimerCancellable = nil
        if resetElapsedSeconds {
            progress?.elapsedSeconds = 0
            if var currentProgress = progress {
                for idx in currentProgress.steps.indices {
                    currentProgress.steps[idx].elapsedMilliseconds = 0
                }
                progress = currentProgress
            }
            stepStartedAt = [:]
        }
    }

    func selectOverrideDocumentKindForRetry(_ kind: MedicalDocumentKind) {
        overrideDocumentKindForRetry = kind
        preferredExtractModelName = nil
        extractModelOptions = []

        extractModelOptionsRefreshTask?.cancel()
        let scenario = scenario(for: kind)
        extractModelOptionsRefreshTask = Task { [weak self] in
            await self?.refreshExtractModelOptions(for: scenario)
        }
    }

    private func refreshExtractModelOptions(for scenario: AIScenario) async {
        do {
            let bundles = try await aiConfigCenter.effectiveScenarioBundles()
            guard !Task.isCancelled else { return }
            extractModelOptions = bundles.bundle(for: scenario).models.map {
                RecognitionModelOption(name: $0.name, displayName: $0.displayName.isEmpty ? $0.name : $0.displayName)
            }
        } catch is CancellationError {
            return
        } catch {
            extractModelOptions = []
            logger.warning("加载抽取模型列表失败：\(error.localizedDescription)", module: .medical)
        }
    }

    /// 根据模型名称获取对应的展示名称（用于UI显示）
    /// - Parameter preferredModelName: 用户偏好选择/指定的模型名称
    /// - Returns: 模型展示名称（找不到则返回第一个模型的展示名）
    private func modelDisplayName(for preferredModelName: String?) -> String? {
        // 如果传入了指定模型名称，且在可选模型列表中能找到匹配项，则返回该模型的展示名称
        if let preferredModelName,
           let option = extractModelOptions.first(where: { $0.name == preferredModelName })
        {
            return option.displayName
        }
        
        // 没有指定模型 或 模型不存在 → 返回可选模型列表中第一个的展示名
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

// MARK: - 医疗文档上传步骤上报 扩展
/// 让上传ViewModel遵循步骤上报协议，统一处理上传流程的步骤状态更新
extension MedicalDocumentUploadViewModel: MedicalDocumentUploadStepReporter {

    /// 开始执行某个上传步骤
    /// - Parameter step: 当前要开始执行的步骤类型
    func start(_ step: MedicalDocumentUploadFlowStep.Kind) {
        // 取出当前进度，为空则直接返回
        guard var currentProgress = progress else { return }

        // 确保进度中包含所有标准流程步骤（补全缺失的步骤）
        ensurePipelineSteps(in: &currentProgress)
        
        // 遍历所有步骤，更新状态
        for idx in currentProgress.steps.indices {
            let kind = currentProgress.steps[idx].flowStep.kind
            
            if kind == step {
                // 当前要执行的步骤 → 标记为运行中
                currentProgress.steps[idx].flowStep.outcome = .running
            }
            else if kind.pipelineOrder < step.pipelineOrder,
                    // 前置步骤未成功、未失败 → 自动标记为成功
                    currentProgress.steps[idx].flowStep.outcome.isTerminalSuccess == false,
                    currentProgress.steps[idx].flowStep.outcome.isFailed == false {
                currentProgress.steps[idx].flowStep.outcome = .success
            }
            else if currentProgress.steps[idx].flowStep.outcome.isRunning {
                // 其他正在运行的步骤 → 重置为等待中，并清空结果
                currentProgress.steps[idx].flowStep.outcome = .pending
                currentProgress.steps[idx].resultSummary = nil
            }
        }

        // 记录步骤开始时间
        recordStepStart(step)
        // 更新界面提示文字：处理中
        currentProgress.statusLabel = L10n.text("medical.upload.status.processing")
        // 保存最新进度
        progress = currentProgress
        // 日志输出
        logger.debug("开始步骤: \(step.rawValue)", module: .medical)
    }

    /// 完成某个上传步骤（成功/跳过）
    /// - Parameters:
    ///   - step: 完成的步骤
    ///   - outcome: 完成结果（成功/跳过）
    ///   - resultSummary: 结果描述文本（可选）
    func complete(
        _ step: MedicalDocumentUploadFlowStep.Kind,
        outcome: MedicalDocumentUploadFlowStep.CompletionOutcome,
        resultSummary: String? = nil
    ) {
        guard var currentProgress = progress else { return }

        // 确保步骤完整
        ensurePipelineSteps(in: &currentProgress)
        // 计算步骤耗时
        finalizeStepElapsed(step, in: &currentProgress)

        // 找到对应步骤并更新结果和描述
        if let idx = currentProgress.steps.firstIndex(where: { $0.flowStep.kind == step }) {
            currentProgress.steps[idx].flowStep.outcome = outcome
            currentProgress.steps[idx].resultSummary = resultSummary
        }

        // 保存进度
        progress = currentProgress
        logger.debug("完成步骤 step=\(step.rawValue)", module: .medical)
    }

    /// 某个上传步骤执行失败
    /// - Parameter step: 失败的步骤
    func fail(_ step: MedicalDocumentUploadFlowStep.Kind) {
        guard var currentProgress = progress else { return }

        ensurePipelineSteps(in: &currentProgress)
        finalizeStepElapsed(step, in: &currentProgress)
        
        // 找到步骤并标记为失败
        if let idx = currentProgress.steps.firstIndex(where: { $0.flowStep.kind == step }) {
            currentProgress.steps[idx].flowStep.outcome = .failed
        }
        
        // 更新界面提示：上传失败
        currentProgress.statusLabel = L10n.text("medical.upload.status.failed")

        progress = currentProgress
        // 停止进度计时
        stopProgressTimer()
        logger.debug("步骤失败: \(step.rawValue)", module: .medical)
    }

    // MARK: - 私有工具方法
    
    /// 确保进度对象中包含所有标准上传流程步骤
    /// 不存在的步骤会自动创建，保持步骤顺序固定
    /// - Parameter currentProgress: 要校验/补全的进度对象
    private func ensurePipelineSteps(in currentProgress: inout MedicalDocumentUploadProgress) {
        // 把现有步骤转成字典，方便按类型查找
        let existing = Dictionary(uniqueKeysWithValues: currentProgress.steps.map { ($0.flowStep.kind, $0) })
        // 用标准步骤列表重建步骤数组：已存在的复用，不存在的新建
        currentProgress.steps = MedicalDocumentUploadFlowStep.Kind.pipelineSteps.map { kind in
            existing[kind] ?? MedicalDocumentUploadStep(kind: kind)
        }
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
            bindUseCase: BindUploadedFilesToMedicalBusinessUseCase(binder: binder),
            aiConfigCenter: AppContainer.preview.aiConfigCenter,
            workflowAPIForLocalForms: previewWorkflowAPI
        )
    }

    static func preview(output: MedicalDocumentTypedExtractionOutput) -> MedicalDocumentUploadViewModel {
        let viewModel = preview()
        viewModel.stage = .result
        viewModel.typedOutput = output
        return viewModel
    }
}
#endif
