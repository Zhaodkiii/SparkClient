import Foundation

/// DeepTutor 首页快捷入口预留模式（体检计划、报告解读）；本期仅影响会话标题与输入草稿。
enum DeepTutorQuickStartMode: String, Sendable {
    case checkupPlan = "checkup_plan"
    case reportInterpretation = "report_interpretation"

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
