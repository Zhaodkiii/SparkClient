import Foundation

/// 普通 Chat 首页快捷入口模式。
enum ChatQuickStartMode: String, Sendable {
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
