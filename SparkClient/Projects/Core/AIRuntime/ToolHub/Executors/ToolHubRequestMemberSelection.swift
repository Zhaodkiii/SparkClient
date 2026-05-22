import Foundation

extension ToolHub {
    func runRequestMemberSelection(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        if let memberID = await resolveTargetMemberID(invocation: invocation, context: context) {
            return memberSelectionAlreadyResolvedResult(memberID: memberID)
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
