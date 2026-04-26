import SwiftUI
import UIKit

/// 单条消息气泡内容：
/// - 纯渲染组件，不直接持有全局状态；
/// - 通过入参和回调与上层协作。
struct ChatMessageBubbleContentView: View {
    @State private var unifiedFilePreview: FilePreviewInput?

    let message: ChatMessage
    let metadata: ChatMessageMetadata
    let isLastAssistantMessage: Bool
    let translatedText: String?
    let combinedKnowledgeCards: [ChatKnowledgeCard]
    let isMathMode: Bool
    let isTranslating: Bool
    let isSavingMessage: Bool
    let isSavedMessage: Bool
    let isSpeaking: Bool
    let taskCardLoadingIDs: Set<Int>
    let ignoredTaskCardIDs: Set<Int>
    let createdTaskCardIDs: Set<Int>
    let savingKnowledgeCardIDs: Set<UUID>
    let savedKnowledgeCardIDs: Set<UUID>
    let showActions: Bool

    let onRetry: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onToggleSpeech: () -> Void
    let onToggleTranslate: () -> Void
    let onOpenNetworkSearch: () -> Void
    let onSaveMessageToKnowledge: () -> Void
    let onGenerateKnowledgeCardsPreview: () -> Void
    let onSaveKnowledgeCard: (ChatKnowledgeCard) -> Void
    let onConfirmTaskCard: (TaskCard) -> Void
    let onIgnoreTaskCard: (TaskCard) -> Void
    let savingStructuredHealthCardIDs: Set<UUID>
    let onSaveMedicationCard: (MedicationChatCardPayload) -> Void
    let onSavePrescriptionCard: (PrescriptionChatCardPayload) -> Void
    let onSaveExamReportCard: (ExamReportChatCardPayload) -> Void
    let onSaveMedicalCaseCard: (MedicalCaseChatCardPayload) -> Void
    let onCaptureOpenCamera: () -> Void
    let onCaptureOpenPhotoLibrary: () -> Void
    let onCaptureOpenFiles: () -> Void
    let onCachedChatAttachmentLocalURL: (ChatAttachment) async -> URL?
    let onDownloadChatAttachmentToLocalFile: (ChatAttachment) async throws -> URL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if shouldRenderErrorCard {
                ChatMessageErrorCard(
                    title: L10n.text("chat.error_card.title"),
                    message: errorCardBodyText,
                    retryTitle: L10n.text("chat.error_card.retry"),
                    onRetry: onRetry
                )
            }

            if message.role == .assistant {
                let payloads = imagePayloads(from: message)
                if payloads.isEmpty == false {
                    ChatImageGalleryBlockView(
                        images: payloads,
                        style: .assistant,
                        unifiedFilePreview: $unifiedFilePreview,
                        downloadToLocalFile: onDownloadChatAttachmentToLocalFile
                    )
                }
            }

            if message.role == .assistant,
               let reasoning = message.reasoningContent?.trimmingCharacters(in: .whitespacesAndNewlines),
               reasoning.isEmpty == false {
                ChatReasoningBlockView(
                    text: reasoning,
                    timeText: formatReasoningTime(message.reasoningDurationMs),
                    isStreaming: message.deliveryState == .sending,
                    isLastAssistantMessage: isLastAssistantMessage
                )
            }

            if message.role == .assistant,
               let operational = operationalMeta(),
               isLastAssistantMessage {
                ChatOperationalStatusBlockView(
                    operationalState: operational.state,
                    operationalDescription: operational.description
                )
            }

            if message.role == .assistant,
               let tool = toolMeta() {
                ChatToolContentBlockView(
                    toolName: tool.name,
                    toolContent: tool.content,
                    isStreaming: message.deliveryState == .sending
                )
            }

            if message.role == .assistant,
               combinedKnowledgeCards.isEmpty == false {
                ChatKnowledgeCardListView(
                    cards: combinedKnowledgeCards,
                    onSave: onSaveKnowledgeCard,
                    isSaving: { card in
                        savingKnowledgeCardIDs.contains(card.id)
                    },
                    isSaved: { card in
                        savedKnowledgeCardIDs.contains(card.id)
                    }
                )
            }

            if message.role == .assistant,
               let translatedText,
               translatedText.isEmpty == false {
                ChatTranslatedBlockView(text: translatedText)
            }

            if message.role == .assistant,
               metadata.locations.isEmpty == false || metadata.routes.isEmpty == false {
                ChatMapRouteBlockView(locations: metadata.locations, routes: metadata.routes)
            }

            if message.role == .assistant,
               metadata.events.isEmpty == false {
                ChatEventsCardListView(events: metadata.events)
            }

            if message.role == .assistant,
               metadata.healthCards.isEmpty == false {
                ChatHealthCardListView(cards: metadata.healthCards)
            }
            if message.role == .assistant,
               let blob = metadata.structuredHealthCards,
               blob.medications.isEmpty == false
                || blob.prescriptions.isEmpty == false
                || blob.examReports.isEmpty == false
                || blob.medicalCases.isEmpty == false {
                ChatStructuredHealthCardsBlockView(
                    blob: blob,
                    isSavingIDs: savingStructuredHealthCardIDs,
                    onSaveMedication: onSaveMedicationCard,
                    onSavePrescription: onSavePrescriptionCard,
                    onSaveExamReport: onSaveExamReportCard,
                    onSaveMedicalCase: onSaveMedicalCaseCard
                )
            }
            if message.role == .assistant,
               let sleep = metadata.sleepVisualization {
                ChatSleepVisualizationMessageCard(model: sleep)
            }

            if message.role == .assistant,
               let captureCard = metadata.captureMessageCard {
                ChatCaptureTypeMessageCard(
                    cardType: captureCard.cardType,
                    onOpenCamera: onCaptureOpenCamera,
                    onOpenPhotoLibrary: onCaptureOpenPhotoLibrary,
                    onOpenFiles: onCaptureOpenFiles
                )
            }

            if message.role == .assistant,
               let htmlContent = metadata.htmlContent,
               htmlContent.isEmpty == false {
                ChatHTMLPreviewBlockView(htmlContent: htmlContent)
            }

            if message.role == .user {
                if let smallTaskCard = metadata.smallTaskCard {
                    ChatSmallTaskMessageCard(payload: smallTaskCard)
                }

                let payloads = imagePayloads(from: message)
                if payloads.isEmpty == false {
                    ChatImageGalleryBlockView(
                        images: payloads,
                        style: .user,
                        unifiedFilePreview: $unifiedFilePreview,
                        downloadToLocalFile: onDownloadChatAttachmentToLocalFile
                    )
                }
            }

            let fileAttachments = message.attachments.filter(\.isGenericFileAttachment)
            if fileAttachments.isEmpty == false {
                ChatFileAttachmentBlockView(
                    unifiedFilePreview: $unifiedFilePreview,
                    attachments: fileAttachments,
                    role: message.role,
                    cachedLocalURL: onCachedChatAttachmentLocalURL,
                    downloadToLocalFile: onDownloadChatAttachmentToLocalFile
                )
            }

            if shouldRenderMainMarkdown {
                if isMathMode {
                    Text(message.content)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Markdown(message.content)
                        .markdownTheme(.chatBubble(foreground: message.role == .user ? .white : .primary))
                }
            }

            if message.deliveryState == .failed, shouldRenderErrorCard == false {
                Button(action: onRetry) {
                    Text(L10n.text("common.retry"))
                        .font(.caption)
                }
            }

            if showActions {
                if message.role == .assistant, message.deliveryState == .sending {
                    EmptyView()
                } else {
                    HStack(spacing: 10) {
                        Button(action: onCopy) {
                            Image(systemName: "square.on.square")
                        }
                        .font(.caption)

                        Button(role: .destructive, action: onDelete) {
                            Image(systemName: "trash")
                        }
                        .font(.caption)

                        if message.role == .assistant {
                            Button(action: onToggleSpeech) {
                                Image(systemName: isSpeaking ? "pause.circle" : "waveform")
                            }
                            .font(.caption)

                            Button(action: onToggleTranslate) {
                                if isTranslating {
                                    ProgressView().scaleEffect(0.8)
                                } else {
                                    Image(systemName: translatedText?.isEmpty == false ? "trash" : "globe")
                                }
                            }
                            .font(.caption)

                            Button(action: onOpenNetworkSearch) {
                                Image(systemName: "network")
                            }
                            .font(.caption)

                            Button(action: onSaveMessageToKnowledge) {
                                if isSavingMessage {
                                    ProgressView().scaleEffect(0.8)
                                } else {
                                    Image(systemName: isSavedMessage ? "checkmark.circle.fill" : "square.and.arrow.down")
                                }
                            }
                            .font(.caption)

                            Button(action: onGenerateKnowledgeCardsPreview) {
                                Image(systemName: combinedKnowledgeCards.isEmpty ? "backpack" : "backpack.fill")
                            }
                            .font(.caption)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }

            if message.role == .assistant {
                let cards = metadata.taskCards
                if cards.isEmpty == false {
                    ForEach(cards) { card in
                        TaskCardCell(
                            card: card,
                            onConfirm: { onConfirmTaskCard(card) },
                            onIgnore: { onIgnoreTaskCard(card) },
                            isLoading: taskCardLoadingIDs.contains(card.id)
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(message.role == .user ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground))
        )
        .unifiedFilePreview(selection: $unifiedFilePreview)
    }

    private var shouldRenderMainMarkdown: Bool {
        if shouldRenderErrorCard {
            return false
        }
        if message.role == .user {
            if metadata.smallTaskCard != nil {
                return false
            }
            let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty == false
        }
        guard message.role == .assistant else { return true }
        guard message.kind == .tool else { return true }
        let trimmedContent = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedContent.isEmpty == false else { return false }

        let toolContent = metadata.toolContent ?? ""
        if toolContent.isEmpty { return true }
        return trimmedContent != toolContent
    }

    private var shouldRenderErrorCard: Bool {
        message.deliveryState == .failed && message.role != .user
    }

    private var errorCardBodyText: String {
        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false {
            return trimmed
        }
        if let description = metadata.operationalDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           description.isEmpty == false {
            return description
        }
        return L10n.text("chat.error_card.generic_body")
    }

    private func toolMeta() -> (name: String, content: String)? {
        let name = metadata.toolName ?? ""
        if metadata.captureMessageCard != nil,
           name.lowercased().contains("show_custom_message_card") {
            return nil
        }
        let rawContent = metadata.toolContent ?? ""
        guard rawContent.isEmpty == false else { return nil }
        return (
            name.isEmpty ? L10n.text("chat.bubble.tool.default_name") : name,
            rawContent
        )
    }

    private func operationalMeta() -> (state: String, description: String)? {
        guard message.deliveryState == .sending else { return nil }
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

    private func imagePayloads(from message: ChatMessage) -> [ChatImagePayload] {
        ChatImagePayloadBuilder.imagePayloads(from: message)
    }
    
    
}

private struct ChatSmallTaskMessageCard: View {
    let payload: ChatSmallTaskMessageCardPayload

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: payload.displayIcon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(0.18)))

            VStack(alignment: .leading, spacing: 4) {
                Text(payload.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if payload.displayBrief.isEmpty == false {
                    Text(payload.displayBrief)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 260, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
    }
}

private struct ChatMessageErrorCard: View {
    let title: String
    let message: String
    let retryTitle: String
    let onRetry: () -> Void

    var bodyView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onRetry) {
                Label(retryTitle, systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding(14)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
    }

    var body: some View {
        bodyView
    }
}
