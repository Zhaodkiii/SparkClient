import Foundation

enum DeepTutorToolInteractionSnapshot: Equatable, Sendable {
    case toolPreview(DeepTutorToolPreviewPrompt)

    var requiresForcedSheetDismiss: Bool { false }

    var label: String {
        switch self {
        case .toolPreview(let prompt):
            return "toolPreview(\(prompt.toolName))"
        }
    }
}
