import SwiftUI

struct DeepTutorAssistantBubble: View {
    let message: DeepTutorMessage
    let members: [Member]
    let onCopy: () -> Void
    let onRetry: () -> Void
    let onDelete: (() -> Void)?
    let onSubmitAskUser: (String, [DeepTutorAskUserAnswer]) -> Void
    let onSubmitMemberSelection: (String, Int) -> Void
    let onQuizFollowUp: (String) -> Void
    let onQuizJudge: (DeepTutorQuizQuestion, String) async -> String?
    let onQuizInlineInputFocusChanged: (Bool) -> Void

    init(
        message: DeepTutorMessage,
        members: [Member],
        onCopy: @escaping () -> Void,
        onRetry: @escaping () -> Void,
        onDelete: (() -> Void)? = nil,
        onSubmitAskUser: @escaping (String, [DeepTutorAskUserAnswer]) -> Void,
        onSubmitMemberSelection: @escaping (String, Int) -> Void,
        onQuizFollowUp: @escaping (String) -> Void = { _ in },
        onQuizJudge: @escaping (DeepTutorQuizQuestion, String) async -> String? = { _, _ in nil },
        onQuizInlineInputFocusChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.message = message
        self.members = members
        self.onCopy = onCopy
        self.onRetry = onRetry
        self.onDelete = onDelete
        self.onSubmitAskUser = onSubmitAskUser
        self.onSubmitMemberSelection = onSubmitMemberSelection
        self.onQuizFollowUp = onQuizFollowUp
        self.onQuizJudge = onQuizJudge
        self.onQuizInlineInputFocusChanged = onQuizInlineInputFocusChanged
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(displayBlocks) { block in
                blockView(block)
            }

            if message.status == .ready {
                actionsRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayBlocks: [DeepTutorMessageBlock] {
        message.blocks.filter { $0.kind != .envelope }
    }

    @ViewBuilder
    private func blockView(_ block: DeepTutorMessageBlock) -> some View {
        switch block.payload {
        case .trace(let payload):
            DeepTutorTracePanelView(messageID: message.id, payload: payload)
        case .askUser(let payload):
            DeepTutorAskUserCardView(payload: payload) { answers in
                onSubmitAskUser(payload.toolCallID, answers)
            }
        case .memberSelection(let payload):
            DeepTutorMemberSelectionCardView(payload: payload, members: members) { memberID in
                onSubmitMemberSelection(payload.toolCallID, memberID)
            }
        case .researchOutline(let payload):
            DeepTutorResearchOutlineCardView(payload: payload)
        case .quiz(let payload):
            DeepTutorQuizCardView(
                conversationID: message.conversationID,
                messageID: message.id,
                payload: payload,
                onFollowUp: onQuizFollowUp,
                onJudge: onQuizJudge,
                onInlineInputFocusChanged: onQuizInlineInputFocusChanged
            )
        case .quizParseError(let payload):
            DeepTutorQuizParseErrorCardView(payload: payload, onRegenerate: onRetry)
        case .visualization(let payload):
            DeepTutorVisualizationPlaceholderView(payload: payload)
        case .generatedFile(let payload):
            DeepTutorGeneratedFileCardView(payload: payload)
        case .thinking(let text):
            DeepTutorThinkingCardView(text: text)
        case .text(let text):
            DeepTutorMarkdownRenderer(markdown: text)
        case .error(let text):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 8) {
                    Text(text)
                        .font(.subheadline)
                    Button("Retry", action: onRetry)
                        .buttonStyle(.bordered)
                }
            }
            .padding(12)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .envelope:
            EmptyView()
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 14) {
            actionButton(systemName: "doc.on.doc", action: onCopy)
            actionButton(systemName: "arrow.clockwise", action: onRetry)
            if let onDelete {
                actionButton(systemName: "trash", action: onDelete)
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)
        .opacity(0.85)
    }

    private func actionButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 28, height: 28)
                .background(Color(.tertiarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
    }
}
