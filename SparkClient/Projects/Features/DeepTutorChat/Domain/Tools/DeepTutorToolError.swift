import Foundation

nonisolated enum DeepTutorToolError: LocalizedError, Sendable {
    case unavailable(String)
    case invalidArguments(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let name):
            return "Tool '\(name)' is unavailable."
        case .invalidArguments(let message):
            return message
        }
    }
}

