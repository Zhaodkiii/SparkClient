import Foundation

struct PopularScienceRemoteAPI: Sendable {
    private static let defaultETagTTL: TimeInterval = 24 * 60 * 60

    let configuration: SparkBackendConfiguration

    init(configuration: SparkBackendConfiguration) {
        self.configuration = configuration
    }

    init(engine: SparkNetworkEngine) {
        self.configuration = SparkBackendConfiguration(
            engine: engine,
            deviceCache: engine.cache(),
            logger: engine.networkLogger
        )
    }

    func listArticles(
        locale: String,
        page: Int,
        pageSize: Int,
        categoryID: Int?,
        tagID: Int?,
        query: String?,
        recommendedOnly: Bool?
    ) async throws -> PopularSciencePageDTO<PopularScienceArticleSummaryDTO> {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "locale", value: locale),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: String(pageSize))
        ]
        if let categoryID {
            queryItems.append(URLQueryItem(name: "category_id", value: String(categoryID)))
        }
        if let tagID {
            queryItems.append(URLQueryItem(name: "tag_id", value: String(tagID)))
        }
        if let query, query.isEmpty == false {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }
        if let recommendedOnly {
            queryItems.append(URLQueryItem(name: "is_recommended", value: recommendedOnly ? "true" : "false"))
        }

        let operation = CacheableSparkNetworkOperation(
            name: "PopularScience.ListArticles",
            apiName: "PopularScienceAPI",
            request: SparkNetworkRequest(
                method: .get,
                path: "/api/v1/content/articles/",
                queryItems: queryItems,
                strategy: NetworkStrategy(
                    requiresAuth: false,
                    // 文章列表是高频只读接口，服务端返回 ETag 时可用 304 降低列表刷新流量。
                    allowETag: true,
                    serialKey: "popular_science.articles.list",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .normal,
                    etagTTL: Self.defaultETagTTL
                )
            )
        )
        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedDataOrDirect(
            PopularSciencePageDTO<PopularScienceArticleSummaryDTO>.self,
            from: response
        )
    }

    func loadArticle(id: Int, locale: String?) async throws -> PopularScienceArticleDetailDTO {
        var queryItems: [URLQueryItem] = []
        if let locale, locale.isEmpty == false {
            queryItems.append(URLQueryItem(name: "locale", value: locale))
        }
        let operation = detailOperation(
            name: "PopularScience.DetailByID",
            path: "/api/v1/content/articles/\(id)/",
            queryItems: queryItems,
            serialKey: "popular_science.article.detail.\(id)"
        )
        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedDataOrDirect(PopularScienceArticleDetailDTO.self, from: response)
    }

    func loadArticle(slug: String, locale: String) async throws -> PopularScienceArticleDetailDTO {
        let safeSlug = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug
        let operation = detailOperation(
            name: "PopularScience.DetailBySlug",
            path: "/api/v1/content/articles/\(safeSlug)/",
            queryItems: [URLQueryItem(name: "locale", value: locale)],
            serialKey: "popular_science.article.slug.\(locale).\(slug)"
        )
        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedDataOrDirect(PopularScienceArticleDetailDTO.self, from: response)
    }

    func listCategories(locale: String) async throws -> [PopularScienceCategoryDTO] {
        let operation = CacheableSparkNetworkOperation(
            name: "PopularScience.Categories",
            apiName: "PopularScienceAPI",
            request: SparkNetworkRequest(
                method: .get,
                path: "/api/v1/content/categories/",
                queryItems: [URLQueryItem(name: "locale", value: locale)],
                strategy: NetworkStrategy(
                    requiresAuth: false,
                    // 分类变更频率低，适合条件请求缓存。
                    allowETag: true,
                    serialKey: "popular_science.categories",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .low,
                    etagTTL: Self.defaultETagTTL
                )
            )
        )
        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedDataOrDirect([PopularScienceCategoryDTO].self, from: response)
    }

    func listTags(locale: String) async throws -> [PopularScienceTagDTO] {
        let operation = CacheableSparkNetworkOperation(
            name: "PopularScience.Tags",
            apiName: "PopularScienceAPI",
            request: SparkNetworkRequest(
                method: .get,
                path: "/api/v1/content/tags/",
                queryItems: [URLQueryItem(name: "locale", value: locale)],
                strategy: NetworkStrategy(
                    requiresAuth: false,
                    // 标签变更频率低，适合条件请求缓存。
                    allowETag: true,
                    serialKey: "popular_science.tags",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .low,
                    etagTTL: Self.defaultETagTTL
                )
            )
        )
        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedDataOrDirect([PopularScienceTagDTO].self, from: response)
    }

    func reportView(articleID: Int) async throws {
        let operation = CacheableSparkNetworkOperation(
            name: "PopularScience.ReportView",
            apiName: "PopularScienceAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/content/articles/\(articleID)/view/",
                body: .json(AnyEncodable(PopularScienceViewPayload())),
                strategy: statisticsStrategy(serialKey: "popular_science.article.view.\(articleID)")
            )
        )
        _ = try await configuration.execute(operation)
    }

    func reportReadingDuration(articleID: Int, durationSeconds: Int, sessionID: String?) async throws {
        let payload = PopularScienceReadingDurationPayload(
            durationSeconds: durationSeconds,
            sessionId: sessionID
        )
        let operation = CacheableSparkNetworkOperation(
            name: "PopularScience.ReportReadingDuration",
            apiName: "PopularScienceAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/content/articles/\(articleID)/reading-duration/",
                body: .json(AnyEncodable(payload)),
                strategy: statisticsStrategy(serialKey: "popular_science.article.reading_duration.\(articleID)")
            )
        )
        _ = try await configuration.execute(operation)
    }

    func shareLink(articleID: Int) async throws -> URL {
        let operation = CacheableSparkNetworkOperation(
            name: "PopularScience.ShareLink",
            apiName: "PopularScienceAPI",
            request: SparkNetworkRequest(
                method: .get,
                path: "/api/v1/content/articles/\(articleID)/share-link/",
                strategy: NetworkStrategy(
                    requiresAuth: false,
                    // 分享链接是只读且通常稳定；若服务端返回 ETag，可复用本地 share_url。
                    allowETag: true,
                    serialKey: "popular_science.article.share_link.\(articleID)",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .normal,
                    etagTTL: Self.defaultETagTTL
                )
            )
        )
        let response = try await configuration.execute(operation)
        let payload = try APIResponseDecoder.decodeWrappedDataOrDirect(PopularScienceShareLinkDTO.self, from: response)
        guard let url = URL(string: payload.shareUrl) else {
            throw PopularScienceError.invalidShareURL
        }
        return url
    }

    private func detailOperation(
        name: String,
        path: String,
        queryItems: [URLQueryItem],
        serialKey: String
    ) -> CacheableSparkNetworkOperation {
        CacheableSparkNetworkOperation(
            name: name,
            apiName: "PopularScienceAPI",
            request: SparkNetworkRequest(
                method: .get,
                path: path,
                queryItems: queryItems.isEmpty ? nil : queryItems,
                strategy: NetworkStrategy(
                    requiresAuth: false,
                    // 文章正文体积较大，详情页最适合用 ETag 做 304 合并。
                    allowETag: true,
                    serialKey: serialKey,
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .normal,
                    etagTTL: Self.defaultETagTTL
                )
            )
        )
    }

    private func statisticsStrategy(serialKey: String) -> NetworkStrategy {
        NetworkStrategy(
            requiresAuth: false,
            allowETag: false,
            serialKey: serialKey,
            retryConfig: RetryConfig(
                isEnabled: false,
                maxRetryCount: 0,
                retryableStatusCodes: [],
                retryableURLErrorCodes: [],
                honorsRetryAfter: false,
                backoffIntervals: []
            ),
            isIdempotent: false,
            queuePriority: .low
        )
    }
}
