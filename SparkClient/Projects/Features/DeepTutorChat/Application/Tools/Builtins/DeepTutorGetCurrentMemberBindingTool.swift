import Foundation

struct DeepTutorGetCurrentMemberBindingTool: DeepTutorTool {
    let name: DeepTutorToolName = .getCurrentMemberBinding

    func definition() -> AIRuntimeToolDefinition {
        AIRuntimeToolDefinition(
            name: name.rawValue,
            summary: "Check whether the current DeepTutorChat conversation is already bound to a family member.",
            properties: [:],
            required: []
        )
    }

    func execute(arguments: [String: Any], context: DeepTutorToolContext) async -> DeepTutorToolResult {
        guard let memberID = context.boundMemberID, memberID > 0 else {
            return DeepTutorToolResult(
                content: #"{"bound":false,"instruction":"Call request_member_selection if member-specific context is required."}"#,
                metadata: [
                    "bound": "false"
                ]
            )
        }

        return DeepTutorToolResult(
            content: #"{"bound":true,"member_id":\#(memberID),"instruction":"Use the current conversation member context."}"#,
            metadata: [
                "bound": "true",
                "member_id": "\(memberID)"
            ]
        )
    }
}
