import Foundation

enum MemberSetupSheetRoute: String, Identifiable, Hashable {
    case medical
    case nutrition
    case lifestyle

    var id: String { rawValue }
}
