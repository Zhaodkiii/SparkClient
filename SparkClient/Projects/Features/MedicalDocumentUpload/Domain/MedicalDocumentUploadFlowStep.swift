import Foundation

// MARK: - 流程步骤

/// 医疗文档上传流水线中的单个步骤（含运行时状态）。
struct MedicalDocumentUploadFlowStep: Equatable, Sendable {
    var kind: Kind
    var outcome: CompletionOutcome

    init(kind: Kind, outcome: CompletionOutcome = .pending) {
        self.kind = kind
        self.outcome = outcome
    }

    /// 步骤种类（与流水线拓扑一一对应）。
    enum Kind: String, CaseIterable, Sendable, Hashable, Codable {
        case upload
        case ocr
        case typeRecognition = "type_recognition"
        case extract
        case attachmentBinding = "attachment_binding"
        case save
    }

    /// 步骤状态与完成结果。
    enum CompletionOutcome: Equatable, Sendable {
        case pending
        case running
        case success
        case skipped
        case failed

        var accessibilityValue: String {
            switch self {
            case .pending: return "pending"
            case .running: return "running"
            case .success: return "success"
            case .skipped: return "skipped"
            case .failed: return "failed"
            }
        }

        var isTerminalSuccess: Bool {
            self == .success || self == .skipped
        }

        var isRunning: Bool {
            self == .running
        }

        var isFailed: Bool {
            self == .failed
        }
    }
}

// MARK: - 文案管理

extension MedicalDocumentUploadFlowStep.Kind {
    func runningPresentation() -> (title: String, subtitle: String?) {
        switch self {
        case .upload:
            return (L10n.text("medical.upload.step.upload.running"), L10n.text("medical.upload.step.upload.subtitle"))
        case .ocr:
            return (L10n.text("medical.upload.step.ocr.running"), L10n.text("medical.upload.step.ocr.subtitle"))
        case .typeRecognition:
            return (L10n.text("medical.upload.step.type.running"), L10n.text("medical.upload.step.type.subtitle"))
        case .extract:
            return (L10n.text("medical.upload.step.extract.running"), L10n.text("medical.upload.step.extract.subtitle.default"))
        case .attachmentBinding:
            return (L10n.text("medical.upload.step.attachment_binding.running", fallback: "正在匹配附件"), nil)
        case .save:
            return (L10n.text("medical.upload.step.save.running"), nil)
        }
    }

    func completionPresentation(outcome: MedicalDocumentUploadFlowStep.CompletionOutcome) -> (title: String, subtitle: String?) {
        switch (self, outcome) {
        case (.upload, .success), (.upload, .skipped):
            return (L10n.text("medical.upload.step.upload.completed"), nil)
        case (.upload, .failed):
            return (L10n.text("medical.upload.step.upload.failed"), nil)

        case (.ocr, .success), (.ocr, .skipped):
            return (L10n.text("medical.upload.step.ocr.completed"), L10n.text("medical.upload.step.ocr.subtitle"))
        case (.ocr, .failed):
            return (L10n.text("medical.upload.step.ocr.failed"), nil)

        case (.typeRecognition, .success), (.typeRecognition, .skipped):
            return (L10n.text("medical.upload.step.type.completed"), nil)
        case (.typeRecognition, .failed):
            return (L10n.text("medical.upload.step.type.failed"), nil)

        case (.extract, .success), (.extract, .skipped):
            return (L10n.text("medical.upload.step.extract.completed"), nil)
        case (.extract, .failed):
            return (L10n.text("medical.upload.step.extract.failed"), nil)

        case (.attachmentBinding, .success), (.attachmentBinding, .skipped):
            return (L10n.text("medical.upload.step.attachment_binding.completed", fallback: "附件匹配完成"), nil)
        case (.attachmentBinding, .failed):
            return (L10n.text("medical.upload.step.attachment_binding.failed", fallback: "附件匹配失败"), nil)

        case (.save, .success), (.save, .skipped):
            return (L10n.text("medical.upload.step.save.completed"), nil)
        case (.save, .failed):
            return (L10n.text("medical.upload.step.save.failed"), nil)

        case (_, .pending), (_, .running):
            return runningPresentation()
        }
    }

    func presentation(outcome: MedicalDocumentUploadFlowStep.CompletionOutcome) -> (title: String, subtitle: String?) {
        switch outcome {
        case .pending, .running:
            return runningPresentation()
        case .success, .skipped, .failed:
            return completionPresentation(outcome: outcome)
        }
    }

    func title(outcome: MedicalDocumentUploadFlowStep.CompletionOutcome) -> String {
        presentation(outcome: outcome).title
    }

    func subtitle(outcome: MedicalDocumentUploadFlowStep.CompletionOutcome) -> String? {
        presentation(outcome: outcome).subtitle
    }

    static var pipelineSteps: [MedicalDocumentUploadFlowStep.Kind] {
        allCases.sorted { $0.pipelineOrder < $1.pipelineOrder }
    }

    var pipelineOrder: Int {
        switch self {
        case .upload: return 0
        case .ocr: return 1
        case .typeRecognition: return 2
        case .extract: return 3
        case .attachmentBinding: return 4
        case .save: return 5
        }
    }
}

extension MedicalDocumentUploadFlowStep {
    func title() -> String {
        kind.title(outcome: outcome)
    }

    func subtitle() -> String? {
        kind.subtitle(outcome: outcome)
    }
}

// MARK: - StepReporter 协议

@MainActor
protocol MedicalDocumentUploadStepReporter: AnyObject {
    func start(_ step: MedicalDocumentUploadFlowStep.Kind)
    func complete(
        _ step: MedicalDocumentUploadFlowStep.Kind,
        outcome: MedicalDocumentUploadFlowStep.CompletionOutcome,
        resultSummary: String?
    )
    func fail(_ step: MedicalDocumentUploadFlowStep.Kind)
}

extension MedicalDocumentUploadStepReporter {
    func complete(
        _ step: MedicalDocumentUploadFlowStep.Kind,
        outcome: MedicalDocumentUploadFlowStep.CompletionOutcome = .success
    ) {
        complete(step, outcome: outcome, resultSummary: nil)
    }
}
