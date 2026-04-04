import Foundation

enum ConsentDestination: Sendable {
    case model
    case user
}

struct ConsentDecision: Sendable {
    let allowed: Bool
    let reason: String?
}

struct ConsentGate {
    func evaluate(result: ToolExecutionResult, destination: ConsentDestination) -> ConsentDecision {
        switch destination {
        case .user:
            return ConsentDecision(allowed: true, reason: nil)
        case .model:
            if result.sensitive {
                return ConsentDecision(
                    allowed: false,
                    reason: "检测到敏感医疗信息，默认不自动上传到第三方模型。"
                )
            }
            return ConsentDecision(allowed: true, reason: nil)
        }
    }
}

