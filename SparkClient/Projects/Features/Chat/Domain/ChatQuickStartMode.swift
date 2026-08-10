import Foundation

/// 普通 Chat 首页快捷入口模式；与 DeepTutor 快捷入口保持同一标题和预填草稿。
enum ChatQuickStartMode: String, Sendable {
    case checkupPlan = "checkup_plan"
    case reportInterpretation = "report_interpretation"

    init(deepTutorMode: DeepTutorQuickStartMode) {
        switch deepTutorMode {
        case .checkupPlan:
            self = .checkupPlan
        case .reportInterpretation:
            self = .reportInterpretation
        }
    }

    var title: String {
        switch self {
        case .checkupPlan:
            return L10n.text("ios26.home.action.checkup_plan.title")
        case .reportInterpretation:
            return L10n.text("ios26.home.action.report_interpretation.title")
        }
    }

    var initialDraft: String {
        switch self {
        case .checkupPlan:
            return L10n.text("ios26.home.action.checkup_plan.draft")
        case .reportInterpretation:
            return L10n.text("ios26.home.action.report_interpretation.draft")
        }
    }
}
