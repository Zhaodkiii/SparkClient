import Foundation

// ToolHub extension: Apple Health model egress consent before returning tool results to the LLM.

extension ToolHub {
    func applyModelEgressConsentIfNeeded(
        invocation: ToolInvocation,
        context: ToolExecutionContext,
        result: ToolExecutionResult
    ) async -> ToolExecutionResult {
        guard appleHealthToolConsentPolicy.requiresConsent(
            result: result,
            providerCompany: context.providerCompany
        ) else {
            return result
        }
        guard let toolInteractionCoordinator else {
            return modelEgressDeniedResult(
                toolName: result.toolName,
                reason: "当前界面无法展示授权弹窗，已阻止敏感工具结果发送给模型。"
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
            privacyPolicyURL: context.privacyPolicyURL
        )
        switch decision {
        case .success(let decision):
            guard decision.allowed else {
                return modelEgressDeniedResult(
                    toolName: result.toolName,
                    reason: "用户未授权将该工具结果发送给第三方模型。"
                )
            }
            if decision.rememberTool {
                appleHealthToolConsentPolicy.rememberAllowed(toolName: result.toolName)
            }
            return result
        case .cancelled:
            return modelEgressDeniedResult(
                toolName: result.toolName,
                reason: "用户未授权将该工具结果发送给第三方模型。"
            )
        case .conflict:
            return modelEgressDeniedResult(
                toolName: result.toolName,
                reason: "授权交互繁忙，已阻止敏感工具结果发送给模型。"
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
