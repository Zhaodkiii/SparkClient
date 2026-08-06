import Foundation

/// 保留 Markdown 原文用于正文渲染，与会话 preview 的 plain text 分离。
enum DeepTutorMarkdownPreserver: Sendable {
    nonisolated static func consolidatedContent(
        events: [DeepTutorStreamEvent],
        runtimeAnswer: String
    ) -> String {
        let fromEvents = events.compactMap { event -> String? in
            if case let .contentDelta(text, _, _) = event { return text }
            return nil
        }.joined()

        if fromEvents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return DeepTutorContentSanitizer.stripLeadingInternalThinking(from: fromEvents)
        }
        return DeepTutorContentSanitizer.stripLeadingInternalThinking(from: runtimeAnswer)
    }

    nonisolated static func renderMarkdownText(from message: DeepTutorMessage) -> String {
        let fromEvents = consolidatedContent(events: message.events, runtimeAnswer: message.content)
        let fromRouter = DeepTutorContentRouter.finalAnswerContent(from: message)
        return fidelityScore(fromEvents) >= fidelityScore(fromRouter) ? fromEvents : fromRouter
    }

    nonisolated static func plainPreviewText(from message: DeepTutorMessage, limit: Int = 120) -> String {
        let markdown = renderMarkdownText(from: message)
        let collapsed = markdown
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)) + "…"
    }

    nonisolated static func fidelityScore(_ message: DeepTutorMessage) -> Int {
        fidelityScore(renderMarkdownText(from: message))
    }

    nonisolated static func fidelityScore(_ text: String) -> Int {
        var score = text.count
        score += text.filter { $0 == "\n" }.count * 10
        score += text.filter { $0 == "|" }.count * 5
        if text.contains("##") { score += 50 }
        if text.contains("\n|") || text.contains("|\n") { score += 30 }
        return score
    }

    nonisolated static func markdownPreserved(db: DeepTutorMessage, memory: DeepTutorMessage) -> Bool {
        fidelityScore(memory) >= fidelityScore(db)
    }
}
