import Foundation

// MARK: - 步骤模型
/// 医疗文档上传【单个步骤】模型
/// 描述上传流程中的一个具体执行步骤（如：文件准备、文件上传、服务器校验等）
struct MedicalDocumentUploadStep: Identifiable, Equatable, Sendable {
    var id: MedicalDocumentUploadFlowStep.Kind { flowStep.kind }

    /// 流水线步骤（含种类与完成状态）。
    var flowStep: MedicalDocumentUploadFlowStep

    /// 步骤已耗时（毫秒）。
    var elapsedMilliseconds: Int

    /// 预估执行耗时（单位：秒，可选）
    var estimatedSeconds: Int?

    /// 步骤完成后展示在右侧或副区域的短结果摘要。
    var resultSummary: String?

    init(
        flowStep: MedicalDocumentUploadFlowStep,
        elapsedMilliseconds: Int = 0,
        estimatedSeconds: Int? = nil,
        resultSummary: String? = nil
    ) {
        self.flowStep = flowStep
        self.elapsedMilliseconds = elapsedMilliseconds
        self.estimatedSeconds = estimatedSeconds
        self.resultSummary = resultSummary
    }

    init(
        kind: MedicalDocumentUploadFlowStep.Kind,
        elapsedMilliseconds: Int = 0,
        estimatedSeconds: Int? = nil,
        resultSummary: String? = nil
    ) {
        self.init(
            flowStep: MedicalDocumentUploadFlowStep(kind: kind),
            elapsedMilliseconds: elapsedMilliseconds,
            estimatedSeconds: estimatedSeconds,
            resultSummary: resultSummary
        )
    }
}

// MARK: - 进度模型
/// 医疗文档上传进度模型
/// 用于统一管理和展示单个文档上传的整体进度、状态、耗时及分步流程
struct MedicalDocumentUploadProgress: Identifiable, Equatable, Sendable {
    let id = UUID()

    var title: String
    var statusLabel: String
    var elapsedSeconds: Int
    var estimatedSeconds: Int?
    var steps: [MedicalDocumentUploadStep]

    var overallOutcome: MedicalDocumentUploadFlowStep.CompletionOutcome {
        if steps.contains(where: { $0.flowStep.outcome.isFailed }) {
            return .failed
        } else if steps.contains(where: { $0.flowStep.outcome.isRunning }) {
            return .running
        } else if steps.isEmpty == false, steps.allSatisfy({ $0.flowStep.outcome.isTerminalSuccess }) {
            return .success
        } else {
            return .pending
        }
    }

    var runningStep: MedicalDocumentUploadFlowStep.Kind? {
        steps.first { $0.flowStep.outcome.isRunning }?.flowStep.kind
    }
}
