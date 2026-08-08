import Foundation

struct DeepTutorMemberSelectionTool: DeepTutorTool {
    let name: DeepTutorToolName = .requestMemberSelection

    func definition() -> AIRuntimeToolDefinition {
        AIRuntimeToolDefinition(
            name: name.rawValue,
            summary: "Pause the turn and ask the user to choose the family member this answer should use.",
            properties: [
                "reason": AIRuntimeToolProperty(type: "string", description: "Why a member is needed for this request."),
                "required_context": AIRuntimeToolProperty(type: "string", description: "The kind of member-specific context required."),
                "allow_skip": AIRuntimeToolProperty(type: "boolean", description: "Whether the user may continue without selecting a member.")
            ],
            required: ["reason"]
        )
    }

    func execute(arguments: [String: Any], context: DeepTutorToolContext) async -> DeepTutorToolResult {
        var mapped: [String: String] = [:]
        for (key, value) in arguments {
            mapped[key] = String(describing: value)
        }
        let reason = DeepTutorToolArgumentDecoder.string(arguments, "reason") ?? "需要先确认本次对话对应的家庭成员。"
        mapped["reason"] = reason
        if let currentMemberID = context.boundMemberID, currentMemberID > 0 {
            mapped["current_member_id"] = "\(currentMemberID)"
        }
        return DeepTutorToolResult(
            content: "[awaiting member selection]",
            metadata: {
                var metadata = ["pause": "member_selection"]
                if let currentMemberID = context.boundMemberID, currentMemberID > 0 {
                    metadata["current_member_id"] = "\(currentMemberID)"
                }
                return metadata
            }(),
            pauseForUser: .memberSelection(reason: reason, arguments: mapped)
        )
    }
}
