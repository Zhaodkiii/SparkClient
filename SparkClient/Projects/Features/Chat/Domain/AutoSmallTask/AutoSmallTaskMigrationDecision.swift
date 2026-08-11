import Foundation

nonisolated enum AutoSmallTaskMigrationAction: String, Codable, Equatable, Sendable {
    case inserted
    case skipped
    case upgraded
    case preservedUserEdited
    case blocked
    case hashConflict
}

nonisolated enum AutoSmallTaskMigrationBlockedReason: String, Codable, Equatable, Sendable {
    case runtimeVersionTooLow
    case toolContractVersionTooLow
    case missingRequiredTools
    case localVersionNewerThanBundle
}

nonisolated enum AutoSmallTaskMigrationDecision: Equatable, Sendable {
    case insert
    case skip
    case upgrade(fromVersion: Int, toVersion: Int)
    case preserveUserEdited
    case hashConflict
    case blocked(reason: AutoSmallTaskMigrationBlockedReason)

    var action: AutoSmallTaskMigrationAction {
        switch self {
        case .insert:
            return .inserted
        case .skip:
            return .skipped
        case .upgrade:
            return .upgraded
        case .preserveUserEdited:
            return .preservedUserEdited
        case .hashConflict:
            return .hashConflict
        case .blocked:
            return .blocked
        }
    }

    var blockedReason: AutoSmallTaskMigrationBlockedReason? {
        if case .blocked(let reason) = self {
            return reason
        }
        return nil
    }
}
