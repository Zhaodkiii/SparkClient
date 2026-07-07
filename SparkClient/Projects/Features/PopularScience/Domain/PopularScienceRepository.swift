import Foundation

protocol PopularScienceRepository: Sendable {
    func listArticles(
        filter: PopularScienceListFilter,
        page: Int,
        pageSize: Int
    ) async throws -> PopularSciencePage<PopularScienceArticleSummary>

    func loadArticle(id: Int, locale: String?) async throws -> PopularScienceArticleDetail
    func loadArticle(slug: String, locale: String) async throws -> PopularScienceArticleDetail
    func listCategories(locale: String) async throws -> [PopularScienceCategory]
    func listTags(locale: String) async throws -> [PopularScienceTag]
    func reportView(articleID: Int) async throws
    func reportReadingDuration(articleID: Int, durationSeconds: Int, sessionID: String?) async throws
    func shareLink(articleID: Int) async throws -> URL
}

enum PopularScienceError: LocalizedError, Sendable {
    case notFound
    case cacheMiss
    case invalidShareURL
    case unsupportedContentFormat(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return L10n.text("popular_science.error.not_found", fallback: "Content is unavailable.")
        case .cacheMiss:
            return L10n.text("popular_science.error.cache_miss", fallback: "No cached content.")
        case .invalidShareURL:
            return L10n.text("popular_science.error.invalid_share_url", fallback: "Unable to create share link.")
        case .unsupportedContentFormat:
            return L10n.text("popular_science.error.unsupported_format", fallback: "This content format is not supported.")
        }
    }
}

