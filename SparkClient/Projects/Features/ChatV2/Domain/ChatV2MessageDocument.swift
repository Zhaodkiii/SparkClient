import Foundation

enum ChatV2Role: String, Codable, Sendable {
    case system
    case user
    case assistant
}

enum ChatV2MessageStatus: String, Codable, Sendable {
    case draft
    case streaming
    case committed
    case failed
    case tombstoned
}

enum ChatV2ThreadStatus: String, Codable, Sendable {
    case active
    case archived
    case deleted
}

enum ChatV2Scenario: String, Codable, Sendable {
    case chat
}

struct ChatV2TextNode: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

struct ChatV2ToolStatusPayload: Codable, Equatable, Sendable {
    let toolCallID: String
    let toolName: String
    let state: String
    let description: String

    init(toolCallID: String, toolName: String, state: String, description: String) {
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.state = state
        self.description = description
    }
}

struct ChatV2KnowledgeCardPayload: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let content: String

    init(id: UUID = UUID(), title: String, content: String) {
        self.id = id
        self.title = title
        self.content = content
    }
}

struct ChatV2TaskCardPayload: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let summary: String
    let isCompleted: Bool

    init(id: UUID = UUID(), title: String, summary: String, isCompleted: Bool = false) {
        self.id = id
        self.title = title
        self.summary = summary
        self.isCompleted = isCompleted
    }
}

struct ChatV2MapLocationPayload: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double

    init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}

struct ChatV2MapRoutePayload: Codable, Equatable, Sendable {
    let locations: [ChatV2MapLocationPayload]
    let encodedPolyline: String?

    init(locations: [ChatV2MapLocationPayload], encodedPolyline: String? = nil) {
        self.locations = locations
        self.encodedPolyline = encodedPolyline
    }
}

struct ChatV2SleepStagePayload: Codable, Equatable, Identifiable, Sendable {
    enum Stage: String, Codable, Sendable {
        case awake
        case rem
        case core
        case deep
        case unspecified
    }

    let id: UUID
    let stage: Stage
    let startAt: Date
    let endAt: Date

    init(id: UUID = UUID(), stage: Stage, startAt: Date, endAt: Date) {
        self.id = id
        self.stage = stage
        self.startAt = startAt
        self.endAt = endAt
    }
}

struct ChatV2SleepVisualizationPayload: Codable, Equatable, Sendable {
    let day: Date
    let totalSleepMinutes: Int
    let deepSleepMinutes: Int
    let coreSleepMinutes: Int
    let remSleepMinutes: Int
    let awakeMinutes: Int
    let stages: [ChatV2SleepStagePayload]

    init(
        day: Date,
        totalSleepMinutes: Int,
        deepSleepMinutes: Int,
        coreSleepMinutes: Int,
        remSleepMinutes: Int,
        awakeMinutes: Int,
        stages: [ChatV2SleepStagePayload]
    ) {
        self.day = day
        self.totalSleepMinutes = totalSleepMinutes
        self.deepSleepMinutes = deepSleepMinutes
        self.coreSleepMinutes = coreSleepMinutes
        self.remSleepMinutes = remSleepMinutes
        self.awakeMinutes = awakeMinutes
        self.stages = stages
    }
}

struct ChatV2ErrorPayload: Codable, Equatable, Sendable {
    let title: String
    let message: String

    init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}

enum ChatV2BlockPayload: Codable, Equatable, Sendable {
    case toolStatus(ChatV2ToolStatusPayload)
    case sleepVisualization(ChatV2SleepVisualizationPayload)
    case knowledgeCards([ChatV2KnowledgeCardPayload])
    case taskCards([ChatV2TaskCardPayload])
    case mapRoute(ChatV2MapRoutePayload)
    case error(ChatV2ErrorPayload)

    private enum CodingKeys: String, CodingKey {
        case kind
        case toolStatus
        case sleepVisualization
        case knowledgeCards
        case taskCards
        case mapRoute
        case error
    }

    private enum Kind: String, Codable {
        case toolStatus
        case sleepVisualization
        case knowledgeCards
        case taskCards
        case mapRoute
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .toolStatus:
            self = .toolStatus(try container.decode(ChatV2ToolStatusPayload.self, forKey: .toolStatus))
        case .sleepVisualization:
            self = .sleepVisualization(try container.decode(ChatV2SleepVisualizationPayload.self, forKey: .sleepVisualization))
        case .knowledgeCards:
            self = .knowledgeCards(try container.decode([ChatV2KnowledgeCardPayload].self, forKey: .knowledgeCards))
        case .taskCards:
            self = .taskCards(try container.decode([ChatV2TaskCardPayload].self, forKey: .taskCards))
        case .mapRoute:
            self = .mapRoute(try container.decode(ChatV2MapRoutePayload.self, forKey: .mapRoute))
        case .error:
            self = .error(try container.decode(ChatV2ErrorPayload.self, forKey: .error))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .toolStatus(let payload):
            try container.encode(Kind.toolStatus, forKey: .kind)
            try container.encode(payload, forKey: .toolStatus)
        case .sleepVisualization(let payload):
            try container.encode(Kind.sleepVisualization, forKey: .kind)
            try container.encode(payload, forKey: .sleepVisualization)
        case .knowledgeCards(let payload):
            try container.encode(Kind.knowledgeCards, forKey: .kind)
            try container.encode(payload, forKey: .knowledgeCards)
        case .taskCards(let payload):
            try container.encode(Kind.taskCards, forKey: .kind)
            try container.encode(payload, forKey: .taskCards)
        case .mapRoute(let payload):
            try container.encode(Kind.mapRoute, forKey: .kind)
            try container.encode(payload, forKey: .mapRoute)
        case .error(let payload):
            try container.encode(Kind.error, forKey: .kind)
            try container.encode(payload, forKey: .error)
        }
    }
}

struct ChatV2BlockNode: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let payload: ChatV2BlockPayload
    let children: [ChatV2MessageNode]

    init(
        id: String,
        payload: ChatV2BlockPayload,
        children: [ChatV2MessageNode] = []
    ) {
        self.id = id
        self.payload = payload
        self.children = children
    }
}

enum ChatV2MessageNode: Codable, Equatable, Identifiable, Sendable {
    case text(ChatV2TextNode)
    case block(ChatV2BlockNode)

    var id: String {
        switch self {
        case .text(let node):
            return node.id.uuidString.lowercased()
        case .block(let node):
            return node.id
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case text
        case block
    }

    private enum Kind: String, Codable {
        case text
        case block
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .text:
            self = .text(try container.decode(ChatV2TextNode.self, forKey: .text))
        case .block:
            self = .block(try container.decode(ChatV2BlockNode.self, forKey: .block))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let node):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(node, forKey: .text)
        case .block(let node):
            try container.encode(Kind.block, forKey: .kind)
            try container.encode(node, forKey: .block)
        }
    }
}

struct ChatV2MessageDocument: Codable, Equatable, Sendable {
    var nodes: [ChatV2MessageNode]

    init(nodes: [ChatV2MessageNode] = []) {
        self.nodes = nodes
    }

    static let empty = ChatV2MessageDocument(nodes: [])
}
