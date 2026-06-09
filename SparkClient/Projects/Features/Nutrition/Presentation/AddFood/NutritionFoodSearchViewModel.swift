import Combine
import Foundation

@MainActor
final class NutritionFoodSearchViewModel: ObservableObject {
    @Published var query: String
    @Published var favoriteOnly = false
    @Published var createdByMeOnly = false
    @Published private(set) var results: [NutritionFoodSearchResultViewData] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasSearched = false
    @Published private(set) var errorMessageKey: String?

    let mode: NutritionFoodSearchMode
    private let memberID: Int
    private let searchUseCase: NutritionSearchUseCase
    private let notificationStore: NotificationStore
    private var searchTask: Task<Void, Never>?

    init(
        memberID: Int,
        searchUseCase: NutritionSearchUseCase,
        notificationStore: NotificationStore,
        mode: NutritionFoodSearchMode,
        initialQuery: String = ""
    ) {
        self.memberID = memberID
        self.searchUseCase = searchUseCase
        self.notificationStore = notificationStore
        self.mode = mode
        self.query = initialQuery
    }

    deinit {
        searchTask?.cancel()
    }

    func loadInitialIfNeeded() async {
        guard hasSearched == false else { return }
        await performSearch()
    }

    func submitSearch() {
        Task { await performSearch() }
    }

    func queryChanged() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard Task.isCancelled == false else { return }
            await performSearch()
        }
    }

    func clearQuery() {
        query = ""
        queryChanged()
    }

    func resetFilters() {
        favoriteOnly = false
        createdByMeOnly = false
        submitSearch()
    }

    func toggleFavorite(for result: NutritionFoodSearchResultViewData) {
        Task {
            do {
                try await searchUseCase.toggleFavorite(
                    targetType: result.favoriteTargetType,
                    targetID: result.targetID,
                    isFavorite: result.isFavorite
                )
                await performSearch()
            } catch {
                let messageKey = NutritionErrorMapper.messageKey(for: error)
                errorMessageKey = messageKey
                NutritionNotificationPresenter.presentError(
                    store: notificationStore,
                    messageKey: messageKey,
                    source: "nutrition.food_search.favorite"
                )
            }
        }
    }

    func clearError() {
        errorMessageKey = nil
    }

    private func performSearch() async {
        isLoading = true
        errorMessageKey = nil
        hasSearched = true
        defer { isLoading = false }

        let filters = NutritionFoodSearchFilterState(
            mode: mode,
            query: query.trimmingCharacters(in: .whitespacesAndNewlines),
            type: nil,
            favoriteOnly: favoriteOnly,
            createdByMeOnly: createdByMeOnly
        )

        do {
            results = try await searchUseCase.search(memberID: memberID, filters: filters)
        } catch {
            results = []
            let messageKey = NutritionErrorMapper.messageKey(for: error)
            errorMessageKey = messageKey
            NutritionNotificationPresenter.presentError(
                store: notificationStore,
                messageKey: messageKey,
                source: "nutrition.food_search.search"
            )
        }
    }
}
