import Foundation

enum ChatSwiftUIConversationLayoutConstants {
    static let loadMoreRowID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F1")!
    static let bottomAnchorID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F2")!
}

struct ChatSwiftUIMessageRenderSignature: Equatable, Sendable {
    let blockIDs: [UUID]
    let blockRevisions: [Int64]
    let deliveryStateRaw: String
    let isTombstone: Bool
    let textLength: Int
    let toolBlockCount: Int

    static func make(message: ChatMessage) -> ChatSwiftUIMessageRenderSignature {
        let texts = message.blocks.compactMap(\.text).joined()
        return ChatSwiftUIMessageRenderSignature(
            blockIDs: message.blocks.map(\.id),
            blockRevisions: message.blocks.map(\.revision),
            deliveryStateRaw: message.deliveryState.rawValue,
            isTombstone: message.isTombstone,
            textLength: texts.count,
            toolBlockCount: message.blocks.filter { $0.kind == .tool }.count
        )
    }
}

struct ChatSwiftUIStreamingState: Equatable, Sendable {
    var isStreaming: Bool
    var textCharacterCount: Int
    var toolBlockCount: Int
    var blockRevisionTotal: Int64

    static let idle = ChatSwiftUIStreamingState(
        isStreaming: false,
        textCharacterCount: 0,
        toolBlockCount: 0,
        blockRevisionTotal: 0
    )
}

struct ChatSwiftUIMessageRowModel: Identifiable, Equatable, Sendable {
    let id: UUID
    let message: ChatMessage
    let renderSignature: ChatSwiftUIMessageRenderSignature
    let streamingState: ChatSwiftUIStreamingState

    init(message: ChatMessage, streamingState: ChatSwiftUIStreamingState) {
        id = message.clientMessageID
        self.message = message
        renderSignature = ChatSwiftUIMessageRenderSignature.make(message: message)
        self.streamingState = streamingState
    }
}

struct ChatSwiftUIConversationFrame: Equatable, Sendable {
    let threadID: UUID
    let rows: [ChatSwiftUIMessageRowModel]
    let visibleMessages: [ChatMessage]
    let hasMoreMessages: Bool
    let isLoadingMoreMessages: Bool
    let lockBottomViewport: Bool
    let scrollToBottomRequestGeneration: UInt64
    let contentSignature: String
    let generation: UInt64

    static let empty = ChatSwiftUIConversationFrame(
        threadID: UUID(uuidString: "00000000-0000-0000-0000-0000000000F0")!,
        rows: [],
        visibleMessages: [],
        hasMoreMessages: false,
        isLoadingMoreMessages: false,
        lockBottomViewport: false,
        scrollToBottomRequestGeneration: 0,
        contentSignature: "",
        generation: 0
    )
}

enum ChatSwiftUIFramePriority: Equatable, Sendable {
    case immediate
    case nextFrame
}

enum ChatSwiftUIConversationFrameBuilder {
    static func make(
        threadID: UUID,
        visibleMessages: [ChatMessage],
        hasMoreMessages: Bool,
        isLoadingMoreMessages: Bool,
        lockBottomViewport: Bool,
        scrollToBottomRequestGeneration: UInt64,
        streamingStates: [UUID: ChatSwiftUIStreamingState]
    ) -> ChatSwiftUIConversationFrame {
        let rows = visibleMessages.map { message in
            ChatSwiftUIMessageRowModel(
                message: message,
                streamingState: streamingStates[message.clientMessageID] ?? .idle
            )
        }
        let contentSignature = makeContentSignature(
            rows: rows,
            hasMoreMessages: hasMoreMessages,
            isLoadingMoreMessages: isLoadingMoreMessages
        )
        return ChatSwiftUIConversationFrame(
            threadID: threadID,
            rows: rows,
            visibleMessages: visibleMessages,
            hasMoreMessages: hasMoreMessages,
            isLoadingMoreMessages: isLoadingMoreMessages,
            lockBottomViewport: lockBottomViewport,
            scrollToBottomRequestGeneration: scrollToBottomRequestGeneration,
            contentSignature: contentSignature,
            generation: makeGeneration(signature: contentSignature)
        )
    }

    static func priority(previous: ChatSwiftUIConversationFrame, next: ChatSwiftUIConversationFrame) -> ChatSwiftUIFramePriority {
        guard previous.rows.map(\.id) == next.rows.map(\.id),
              previous.hasMoreMessages == next.hasMoreMessages
        else {
            return .immediate
        }
        let streamingChanged = zip(previous.rows, next.rows).contains { old, new in
            old.streamingState != new.streamingState
        }
        return streamingChanged ? .nextFrame : .immediate
    }

    private static func makeContentSignature(
        rows: [ChatSwiftUIMessageRowModel],
        hasMoreMessages: Bool,
        isLoadingMoreMessages: Bool
    ) -> String {
        let rowSignature = rows.map { row in
            let revisions = row.renderSignature.blockRevisions.map(String.init).joined(separator: ",")
            return "\(row.id.uuidString):\(revisions):\(row.renderSignature.deliveryStateRaw):\(row.renderSignature.textLength):\(row.renderSignature.toolBlockCount)"
        }.joined(separator: ";")
        return "\(rowSignature)|more=\(hasMoreMessages ? 1 : 0)|loading=\(isLoadingMoreMessages ? 1 : 0)"
    }

    private static func makeGeneration(signature: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in signature.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}
