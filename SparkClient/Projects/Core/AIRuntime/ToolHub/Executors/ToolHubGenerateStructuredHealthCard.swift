import Foundation

extension ToolHub {
    func runGenerateStructuredHealthCard(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        // 获取对应语言的本地化文案
        let l10n = AIPromptL10n(locale: context.locale)
        
        // 生成模型提示文案：告知用户结构化卡片正在后台生成，无需等待，可继续对话
        let hintTemplate = l10n.tool(
            "tool.async.structured_health_card.model_hint",
            fallback: """
                [系统] 结构化健康卡片正在后台生成中。无需等待，可继续根据用户消息进行回复；卡片将展示在本条回复下方。
                """
        )
        
        // 解析报告类型：支持 report_type / category 两个参数名，统一做小写、去空格处理
        let reportType = (invocation.arguments["report_type"] ?? invocation.arguments["category"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        
        // 解析原始文本：支持 raw_text / content 两个参数名，去空格处理
        let rawText = (invocation.arguments["raw_text"] ?? invocation.arguments["content"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 校验：原始文本为空，返回错误
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
        
        // 校验：缺少会话ID 或 助手消息客户端ID，返回内部错误
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
        
        // 确定最终使用的报告类型，未传参则默认使用 medical_case
        let effectiveReportType = reportType.isEmpty ? "medical_case" : reportType
        
        // 解析 OSS 文件ID（转为整型，可选）
        let ossFileId = invocation.arguments["oss_file_id"].flatMap { Int($0) }
        let boundMemberID = context.memberID
        let normalizedToolCallID = normalizedToolCallID(from: context)
        
        // 依赖的协程管理器与文档抽取器
        let merge = structuredHealthCardMergeCoordinator
        let extractor = typedMedicalDocumentExtractor
        
        // 开启后台任务：执行结构化健康卡片抽取与合并（不阻塞当前方法返回）
        Task {
            do {
                // 1. 从聊天摘要文本中抽取结构化健康数据
                let output = try await extractor.extractFromChatDistilledText(
                    memberID: boundMemberID,
                    reportType: effectiveReportType,
                    rawText: rawText
                )
                
                // 2. 构建卡片数据增量更新 payload
                let delta = ChatStructuredHealthCardsPayloadBuilder.appendPayloads(
                    from: output,
                    memberID: boundMemberID,
                    ossFileId: ossFileId
                )
                
                // 3. 与睡眠/运动卡片一致：用工具调用 ID 锚定到对应工具行，并走统一富卡片合并入口
                await merge.insertStructuredHealthCardsWhenAssistantMessageReady(
                    threadID: threadID,
                    assistantClientMessageID: assistantID,
                    delta: delta,
                    anchorToolCallID: normalizedToolCallID
                )
            } catch {
                // 抽取失败：打印警告日志，并生成失败状态的卡片占位数据
                logger.warning(
                    "generate_structured_health_card 抽取失败：\(error.localizedDescription)",
                    module: .aiConfig
                )
                
                let delta = ChatStructuredHealthCardsPayloadBuilder.extractionFailureBlob(
                    memberID: boundMemberID,
                    reportType: effectiveReportType,
                    ossFileId: ossFileId
                )
                
                // 合并失败占位信息到助手消息
                await merge.insertStructuredHealthCardsWhenAssistantMessageReady(
                    threadID: threadID,
                    assistantClientMessageID: assistantID,
                    delta: delta,
                    anchorToolCallID: normalizedToolCallID
                )
            }
        }
        
        // 同步返回：立即告诉模型“后台正在生成”，不等待异步任务完成
        return ToolExecutionResult(
            toolName: SparkToolName.generateStructuredHealthCard,
            outputText: hintTemplate,
            sensitive: false,
            shouldBypassModel: false
        )
    }

}
