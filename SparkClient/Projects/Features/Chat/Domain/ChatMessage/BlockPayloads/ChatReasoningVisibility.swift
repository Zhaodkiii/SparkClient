import Foundation

/// How much of the model reasoning chain is shown in the message UI.
enum ChatReasoningVisibility: String, Codable, Sendable, Equatable {
    case hidden
    case summary
    case full
}
