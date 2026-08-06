import Foundation

struct DeepTutorMessageBranchInfo: Equatable, Sendable {
    let index: Int
    let count: Int
    let parentMessageID: UUID
}

struct DeepTutorMessageRowModel: Equatable, Identifiable, Sendable {
    let id: UUID
    let conversationID: UUID
    let message: DeepTutorMessage
    let branchInfo: DeepTutorMessageBranchInfo?
    let isStreamingTail: Bool
    let renderSignature: Int
}

struct DeepTutorMessageRowActions {
    var onCopy: (UUID) -> Void
    var onEdit: (UUID, String) -> Void
    var onRetry: (UUID) -> Void
    var onSelectBranch: (UUID, Int) -> Void
    var onSubmitAskUser: (UUID, String, [DeepTutorAskUserAnswer]) -> Void
    var onSubmitMemberSelection: (UUID, String, Int) -> Void
    var onQuizFollowUp: (String) -> Void
    var onQuizJudge: (DeepTutorQuizQuestion, String) async -> String?
    var onQuizInlineInputFocusChanged: (Bool) -> Void
}

enum DeepTutorMessageRowModelBuilder: Sendable {
    static func makeRenderSignature(message: DeepTutorMessage) -> Int {
        var hasher = Hasher()
        hasher.combine(message.id)
        hasher.combine(message.status)
        hasher.combine(message.content)
        hasher.combine(message.capability.rawValue)
        for block in message.blocks {
            hasher.combine(block.id)
            hasher.combine(block.kind.rawValue)
            switch block.payload {
            case .trace(let payload):
                hasher.combine(payload.isFinalAnswerPhase)
                hasher.combine(payload.isStreaming)
                hasher.combine(payload.title)
                hasher.combine(payload.elapsedSeconds)
                for row in payload.rows {
                    hasher.combine(row.id)
                    hasher.combine(row.kind.rawValue)
                    hasher.combine(row.verb)
                    hasher.combine(row.chip)
                    hasher.combine(row.status.rawValue)
                    hasher.combine(row.resultDetail)
                }
            case .askUser(let payload):
                hasher.combine(payload.toolCallID)
                hasher.combine(payload.isResolved)
                hasher.combine(payload.payload.questions.count)
                hasher.combine(payload.answers.count)
            case .memberSelection(let payload):
                hasher.combine(payload.toolCallID)
                hasher.combine(payload.status.rawValue)
                hasher.combine(payload.selectedMemberID)
                hasher.combine(payload.reason)
            case .quiz(let payload):
                hasher.combine(payload.turnID)
                hasher.combine(payload.questions.count)
            case .quizParseError(let payload):
                hasher.combine(payload.reason)
                hasher.combine(payload.messageID)
            case .text(let text):
                hasher.combine(text)
            case .thinking(let text):
                hasher.combine(text)
            case .error(let text):
                hasher.combine(text)
            case .researchOutline(let payload):
                hasher.combine(payload.title)
                hasher.combine(payload.sections.count)
            case .visualization(let payload):
                hasher.combine(payload.title)
                hasher.combine(payload.snapshotDescription)
            case .generatedFile(let payload):
                hasher.combine(payload.filename)
            case .envelope:
                break
            }
        }
        return hasher.finalize()
    }
}
