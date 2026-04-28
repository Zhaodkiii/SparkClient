import Foundation

struct ChatV2StreamingToolState: Equatable, Identifiable, Sendable {
    let id: String
    let toolName: String
    let state: String
    let description: String

    init(id: String, toolName: String, state: String, description: String) {
        self.id = id
        self.toolName = toolName
        self.state = state
        self.description = description
    }
}

struct ChatV2StreamingMessageState: Equatable, Identifiable, Sendable {
    let id: UUID
    let threadID: UUID
    let role: ChatV2Role
    let startedAt: Date
    private(set) var document: ChatV2MessageDocument
    private(set) var transientToolStates: [ChatV2StreamingToolState]

    init(
        id: UUID = UUID(),
        threadID: UUID,
        role: ChatV2Role = .assistant,
        startedAt: Date = Date(),
        document: ChatV2MessageDocument = .empty,
        transientToolStates: [ChatV2StreamingToolState] = []
    ) {
        self.id = id
        self.threadID = threadID
        self.role = role
        self.startedAt = startedAt
        self.document = document
        self.transientToolStates = transientToolStates
    }

    mutating func appendText(_ chunk: String) {
        guard chunk.isEmpty == false else { return }
        if let lastIndex = document.nodes.indices.last,
           case .text(let textNode) = document.nodes[lastIndex] {
            document.nodes[lastIndex] = .text(
                ChatV2TextNode(id: textNode.id, text: textNode.text + chunk)
            )
        } else {
            document.nodes.append(.text(ChatV2TextNode(text: chunk)))
        }
    }

    mutating func appendBlock(id: String, payload: ChatV2BlockPayload) {
        removeTransientToolState(toolCallID: id)
        document.nodes.append(.block(ChatV2BlockNode(id: id, payload: payload)))
    }

    mutating func upsertToolState(_ state: ChatV2StreamingToolState) {
        if let index = transientToolStates.firstIndex(where: { $0.id == state.id }) {
            transientToolStates[index] = state
        } else {
            transientToolStates.append(state)
        }
    }

    mutating func removeTransientToolState(toolCallID: String) {
        transientToolStates.removeAll { $0.id == toolCallID }
    }

    func finalizedDocument(includeResidualToolStates: Bool = false) -> ChatV2MessageDocument {
        guard includeResidualToolStates else { return document }
        let toolNodes = transientToolStates.map { state in
            ChatV2MessageNode.block(
                ChatV2BlockNode(
                    id: state.id,
                    payload: .toolStatus(
                        ChatV2ToolStatusPayload(
                            toolCallID: state.id,
                            toolName: state.toolName,
                            state: state.state,
                            description: state.description
                        )
                    )
                )
            )
        }
        return ChatV2MessageDocument(nodes: document.nodes + toolNodes)
    }
}
