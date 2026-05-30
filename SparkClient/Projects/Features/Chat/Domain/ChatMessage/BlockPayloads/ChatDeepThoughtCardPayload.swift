import Foundation

nonisolated struct ChatDeepThoughtCardPayload: Equatable, Codable, Sendable {
    var reasoningContent: String?
    var reasoningDurationMs: Int64?
    var reasoningExpanded: Bool
    var reasoningVisibility: ChatReasoningVisibility
}
