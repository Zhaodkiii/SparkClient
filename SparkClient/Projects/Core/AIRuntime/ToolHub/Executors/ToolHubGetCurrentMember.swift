import Foundation

extension ToolHub {
    func runGetCurrentMember(context: ToolExecutionContext) async -> ToolExecutionResult {
        let invocation = ToolInvocation(name: SparkToolName.getCurrentMember.rawValue, arguments: [:])
        guard let memberID = await resolveTargetMemberID(invocation: invocation, context: context) else {
            return ToolExecutionResult(
                toolName: SparkToolName.getCurrentMember,
                outputText: "当前未选择成员（会话未绑定成员且本轮未解析到 member_id）。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let data: SparkMedicalSyncAPI.RemoteMemberCompleteData
        do {
            data = try await medicalQueryAPI.fetchMemberCompleteData(memberID: memberID)
        } catch {
            return ToolExecutionResult(
                toolName: SparkToolName.getCurrentMember,
                outputText: "当前成员数据加载失败。",
                sensitive: false,
                shouldBypassModel: true
            )
        }
        let member = data.member
        let output = "当前成员：\(member.name)，关系：\(member.relationship)，member_id：\(memberID)。"
        return ToolExecutionResult(
            toolName: SparkToolName.getCurrentMember,
            outputText: output,
            sensitive: true,
            shouldBypassModel: true,
            resolvedMemberID: context.memberID == memberID ? nil : memberID
        )
    }

}
