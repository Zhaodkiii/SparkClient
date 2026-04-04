import Combine
import Foundation

@MainActor
final class HealthTimelineViewModel: ObservableObject {
    @Published private(set) var metrics: [HealthMetric] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let sessionStore: AppSessionStore
    private let loadHealthTimelineUseCase: LoadHealthTimelineUseCase

    init(
        sessionStore: AppSessionStore,
        loadHealthTimelineUseCase: LoadHealthTimelineUseCase
    ) {
        self.sessionStore = sessionStore
        self.loadHealthTimelineUseCase = loadHealthTimelineUseCase
    }

    func load() async {
        guard case .signedIn(let session) = sessionStore.state else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            metrics = try await loadHealthTimelineUseCase.execute(profileID: session.profileID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
