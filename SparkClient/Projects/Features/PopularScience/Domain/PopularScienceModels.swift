import Foundation

struct PopularScienceArticleSummary: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let slug: String
    let locale: String
    let summary: String?
    let coverImageURL: URL?
    let category: PopularScienceCategory?
    let tags: [PopularScienceTag]
    let isTop: Bool
    let isRecommended: Bool
    let viewCount: Int
    let estimatedReadingMinutes: Int?
    let publishedAt: Date?
}

struct PopularScienceArticleDetail: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let slug: String
    let locale: String
    let translationGroupID: Int?
    let summary: String?
    let coverImageURL: URL?
    let content: String
    let contentFormat: String
    let category: PopularScienceCategory?
    let tags: [PopularScienceTag]
    let sourceURL: URL?
    let references: [PopularScienceReference]
    let shareURL: URL?
    let estimatedReadingMinutes: Int?
    let publishedAt: Date?
    let updatedAt: Date?
}

struct PopularScienceCategory: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let slug: String
}

struct PopularScienceTag: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let slug: String
}

struct PopularScienceReference: Hashable, Sendable {
    let title: String
    let url: URL?
    let source: String?
    let publishedAt: Date?
}

struct PopularSciencePage<T: Sendable>: Sendable {
    let items: [T]
    let page: Int
    let pageSize: Int
    let total: Int
    let hasNext: Bool
}

struct PopularScienceListFilter: Hashable, Sendable {
    var locale: String
    var categoryID: Int?
    var tagID: Int?
    var query: String?
    var recommendedOnly: Bool?

    static func current(categoryID: Int? = nil) -> PopularScienceListFilter {
        PopularScienceListFilter(
            locale: PopularScienceLocale.current,
            categoryID: categoryID,
            tagID: nil,
            query: nil,
            recommendedOnly: nil
        )
    }
}

enum PopularScienceLocale {
    static var current: String {
        let identifier = Locale.current.identifier
        if identifier.hasPrefix("zh-Hant") || identifier.hasPrefix("zh_TW") || identifier.hasPrefix("zh-HK") {
            return "zh-Hant"
        }
        if identifier.hasPrefix("zh") {
            return "zh-CN"
        }
        return "en-US"
    }
}

