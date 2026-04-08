import Foundation

/// 模型推理「最终输出」的统一日志入口，仅由 `AIRuntimeService` 在每次成功返回后调用，避免在聊天/抽取等各业务用例重复打印。
enum AIRuntimeOutputLog: Sendable {
    nonisolated static func recordFinalModelOutput(
        scenario: AIScenario,
        inferenceSource: String,
        response: AIRuntimeTextResponse,
        logger: Logger
    ) {
        let reasoning = response.reasoningText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let finish = response.finishReason ?? "-"
        var message = """
        AI 输出全文，scenario=\(scenario.rawValue), source=\(inferenceSource), model=\(response.model), finishReason=\(finish)
        ---text---
        \(response.text)
        """
        if reasoning.isEmpty == false {
            message += "\n---reasoning---\n\(reasoning)"
        }
        logger.debug(message, category: "ai_runtime")
    }
}
