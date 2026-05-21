import Foundation

extension ToolHub {
    func runGenerateStructuredHealthCard(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let l10n = AIPromptL10n(locale: context.locale)

        let hintTemplate = l10n.tool(
            "tool.async.structured_health_card.model_hint",
            fallback: """
                [系统] 结构化健康卡片正在后台生成中。无需等待，可继续根据用户消息进行回复；卡片将展示在本条回复下方。
                """
        )

        let extractionFailureNotice = l10n.tool(
            "tool.error.structured_health_card.extraction_failed",
            fallback: "结构化健康卡片生成失败，请稍后重试或补充更完整的病历摘要。"
        )

        let reportType = (invocation.arguments["report_type"] ?? invocation.arguments["category"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let rawText = (invocation.arguments["raw_text"] ?? invocation.arguments["content"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard rawText.isEmpty == false else {
            return ToolExecutionResult(
                toolName: SparkToolName.generateStructuredHealthCard,
                outputText: l10n.tool(
                    "tool.error.structured_health_card.empty_raw_text",
                    fallback: "缺少原始文本（摘要内容）。"
                ),
                sensitive: false,
                shouldBypassModel: true
            )
        }

        guard let threadID = context.threadID, let assistantID = context.assistantMessageClientID else {
            return ToolExecutionResult(
                toolName: SparkToolName.generateStructuredHealthCard,
                outputText: l10n.tool(
                    "tool.error.structured_health_card.no_message_binding",
                    fallback: "[系统] 内部错误：未绑定助手消息。"
                ),
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let effectiveReportType = reportType.isEmpty ? "medical_case" : reportType
        let ossFileId = invocation.arguments["oss_file_id"].flatMap { Int($0) }
        let boundMemberID = context.memberID
        let normalizedToolCallID = normalizedToolCallID(from: context)

        let merge = structuredHealthCardMergeCoordinator
        let extractor = typedMedicalDocumentExtractor
        let taskLogger = logger

        await merge.publishHealthStructuredHealthCardsPending(
            threadID: threadID,
            assistantClientMessageID: assistantID,
            anchorToolCallID: normalizedToolCallID
        )

        Task {
            do {
                let output = try await withStructuredHealthExtractionTimeout(seconds: 145) {
                    try await extractor.extractFromChatDistilledText(
                        memberID: boundMemberID,
                        reportType: effectiveReportType,
                        rawText: rawText
                    )
                }

                let blob = ChatStructuredHealthCardsPayloadBuilder.appendPayloads(
                    from: output,
                    memberId: boundMemberID,
                    ossFileId: ossFileId
                )

                await merge.publishHealthStructuredHealthCards(
                    threadID: threadID,
                    assistantClientMessageID: assistantID,
                    blob: blob,
                    anchorToolCallID: normalizedToolCallID
                )
            } catch {
                taskLogger.error(
                    "generate_structured_health_card failed: \(error.localizedDescription)",
                    module: .aiConfig
                )

                await merge.publishStructuredHealthCardsFailed(
                    assistantClientMessageID: assistantID,
                    anchorToolCallID: normalizedToolCallID,
                    message: extractionFailureNotice
                )
                await merge.publishAssistantTimelineNotice(
                    assistantClientMessageID: assistantID,
                    text: extractionFailureNotice
                )
            }
        }

        return ToolExecutionResult(
            toolName: SparkToolName.generateStructuredHealthCard,
            outputText: hintTemplate,
            sensitive: false,
            shouldBypassModel: false,
            arguments: invocation.arguments
        )
    }

    private func withStructuredHealthExtractionTimeout<T: Sendable>(
        seconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw SparkHealthToolError(message: "结构化健康卡片生成超时")
            }
            guard let result = try await group.next() else {
                throw SparkHealthToolError(message: "结构化健康卡片生成失败")
            }
            group.cancelAll()
            return result
        }
    }

}
