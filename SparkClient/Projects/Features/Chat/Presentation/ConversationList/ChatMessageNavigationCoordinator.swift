import Combine
import Foundation

struct ToolConsentDetailNavigationTarget: Identifiable, Hashable {
    let toolName: String
    var id: String { toolName }
}

@MainActor
final class ChatMessageNavigationCoordinator: ObservableObject {
    @Published var activeSmallTaskPayload: ChatSmallTaskMessageCardPayload?
    @Published var activeTaskDetailMode: TaskDetailMode?
    @Published var activeStructuredHealthPreview: ChatStructuredHealthCardPreviewContext?
    @Published var activeWeatherConfigCard: ChatWeatherConfigCardPayload?
    @Published var activeToolConsentDetailTarget: ToolConsentDetailNavigationTarget?

    func reset() {
        activeSmallTaskPayload = nil
        activeTaskDetailMode = nil
        activeStructuredHealthPreview = nil
        activeWeatherConfigCard = nil
        activeToolConsentDetailTarget = nil
    }
}
