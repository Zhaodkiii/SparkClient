import SwiftUI
import UIKit

/// 单条会话消息行（从 ``ChatView`` 抽出），供 `UICollectionView` + `UIHostingController` 复用。
struct ChatConversationMessageRow: View {
    let threadID: UUID
    let message: ChatMessage
    let visibleMessages: [ChatMessage]
    @ObservedObject var stateStore: ChatStateStore
    @ObservedObject var detailViewModel: ChatDetailViewModel
    @ObservedObject var uiStateStore: ChatMessageUIStateStore
    @ObservedObject var speechHelper: ChatSpeechHelper
    let actionState: ChatMessageActionState
    let taskManager: TaskManager
    let logger: Logger

    private var messageActionUseCase: any ChatMessageActionUseCase {
        DefaultChatMessageActionUseCase(taskManager: taskManager, logger: logger)
    }

    var body: some View {
        HStack {
            if message.role == .assistant || message.role == .system {
                bubbleContent
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 40)
                bubbleContent
            }
        }
        .padding(.trailing, 16)
    }

    private var bubbleContent: some View {
        let metadata = ChatMessageMetadata(message: message)
        return ChatMessageBubbleContentView(
            message: message,
            metadata: metadata,
            isLastAssistantMessage: isLastAssistantMessage(message),
            translatedText: translatedText(for: message, metadata: metadata),
            combinedKnowledgeCards: combinedKnowledgeCards(for: message, metadata: metadata),
            isMathMode: uiStateStore.isMathMode(message.id),
            isTranslating: uiStateStore.isTranslating(message.id),
            isSavingMessage: uiStateStore.isMessageSaving(message.id),
            isSavedMessage: uiStateStore.isMessageSaved(message.id),
            isSpeaking: speechHelper.isSpeaking(message.id),
            taskCardLoadingIDs: uiStateStore.taskCardLoadingIDs,
            ignoredTaskCardIDs: uiStateStore.ignoredTaskCardIDs,
            createdTaskCardIDs: uiStateStore.createdTaskCardIDs,
            savingKnowledgeCardIDs: uiStateStore.savingKnowledgeCardIDs,
            savedKnowledgeCardIDs: uiStateStore.savedKnowledgeCardIDs,
            showActions: message.id == visibleMessages.last?.id,
            onRetry: {
                Task {
                    await detailViewModel.retryFailedMessage(clientMessageID: message.clientMessageID)
                }
            },
            onCopy: {
                UIPasteboard.general.string = message.content
            },
            onDelete: {
                uiStateStore.markDeleted(message.id)
            },
            onToggleSpeech: {
                speechHelper.toggle(text: message.content, id: message.id)
            },
            onToggleTranslate: {
                toggleTranslate(message)
            },
            onOpenNetworkSearch: {
                openNetworkSearch(with: message.content)
            },
            onSaveMessageToKnowledge: {
                saveMessageToKnowledge(message)
            },
            onGenerateKnowledgeCardsPreview: {
                generateKnowledgeCardsPreview(for: message, metadata: metadata)
            },
            onSaveKnowledgeCard: { card in
                saveKnowledgeCard(card, from: message)
            },
            onConfirmTaskCard: { card in
                confirmTaskCard(card)
            },
            onIgnoreTaskCard: { card in
                ignoreTaskCard(card)
            },
            savingStructuredHealthCardIDs: detailViewModel.savingStructuredHealthCardIDs,
            onSaveMedicationCard: { card in
                Task {
                    await detailViewModel.saveMedicationStructuredCard(threadID: threadID, message: message, card: card)
                }
            },
            onSavePrescriptionCard: { card in
                Task {
                    await detailViewModel.savePrescriptionStructuredCard(threadID: threadID, message: message, card: card)
                }
            },
            onSaveExamReportCard: { card in
                Task {
                    await detailViewModel.saveExamReportStructuredCard(threadID: threadID, message: message, card: card)
                }
            },
            onSaveMedicalCaseCard: { card in
                Task {
                    await detailViewModel.saveMedicalCaseStructuredCard(threadID: threadID, message: message, card: card)
                }
            },
            onDownloadImageToLocalFile: { attachment in
                try await detailViewModel.downloadChatImageToLocalFile(attachment: attachment)
            }
        )
    }

    private func isLastAssistantMessage(_ message: ChatMessage) -> Bool {
        guard message.role == .assistant else { return false }
        return visibleMessages.last(where: { $0.role == .assistant })?.id == message.id
    }

    private func toolMeta() -> (name: String, content: String)? {
        let name = ChatMessageMetadata(message: message).toolName ?? ""
        let rawContent = ChatMessageMetadata(message: message).toolContent ?? ""
        guard rawContent.isEmpty == false else { return nil }
        return (name.isEmpty ? L10n.text("chat.bubble.tool.default_name") : name, rawContent)
    }

    private func operationalMeta() -> (state: String, description: String)? {
        guard message.deliveryState == .sending else { return nil }
        let metadata = ChatMessageMetadata(message: message)
        let storedState = metadata.operationalState ?? ""
        let storedDesc = metadata.operationalDescription ?? ""
        if storedState.isEmpty == false || storedDesc.isEmpty == false {
            return (storedState, storedDesc)
        }
        guard let tool = toolMeta() else { return nil }
        let lines = tool.content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        let state: String
        if let first = lines.first, first.hasPrefix("使用工具：") {
            state = first
        } else {
            state = L10n.text("chat.bubble.tool.operating_prefix") + tool.name
        }
        let description = lines.dropFirst().joined(separator: "\n")
        return (state, description)
    }

    private func knowledgeCards(from message: ChatMessage) -> [ChatKnowledgeCard] {
        ChatMessageMetadata(message: message).knowledgeCards
    }

    private func combinedKnowledgeCards(for message: ChatMessage, metadata: ChatMessageMetadata? = nil) -> [ChatKnowledgeCard] {
        let persisted = metadata?.knowledgeCards ?? knowledgeCards(from: message)
        let generated = uiStateStore.knowledgeCards(for: message.id)
        var dedup: Set<String> = []
        var merged: [ChatKnowledgeCard] = []
        for card in persisted + generated {
            let normalizedTitle = card.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedContent = card.content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let key = "\(normalizedTitle)|\(normalizedContent)"
            guard dedup.insert(key).inserted else { continue }
            merged.append(card)
        }
        return merged
    }

    private func formatReasoningTime(_ durationMs: Int64?) -> String? {
        guard let durationMs, durationMs > 0 else { return nil }
        let seconds = Double(durationMs) / 1_000
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let minutes = Int(seconds) / 60
        let remainSeconds = seconds.truncatingRemainder(dividingBy: 60)
        return String(format: "%dm %.1fs", minutes, remainSeconds)
    }

    private func openNetworkSearch(with text: String) {
        let keyword = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard keyword.isEmpty == false else { return }
        let escaped = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        guard let url = URL(string: "https://www.bing.com/search?q=\(escaped)") else { return }
        UIApplication.shared.open(url)
    }

    private func saveMessageToKnowledge(_ message: ChatMessage) {
        guard uiStateStore.isMessageSaving(message.id) == false else { return }
        guard uiStateStore.isMessageSaved(message.id) == false else { return }
        Task {
            guard await actionState.beginSavingMessage(message.id) else { return }
            await MainActor.run {
                uiStateStore.setMessageSaving(true, for: message.id)
            }
            defer {
                Task {
                    await actionState.endSavingMessage(message.id)
                    await MainActor.run {
                        uiStateStore.setMessageSaving(false, for: message.id)
                    }
                }
            }
            do {
                try await messageActionUseCase.saveMessageToKnowledge(
                    content: message.content,
                    detailViewModel: detailViewModel
                )
                await MainActor.run {
                    uiStateStore.setMessageSaved(true, for: message.id)
                }
            } catch {
                logger.error("保存消息到知识库失败：\(error.localizedDescription)", module: .general)
            }
        }
    }

    private func toggleTranslate(_ message: ChatMessage) {
        if uiStateStore.translatedText(for: message.id)?.isEmpty == false {
            uiStateStore.setTranslatedText(nil, for: message.id)
            return
        }
        guard uiStateStore.isTranslating(message.id) == false else { return }
        Task {
            guard await actionState.beginTranslating(message.id) else { return }
            await MainActor.run {
                uiStateStore.setTranslating(true, for: message.id)
            }
            defer {
                Task {
                    await actionState.endTranslating(message.id)
                    await MainActor.run {
                        uiStateStore.setTranslating(false, for: message.id)
                    }
                }
            }
            do {
                let translated = try await messageActionUseCase.translate(message.content, detailViewModel: detailViewModel)
                await MainActor.run {
                    uiStateStore.setTranslatedText(translated.trimmingCharacters(in: .whitespacesAndNewlines), for: message.id)
                }
            } catch {
                await MainActor.run {
                    uiStateStore.setTranslatedText(nil, for: message.id)
                }
            }
        }
    }

    private func confirmTaskCard(_ card: TaskCard) {
        guard uiStateStore.isTaskCardLoading(card.id) == false else { return }
        guard let message = messageContainingTaskCard(cardID: card.id) else { return }
        Task {
            guard await actionState.beginTaskCardLoading(card.id) else { return }
            await MainActor.run {
                uiStateStore.setTaskCardLoading(true, for: card.id)
            }
            defer {
                Task {
                    await actionState.endTaskCardLoading(card.id)
                    await MainActor.run {
                        uiStateStore.setTaskCardLoading(false, for: card.id)
                    }
                }
            }
            do {
                try await messageActionUseCase.createTask(from: card)
                await detailViewModel.updateTaskCardStatus(
                    threadID: threadID,
                    message: message,
                    cardID: card.id,
                    status: .confirmed
                )
            } catch {
                logger.error("任务卡片直接创建任务失败 card_id=\(card.id) error=\(error.localizedDescription)", module: .general)
            }
        }
    }

    private func ignoreTaskCard(_ card: TaskCard) {
        guard let message = messageContainingTaskCard(cardID: card.id) else { return }
        Task {
            await detailViewModel.updateTaskCardStatus(
                threadID: threadID,
                message: message,
                cardID: card.id,
                status: .ignored
            )
        }
        logger.info("任务卡片本地忽略 card_id=\(card.id)", module: .general)
    }

    private func messageContainingTaskCard(cardID: Int) -> ChatMessage? {
        visibleMessages.first { message in
            ChatMessageMetadata(message: message).taskCards.contains(where: { $0.id == cardID })
        }
    }

    private func generateKnowledgeCardsPreview(for message: ChatMessage, metadata: ChatMessageMetadata? = nil) {
        guard message.role == .assistant else { return }
        guard combinedKnowledgeCards(for: message).isEmpty else {
            logger.debug("知识卡预览已存在，跳过重新生成，message=\(message.id.uuidString)", module: .general)
            return
        }
        let resolved = metadata ?? ChatMessageMetadata(message: message)
        let card = messageActionUseCase.buildKnowledgePreviewCard(message: message, metadata: resolved)
        uiStateStore.setKnowledgeCards([card], for: message.id)
        logger.info("知识卡预览已生成，message=\(message.id.uuidString), title=\(card.title)", module: .general)
    }

    private func saveKnowledgeCard(_ card: ChatKnowledgeCard, from message: ChatMessage) {
        guard uiStateStore.isKnowledgeCardSaving(card.id) == false else { return }
        guard uiStateStore.isKnowledgeCardSaved(card.id) == false else { return }
        Task {
            guard await actionState.beginSavingKnowledgeCard(card.id) else { return }
            await MainActor.run {
                uiStateStore.setKnowledgeCardSaving(true, for: card.id)
            }
            defer {
                Task {
                    await actionState.endSavingKnowledgeCard(card.id)
                    await MainActor.run {
                        uiStateStore.setKnowledgeCardSaving(false, for: card.id)
                    }
                }
            }
            do {
                try await messageActionUseCase.saveKnowledgeCard(card, detailViewModel: detailViewModel)
                await MainActor.run {
                    uiStateStore.setKnowledgeCardSaved(true, for: card.id)
                }
                logger.info("知识卡保存成功，message=\(message.id.uuidString), card=\(card.id.uuidString)", module: .general)
            } catch {
                logger.error("知识卡保存失败：\(error.localizedDescription)", module: .general)
            }
        }
    }

    private func translatedText(for message: ChatMessage, metadata: ChatMessageMetadata? = nil) -> String? {
        if let local = uiStateStore.translatedText(for: message.id), local.isEmpty == false {
            return local
        }
        let attachment = metadata?.translatedText ?? ChatMessageMetadata(message: message).translatedText
        return attachment?.isEmpty == false ? attachment : nil
    }
}

struct ChatSelectableTextPayload: Identifiable {
    let id = UUID()
    let title: String
    let text: String
}
