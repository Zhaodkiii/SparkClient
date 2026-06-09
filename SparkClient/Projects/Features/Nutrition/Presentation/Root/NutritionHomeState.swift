import Foundation

enum NutritionHomeLoadState: Equatable, Sendable {
    case idle
    case loading
    case content(NutritionDashboardViewData)
    case error(messageKey: String)
}

struct NutritionHomeState: Equatable, Sendable {
    var loadState: NutritionHomeLoadState = .idle
    var selectedDate: Date = .now
    var selectedMemberID: Int?
}

extension NutritionHomeState {
    static let previewLoading = NutritionHomeState(loadState: .loading)
    static let previewError = NutritionHomeState(loadState: .error(messageKey: "nutrition.home.error.load_failed"))
}
