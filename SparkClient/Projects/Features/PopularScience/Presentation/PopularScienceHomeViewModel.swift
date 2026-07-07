import Combine
import Foundation

@MainActor
final class PopularScienceHomeViewModel: ObservableObject {
    @Published private(set) var phase: PopularScienceListPhase = .idle
    @Published private(set) var articles: [PopularScienceArticleSummary] = []
    @Published private(set) var categories: [PopularScienceCategory] = []
    @Published var selectedCategoryID: Int?
    @Published private(set) var isLoadingNextPage = false
    @Published private(set) var offlineNotice: String?

    private let loadArticlesUseCase: LoadPopularScienceArticlesUseCase
    private let loadCategoriesUseCase: LoadPopularScienceCategoriesUseCase
    private let routeStore: AppRouteStore
    private let pageSize: Int
    private var page = 1
    private var hasNext = true
    private var hasLoaded = false

    init(
        loadArticlesUseCase: LoadPopularScienceArticlesUseCase,
        loadCategoriesUseCase: LoadPopularScienceCategoriesUseCase,
        routeStore: AppRouteStore,
        pageSize: Int = 20
    ) {
        self.loadArticlesUseCase = loadArticlesUseCase
        self.loadCategoriesUseCase = loadCategoriesUseCase
        self.routeStore = routeStore
        self.pageSize = pageSize
    }

    func loadIfNeeded() async {
        guard hasLoaded == false else { return }
        await refresh()
    }

    func refresh() async {
        phase = .loading
        offlineNotice = nil
        page = 1
        hasNext = true

        async let categoryResult = loadCategoriesUseCase.execute(locale: PopularScienceLocale.current)
        do {
            let filter = makeFilter()
            let articlePage = try await loadArticlesUseCase.execute(
                filter: filter,
                page: page,
                pageSize: pageSize
            )
            articles = articlePage.items
            hasNext = articlePage.hasNext
            hasLoaded = true
            phase = articles.isEmpty ? .empty : .loaded
            categories = (try? await categoryResult) ?? categories
        } catch {
            phase = .failed(userFacingMessage(for: error))
            categories = (try? await categoryResult) ?? categories
        }
    }

    func loadNextPageIfNeeded(currentItem: PopularScienceArticleSummary) async {
        guard hasNext, isLoadingNextPage == false else { return }
        guard articles.suffix(5).contains(currentItem) else { return }

        isLoadingNextPage = true
        defer { isLoadingNextPage = false }

        do {
            let nextPage = page + 1
            let articlePage = try await loadArticlesUseCase.execute(
                filter: makeFilter(),
                page: nextPage,
                pageSize: pageSize
            )
            page = nextPage
            hasNext = articlePage.hasNext
            articles.append(contentsOf: articlePage.items.filter { newItem in
                articles.contains(where: { $0.id == newItem.id }) == false
            })
        } catch {
            offlineNotice = userFacingMessage(for: error)
        }
    }

    func selectCategory(_ category: PopularScienceCategory?) async {
        selectedCategoryID = category?.id
        await refresh()
    }

    func openArticle(_ article: PopularScienceArticleSummary) {
        routeStore.route(to: .popularScienceArticle(id: article.id))
    }

    private func makeFilter() -> PopularScienceListFilter {
        PopularScienceListFilter.current(categoryID: selectedCategoryID)
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return L10n.text("popular_science.error.load_failed", fallback: "Unable to load content. Pull to retry.")
    }
}
