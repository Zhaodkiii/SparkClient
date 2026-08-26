import Combine
import Foundation

enum HomeQuickStartConversationTarget: String, CaseIterable, Identifiable {
    case chat

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .chat:
            return "settings.general.home_quick_start_target.chat"
        }
    }
}

@MainActor
final class HomeQuickStartConversationPreferenceStore: ObservableObject {
    static let shared = HomeQuickStartConversationPreferenceStore()

    private static let storageKey = "home.quick_start_conversation_target"
    private let defaults: UserDefaults

    @Published var target: HomeQuickStartConversationTarget {
        didSet {
            defaults.set(target.rawValue, forKey: Self.storageKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let rawValue = defaults.string(forKey: Self.storageKey)
        self.target = rawValue
            .flatMap(HomeQuickStartConversationTarget.init(rawValue:))
            ?? .chat
    }
}
