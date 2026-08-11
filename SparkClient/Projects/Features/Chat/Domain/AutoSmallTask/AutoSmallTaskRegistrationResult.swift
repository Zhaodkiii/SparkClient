import Foundation

nonisolated struct AutoSmallTaskRegistrationResult: Equatable, Sendable {
    let smallTask: SmallTask?
    let action: AutoSmallTaskMigrationAction
    let isRunnable: Bool
    let blockedReason: AutoSmallTaskMigrationBlockedReason?

    static func blocked(_ reason: AutoSmallTaskMigrationBlockedReason) -> AutoSmallTaskRegistrationResult {
        AutoSmallTaskRegistrationResult(
            smallTask: nil,
            action: .blocked,
            isRunnable: false,
            blockedReason: reason
        )
    }
}
