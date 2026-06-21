import Foundation

enum MemberSetupSheetRoute: Identifiable, Hashable {
    case medical(MedicalSetupEntryMode)
    case nutrition(NutritionSetupEntryMode)
    case lifestyle

    var id: String {
        switch self {
        case .medical(let mode):
            return "medical-\(mode.rawValue)"
        case .nutrition(let mode):
            return "nutrition-\(mode.rawValue)"
        case .lifestyle:
            return "lifestyle"
        }
    }
}
