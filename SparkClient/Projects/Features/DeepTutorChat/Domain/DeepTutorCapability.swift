import Foundation

/// DeepTutor 能力类型，对齐 Web `capability` 字段。
nonisolated enum DeepTutorCapability: String, Codable, CaseIterable, Sendable {
    case chat
    case deepResearch = "deep_research"
    case deepQuestion = "deep_question"
    case mathAnimator = "math_animator"
    case visualize
    case masteryPath = "mastery_path"

    var badgeLabel: String {
        switch self {
        case .chat:
            return "Chat"
        case .deepResearch:
            return "Deep Research"
        case .deepQuestion:
            return "Quiz"
        case .mathAnimator:
            return "Math Animator"
        case .visualize:
            return "Visualize"
        case .masteryPath:
            return "Mastery Path"
        }
    }
}
