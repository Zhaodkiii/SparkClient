import Foundation

/// Chat 行为用例协议：
/// View 只关心交互触发，不关心底层实现细节，便于测试与替换。
@MainActor
protocol ChatMessageActionUseCase {
    func translate(_ text: String, detailViewModel: ChatDetailViewModel) async throws -> String
    func saveMessageToKnowledge(content: String, detailViewModel: ChatDetailViewModel) async throws
    func saveKnowledgeCard(_ card: ChatKnowledgeCard, detailViewModel: ChatDetailViewModel) async throws
    func buildKnowledgePreviewCard(message: ChatMessage, metadata: ChatMessageMetadata) -> ChatKnowledgeCard
}

@MainActor
final class DefaultChatMessageActionUseCase: ChatMessageActionUseCase {
    private let taskManager: TaskManager
    private let logger: Logger

    init(taskManager: TaskManager, logger: Logger) {
        self.taskManager = taskManager
        self.logger = logger
    }

    func translate(_ text: String, detailViewModel: ChatDetailViewModel) async throws -> String {
        try await detailViewModel.translateMessageText(text)
    }

    func saveMessageToKnowledge(content: String, detailViewModel: ChatDetailViewModel) async throws {
        _ = try await detailViewModel.saveMessageAsKnowledge(
            content: content,
            suggestedTitle: nil
        )
    }

    func saveKnowledgeCard(_ card: ChatKnowledgeCard, detailViewModel: ChatDetailViewModel) async throws {
        _ = try await detailViewModel.saveKnowledgeCard(title: card.title, content: card.content)
    }

    /// 使用轻量本地规则先生成可预览知识卡，再由用户决定是否保存到知识库。
    func buildKnowledgePreviewCard(message: ChatMessage, metadata: ChatMessageMetadata) -> ChatKnowledgeCard {
        // 优先使用 block 中的工具输出；元数据聚合统一来自 blocks。
        let blockToolContent = message.blocks.last(where: { $0.kind == .tool })?.text ?? ""
        let toolContent = blockToolContent.isEmpty ? (metadata.toolContent ?? "") : blockToolContent
        let fallbackText = message.blocks
            .filter { $0.kind == .text || $0.kind == .error || $0.kind == .assistantStatusCard }
            .compactMap(\.text)
            .joined(separator: "\n")
        let primary = toolContent.isEmpty ? fallbackText : toolContent
        // 文本预处理：压缩空行、去首尾空白，避免卡片展示噪音。
        let normalized = primary
            .replacingOccurrences(of: "\n\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // 预览控制长度，避免气泡中出现超长卡片影响可读性。
        let previewBody = String(normalized.prefix(320))
        // 标题优先取首个非空行，再截断到固定长度；兜底走本地化默认标题。
        let titleSeed = normalized.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { $0.isEmpty == false }) ?? ""
        let title = titleSeed.isEmpty
            ? L10n.text("chat.bubble.knowledge.default_title")
            : String(titleSeed.prefix(20))
        return ChatKnowledgeCard(title: title, content: previewBody)
    }
}
