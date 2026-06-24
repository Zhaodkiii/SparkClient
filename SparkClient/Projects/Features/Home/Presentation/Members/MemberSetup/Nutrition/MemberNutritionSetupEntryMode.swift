import Foundation

enum NutritionSetupEntryMode: String, Hashable, Sendable, CaseIterable {
    case full
    case basicInfo

    var sectionCode: String? {
        switch self {
        case .full: return nil
        case .basicInfo: return MemberNutritionSectionCode.basicInfo.rawValue
        }
    }

    var isSectionMode: Bool {
        self != .full
    }
}

enum MemberNutritionSectionCode: String, CaseIterable, Sendable {
    case basicInfo = "basic_info"

    var title: String {
        switch self {
        case .basicInfo: return L10n.text("member.setup.nutrition.nutrition.6ea1fe");        }
    }

    var subtitle: String {
        switch self {
        case .basicInfo: return L10n.text("member.setup.nutrition.nutrition.f6db8a");        }
    }

    var iconName: String {
        switch self {
        case .basicInfo: return "person.fill"
        }
    }

    var entryMode: NutritionSetupEntryMode {
        switch self {
        case .basicInfo: return .basicInfo
        }
    }
}
