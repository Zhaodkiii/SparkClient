import Foundation

nonisolated struct ChatEventPayload: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let type: String
    let title: String
    let dateText: String?
    let location: String?
    let notes: String?

    init(
        id: UUID = UUID(),
        type: String,
        title: String,
        dateText: String? = nil,
        location: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.dateText = dateText
        self.location = location
        self.notes = notes
    }
}
