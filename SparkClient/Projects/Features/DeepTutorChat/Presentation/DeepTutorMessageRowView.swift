import SwiftUI

struct DeepTutorMessageRowView: View {
    let model: DeepTutorMessageRowModel
    let actions: DeepTutorMessageRowActions
    let members: [Member]
    let fileTransferService: FileTransferService?

    private var bubbleMaxWidth: CGFloat {
        DeepTutorPalette.bubbleMaxWidth(for: UIScreen.main.bounds.width)
    }

    var body: some View {
        let message = model.message
        HStack {
            if message.role == .user {
                Spacer(minLength: 40)
                DeepTutorUserBubble(
                    message: message,
                    fileTransferService: fileTransferService,
                    branchInfo: model.branchInfo.map { ($0.index, $0.count) },
                    onCopy: { actions.onCopy(message.id) },
                    onEdit: { actions.onEdit(message.id, $0) },
                    onSelectPreviousBranch: {
                        guard let info = model.branchInfo, info.index > 0 else { return }
                        actions.onSelectBranch(info.parentMessageID, info.index - 1)
                    },
                    onSelectNextBranch: {
                        guard let info = model.branchInfo, info.index < info.count - 1 else { return }
                        actions.onSelectBranch(info.parentMessageID, info.index + 1)
                    }
                )
                .frame(maxWidth: bubbleMaxWidth, alignment: .trailing)
            } else {
                DeepTutorAssistantBubble(
                    message: message,
                    members: members,
                    onCopy: { actions.onCopy(message.id) },
                    onRetry: { actions.onRetry(message.id) },
                    onSubmitAskUser: { toolCallID, answers in
                        actions.onSubmitAskUser(message.id, toolCallID, answers)
                    },
                    onSubmitMemberSelection: { toolCallID, memberID in
                        actions.onSubmitMemberSelection(message.id, toolCallID, memberID)
                    },
                    onCaptureCardAction: actions.onCaptureCardAction,
                    onToolPreview: actions.onToolPreview,
                    onQuizFollowUp: actions.onQuizFollowUp,
                    onQuizJudge: actions.onQuizJudge,
                    onQuizInlineInputFocusChanged: actions.onQuizInlineInputFocusChanged
                )
                .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
