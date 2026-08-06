import Foundation

extension ToolHub {
    func runRequestMemberSelection(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        if let memberID = await resolveTargetMemberID(invocation: invocation, context: context) {
            return memberSelectionAlreadyResolvedResult(memberID: memberID)
        }

        if context.preferInlineMemberSelection {
            return ToolExecutionResult(
                toolName: SparkToolName.requestMemberSelection.rawValue,
                outputText: "【系统】已在消息内展示成员选择卡片，等待用户选择。",
                sensitive: false,
                shouldBypassModel: false,
                isAwaitingUserInput: true,
                arguments: invocation.arguments
            )
        }

        let rawReason = invocation.arguments["reason"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = rawReason?.isEmpty == false ? rawReason : nil
        guard let selectedMemberID = await awaitMemberSelection(
            invocation: invocation,
            context: context,
            reason: reason ?? "request_member_selection"
        ) else {
            return memberSelectionTimeoutResult(toolName: SparkToolName.requestMemberSelection.rawValue)
        }
        return memberSelectionCompletedResult(toolName: SparkToolName.requestMemberSelection.rawValue, memberID: selectedMemberID)
    }


}
