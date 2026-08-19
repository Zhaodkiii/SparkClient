import Foundation

extension ToolHub {
    func runShowCustomMessageCard(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let cardType = (invocation.arguments["card_type"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hint = cardType.isEmpty ? "" : "（\(cardType)）"
        let outputText = "已展示上传/拍照卡片入口\(hint)，请继续引导用户上传材料。"

        guard let type = ChatCaptureCardType(rawValue: cardType) else {
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: "show_custom_message_card 参数无效：card_type 必须是 report_photo、medicine_box_photo 或 skin_photo。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        // upload_mode 可选：inline 消息内处理（默认，卡片内上传后续跑对话）；
        // composer 插入输入框（与历史插入卡片版本一致）——材料进入输入框预览区自动上传+OCR，
        // 随下一条消息发送，不在消息内处理、不阻塞本轮生成（无需等待 continuation）。
        let uploadModeRaw = (invocation.arguments["upload_mode"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let uploadMode = ChatCaptureUploadMode(rawValue: uploadModeRaw) ?? .inline
        if uploadMode == .composer {
            let payload = ChatCaptureMessageCardPayload(cardType: type, uploadMode: .composer)
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: "已展示上传/拍照卡片入口\(hint)，用户上传的材料将进入输入框，随下一条消息发送。请继续引导用户上传材料。",
                sensitive: false,
                shouldBypassModel: true,
                sideEffects: [.captureCard(payload)]
            )
        }

        guard let toolInteractionCoordinator else {
            let payload = ChatCaptureMessageCardPayload(cardType: type)
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
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: capture.modelContextText,
                sensitive: true,
                shouldBypassModel: true
            )
        case .cancelled, .conflict:
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
