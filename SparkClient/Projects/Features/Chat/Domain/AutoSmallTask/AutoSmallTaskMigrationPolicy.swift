import Foundation

nonisolated enum AutoSmallTaskMigrationPolicy: String, Codable, Sendable {
    case overwriteBuiltInOnly
    case preserveUserEdited
    case forceOverwrite
}
