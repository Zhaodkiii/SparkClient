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

    /// 缺模型场景；非 nil 时由 Host 弹出配置引导，不写入 `errorMessage`。
    @Published var missingModelScenarioForAlert: AIScenario?

    /// 保存成功后的回执信息
    @Published var saveReceipt: MedicalDocumentSaveReceipt?

    /// 保存成功事件版本号，供首页等宿主页面监听后刷新最新数据。
    @Published private(set) var saveSucceededRevision = 0

    /// 提交前本地预校验错误（阻断保存并驱动结果页高亮）。
    @Published private(set) var preSubmitValidationIssues: [MedicalPreSubmitValidationIssue] = []

    /// 用户手动指定的文档类型
    /// 为 .auto 时表示由服务端/AI 自动推断类型
    @Published var selectedKind: MedicalDocumentKind = .auto

    /// 流水线处理得到的 OCR 纯文本内容
    @Published private(set) var pipelineOCRText: String?

    /// 文档类型识别结果
    @Published private(set) var typeResolution: MedicalDocumentTypeResolution?

    /// 执行失败的步骤（用于失败重试）
    @Published private(set) var failedStep: MedicalDocumentUploadFlowStep.Kind?

    /// 最近一次结构化抽取失败反馈（继续识别时追加到 Prompt）
    @Published private(set) var lastExtractionRetryFeedback: MedicalExtractionRetryFeedback?

    /// 是否正在携带失败反馈重试结构化抽取
    @Published private(set) var isRetryingExtraction = false

    /// 当前自动重试次数（仅解码失败且开启自动重试时有意义）
    @Published private(set) var autoRetryAttempt = 0

    /// 配置的最大自动重试次数
    @Published private(set) var maxAutoRetryAttempts = 0

    /// 是否正在执行解码失败自动重试
    @Published private(set) var isAutoRetryingExtraction = false

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

    /// 远程推送适配器，用于开始识别时请求系统通知权限。
    private let pushAdapter: PushAdapter?

    /// 本地表单编辑复用首页表单组件所需的工作流 API。
    private let workflowAPIForLocalForms: SparkMedicalWorkflowAPI?
    
    /// 日志记录器
    private let logger: Logger

    /// 医疗抽取自动重试本地配置
    private let extractionRetrySettingsStore: MedicalExtractionRetrySettingsStore

    /// 抽取输入源决策（OCR 文本 vs 图片多模态）
    private let extractionInputSourceResolver: MedicalExtractionInputSourceResolver

    /// 保存前本地字段预校验
    private let preSubmitValidator: any MedicalPreSubmitValidating

    /// 当前正在执行的 上传/OCR/AI识别 任务
    /// 取消时会中断任务并触发取消令牌
    private var recognitionTask: Task<Void, Never>?

    /// AI 运行时取消令牌（用于中断模型推理）
    private var recognitionCancellationToken: AIRuntimeCancellationToken?

    /// 进度模拟/轮询定时器（可选）
    private var progressTimerCancellable: AnyCancellable?

    /// 各步骤开始时刻，用于在步骤完成时写入实际墙钟耗时（毫秒）
    private var stepStartedAt: [MedicalDocumentUploadFlowStep.Kind: Date] = [:]

    /// 当前流水线绑定的成员 ID，用于检测切换成员后清空抽取重试反馈
    private var pipelineMemberID: Int?

    /// 本次上传识别显式绑定的成员。成员引导流程进入识别时不一定已经切换全局选中成员，
    /// 需要用该值保证识别 envelope 与结果页默认成员都指向引导中的成员。
    private var pendingMemberOverride: Member?

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
        pushAdapter: PushAdapter? = nil,
        extractionRetrySettingsStore: MedicalExtractionRetrySettingsStore = MedicalExtractionRetrySettingsStore(),
        preSubmitValidator: any MedicalPreSubmitValidating = MedicalPreSubmitValidator(),
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
        self.pushAdapter = pushAdapter
        self.extractionRetrySettingsStore = extractionRetrySettingsStore
        self.preSubmitValidator = preSubmitValidator
        self.logger = logger
        self.extractionInputSourceResolver = MedicalExtractionInputSourceResolver(logger: logger)
        self.selectedMemberName = memberContextStore.context.selectedMember?.name
    }

    // MARK: - Derived state

    /// 是否允许开始识别：已选文件且成员上下文中有当前选中成员。
    var canStartRecognition: Bool {
        selectedFiles.isEmpty == false && recognitionMember != nil
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
        missingModelScenarioForAlert = nil
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

        pushAdapter?.requestAuthorizationIfNotDetermined()

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
        guard let member = recognitionMember else {
            // 给 UI 展示国际化错误文案
            errorMessage = L10n.text("medical.upload.error.no_member")
            // 打印警告日志
            logger.warning("开始识别失败：未选择就诊成员", module: .medical)
            return
        }

        // 保存患者姓名用于 UI 展示
        selectedMemberName = member.name
        if let pipelineMemberID, pipelineMemberID != member.id {
            clearExtractionRetryFeedback()
        }
        pipelineMemberID = member.id
        // 清空历史错误、识别结果等数据，避免脏数据干扰
        errorMessage = nil
        missingModelScenarioForAlert = nil
        typedOutput = nil
        saveReceipt = nil
        // 将页面状态切换为处理中
        stage = .processing

        // MARK: 2. 初始化进度条模型（用于 UI 展示进度）
        // 如果是全新运行 或 进度对象为空，则清空检查点并创建新进度
        if resetForFreshRun || progress == nil {
            clearPipelineCheckpoints()
            isRetryingExtraction = false
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

        // MARK: 4. 执行完整医疗单据识别流水线主流程，统一捕获全流程所有异常
        // 记录当前正在执行的流水线步骤，用于失败时定位报错环节
        var currentStep: MedicalDocumentUploadFlowStep.Kind = requestedStartStep
        do {
            // ====================== 步骤1：文件云端上传 ======================
            // 判断当前流程是否需要执行上传环节（断点续跑可跳过）
            if shouldRun(.upload, from: requestedStartStep) {
                currentStep = .upload
                // 标记上传步骤开始，更新界面进度状态
                start(.upload)
                // 执行文件上传逻辑；断点续跑复用已有远端文件，全新流程全部重传
                let uploadedFiles = try await uploadFilesUseCase.execute(
                    memberID: member.id,
                    files: selectedFiles,
                    reuploadAll: false
                )
                // 更新本地文件列表，回填远端文件信息
                selectedFiles = uploadedFiles
                // 校验任务是否被手动取消，取消则抛出终止异常
                try cancellationToken.checkCancellation()
                logger.info("文件上传完成，远端文件数=\(uploadedFiles.count)", module: .medical)
                // 标记上传步骤执行成功，写入步骤摘要用于UI展示
                complete(.upload, outcome: .success, resultSummary: "已上传 \(uploadedFiles.count) 个文件")
            } else if selectedFiles.contains(where: { $0.remoteFile != nil }) {
                // 断点续跑场景：存在已上传完成的远端文件，直接跳过上传步骤
                let uploadedCount = selectedFiles.filter { $0.remoteFile != nil }.count
                complete(.upload, outcome: .skipped, resultSummary: "沿用 \(uploadedCount) 个已上传文件")
            }

            // ====================== 步骤2：OCR全文文字识别与合并 ======================
            if shouldRun(.ocr, from: requestedStartStep) {
                currentStep = .ocr
                start(.ocr)
                // 对所有文件执行OCR识别，断点续跑复用已有识别文本，无需重复识别
                let ocrFiles = try await extractUseCase.recognizeOCRFiles(
                    files: selectedFiles,
                    reRecognizeAll: false,
                    cancellationToken: cancellationToken
                )
                selectedFiles = ocrFiles
                // 将多份文件的OCR文本合并为一整段文本，供后续AI分析使用
                let ocrText = try await extractUseCase.mergeOCRText(
                    files: ocrFiles,
                    reRecognizeAll: false,
                    cancellationToken: cancellationToken
                )
                try cancellationToken.checkCancellation()
                // 全局缓存合并后的OCR文本，作为流水线断点缓存
                pipelineOCRText = ocrText
                complete(
                    .ocr,
                    outcome: .success,
                    resultSummary: "约 \(ocrText.count) 字"
                )
            } else if let ocrText = pipelineOCRText {
                // 断点续跑：已缓存OCR文本，跳过识别步骤
                complete(
                    .ocr,
                    outcome: .skipped,
                    resultSummary: "沿用约 \(ocrText.count) 字"
                )
            }

            // 合法性校验：无OCR文本无法继续后续识别流程，抛出断点缺失异常
            guard let mergedOCRText = pipelineOCRText else {
                throw RecognitionPipelineError.missingCheckpoint("OCR")
            }

            // ====================== 步骤3：AI自动识别单据分类（病历/体检/处方等） ======================
            if shouldRun(.typeRecognition, from: requestedStartStep) {
                currentStep = .typeRecognition
                start(.typeRecognition)
                // 重试流程优先使用重试指定单据类型；正常流程使用用户手动选择类型
                let kindForRetry = overrideDocumentKindForRetry ?? selectedKind
                // AI根据OCR文本自动判定单据类型
                let resolution = try await extractUseCase.resolveType(
                    selectedKind: kindForRetry,
                    mergedOCRText: mergedOCRText,
                    cancellationToken: cancellationToken
                )
                try cancellationToken.checkCancellation()
                // 缓存单据分类识别结果，用于断点续跑
                typeResolution = resolution
                // 若非自动识别模式，同步更新用户选择单据类型
                if kindForRetry != .auto {
                    selectedKind = kindForRetry
                }
                // 记录本次识别出的单据类型，供重试流程复用
                overrideDocumentKindForRetry = resolution.kind
                complete(
                    .typeRecognition,
                    outcome: .success,
                    resultSummary: "\(resolution.kind.localizedUploadLabel) · \(resolution.source.localizedUploadLabel)"
                )
            } else if let resolution = typeResolution {
                // 断点续跑：已有单据分类结果，跳过类型识别
                complete(
                    .typeRecognition,
                    outcome: .skipped,
                    resultSummary: "\(resolution.kind.localizedUploadLabel) · 沿用"
                )
            }

            // 合法性校验：无单据分类结果无法执行结构化抽取
            guard let resolution = typeResolution else {
                throw RecognitionPipelineError.missingCheckpoint("类型识别")
            }

            // ====================== 步骤4：AI结构化医疗信息抽取（核心解析逻辑） ======================
            currentStep = .extract
            // 根据单据分类匹配对应AI抽取业务场景
            let extractScenario = scenario(for: resolution.kind)
            // 刷新当前场景支持的AI模型列表，更新可选模型
            await refreshExtractModelOptions(for: extractScenario)
            let preferredModelNameForRequest = preferredExtractModelName
            let modelSummary = modelDisplayName(for: preferredModelNameForRequest) ?? "默认模型"

            let manualRetryFeedback = extractionRetryFeedbackForCurrentRun(startingAt: requestedStartStep)
            start(.extract)
            updateExtractStepSummary(
                extractScenario: extractScenario,
                modelSummary: modelSummary,
                manualRetryFeedback: manualRetryFeedback
            )

            let bundles = try await aiConfigCenter.effectiveScenarioBundles()
            let extractionInputSource = extractionInputSourceResolver.resolve(
                files: selectedFiles,
                mergedOCRText: mergedOCRText,
                kind: resolution.kind,
                scenario: extractScenario,
                preferredModelName: preferredModelNameForRequest,
                bundles: bundles
            )

            let output = try await runExtractWithOptionalAutoRetry(
                memberID: member.id,
                files: selectedFiles,
                mergedOCRText: mergedOCRText,
                extractionInputSource: extractionInputSource,
                resolution: resolution,
                extractScenario: extractScenario,
                preferredModelNameForRequest: preferredModelNameForRequest,
                modelSummary: modelSummary,
                manualRetryFeedback: manualRetryFeedback,
                cancellationToken: cancellationToken
            )
            try cancellationToken.checkCancellation()

            // 抽取成功，清空所有重试状态标记
            clearExtractionRetryState()
            complete(
                .extract,
                outcome: .success,
                resultSummary: "\(scenarioLabel(for: extractScenario)) · \(modelSummary)"
            )

            // ====================== 步骤5：结构化结果与上传附件业务绑定匹配 ======================
            currentStep = .attachmentBinding
            start(.attachmentBinding)
            // 将远端附件ID与AI抽取结果进行关联绑定，完善业务信封数据
            let matchedOutput = MedicalDocumentAttachmentBusinessMatcher.matchAndUpdate(
                files: selectedFiles,
                output: output
            )
            complete(
                .attachmentBinding,
                outcome: .success,
                resultSummary: "已匹配 \(selectedFiles.compactMap { $0.remoteFile?.id }.count) 个附件"
            )

            // 存储最终完整识别输出，跳转结果路由页面使用
            typedOutput = matchedOutput
            // 关闭顶部进度加载动画
            stopProgressTimer()
            // 切换页面状态至结果展示页
            stage = .result
            logger.info(
                "Typed 识别流程完成，resolvedKind=\(matchedOutput.envelope.typeResolution.kind.rawValue)",
                module: .medical
            )

        } catch is CancellationError {
            // 捕获用户手动取消任务异常
            // 仅处理当前有效任务的取消，过期任务忽略
            if recognitionCancellationToken === cancellationToken {
                // 重置全部识别流水线缓存与状态，退回文件选择页面
                resetRecognitionState()
                stage = .picking
            }
            logger.info("Typed 识别流程已取消", module: .medical)
            
        } catch {
            // 捕获上传/OCR/类型识别/抽取全流程所有业务异常
            // 过滤过期旧任务报错，不更新UI
            if recognitionCancellationToken !== cancellationToken {
                logger.debug("忽略过期识别任务错误：\(error.localizedDescription)", module: .medical)
                return
            }
            // 记录失败步骤，触发UI失败状态展示
            failedStep = currentStep
            fail(currentStep)
            if currentStep == .extract {
                // 若抽取环节失败：区分解码失败与普通异常
                if MedicalExtractionFailureClassifier.isDecodingFailure(error) {
                    // 解码解析失败，记录失败日志供自动重试使用
                    recordExtractionFailure(error: error, resolution: typeResolution)
                } else {
                    // 非解码类错误，清空所有重试缓存
                    clearExtractionRetryFeedback()
                    clearAutoRetryState()
                }
            } else {
                // 上传/OCR/类型识别等前置步骤报错，直接清空重试状态
                clearExtractionRetryFeedback()
                clearAutoRetryState()
            }
            // 关闭所有重试标记
            isRetryingExtraction = false
            isAutoRetryingExtraction = false
            // 判断是否为模型缺失错误，弹窗提示下载模型；否则生成本地化错误文案
            if let scenario = missingModelScenario(from: error) {
                missingModelScenarioForAlert = scenario
                errorMessage = nil
            } else {
                errorMessage = localizedRecognitionErrorMessage(for: error, failedStep: currentStep)
            }
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

        let issues = preSubmitValidator.validate(output: typedOutput)
        if issues.blockingIssues.isEmpty == false {
            preSubmitValidationIssues = issues
            fail(.save)
            errorMessage = L10n.text("medical.upload.presubmit.error.save_blocked")
            logger.warning(
                "保存前本地预校验失败，阻断请求 issues=\(issues.blockingIssues.count)",
                module: .medical
            )
            return false
        }

        preSubmitValidationIssues = []

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

            preSubmitValidationIssues = []
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
        } catch let error as PrescriptionPayloadPreflightError {
            fail(.save)
            preSubmitValidationIssues = error.issues
            errorMessage = L10n.text("medical.upload.presubmit.error.save_blocked")
            logger.warning(
                "保存前 payload preflight 失败，阻断请求 issues=\(error.issues.count)",
                module: .medical
            )
            return false
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

    /// 用户编辑字段后，移除已修复字段对应的本地预校验错误。
    func clearPreSubmitValidationIssues(matchingFieldKeys keys: Set<String>) {
        guard keys.isEmpty == false else { return }
        preSubmitValidationIssues.removeAll { keys.contains($0.fieldKey) }
    }

    func clearPreSubmitValidationIssues(matchingFieldKey key: String) {
        clearPreSubmitValidationIssues(matchingFieldKeys: [key])
    }

    func clearAllPreSubmitValidationIssues() {
        preSubmitValidationIssues = []
    }

    func prepareAndStart(files: [MedicalUploadLocalFile], kind: MedicalDocumentKind, member: Member? = nil) {
        reset()
        pendingMemberOverride = member
        selectedMemberName = recognitionMember?.name
        selectedKind = kind
        setSelectedFiles(files)
        stage = .processing
        presentUploadPage()
        startRecognitionTask()
    }

    /// 外部 PDF 导入：重置状态、注入文件并打开上传页，保持在 `.picking` 阶段。
    func prepareForExternalImport(files: [MedicalUploadLocalFile]) {
        reset()
        setSelectedFiles(files)
        presentUploadPage()
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
        preSubmitValidationIssues = []
        errorMessage = nil
        missingModelScenarioForAlert = nil
        selectedKind = .auto
        clearPipelineCheckpoints()
        pendingMemberOverride = nil
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
        missingModelScenarioForAlert = nil
        failedStep = nil
        stepStartedAt = [:]
        clearExtractionRetryState()
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
        pipelineMemberID = nil
        clearExtractionRetryState()
    }

    private var recognitionMember: Member? {
        pendingMemberOverride ?? memberContextStore.context.selectedMember
    }

    private func clearExtractionRetryFeedback() {
        lastExtractionRetryFeedback = nil
    }

    private func clearAutoRetryState() {
        autoRetryAttempt = 0
        maxAutoRetryAttempts = 0
        isAutoRetryingExtraction = false
    }

    private func clearExtractionRetryState() {
        clearExtractionRetryFeedback()
        clearAutoRetryState()
        isRetryingExtraction = false
    }

    /// 执行结构化抽取，内置可选自动重试逻辑
    /// - Parameters:
    ///   - memberID: 当前家庭成员ID
    ///   - files: 待上传的本地医疗文件数组
    ///   - mergedOCRText: 多文件合并后的OCR识别全文
    ///   - resolution: 文档类型判定结果
    ///   - extractScenario: AI抽取业务场景枚举
    ///   - modelSummary: 当前选用模型描述文案，用于界面步骤展示
    ///   - manualRetryFeedback: 手动重试时携带的用户反馈修正信息，首次正常抽取为nil
    ///   - cancellationToken: AI任务取消令牌，支持中途终止请求
    /// - Returns: 带文档分类的结构化抽取输出结果
    /// - Throws: 抽取异常、任务取消异常、达到最大重试次数后的解码失败异常
    private func runExtractWithOptionalAutoRetry(
        memberID: Int,
        files: [MedicalUploadLocalFile],
        mergedOCRText: String,
        extractionInputSource: MedicalExtractionInputSource,
        resolution: MedicalDocumentTypeResolution,
        extractScenario: AIScenario,
        preferredModelNameForRequest: String?,
        modelSummary: String,
        manualRetryFeedback: MedicalExtractionRetryFeedback?,
        cancellationToken: AIRuntimeCancellationToken
    ) async throws -> MedicalDocumentTypedExtractionOutput {
        // 读取本地存储的抽取自动重试配置
        let settings = extractionRetrySettingsStore.load()
        // 根据配置获取最大自动重试次数，关闭自动重试则次数置0
        let maxAutoRetry = settings.autoRetryOnDecodingFailureEnabled
            ? settings.maxDecodingFailureAutoRetryCount
            : 0
        // 赋值全局最大自动重试上限
        maxAutoRetryAttempts = maxAutoRetry
        // 重置当前自动重试计数
        autoRetryAttempt = 0
        // 重置自动重试标记
        isAutoRetryingExtraction = false

        var attempt = 0
        // 初始化重试反馈信息，优先使用传入的手动重试反馈
        var retryFeedback = manualRetryFeedback
        // 存在手动反馈则标记当前处于重试流程
        isRetryingExtraction = retryFeedback != nil

        // 无限循环执行抽取，成功返回或超限抛异常才退出
        while true {
            // 更新界面抽取步骤展示文案
            updateExtractStepSummary(
                extractScenario: extractScenario,
                modelSummary: modelSummary,
                manualRetryFeedback: retryFeedback
            )

            do {
                // 调用核心用例执行AI结构化抽取
                let output = try await extractUseCase.extractStructured(
                    memberID: memberID,
                    files: files,
                    mergedOCRText: mergedOCRText,
                    extractionInputSource: extractionInputSource,
                    resolution: resolution,
                    preferredModelName: preferredModelNameForRequest,
                    retryFeedback: retryFeedback,
                    cancellationToken: cancellationToken
                )
                // 抽取成功，直接返回结构化结果
                return output
            } catch {
                // 校验任务是否已被取消，取消则直接抛出取消异常
                try cancellationToken.checkCancellation()

                // 判断异常是否为解码失败；非解码失败不进入自动重试，清理状态并向上抛出
                guard MedicalExtractionFailureClassifier.isDecodingFailure(error) else {
                    clearExtractionRetryState()
                    throw error
                }

                // 记录本次解码失败日志与异常信息
                recordExtractionFailure(error: error, resolution: resolution)

                // 校验开关是否开启、当前重试次数未达上限，不满足则终止重试抛异常
                guard settings.autoRetryOnDecodingFailureEnabled, attempt < maxAutoRetry else {
                    isAutoRetryingExtraction = false
                    throw error
                }

                // 重试计数自增
                attempt += 1
                autoRetryAttempt = attempt
                // 标记当前进入自动重试流程
                isAutoRetryingExtraction = true
                isRetryingExtraction = true
                // 复用上一次失败的重试反馈进行重试
                retryFeedback = lastExtractionRetryFeedback
                // 打印自动重试日志，记录当前轮次与最大重试次数
                logger.info(
                    "结构化抽取解码失败，自动重试 attempt=\(attempt)/\(maxAutoRetry)",
                    module: .medical
                )
            }
        }
    }

    private func updateExtractStepSummary(
        extractScenario: AIScenario,
        modelSummary: String,
        manualRetryFeedback: MedicalExtractionRetryFeedback?
    ) {
        let prefix: String
        if isAutoRetryingExtraction, maxAutoRetryAttempts > 0 {
            prefix = String(
                format: L10n.text("medical.upload.extract.auto_retry.summary"),
                autoRetryAttempt,
                maxAutoRetryAttempts
            )
        } else if manualRetryFeedback != nil {
            prefix = L10n.text("medical.upload.extract.retry.summary")
        } else {
            prefix = scenarioLabel(for: extractScenario)
        }
        updateStepResultSummary(.extract, resultSummary: "\(prefix) · \(modelSummary)")
    }

    private func extractionRetryFeedbackForCurrentRun(
        startingAt requestedStartStep: MedicalDocumentUploadFlowStep.Kind
    ) -> MedicalExtractionRetryFeedback? {
        guard requestedStartStep == .extract else { return nil }
        return lastExtractionRetryFeedback
    }

    private func recordExtractionFailure(
        error: Error,
        resolution: MedicalDocumentTypeResolution?
    ) {
        let kind = resolution?.kind ?? overrideDocumentKindForRetry ?? selectedKind
        let preview: String?
        if case ExtractionError.decodingFailed(let context) = error {
            preview = context?.outputPreview
        } else {
            preview = nil
        }
        lastExtractionRetryFeedback = MedicalExtractionErrorNormalizer.makeFeedbackIfDecodingFailure(
            kind: kind == .auto ? (resolution?.kind ?? .medicalReport) : kind,
            step: .extract,
            error: error,
            aiOutputPreview: preview
        )
    }

    private func localizedRecognitionErrorMessage(
        for error: Error,
        failedStep: MedicalDocumentUploadFlowStep.Kind
    ) -> String {
        var message = error.localizedDescription
        guard failedStep == .extract, lastExtractionRetryFeedback != nil else {
            return message
        }
        if maxAutoRetryAttempts > 0, autoRetryAttempt >= maxAutoRetryAttempts {
            message += "\n" + L10n.text("medical.upload.extract.auto_retry.exhausted")
        } else {
            message += "\n" + L10n.text("medical.upload.extract.retry.hint")
        }
        return message
    }

#if DEBUG
    var extractionRetryDebugLines: [String] {
        guard let feedback = lastExtractionRetryFeedback else { return [] }
        var lines: [String] = []
        if let fieldPath = feedback.fieldPath {
            lines.append(L10n.format("medical.upload.extract.retry.debug_field", fieldPath))
        }
        if let expectedType = feedback.expectedType {
            lines.append(L10n.format("medical.upload.extract.retry.debug_expected", expectedType))
        }
        if let actualType = feedback.actualType {
            lines.append(L10n.format("medical.upload.extract.retry.debug_actual", actualType))
        }
        return lines
    }
#endif

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
        clearExtractionRetryFeedback()
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
        case .medicationPlan:
            return .medicationExtraction
        case .medicineBox:
            return .medicineBoxExtraction
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
        case .medicineBoxExtraction:
            return "药品抽取"
        default:
            return "结构化抽取"
        }
    }

    // MARK: - Errors

    /// 从直接抛出或包装后的错误链中识别 `AIConfigError.missingModelForScenario`。
    private func missingModelScenario(from error: Error) -> AIScenario? {
        var current: Error? = error
        for _ in 0..<8 {
            guard let err = current else { return nil }
            if let configError = err as? AIConfigError,
               case .missingModelForScenario(let scenario) = configError {
                return scenario
            }
            let nsError = err as NSError
            current = nsError.userInfo[NSUnderlyingErrorKey] as? Error
        }
        return nil
    }

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
