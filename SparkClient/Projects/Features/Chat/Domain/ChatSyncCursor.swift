import Foundation

struct ChatSyncCursor: Codable, Equatable, Sendable {
    let value: String
    let updatedAt: Date

    init(value: String, updatedAt: Date = Date()) {
        self.value = value
        self.updatedAt = updatedAt
    }
}
