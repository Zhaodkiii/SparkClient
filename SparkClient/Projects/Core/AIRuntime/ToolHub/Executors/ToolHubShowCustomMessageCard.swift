import Foundation

extension ToolHub {
    func runShowCustomMessageCard(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let cardType = (invocation.arguments["card_type"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hint = cardType.isEmpty ? "" : "（\(cardType)）"
        let outputText = "已展示上传/拍照卡片入口\(hint)，请继续引导用户上传材料。"
        SparkLogger.log(
            level: .info,
            module: .general,
            message: "[CHAT-000017][ToolHub] show_custom_message_card enter cardType=\(cardType) thread=\(context.threadID?.uuidString ?? "-") assistant=\(context.assistantMessageClientID?.uuidString ?? "-") toolCall=\(context.pendingToolCallID ?? "-") hasCoordinator=\(toolInteractionCoordinator != nil)"
        )

        guard let type = ChatCaptureCardType(rawValue: cardType) else {
            SparkLogger.log(
                level: .warning,
                module: .general,
                message: "[CHAT-000017][ToolHub] invalid cardType=\(cardType)"
            )
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: "show_custom_message_card 参数无效：card_type 必须是 report_photo、medicine_box_photo 或 skin_photo。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        guard let toolInteractionCoordinator else {
            let payload = ChatCaptureMessageCardPayload(cardType: type)
            SparkLogger.log(
                level: .warning,
                module: .general,
                message: "[CHAT-000017][ToolHub] fallback sideEffect captureCard card=\(payload.id.uuidString) type=\(type.rawValue)"
            )
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: outputText,
                sensitive: false,
                shouldBypassModel: true,
                sideEffects: [.captureCard(payload)]
            )
        }

        let prompt = ToolAttachmentCapturePrompt(cardType: type)
        let result = await toolInteractionCoordinator.requestAttachmentCapture(
            threadID: context.threadID,
            prompt: prompt,
            toolCallID: context.pendingToolCallID
        )

        switch result {
        case .success(let capture):
            SparkLogger.log(
                level: .info,
                module: .general,
                message: "[CHAT-000017][ToolHub] attachment capture success type=\(capture.cardType.rawValue) count=\(capture.attachments.count) contextChars=\(capture.modelContextText.count)"
            )
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: capture.modelContextText,
                sensitive: true,
                shouldBypassModel: true
            )
        case .cancelled, .conflict:
            SparkLogger.log(
                level: .warning,
                module: .general,
                message: "[CHAT-000017][ToolHub] attachment capture not completed result=\(String(describing: result)) type=\(type.rawValue)"
            )
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: "【系统】用户取消或未完成材料上传。请继续当前对话，必要时用自然语言重新引导用户上传材料。",
                sensitive: false,
                shouldBypassModel: true,
                isAwaitingUserInput: true
            )
        }
    }


}
