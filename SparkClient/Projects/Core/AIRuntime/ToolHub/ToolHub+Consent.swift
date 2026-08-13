import Foundation

// ToolHub extension: Apple Health model egress consent before returning tool results to the LLM.

extension ToolHub {
    func applyModelEgressConsentIfNeeded(
        invocation: ToolInvocation,
        context: ToolExecutionContext,
        result: ToolExecutionResult
    ) async -> ToolExecutionResult {
        let snapshot = await aiConfigCenter.currentSnapshot()
        let resolution = toolModelEgressConsentPolicy.evaluate(
            result: result,
            providerCompany: context.providerCompany,
            snapshot: snapshot
        )

        switch resolution {
        case .allowWithoutPrompt:
            await aiConfigCenter.recordToolModelEgressUsage(
                toolName: result.toolName,
                providerCompany: context.providerCompany,
                modelName: context.modelName
            )
            return result
        case .deny(let reason):
            return modelEgressDeniedResult(
                toolName: result.toolName,
                reason: reason
            )
        case .askEveryTime:
            break
        }

        guard let toolInteractionCoordinator else {
            return modelEgressDeniedResult(
                toolName: result.toolName,
                reason: L10n.text(
                    "ai_settings.tool_consent.runtime.no_consent_ui",
                    fallback: "当前界面无法展示授权弹窗，已阻止敏感工具结果发送给模型。"
                )
            )
        }

        let callArguments = encodeJSON(invocation.arguments) ?? invocation.arguments.description
        let decision = await toolInteractionCoordinator.requestConsentDecision(
            threadID: context.threadID,
            result: result,
            callArguments: callArguments,
            providerCompany: context.providerCompany,
            modelName: context.modelName,
            endpoint: context.endpoint,
            privacyPolicyURL: context.privacyPolicyURL,
            toolCallID: context.pendingToolCallID
        )
        switch decision {
        case .success(let decision):
            guard decision.allowed else {
                return modelEgressDeniedResult(
                    toolName: result.toolName,
                    reason: L10n.text(
                        "ai_settings.tool_consent.runtime.user_denied",
                        fallback: "用户未授权将该工具结果发送给第三方模型。"
                    )
                )
            }
            if decision.rememberTool {
                await aiConfigCenter.updateToolModelEgressConsentMode(
                    .alwaysAllow,
                    for: result.toolName
                )
            }
            await aiConfigCenter.recordToolModelEgressUsage(
                toolName: result.toolName,
                providerCompany: context.providerCompany,
                modelName: context.modelName
            )
            return result
        case .cancelled:
            return modelEgressDeniedResult(
                toolName: result.toolName,
                reason: L10n.text(
                    "ai_settings.tool_consent.runtime.user_denied",
                    fallback: "用户未授权将该工具结果发送给第三方模型。"
                )
            )
        case .conflict:
            return modelEgressDeniedResult(
                toolName: result.toolName,
                reason: L10n.text(
                    "ai_settings.tool_consent.runtime.interaction_busy",
                    fallback: "授权交互繁忙，已阻止敏感工具结果发送给模型。"
                )
            )
        }
    }

    func modelEgressDeniedResult(toolName: String, reason: String) -> ToolExecutionResult {
        ToolExecutionResult(
            toolName: toolName,
            outputText: PromptLocalizer().consentBlockedHint(reason: reason),
            sensitive: false,
            shouldBypassModel: true
        )
    }
}
