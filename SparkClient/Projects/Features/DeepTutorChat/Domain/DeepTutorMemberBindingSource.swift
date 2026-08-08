import Foundation

nonisolated enum DeepTutorMemberBindingSource: String, Codable, CaseIterable, Sendable {
    case composerManual = "composer_manual"
    case toolSelection = "tool_selection"
    case restored = "restored"
    case cleared = "cleared"
}
