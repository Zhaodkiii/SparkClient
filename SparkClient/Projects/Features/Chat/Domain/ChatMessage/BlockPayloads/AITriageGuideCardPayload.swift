import Foundation

nonisolated struct AITriageGuidePrompt: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var message: String
}

nonisolated struct AITriageGuideCardPayload: Codable, Equatable, Sendable {
    var title: String
    var subtitle: String
    var disclaimer: String
    var prompts: [AITriageGuidePrompt]
}
