import Foundation

// MARK: - 流程步骤枚举

/// 上传识别流程中的业务步骤
/// rawValue 与 MedicalDocumentUploadStep.id 保持一致
enum MedicalDocumentUploadFlowStep: String, CaseIterable, Sendable {
    case upload
    case ocr
    case typeRecognition = "type_recognition"
    case extract
    case save
}

// MARK: - 步骤变体

extension MedicalDocumentUploadFlowStep {
    /// 步骤开始的变体，用于区分不同文档类型的文案
    enum StartVariant: Sendable {
        case `default`
        case caseDocument
        case healthExamReport
        case medicalReport
        case prescription
        case medication
    }
    
    /// 步骤完成的结果类型
    enum CompletionOutcome: Equatable, Sendable {
        case success
        case skipped
        case failed
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
                case .medication: return L10n.text("medical.upload.step.extract.subtitle.medication")
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
    func complete(_ step: MedicalDocumentUploadFlowStep, outcome: MedicalDocumentUploadFlowStep.CompletionOutcome)
    
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
}
