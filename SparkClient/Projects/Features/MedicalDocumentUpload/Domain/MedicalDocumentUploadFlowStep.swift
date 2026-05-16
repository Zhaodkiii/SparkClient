import Foundation

// MARK: - 流程步骤枚举

/// 医疗文档上传【完整流程步骤】枚举
/// 定义文档从上传到保存的全流程阶段，按执行顺序排列
enum MedicalDocumentUploadFlowStep: String, CaseIterable, Sendable {
    /// 1. 文件上传（上传本地文件到服务器）
    case upload
    
    /// 2. OCR 文字识别（对图片/文档进行光学字符提取）
    case ocr
    
    /// 3. 文档类型识别（自动识别文档是病历/处方/体检报告等）
    case typeRecognition = "type_recognition"
    
    /// 4. 关键信息提取（从文档中抽取结构化数据）
    case extract
    
    /// 5. 数据保存（将识别结果保存到后端数据库）
    case save
}

// MARK: - 步骤变体

import Foundation

extension MedicalDocumentUploadFlowStep {
    /// 步骤开始时的展示变体
    /// 用于根据不同的【文档类型】显示不同的标题/提示文案
    enum StartVariant: Sendable {
        case `default`          // 默认类型
        case caseDocument       // 病例文档
        case healthExamReport   // 体检报告
        case medicalReport      // 医疗报告
        case prescription       // 处方
        case medicationPlan     // 用药计划
        case medicineBox        // 药箱
    }
    
    /// 步骤执行完成后的结果类型
    /// 用于标记当前步骤最终的执行状态
    enum CompletionOutcome: Equatable, Sendable {
        case success    // 执行成功
        case skipped    // 已跳过
        case failed     // 执行失败
    }
}

// MARK: - 文案管理

extension MedicalDocumentUploadFlowStep {
    /// 获取步骤进行中的展示文案
    /// - Parameter variant: 文档类型变体，不同类型可能有不同的文案
    /// - Returns: (title, subtitle) 标题和副标题
    func runningPresentation(variant: StartVariant = .default) -> (title: String, subtitle: String?) {
        switch self {
        case .upload:
            return (L10n.text("medical.upload.step.upload.running"), L10n.text("medical.upload.step.upload.subtitle"))
        case .ocr:
            return (L10n.text("medical.upload.step.ocr.running"), L10n.text("medical.upload.step.ocr.subtitle"))
        case .typeRecognition:
            return (L10n.text("medical.upload.step.type.running"), L10n.text("medical.upload.step.type.subtitle"))
        case .extract:
            let subtitle: String? = {
                switch variant {
                case .default: return L10n.text("medical.upload.step.extract.subtitle.default")
                case .caseDocument: return L10n.text("medical.upload.step.extract.subtitle.case")
                case .healthExamReport: return L10n.text("medical.upload.step.extract.subtitle.health_exam")
                case .medicalReport: return L10n.text("medical.upload.step.extract.subtitle.medical_report")
                case .prescription: return L10n.text("medical.upload.step.extract.subtitle.prescription")
                case .medicationPlan: return L10n.text("medical.upload.step.extract.subtitle.medicationPlan")
                case .medicineBox: return L10n.text("medical.upload.step.extract.subtitle.medicine_box", fallback: "正在抽取药品包装信息")
                }
            }()
            return (L10n.text("medical.upload.step.extract.running"), subtitle)
        case .save:
            return (L10n.text("medical.upload.step.save.running"), nil)
        }
    }
    
    /// 获取步骤完成后的展示文案
    /// - Parameter outcome: 完成结果类型
    /// - Returns: (title, subtitle) 标题和副标题
    func completionPresentation(outcome: CompletionOutcome) -> (title: String, subtitle: String?) {
        switch (self, outcome) {
        case (.upload, .success):
            return (L10n.text("medical.upload.step.upload.completed"), nil)
        case (.upload, .skipped):
            return (L10n.text("medical.upload.step.upload.completed"), nil)
        case (.upload, .failed):
            return (L10n.text("medical.upload.step.upload.failed"), nil)
            
        case (.ocr, .success):
            return (L10n.text("medical.upload.step.ocr.completed"), L10n.text("medical.upload.step.ocr.subtitle"))
        case (.ocr, .skipped):
            return (L10n.text("medical.upload.step.ocr.completed"), L10n.text("medical.upload.step.ocr.subtitle"))
        case (.ocr, .failed):
            return (L10n.text("medical.upload.step.ocr.failed"), nil)
            
        case (.typeRecognition, .success):
            return (L10n.text("medical.upload.step.type.completed"), nil)
        case (.typeRecognition, .skipped):
            return (L10n.text("medical.upload.step.type.completed"), nil)
        case (.typeRecognition, .failed):
            return (L10n.text("medical.upload.step.type.failed"), nil)
            
        case (.extract, .success):
            return (L10n.text("medical.upload.step.extract.completed"), nil)
        case (.extract, .skipped):
            return (L10n.text("medical.upload.step.extract.completed"), nil)
        case (.extract, .failed):
            return (L10n.text("medical.upload.step.extract.failed"), nil)
            
        case (.save, .success):
            return (L10n.text("medical.upload.step.save.completed"), nil)
        case (.save, .skipped):
            return (L10n.text("medical.upload.step.save.completed"), nil)
        case (.save, .failed):
            return (L10n.text("medical.upload.step.save.failed"), nil)
        }
    }
}

// MARK: - StepReporter 协议

/// 步骤上报协议，用于抽象步骤状态管理
/// ViewModel 实现此协议，视图层通过协议方法更新步骤状态
@MainActor
protocol MedicalDocumentUploadStepReporter: AnyObject {
    /// 开始某个步骤
    /// - Parameters:
    ///   - step: 要开始的步骤
    ///   - variant: 步骤变体，用于获取对应文案
    func start(_ step: MedicalDocumentUploadFlowStep, variant: MedicalDocumentUploadFlowStep.StartVariant)
    
    /// 完成某个步骤
    /// - Parameters:
    ///   - step: 要完成的步骤
    ///   - outcome: 完成结果
    func complete(
        _ step: MedicalDocumentUploadFlowStep,
        outcome: MedicalDocumentUploadFlowStep.CompletionOutcome,
        resultSummary: String?,
        detailKind: MedicalDocumentUploadStepDetailKind?
    )
    
    /// 标记某个步骤失败
    /// - Parameter step: 失败的步骤
    func fail(_ step: MedicalDocumentUploadFlowStep)
}

// MARK: - 协议默认实现

extension MedicalDocumentUploadStepReporter {
    /// 默认变体的开始步骤方法
    func start(_ step: MedicalDocumentUploadFlowStep) {
        start(step, variant: .default)
    }

    func complete(_ step: MedicalDocumentUploadFlowStep, outcome: MedicalDocumentUploadFlowStep.CompletionOutcome) {
        complete(step, outcome: outcome, resultSummary: nil, detailKind: nil)
    }
}

extension MedicalDocumentUploadFlowStep {
    var pipelineOrder: Int {
        switch self {
        case .upload: return 0
        case .ocr: return 1
        case .typeRecognition: return 2
        case .extract: return 3
        case .save: return 4
        }
    }
}
