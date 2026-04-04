import Foundation

struct Patient: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let remoteID: Int?
    let displayName: String
    let relationship: String
    let isPrimary: Bool
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        remoteID: Int? = nil,
        displayName: String,
        relationship: String,
        isPrimary: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.remoteID = remoteID
        self.displayName = displayName
        self.relationship = relationship
        self.isPrimary = isPrimary
        self.updatedAt = updatedAt
    }
}
