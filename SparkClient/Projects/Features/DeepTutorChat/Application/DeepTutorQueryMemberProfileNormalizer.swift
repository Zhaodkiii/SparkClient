import Foundation

enum DeepTutorQueryMemberProfileNormalizer: Sendable {
    nonisolated static func isQueryMemberProfileTool(_ toolName: String?) -> Bool {
        guard let normalized = toolName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            normalized.isEmpty == false else {
            return false
        }
        return normalized == DeepTutorToolName.queryMemberProfile.rawValue
            || normalized == SparkToolName.queryMemberProfile.rawValue
    }

    nonisolated static func payload(from partial: ChatAssistantPartialDelta) -> DeepTutorMemberProfileBlockPayload? {
        guard let payload = DeepTutorQueryMemberProfileFormatter.payload(from: partial.toolInvocationArguments) else {
            return nil
        }
        var copy = payload
        copy.toolCallID = partial.toolCallID ?? payload.toolCallID
        copy.updatedAt = Date()
        if copy.createdAt.timeIntervalSince1970 <= 0 {
            copy.createdAt = copy.updatedAt
        }
        return copy
    }
}

