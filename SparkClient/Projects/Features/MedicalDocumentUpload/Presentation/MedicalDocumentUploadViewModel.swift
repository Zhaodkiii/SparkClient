import Foundation
import Combine

@MainActor
/// 医疗文档上传流程 ViewModel（主线程模型）。
///
/// 设计目标：
/// 1. 将页面状态管理（选择/处理中/结果）集中在单一状态机中；
/// 2. 将业务调用严格下沉到 UseCase（视图层不直接触达 OCR / AI / Repository）；
/// 3. 对外暴露最小可绑定状态，避免页面持有复杂业务对象；
/// 4. 通过标准日志记录关键节点，便于排障与行为追踪。
///
/// 并发约束：
/// - 标注 `@MainActor`，确保所有 `@Published` 状态更新都发生在主线程；
/// - 识别/保存方法内部可 `await` 异步任务，但返回后统一在主线程回写 UI 状态。
final class MedicalDocumentUploadViewModel: ObservableObject {
    /// 页面主状态：控制 HostView 的三态渲染。
    enum Stage: Equatable {
        /// 文件选择态（可添加/删除文件，查看当前成员）。
        case picking
        /// 处理中（显示步骤进度，不允许重复触发识别）。
        case processing
        /// 结果态（展示 OCR 文本、抽取 JSON、可提交保存）。
        case result
    }

    /// 进度步骤模型：用于处理页的可视化步骤列表。
    struct ProgressStep: Identifiable, Equatable {
        /// 单个步骤执行状态。
        enum State: Equatable {
            /// 等待执行。
            case waiting
            /// 正在执行。
            case running
            /// 执行完成。
            case done
            /// 执行失败（当前流程会中断并显示错误）。
            case failed
        }

        /// 步骤唯一标识（例如 prepare/ocr/extract/save）。
        let id: String
        /// 步骤展示文案。
        let title: String
        /// 当前步骤状态。
        var state: State
    }

    // MARK: - 对外状态（供 SwiftUI 绑定）

    /// 当前页面阶段。
    @Published private(set) var stage: Stage = .picking
    /// 当前选中成员名称（来源于首页成员上下文）。
    @Published private(set) var selectedMemberName: String?
    /// 当前待识别的本地文件列表。
    @Published private(set) var selectedFiles: [MedicalUploadLocalFile] = []
    /// 由 `selectedFiles` 映射出的统一预览输入模型。
    @Published private(set) var previewItems: [FilePreviewInput] = []
    /// 处理中步骤列表。
    @Published private(set) var progressSteps: [ProgressStep] = []
    /// 识别结果（进入结果页后展示）。
    @Published private(set) var recognitionResult: MedicalDocumentRecognitionResult?
    /// 是否处于保存中（用于按钮禁用与 loading 态）。
    @Published private(set) var isSaving = false
    /// 错误提示文案（页面统一弹窗/提示使用）。
    @Published var errorMessage: String?
    /// 保存成功回执（记录 ID、时间等）。
    @Published var saveReceipt: MedicalDocumentSaveReceipt?

    // MARK: - 依赖（通过构造注入）

    /// 首页成员上下文存储（不做患者匹配，直接取当前成员）。
    private let patientContextStore: PatientContextStore
    /// 识别用例：负责 OCR + AI 抽取编排。
    private let startUseCase: StartMedicalDocumentRecognitionUseCase
    /// 保存用例：负责将识别结果提交到服务端（或仓储实现）。
    private let saveUseCase: SaveRecognizedMedicalDocumentUseCase
    /// 预览映射用例：将本地文件映射成统一预览输入。
    private let buildPreviewUseCase: BuildMedicalDocumentPreviewItemsUseCase
    /// 标准日志器。
    private let logger: Logger

    /// 初始化：
    /// - 注入所有外部依赖；
    /// - 首次读取当前成员名称，供页面初始渲染。
    init(
        patientContextStore: PatientContextStore,
        startUseCase: StartMedicalDocumentRecognitionUseCase,
        saveUseCase: SaveRecognizedMedicalDocumentUseCase,
        buildPreviewUseCase: BuildMedicalDocumentPreviewItemsUseCase = BuildMedicalDocumentPreviewItemsUseCase(),
        logger: Logger = ConsoleLogger()
    ) {
        self.patientContextStore = patientContextStore
        self.startUseCase = startUseCase
        self.saveUseCase = saveUseCase
        self.buildPreviewUseCase = buildPreviewUseCase
        self.logger = logger
        self.selectedMemberName = patientContextStore.context.selectedMember?.name
    }

    /// 是否允许开始识别。
    ///
    /// 判定条件：
    /// - 至少选择了一个文件；
    /// - 当前存在有效成员上下文。
    var canStartRecognition: Bool {
        selectedFiles.isEmpty == false && patientContextStore.context.selectedMember != nil
    }

    /// 覆盖设置文件列表（由文件选择组件调用）。
    ///
    /// 副作用：
    /// - 同步更新预览列表；
    /// - 清除旧错误提示（新选择行为视为用户重试）。
    func setSelectedFiles(_ files: [MedicalUploadLocalFile]) {
        selectedFiles = files
        previewItems = buildPreviewUseCase.execute(files: files)
        errorMessage = nil
        logger.info("已更新待识别文件，数量=\(files.count)", category: "medical_upload")
    }

    /// 删除指定文件并同步刷新预览列表。
    func removeFile(id: UUID) {
        selectedFiles.removeAll { $0.id == id }
        previewItems = buildPreviewUseCase.execute(files: selectedFiles)
        logger.info("已移除文件，剩余数量=\(selectedFiles.count)", category: "medical_upload")
    }

    /// 启动识别主流程。
    ///
    /// 执行路径：
    /// 1. 校验成员上下文；
    /// 2. 进入 processing，并初始化步骤；
    /// 3. 调用识别用例（OCR + AI）；
    /// 4. 成功进入结果页，失败标记步骤并展示错误。
    func startRecognition() async {
        // 必须绑定到当前成员，若不存在则直接中断。
        guard let member = patientContextStore.context.selectedMember else {
            errorMessage = L10n.text("medical.upload.error.no_member")
            logger.warning("启动识别失败：当前无成员上下文。", category: "medical_upload")
            return
        }
        logger.info("开始识别流程，memberID=\(member.id), fileCount=\(selectedFiles.count)", category: "medical_upload")
        selectedMemberName = member.name
        errorMessage = nil
        recognitionResult = nil
        saveReceipt = nil
        stage = .processing
        // 首期最简流程步骤：prepare -> ocr -> extract -> save。
        progressSteps = [
            .init(id: "prepare", title: "Prepare", state: .running),
            .init(id: "ocr", title: "OCR", state: .waiting),
            .init(id: "extract", title: "Extract", state: .waiting),
            .init(id: "save", title: "Save", state: .waiting)
        ]
        markDone("prepare")
        markRunning("ocr")

        do {
            // 识别用例内部会完成 OCR 与 AI 抽取，并返回统一结果容器。
            let result = try await startUseCase.execute(
                memberID: member.id,
                files: selectedFiles,
                mode: nil
            )
            markDone("ocr")
            markRunning("extract")
            markDone("extract")
            recognitionResult = result
            stage = .result
            logger.info("识别流程完成，进入结果页。", category: "medical_upload")
        } catch {
            // 任一异常都将当前运行步骤标记为失败，并将错误透出给 UI。
            markFailedCurrent()
            errorMessage = error.localizedDescription
            logger.error("识别流程失败：\(error.localizedDescription)", category: "medical_upload")
        }
    }

    /// 提交保存识别结果。
    ///
    /// 返回值：
    /// - `true`：保存成功；
    /// - `false`：保存失败或前置校验未通过。
    func saveResult() async -> Bool {
        // 防重入：避免重复点击造成并发提交。
        guard isSaving == false else { return false }
        // 保存仍依赖成员上下文。
        guard let member = patientContextStore.context.selectedMember else {
            errorMessage = L10n.text("medical.upload.error.no_member")
            logger.warning("保存失败：当前无成员上下文。", category: "medical_upload")
            return false
        }
        // 必须有识别结果才允许保存。
        guard let recognitionResult else {
            errorMessage = "暂无可保存的识别结果。"
            logger.warning("保存失败：识别结果为空。", category: "medical_upload")
            return false
        }
        logger.info("开始提交保存，memberID=\(member.id)", category: "medical_upload")
        isSaving = true
        markRunning("save")
        // 统一收尾：无论成功失败都退出 saving 态。
        defer { isSaving = false }

        do {
            let receipt = try await saveUseCase.execute(
                memberID: member.id,
                result: recognitionResult,
                sourceFiles: selectedFiles
            )
            markDone("save")
            saveReceipt = receipt
            logger.info("提交保存成功，recordID=\(receipt.recordID)", category: "medical_upload")
            return true
        } catch {
            // 保存失败时，同样标记当前步骤失败并反馈错误。
            markFailedCurrent()
            errorMessage = error.localizedDescription
            logger.error("提交保存失败：\(error.localizedDescription)", category: "medical_upload")
            return false
        }
    }

    /// 重置上传流程。
    ///
    /// 触发场景：
    /// - 用户返回重新上传；
    /// - 成功保存后准备新一轮上传；
    /// - 关闭页面前清理状态。
    func reset() {
        stage = .picking
        selectedFiles = []
        previewItems = []
        progressSteps = []
        recognitionResult = nil
        saveReceipt = nil
        errorMessage = nil
        selectedMemberName = patientContextStore.context.selectedMember?.name
        logger.info("上传流程已重置。", category: "medical_upload")
    }

    // MARK: - 步骤状态更新（内部工具方法）

    /// 将指定步骤标记为运行中。
    private func markRunning(_ id: String) {
        update(id) { $0.state = .running }
    }

    /// 将指定步骤标记为已完成。
    private func markDone(_ id: String) {
        update(id) { $0.state = .done }
    }

    /// 将当前运行中的步骤标记为失败。
    ///
    /// 说明：
    /// - 仅标记第一个 `running` 步骤；
    /// - 若没有 running 步骤（异常边界），则静默返回。
    private func markFailedCurrent() {
        guard let running = progressSteps.first(where: { $0.state == .running }) else { return }
        update(running.id) { $0.state = .failed }
    }

    /// 以不可变拷贝方式更新步骤数组中某个元素，确保 `@Published` 触发刷新。
    private func update(_ id: String, transform: (inout ProgressStep) -> Void) {
        guard let idx = progressSteps.firstIndex(where: { $0.id == id }) else { return }
        var next = progressSteps[idx]
        transform(&next)
        progressSteps[idx] = next
    }
}

#if DEBUG
/// 预览专用 AI 运行时桩：返回固定 JSON，避免预览依赖真实网络与模型。
private struct PreviewMedicalRuntimeService: AIRuntimeServing {
    func generateText(request _: AIRuntimeTextRequest) async throws -> AIRuntimeTextResponse {
        AIRuntimeTextResponse(
            text: """
            {"title":"门诊复查记录","summary":"患者主诉咽痛三天，体温正常。","diagnosis":"上呼吸道感染","occurredAt":"2026-04-01"}
            """,
            model: "preview",
            promptTokens: nil,
            completionTokens: nil,
            toolCalls: [],
            finishReason: "stop"
        )
    }
}

/// 预览专用医疗仓储桩：以内存快照模拟读写。
private actor PreviewMedicalDataRepository: MedicalDataRepository {
    private var snapshot = MedicalDataSnapshot.empty

    func loadSnapshot() async -> MedicalDataSnapshot {
        snapshot
    }

    func saveSnapshot(_ snapshot: MedicalDataSnapshot) async throws {
        self.snapshot = snapshot
    }

    func uploadSnapshotToServer(priority _: CloudSyncPriority) async throws {}
    func pullSnapshotFromServer(priority _: CloudSyncPriority) async throws {}
}

extension MedicalDocumentUploadViewModel {
    /// SwiftUI Preview 工厂：
    /// - 构造最小依赖图；
    /// - 注入假成员、假识别器、假保存器；
    /// - 便于在画布中验证状态流转与布局。
    static func preview() -> MedicalDocumentUploadViewModel {
        let patientStore = PatientContextStore()
        let member = Member(id: 1, name: "本人", relationship: "self", isPrimary: true)
        patientStore.update(members: [member], selectedMemberID: member.id)

        let recognizer = DefaultMedicalDocumentRecognizer(
            ocrOrchestrator: OCROrchestrator(config: OCRConfiguration()),
            runtimeService: PreviewMedicalRuntimeService(),
            promptBuilder: MedicalPromptFactory()
        )
        let saver = DefaultMedicalDocumentSaver(medicalDataRepository: PreviewMedicalDataRepository())
        return MedicalDocumentUploadViewModel(
            patientContextStore: patientStore,
            startUseCase: StartMedicalDocumentRecognitionUseCase(recognizer: recognizer),
            saveUseCase: SaveRecognizedMedicalDocumentUseCase(saver: saver)
        )
    }
}
#endif
