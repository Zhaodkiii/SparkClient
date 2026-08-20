import Combine
import Foundation

/// 运动健康模块依赖包（四层装配入口）。
struct FitnessFeatureDependencies {
    let dashboardUseCase: FitnessDashboardUseCase
    let memberContextStore: MemberContextStore
    let logger: Logger
}

/// 运动健康看板加载状态。
enum FitnessHomeLoadState {
    case idle
    case loading
    case content(FitnessDashboard)
    case error(String)
}

@MainActor
final class FitnessHomeViewModel: ObservableObject {
    @Published private(set) var loadState: FitnessHomeLoadState = .idle
    @Published private(set) var authorizationPromptDismissed = false

    private let dashboardUseCase: FitnessDashboardUseCase

    init(dashboardUseCase: FitnessDashboardUseCase) {
        self.dashboardUseCase = dashboardUseCase
    }

    func hideAuthorizationPrompt() {
        authorizationPromptDismissed = true
    }

    func loadIfNeeded(memberID: Int?) async {
        if case .content = loadState { return }
        await reload(memberID: memberID)
    }

    func reload(memberID: Int?) async {
        loadState = .loading
        let dashboard = await dashboardUseCase.loadDashboard(memberID: memberID, date: .now)
        loadState = .content(dashboard)
    }
}