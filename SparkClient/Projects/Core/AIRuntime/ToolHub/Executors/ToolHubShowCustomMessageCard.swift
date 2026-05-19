import Foundation

extension ToolHub {
    func runShowCustomMessageCard(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let cardType = (invocation.arguments["card_type"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hint = cardType.isEmpty ? "" : "（\(cardType)）"
        let outputText = "已展示上传/拍照卡片入口\(hint)，请继续引导用户上传材料。"

        guard let type = ChatCaptureCardType(rawValue: cardType),
              let threadID = context.threadID,
              let assistantID = context.assistantMessageClientID else {
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: outputText,
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let payload = ChatCaptureMessageCardPayload(cardType: type)
        let merge = structuredHealthCardMergeCoordinator
        Task {
            await merge.insertCaptureCardWhenAssistantMessageReady(
                threadID: threadID,
                assistantClientMessageID: assistantID,
                payload: payload
            )
        }

        return ToolExecutionResult(
            toolName: invocation.name,
            outputText: outputText,
            sensitive: false,
            shouldBypassModel: true
        )
    }


}
