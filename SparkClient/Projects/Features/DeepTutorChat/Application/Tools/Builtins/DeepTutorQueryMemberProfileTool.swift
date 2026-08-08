import Foundation

struct DeepTutorQueryMemberProfileTool: DeepTutorTool {
    let name: DeepTutorToolName = .queryMemberProfile

    private let dataSource: any DeepTutorMemberProfileToolDataSource

    init(dataSource: any DeepTutorMemberProfileToolDataSource) {
        self.dataSource = dataSource
    }

    func definition() -> AIRuntimeToolDefinition {
        AIRuntimeToolDefinition(
            name: name.rawValue,
            summary: "Load the bound member's medical profile, health history, lifestyle, exam archive and risk summary before creating any personalized health-check plan.",
            properties: [
                "member_id": AIRuntimeToolProperty(type: "integer", description: "Optional explicit member id. Usually omit this and use the current bound member."),
                "focus": AIRuntimeToolProperty(type: "string", description: "Optional planning focus such as cancer screening, cardiovascular, thyroid, women's health, bone density, or budget.")
            ],
            required: []
        )
    }

    func execute(arguments: [String: Any], context: DeepTutorToolContext) async -> DeepTutorToolResult {
        let targetMemberID = intValue(arguments["member_id"])
            ?? intValue(arguments["patient_id"])
            ?? context.boundMemberID

        guard let memberID = targetMemberID, memberID > 0 else {
            let reason = "制定个性化体检计划前，需要先确认本次使用哪位家庭成员的医疗档案。"
            return DeepTutorToolResult(
                content: "[awaiting member selection for query_member_profile]",
                metadata: [
                    "pause": "member_selection",
                    "requested_tool": name.rawValue
                ],
                pauseForUser: .memberSelection(
                    reason: reason,
                    arguments: [
                        "reason": reason,
                        "required_context": "member_medical_profile",
                        "requested_tool": name.rawValue
                    ]
                )
            )
        }

        do {
            let data = try await dataSource.fetchMemberCompleteData(memberID: memberID)
            let focus = DeepTutorToolArgumentDecoder.string(arguments, "focus")
            let result = await MainActor.run {
                DeepTutorQueryMemberProfileFormatter.makeAIResult(data: data, requestedFocus: focus)
            }
            return DeepTutorToolResult(
                content: result.content,
                metadata: result.metadata
            )
        } catch {
            return DeepTutorToolResult(
                content: "query_member_profile 执行失败：未能读取成员医疗资料，请稍后重试。",
                metadata: [
                    "member_id": String(memberID),
                    "error": error.localizedDescription
                ],
                success: false
            )
        }
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}
