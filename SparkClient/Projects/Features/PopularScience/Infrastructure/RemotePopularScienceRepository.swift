import Foundation

struct RemotePopularScienceRepository: PopularScienceRepository {
    let api: PopularScienceRemoteAPI
    let cacheStore: PopularScienceCacheStore
    let logger: Logger

    init(
        api: PopularScienceRemoteAPI,
        cacheStore: PopularScienceCacheStore = PopularScienceCacheStore(),
        logger: Logger = ConsoleLogger()
    ) {
        self.api = api
        self.cacheStore = cacheStore
        self.logger = logger
    }

    func listArticles(
        filter: PopularScienceListFilter,
        page: Int,
        pageSize: Int
    ) async throws -> PopularSciencePage<PopularScienceArticleSummary> {
        do {
            let dto = try await api.listArticles(
                locale: filter.locale,
                page: page,
                pageSize: pageSize,
                categoryID: filter.categoryID,
                tagID: filter.tagID,
                query: filter.query,
                recommendedOnly: filter.recommendedOnly
            )
            await cacheStore.saveList(dto, filter: filter, pageNumber: page)
            return dto.toDomain()
        } catch {
            logger.error("科普列表远端加载失败，尝试缓存 page=\(page) error=\(error.localizedDescription)", module: .network)
            if let cached = await cacheStore.loadList(filter: filter, pageNumber: page) {
                return cached.toDomain()
            }
            throw error
        }
    }

    func loadArticle(id: Int, locale: String?) async throws -> PopularScienceArticleDetail {
        let effectiveLocale = locale ?? PopularScienceLocale.current
        do {
            let dto = try await api.loadArticle(id: id, locale: locale)
            await cacheStore.saveDetail(dto)
            return dto.toDomain()
        } catch {
            logger.error("科普详情远端加载失败，尝试缓存 id=\(id) error=\(error.localizedDescription)", module: .network)
            if let cached = await cacheStore.loadDetail(id: id, locale: effectiveLocale) {
                return cached.toDomain()
            }
            throw error
        }
    }

    func loadArticle(slug: String, locale: String) async throws -> PopularScienceArticleDetail {
        do {
            let dto = try await api.loadArticle(slug: slug, locale: locale)
            await cacheStore.saveDetail(dto)
            return dto.toDomain()
        } catch {
            logger.error("科普详情远端加载失败，尝试缓存 slug=\(slug) error=\(error.localizedDescription)", module: .network)
            if let cached = await cacheStore.loadDetail(slug: slug, locale: locale) {
                return cached.toDomain()
            }
            throw error
        }
    }

    func listCategories(locale: String) async throws -> [PopularScienceCategory] {
        do {
            let dto = try await api.listCategories(locale: locale)
            await cacheStore.saveCategories(dto, locale: locale)
            return dto.map { $0.toDomain() }
        } catch {
            logger.error("科普分类远端加载失败，尝试缓存 error=\(error.localizedDescription)", module: .network)
            if let cached = await cacheStore.loadCategories(locale: locale) {
                return cached.map { $0.toDomain() }
            }
            return []
        }
    }

    func listTags(locale: String) async throws -> [PopularScienceTag] {
        let dto = try await api.listTags(locale: locale)
        return dto.map { $0.toDomain() }
    }

    func reportView(articleID: Int) async throws {
        try await api.reportView(articleID: articleID)
    }

    func reportReadingDuration(articleID: Int, durationSeconds: Int, sessionID: String?) async throws {
        try await api.reportReadingDuration(
            articleID: articleID,
            durationSeconds: durationSeconds,
            sessionID: sessionID
        )
    }

    func shareLink(articleID: Int) async throws -> URL {
        try await api.shareLink(articleID: articleID)
    }
}

