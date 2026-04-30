import Foundation

enum ConsentDestination: Sendable {
    case model
    case user
}

struct ConsentDecision: Sendable {
    let allowed: Bool
    let reason: String?
}

struct ConsentGate: Sendable {
    let toolInteractionCoordinator: ToolInteractionCoordinator?

    init(toolInteractionCoordinator: ToolInteractionCoordinator? = nil) {
        self.toolInteractionCoordinator = toolInteractionCoordinator
    }

    func evaluate(result: ToolExecutionResult, destination: ConsentDestination) -> ConsentDecision {
        switch destination {
        case .user:
            return ConsentDecision(allowed: true, reason: nil)
        case .model:
            if result.requiresModelConsent {
                return ConsentDecision(
                    allowed: false,
                    reason: "检测到可能包含个人或敏感信息的工具结果，默认不自动上传到第三方模型。"
                )
            }
            return ConsentDecision(allowed: true, reason: nil)
        }
    }

    func awaitModelConsent(
        result: ToolExecutionResult,
        callArguments: String,
        providerCompany: String?,
        modelName: String?,
        endpoint: String?,
        privacyPolicyURL: URL?,
        threadID: UUID? = nil
    ) async -> ConsentDecision {
        guard result.requiresModelConsent else {
            return ConsentDecision(allowed: true, reason: nil)
        }
        guard let toolInteractionCoordinator else {
            return evaluate(result: result, destination: .model)
        }
        let interaction = await toolInteractionCoordinator.requestConsentDecision(
            threadID: threadID,
            result: result,
            callArguments: callArguments,
            providerCompany: providerCompany,
            modelName: modelName,
            endpoint: endpoint,
            privacyPolicyURL: privacyPolicyURL
        )
        switch interaction {
        case .success(let allowed):
            return ConsentDecision(
                allowed: allowed,
                reason: allowed ? nil : "用户未授权将该工具结果发送给第三方模型。"
            )
        case .cancelled:
            return ConsentDecision(allowed: false, reason: "用户未授权将该工具结果发送给第三方模型。")
        case .conflict:
            return ConsentDecision(allowed: false, reason: "交互繁忙，请稍后重试。")
        }
    }
}
