import Foundation

nonisolated enum DeepTutorPagePhase: Equatable, Sendable {
    case idle
    case loadingLocal
    case ready
    case streaming
    case resolvingAskUser
    case resolvingMemberSelection
    case error(String)

    var logLabel: String {
        switch self {
        case .idle:
            return "idle"
        case .loadingLocal:
            return "loadingLocal"
        case .ready:
            return "ready"
        case .streaming:
            return "streaming"
        case .resolvingAskUser:
            return "resolvingAskUser"
        case .resolvingMemberSelection:
            return "resolvingMemberSelection"
        case .error(let message):
            return "error(\(message))"
        }
    }
}

nonisolated struct DeepTutorConversationState: Equatable, Sendable {
    var phase: DeepTutorPagePhase
    var messages: [DeepTutorMessage]
    var selectedBranches: DeepTutorBranchSelection
    var isStreaming: Bool
    var hasMoreMessages: Bool
    var lockBottomViewport: Bool
    var scrollToBottomRequestGeneration: UInt64
    var activeCapability: DeepTutorCapability
    var draftText: String
    var enabledOptionalTools: [String]

    static let initial = DeepTutorConversationState(
        phase: .idle,
        messages: [],
        selectedBranches: DeepTutorBranchSelection(),
        isStreaming: false,
        hasMoreMessages: false,
        lockBottomViewport: false,
        scrollToBottomRequestGeneration: 0,
        activeCapability: .chat,
        draftText: "",
        enabledOptionalTools: DeepTutorUserToolSettingsStore.enabledToolsForCapability(.chat)
    )
}
