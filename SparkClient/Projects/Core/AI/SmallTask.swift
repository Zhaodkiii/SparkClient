import Foundation

enum TaskSource: String, Codable, Sendable {
    case local = "Local"
    case service = "Service"
}

struct SmallTask: Codable, Identifiable, Equatable, Sendable {
    var sourceID: Int
    var name: String
    var code: String
    var brief: String
    var prompt: String
    var icon: String
    var toolList: [String]
    var source: TaskSource

    var id: String {
        code.isEmpty ? "\(source.rawValue)_\(sourceID)" : code
    }

    enum CodingKeys: String, CodingKey {
        case sourceID = "id"
        case name, code, brief, prompt, icon, source
        case toolList = "tool_list"
    }

    init(
        sourceID: Int,
        name: String,
        code: String,
        brief: String,
        prompt: String,
        icon: String,
        toolList: [String],
        source: TaskSource
    ) {
        self.sourceID = sourceID
        self.name = name
        self.code = code
        self.brief = brief
        self.prompt = prompt
        self.icon = icon
        self.toolList = toolList
        self.source = source
    }

    static func createLocalTask(
        id: Int,
        name: String,
        brief: String,
        prompt: String,
        icon: String,
        toolList: [String]
    ) -> SmallTask {
        SmallTask(
            sourceID: id,
            name: name,
            code: "Local_\(id)",
            brief: brief,
            prompt: prompt,
            icon: icon,
            toolList: toolList,
            source: .local
        )
    }
}
