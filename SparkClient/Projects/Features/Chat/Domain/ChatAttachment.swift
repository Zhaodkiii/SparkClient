import Foundation

struct ChatAttachment: Codable, Equatable, Sendable {
    let id: UUID
    let type: String
    let url: URL?
    let text: String?

    init(
        id: UUID = UUID(),
        type: String,
        url: URL? = nil,
        text: String? = nil
    ) {
        self.id = id
        self.type = type
        self.url = url
        self.text = text
    }
}
