import Foundation

extension ToolHub {
    func runCreateKnowledgeDocument(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let title = (invocation.arguments["title"] ?? "未命名文档").trimmingCharacters(in: .whitespacesAndNewlines)
        let content = (invocation.arguments["content"] ?? invocation.arguments["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let autoSave = toolBool(invocation.arguments["auto_save"])
        guard content.isEmpty == false else {
            return ToolExecutionResult(
                toolName: SparkToolName.createKnowledgeDocument,
                outputText: #"{"ok":false,"error":"content_required"}"#,
                sensitive: false,
                shouldBypassModel: true
            )
        }
        let resolvedTitle = title.isEmpty ? "未命名文档" : title
        if autoSave {
            do {
                let document = try await createKnowledgeDocumentUseCase.execute(
                    KnowledgeDocumentDraft(
                        title: resolvedTitle,
                        content: content,
                        scope: .personal,
                        boundModelID: nil,
                        source: .tool
                    )
                )
                logger.info(
                    "create_knowledge_document 自动保存成功，title=\(resolvedTitle), id=\(document.id.uuidString)",
                    module: .aiConfig
                )
                let payload = KnowledgeDocumentSavedToolPayload(
                    ok: true,
                    action: "saved",
                    document: .init(id: document.id.uuidString, title: document.title),
                    businessType: "knowledge",
                    businessId: document.id.uuidString,
                    category: nonEmptyToolText(invocation.arguments["category"])
                )
                var sideEffects: [ToolSideEffect] = []
                if context.threadID != nil, context.assistantMessageClientID != nil {
                    sideEffects = [
                        .knowledgeCards([
                            ChatKnowledgeCard(
                                title: document.title,
                                content: knowledgeCardPreview(from: document.content),
                                documentID: document.id,
                                showsSaveAndCopy: false
                            )
                        ])
                    ]
                }
                return ToolExecutionResult(
                    toolName: SparkToolName.createKnowledgeDocument,
                    outputText: encodeJSON(payload) ?? #"{"ok":false,"error":"encode_failed"}"#,
                    sensitive: false,
                    shouldBypassModel: true,
                    sideEffects: sideEffects
                )
            } catch {
                logger.error(
                    "create_knowledge_document 自动保存失败，title=\(resolvedTitle), error=\(error.localizedDescription)",
                    module: .aiConfig
                )
                return ToolExecutionResult(
                    toolName: SparkToolName.createKnowledgeDocument,
                    outputText: #"{"ok":false,"error":"knowledge_save_failed","recoverable":true}"#,
                    sensitive: false,
                    shouldBypassModel: true
                )
            }
        }

        logger.info(
            "create_knowledge_document 生成预览草稿，title=\(resolvedTitle), contentLength=\(content.count)",
            module: .aiConfig
        )

        let userFacing = "已生成知识库文档草稿「\(resolvedTitle)」，内容已附在消息内知识卡中，用户可点击保存到知识库。"
        var sideEffects: [ToolSideEffect] = []
        if context.threadID != nil, context.assistantMessageClientID != nil {
            sideEffects = [
                .knowledgeCards([ChatKnowledgeCard(title: resolvedTitle, content: content)])
            ]
        }
        return ToolExecutionResult(
            toolName: SparkToolName.createKnowledgeDocument,
            outputText: userFacing,
            sensitive: false,
            shouldBypassModel: true,
            sideEffects: sideEffects
        )
    }

}

private struct KnowledgeDocumentSavedToolPayload: Encodable {
    struct Document: Encodable {
        let id: String
        let title: String
    }

    let ok: Bool
    let action: String
    let document: Document
    let businessType: String
    let businessId: String
    let category: String?
}

private func toolBool(_ value: String?) -> Bool {
    guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
        return false
    }
    return ["1", "true", "yes", "y", "on"].contains(text)
}

private func nonEmptyToolText(_ value: String?) -> String? {
    let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return text.isEmpty ? nil : text
}

private func knowledgeCardPreview(from markdown: String, limit: Int = 220) -> String {
    let normalized = markdown
        .replacingOccurrences(of: #"\!\[[^\]]*\]\([^\)]*\)"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]*\)"#, with: "$1", options: .regularExpression)
        .replacingOccurrences(of: #"[#>*`_~\-]{1,}"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalized.count > limit else {
        return normalized
    }
    return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
}
