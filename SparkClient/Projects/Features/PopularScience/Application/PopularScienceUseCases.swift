import Foundation

struct LoadPopularScienceArticlesUseCase: Sendable {
    let repository: any PopularScienceRepository

    func execute(
        filter: PopularScienceListFilter,
        page: Int,
        pageSize: Int
    ) async throws -> PopularSciencePage<PopularScienceArticleSummary> {
        try await repository.listArticles(filter: filter, page: page, pageSize: pageSize)
    }
}

struct LoadPopularScienceArticleDetailUseCase: Sendable {
    let repository: any PopularScienceRepository

    func execute(id: Int, locale: String?) async throws -> PopularScienceArticleDetail {
        try await repository.loadArticle(id: id, locale: locale)
    }

    func execute(slug: String, locale: String) async throws -> PopularScienceArticleDetail {
        try await repository.loadArticle(slug: slug, locale: locale)
    }
}

struct LoadPopularScienceCategoriesUseCase: Sendable {
    let repository: any PopularScienceRepository

    func execute(locale: String) async throws -> [PopularScienceCategory] {
        try await repository.listCategories(locale: locale)
    }
}

struct ReportPopularScienceReadingUseCase: Sendable {
    let repository: any PopularScienceRepository

    func reportView(articleID: Int) async throws {
        try await repository.reportView(articleID: articleID)
    }

    func reportDuration(articleID: Int, durationSeconds: Int, sessionID: String?) async throws {
        try await repository.reportReadingDuration(
            articleID: articleID,
            durationSeconds: durationSeconds,
            sessionID: sessionID
        )
    }
}

struct SharePopularScienceArticleUseCase: Sendable {
    let repository: any PopularScienceRepository

    func shareURL(for article: PopularScienceArticleDetail) async throws -> URL {
        if let shareURL = article.shareURL {
            return shareURL
        }
        return try await repository.shareLink(articleID: article.id)
    }
}

