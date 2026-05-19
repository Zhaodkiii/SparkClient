import Foundation

extension ToolHub {
    func runExternalConnectorTool(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        if invocation.name == SparkToolName.searchOnline.rawValue || invocation.name == SparkToolName.searchArxivPapers.rawValue {
            return await runWebSearchTool(invocation: invocation, context: context)
        }

        if invocation.name == SparkToolName.readWebPage.rawValue || invocation.name == SparkToolName.extractRemoteFileContent.rawValue {
            return await runReadWebPageTool(invocation: invocation, context: context)
        }

        let snapshot = await aiConfigCenter.currentSnapshot()
        let endpoint = resolveEndpoint(for: invocation.name, toolKeys: snapshot.toolKeys)
        let payloadSummary = invocation.arguments
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: ", ")

        let output = """
        工具 \(invocation.name) 已接入 SparkClient 路由。
        endpoint=\(endpoint ?? "未配置")
        args=\(payloadSummary.isEmpty ? "<empty>" : payloadSummary)
        当前为本地执行占位；如需真实联网调用，请在对应 toolClass 网关实现 HTTP 适配。
        """
        let rich = makeExternalConnectorRichBlocks(
            invocation: invocation,
            toolOutputForWebPreview: output,
            toolCallID: normalizedToolCallID(from: context)
        )
        return returnWithScheduledRichMerge(
            context: context,
            result: ToolExecutionResult(
                toolName: invocation.name,
                outputText: output,
                sensitive: false,
                shouldBypassModel: true
            ),
            richBlocks: rich
        )
    }


    func runWebSearchTool(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let query = (invocation.arguments["query"] ?? invocation.arguments["keyword"] ?? invocation.arguments["content"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else {
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: SearchRuntimeError.emptyQuery.localizedDescription,
                sensitive: false,
                shouldBypassModel: true
            )
        }

        do {
            let config = try await aiConfigCenter.effectiveSearchConfig()
            let primary = try await webSearchGateway.search(query: query, config: config)
            let combined = try await mergedBilingualSearchIfNeeded(primary: primary, query: query, config: config)
            let combinedMarkdown = combined.markdown
            let rich = [
                ChatMessageBlock(
                    anchor: normalizedToolCallID(from: context).map(ChatBlockAnchor.toolCall),
                    kind: .html,
                    text: combinedMarkdown,
                    toolCallID: normalizedToolCallID(from: context)
                )
            ]
            return returnWithScheduledRichMerge(
                context: context,
                result: ToolExecutionResult(
                    toolName: invocation.name,
                    outputText: combinedMarkdown,
                    sensitive: false,
                    shouldBypassModel: false
                ),
                richBlocks: rich
            )
        } catch {
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: error.localizedDescription,
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }


    func runReadWebPageTool(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let url = (invocation.arguments["url"] ?? invocation.arguments["link"] ?? invocation.arguments["query"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard url.isEmpty == false else {
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: "网页读取失败：url 不能为空。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        do {
            let text = try await webSearchGateway.readWebPage(urlString: url)
            let output = "网页读取结果\nURL: \(url)\n\n\(text)"
            let rich = [
                ChatMessageBlock(
                    anchor: normalizedToolCallID(from: context).map(ChatBlockAnchor.toolCall),
                    kind: .html,
                    text: output,
                    toolCallID: normalizedToolCallID(from: context)
                )
            ]
            return returnWithScheduledRichMerge(
                context: context,
                result: ToolExecutionResult(
                    toolName: invocation.name,
                    outputText: output,
                    sensitive: false,
                    shouldBypassModel: false
                ),
                richBlocks: rich
            )
        } catch {
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: error.localizedDescription,
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }

}
