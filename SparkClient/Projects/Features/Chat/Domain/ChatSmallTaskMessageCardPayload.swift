import Foundation

struct ChatSmallTaskMessageCardPayload: Codable, Equatable, Sendable {
    var id: Int
    var code: String
    var name: String
    var brief: String
    var icon: String
    var source: TaskSource


    init(task: SmallTask) {
        id = task.id
        code = task.code
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
        let encoder = JSONEncoder.default
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
