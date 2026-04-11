import Foundation

/// 模型推理「最终输出」的统一日志入口，仅由 `AIRuntimeService` 在每次成功返回后调用。
enum AIRuntimeOutputLog: Sendable {
    nonisolated static func recordFinalModelOutput(
        scenario: AIScenario,
        inferenceSource: String,
        response: AIRuntimeTextResponse,
        logger: Logger
    ) {
        let finish = response.finishReason ?? "-"
        let textLen = response.text.count
        let snippet = LogMessageSanitizer.singleLineSnippet(response.text,limit: 3000)
        let message = "AI输出 scenario=\(scenario.rawValue) source=\(inferenceSource) model=\(response.model) finish=\(finish) textLen=\(textLen) preview=\(snippet)"
        logger.debug(message, module: .aiConfig)
    }
}
