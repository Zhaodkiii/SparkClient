import Foundation

struct DeepTutorShowCustomMessageCardTool: DeepTutorTool {
    let name: DeepTutorToolName = .showCustomMessageCard

    func definition() -> AIRuntimeToolDefinition {
        AIRuntimeToolDefinition(
            name: name.rawValue,
            summary: "Insert a DeepTutorChat upload/capture card and pause the turn while the user chooses an attachment.",
            properties: [
                "card_type": AIRuntimeToolProperty(
                    type: "string",
                    description: "Card type to show: report_photo for medical reports/PDFs, medicine_box_photo for medicine package photos, skin_photo for skin photos.",
                    enumValues: DeepTutorCaptureCardType.allCases.map(\.rawValue)
                ),
            ],
            required: ["card_type"]
        )
    }

    func execute(arguments: [String: Any], context: DeepTutorToolContext) async -> DeepTutorToolResult {
        guard let rawType = DeepTutorToolArgumentDecoder.string(arguments, "card_type"),
              let cardType = DeepTutorCaptureCardType(rawValue: rawType) else {
            return DeepTutorToolResult(
                content: "show_custom_message_card failed: `card_type` must be one of report_photo, medicine_box_photo, skin_photo.",
                metadata: [
                    "kind": "capture_card",
                    "error": "invalid_card_type",
                ],
                success: false
            )
        }

        let payload = DeepTutorCaptureCardPayload(
            cardType: cardType,
            sourceToolCallID: nil
        )

        return DeepTutorToolResult(
            content: "[awaiting user attachment: \(cardType.rawValue)]",
            metadata: [
                "kind": "capture_card",
                "pause": "attachment_capture",
                "card_type": cardType.rawValue,
                "title": payload.title,
                "subtitle": payload.subtitle,
            ],
            pauseForUser: .attachmentCapture(cardType: cardType)
        )
    }
}
