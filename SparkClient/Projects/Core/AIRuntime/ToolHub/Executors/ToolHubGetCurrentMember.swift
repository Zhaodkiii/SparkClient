import Foundation

extension ToolHub {
    func runGetCurrentMember(context: ToolExecutionContext) async -> ToolExecutionResult {
        guard let memberID = context.memberID else {
            return ToolExecutionResult(
                toolName: SparkToolName.getCurrentMember,
                outputText: "当前未选择成员。",
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
        let output = "当前成员：\(member.name)，关系：\(member.relationship)。"
        return ToolExecutionResult(
            toolName: SparkToolName.getCurrentMember,
            outputText: output,
            sensitive: true,
            shouldBypassModel: true
        )
    }

}
