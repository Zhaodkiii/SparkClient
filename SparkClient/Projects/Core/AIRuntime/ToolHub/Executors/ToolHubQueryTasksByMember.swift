import Foundation

extension ToolHub {
    func runQueryTasksByMember(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let memberID: Int
        if let resolved = await resolveTargetMemberID(invocation: invocation, context: context) {
            memberID = resolved
        } else if let selected = await awaitMemberSelection(
            invocation: invocation,
            context: context,
            reason: "query_tasks_by_member"
        ) {
            memberID = selected
        } else {
            return memberSelectionTimeoutResult(toolName: SparkToolName.queryTasksByMember.rawValue)
        }
        let includeCompleted = parseBool(invocation.arguments["include_completed"], defaultValue: true)
        let limit = max(1, min(Int(invocation.arguments["limit"] ?? "") ?? 50, 200))

        do {
            var tasks = try await taskService.fetchTasks(memberID: memberID, since: nil)
            if includeCompleted == false {
                tasks.removeAll { $0.status != .pending }
            }
            tasks = Array(tasks.sorted { $0.updatedAt > $1.updatedAt }.prefix(limit))
            let output = formatTaskQueryText(memberID: memberID, tasks: tasks, queriedAt: Date())
            return ToolExecutionResult(
                toolName: SparkToolName.queryTasksByMember,
                outputText: output,
                sensitive: true,
                shouldBypassModel: true,
                resolvedMemberID: memberID
            )
        } catch {
            return ToolExecutionResult(
                toolName: SparkToolName.queryTasksByMember,
                outputText: #"{"ok":false,"error":"task_query_failed"}"#,
                sensitive: false,
                shouldBypassModel: true,
                resolvedMemberID: memberID
            )
        }
    }


}
