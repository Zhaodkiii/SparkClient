import Foundation

// ToolHub extension: in-process tool audit query and append.

extension ToolHub {
    /// `/audit_tools`：打印最近审计事件摘要。
    func handleAuditTools() async -> ToolHubResult {
        let events = await auditStore.recent(limit: 20)
        if events.isEmpty {
            return .executed(
                ToolExecutionResult(
                    toolName: "audit_tools",
                    outputText: "最近没有工具调用审计记录。",
                    sensitive: false,
                    shouldBypassModel: true
                )
            )
        }

        let lines = events.map { event in
            "[\(event.createdAt.formatted(date: .abbreviated, time: .shortened))] \(event.toolName) - \(event.status.rawValue)"
        }
        return .executed(
            ToolExecutionResult(
                toolName: "audit_tools",
                outputText: lines.joined(separator: "\n"),
                sensitive: false,
                shouldBypassModel: true
            )
        )
    }

    /// 将本次工具调用写入审计存储，并按输出是否含「失败」粗判状态。
    func appendAudit(
        invocation: ToolInvocation,
        context: ToolExecutionContext,
        result: ToolExecutionResult
    ) async {
        let status: ToolAuditStatus = result.outputText.localizedCaseInsensitiveContains("失败") ? .failed : .success
        await auditStore.append(
            ToolAuditEvent(
                toolName: invocation.name,
                memberID: context.memberID,
                inputSummary: String(invocation.arguments.description.prefix(200)),
                outputSummary: String(result.outputText.prefix(200)),
                status: status
            )
        )
        logger.info(
            "工具执行完成，tool=\(invocation.name), status=\(status.rawValue), bypassModel=\(result.shouldBypassModel), sensitive=\(result.sensitive)",
            module: .aiConfig
        )
    }
}
