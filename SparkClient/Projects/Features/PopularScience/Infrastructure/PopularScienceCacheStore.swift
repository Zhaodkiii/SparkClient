import Foundation

actor PopularScienceCacheStore {
    private let rootURL: URL
    private let fileManager: FileManager

    init(
        rootURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            self.rootURL = caches.appendingPathComponent("PopularScience", isDirectory: true)
        }
    }

    func saveList(
        _ page: PopularSciencePageDTO<PopularScienceArticleSummaryDTO>,
        filter: PopularScienceListFilter,
        pageNumber: Int
    ) async {
        try? write(page, to: listURL(filter: filter, page: pageNumber))
    }

    func loadList(
        filter: PopularScienceListFilter,
        pageNumber: Int
    ) async -> PopularSciencePageDTO<PopularScienceArticleSummaryDTO>? {
        try? read(PopularSciencePageDTO<PopularScienceArticleSummaryDTO>.self, from: listURL(filter: filter, page: pageNumber))
    }

    func saveDetail(_ detail: PopularScienceArticleDetailDTO) async {
        try? write(detail, to: detailIDURL(id: detail.id, locale: detail.locale))
        try? write(detail, to: detailSlugURL(slug: detail.slug, locale: detail.locale))
    }

    func loadDetail(id: Int, locale: String) async -> PopularScienceArticleDetailDTO? {
        try? read(PopularScienceArticleDetailDTO.self, from: detailIDURL(id: id, locale: locale))
    }

    func loadDetail(slug: String, locale: String) async -> PopularScienceArticleDetailDTO? {
        try? read(PopularScienceArticleDetailDTO.self, from: detailSlugURL(slug: slug, locale: locale))
    }

    func saveCategories(_ categories: [PopularScienceCategoryDTO], locale: String) async {
        try? write(categories, to: categoriesURL(locale: locale))
    }

    func loadCategories(locale: String) async -> [PopularScienceCategoryDTO]? {
        try? read([PopularScienceCategoryDTO].self, from: categoriesURL(locale: locale))
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try ensureRoot()
        let data = try JSONEncoder.default.encode(value)
        try data.write(to: url, options: [.atomic])
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try JSONDecoder.default.decode(type, from: data)
    }

    private func ensureRoot() throws {
        if fileManager.fileExists(atPath: rootURL.path) == false {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }
    }

    private func listURL(filter: PopularScienceListFilter, page: Int) -> URL {
        let category = filter.categoryID.map(String.init) ?? "all"
        let tag = filter.tagID.map(String.init) ?? "all"
        let recommended = filter.recommendedOnly.map { $0 ? "recommended" : "all" } ?? "all"
        let query = sanitized(filter.query ?? "none")
        return rootURL.appendingPathComponent("articles_\(sanitized(filter.locale))_\(category)_\(tag)_\(recommended)_\(query)_\(page).json")
    }

    private func detailIDURL(id: Int, locale: String) -> URL {
        rootURL.appendingPathComponent("article_\(sanitized(locale))_id_\(id).json")
    }

    private func detailSlugURL(slug: String, locale: String) -> URL {
        rootURL.appendingPathComponent("article_\(sanitized(locale))_slug_\(sanitized(slug)).json")
    }

    private func categoriesURL(locale: String) -> URL {
        rootURL.appendingPathComponent("categories_\(sanitized(locale)).json")
    }

    private func sanitized(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
    }
}

