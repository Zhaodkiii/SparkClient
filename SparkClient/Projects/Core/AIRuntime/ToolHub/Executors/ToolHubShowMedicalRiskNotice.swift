import Foundation

extension ToolHub {
    func runShowMedicalRiskNotice(invocation: ToolInvocation, context: ToolExecutionContext) -> ToolExecutionResult {
        guard let riskLevel = parseMedicalRiskLevel(invocation.arguments["risk_level"]) else {
            return ToolExecutionResult(
                toolName: SparkToolName.showMedicalRiskNotice,
                outputText: L10n.text(
                    "tool.error.medical_risk_notice.invalid_level",
                    fallback: "无效的风险等级，请使用 low、medium、high 或 emergency。"
                ),
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let title = trimmedOptional(invocation.arguments["title"])
        let message = trimmedOptional(invocation.arguments["message"])
            ?? defaultMedicalRiskMessage(for: riskLevel)
        let recommendedAction = trimmedOptional(invocation.arguments["recommended_action"])
        let relatedReason = trimmedOptional(invocation.arguments["related_reason"])

        let payload = ChatMedicalRiskNoticePayload(
            riskLevel: riskLevel,
            title: title,
            message: message,
            recommendedAction: recommendedAction,
            relatedReason: relatedReason
        )

        var sideEffects: [ToolSideEffect] = []
        if context.threadID != nil, context.assistantMessageClientID != nil {
            sideEffects = [.medicalRiskNotice(payload)]
        }

        return ToolExecutionResult(
            toolName: SparkToolName.showMedicalRiskNotice,
            outputText: L10n.text(
                "tool.result.medical_risk_notice.inserted",
                fallback: "医疗风险提示卡片已插入消息。"
            ),
            sensitive: false,
            shouldBypassModel: true,
            sideEffects: sideEffects
        )
    }

    private func parseMedicalRiskLevel(_ raw: String?) -> ChatMedicalRiskLevel? {
        guard let raw = trimmedOptional(raw)?.lowercased() else { return nil }
        return ChatMedicalRiskLevel(rawValue: raw)
    }

    private func trimmedOptional(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func defaultMedicalRiskMessage(for level: ChatMedicalRiskLevel) -> String {
        switch level {
        case .emergency, .high:
            return L10n.text("chat.medical_risk_notice.message.emergency_fallback")
        default:
            return L10n.text("chat.medical_risk_notice.message.default")
        }
    }
}
