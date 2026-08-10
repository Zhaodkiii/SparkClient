import Combine
import Foundation

@MainActor
final class ChatSwiftUIStreamEventBuffer: ObservableObject {
    private var previousSignatures: [UUID: ChatSwiftUIMessageRenderSignature] = [:]
    private var states: [UUID: ChatSwiftUIStreamingState] = [:]

    func ingest(messages: [ChatMessage]) -> [UUID: ChatSwiftUIStreamingState] {
        var nextSignatures: [UUID: ChatSwiftUIMessageRenderSignature] = [:]
        var nextStates: [UUID: ChatSwiftUIStreamingState] = [:]

        for message in messages {
            let id = message.clientMessageID
            let signature = ChatSwiftUIMessageRenderSignature.make(message: message)
            nextSignatures[id] = signature

            let textCharacterCount = message.blocks.compactMap(\.text).joined().count
            let toolBlockCount = message.blocks.filter { $0.kind == .tool }.count
            let blockRevisionTotal = message.blocks.reduce(Int64(0)) { $0 + $1.revision }
            let oldSignature = previousSignatures[id]
            let isStreaming = message.deliveryState == .sending
                || oldSignature?.textLength != signature.textLength
                || oldSignature?.blockRevisions != signature.blockRevisions

            nextStates[id] = ChatSwiftUIStreamingState(
                isStreaming: isStreaming,
                textCharacterCount: textCharacterCount,
                toolBlockCount: toolBlockCount,
                blockRevisionTotal: blockRevisionTotal
            )
        }

        previousSignatures = nextSignatures
        states = nextStates
        return nextStates
    }

    func reset() {
        previousSignatures = [:]
        states = [:]
    }
}

@MainActor
final class ChatSwiftUIFrameScheduler: ObservableObject {
    @Published private(set) var frame: ChatSwiftUIConversationFrame = .empty

    private var pendingTask: Task<Void, Never>?
    private var queuedFrame: ChatSwiftUIConversationFrame?

    deinit {
        pendingTask?.cancel()
    }

    func reset(to frame: ChatSwiftUIConversationFrame = .empty) {
        pendingTask?.cancel()
        pendingTask = nil
        queuedFrame = nil
        self.frame = frame
    }

    func submit(_ nextFrame: ChatSwiftUIConversationFrame, priority: ChatSwiftUIFramePriority) {
        guard nextFrame != frame else { return }

        switch priority {
        case .immediate:
            pendingTask?.cancel()
            pendingTask = nil
            queuedFrame = nil
            frame = nextFrame
        case .nextFrame:
            queuedFrame = nextFrame
            guard pendingTask == nil else { return }
            pendingTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 16_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    if let queuedFrame = self.queuedFrame {
                        self.frame = queuedFrame
                    }
                    self.queuedFrame = nil
                    self.pendingTask = nil
                }
            }
        }
    }
}
