import Foundation

enum DeepTutorToolInteractionResult<Value: Sendable>: Sendable {
    case success(Value)
    case cancelled
}

struct DeepTutorToolPreviewAction: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let systemImage: String?

    init(id: String? = nil, title: String, systemImage: String? = nil) {
        self.id = id ?? "\(title)|\(systemImage ?? "-")"
        self.title = title
        self.systemImage = systemImage
    }
}

struct DeepTutorToolPreviewRelatedContent: Equatable, Sendable, Identifiable {
    let id: String
    let kindLabel: String
    let title: String
    let subtitle: String?
    let body: String?
    let badges: [String]
    let actions: [DeepTutorToolPreviewAction]
}

struct DeepTutorToolPreviewPrompt: Equatable, Sendable, Identifiable {
    let id: UUID
    let conversationID: UUID?
    let messageID: UUID?
    let toolCallID: String?
    let toolName: String
    let displayTitle: String
    let arguments: String?
    let output: String?
    let outputIsMarkdown: Bool
    let metadata: [String: String]
    let relatedContent: [DeepTutorToolPreviewRelatedContent]

    init(
        id: UUID = UUID(),
        conversationID: UUID?,
        messageID: UUID?,
        toolCallID: String?,
        toolName: String,
        displayTitle: String,
        arguments: String?,
        output: String?,
        outputIsMarkdown: Bool,
        metadata: [String: String] = [:],
        relatedContent: [DeepTutorToolPreviewRelatedContent] = []
    ) {
        self.id = id
        self.conversationID = conversationID
        self.messageID = messageID
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.displayTitle = displayTitle
        self.arguments = arguments
        self.output = output
        self.outputIsMarkdown = outputIsMarkdown
        self.metadata = metadata
        self.relatedContent = relatedContent
    }
}
