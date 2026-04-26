import Foundation

struct ChatSmallTaskMessageCardPayload: Codable, Equatable, Sendable {
    var sourceID: Int
    var code: String
    var name: String
    var brief: String
    var icon: String
    var source: TaskSource

    enum CodingKeys: String, CodingKey {
        case sourceID = "source_id"
        case code
        case name
        case brief
        case icon
        case source
    }

    init(task: SmallTask) {
        sourceID = task.sourceID
        code = task.id
        name = task.name
        brief = task.brief
        icon = task.icon
        source = task.source
    }

    var displayIcon: String {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "checklist" : trimmed
    }

    var displayBrief: String {
        brief.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func encodedString() -> String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
