import Foundation

nonisolated struct PopularSciencePaginationDTO: Codable, Sendable {
    let page: Int
    let pageSize: Int
    let total: Int
    let totalPages: Int
}

nonisolated struct PopularSciencePageDTO<T: Codable & Sendable>: Codable, Sendable {
    let items: [T]
    let pagination: PopularSciencePaginationDTO
}

nonisolated struct PopularScienceArticleSummaryDTO: Codable, Sendable {
    let id: Int
    let title: String
    let slug: String
    let locale: String
    let summary: String?
    let coverImage: String?
    let category: PopularScienceCategoryDTO?
    let tags: [PopularScienceTagDTO]?
    let isTop: Bool?
    let isRecommended: Bool?
    let viewCount: Int?
    let estimatedReadingMinutes: Int?
    let publishedAt: Date?
}

nonisolated struct PopularScienceArticleDetailDTO: Codable, Sendable {
    let id: Int
    let title: String
    let slug: String
    let locale: String
    let translationGroupId: Int?
    let summary: String?
    let coverImage: String?
    let content: String
    let contentFormat: String?
    let category: PopularScienceCategoryDTO?
    let tags: [PopularScienceTagDTO]?
    let sourceUrl: String?
    let references: FlexibleReferencesList?
    let referencesJson: FlexibleReferencesList?
    let shareUrl: String?
    let shareLinks: PopularScienceShareLinksDTO?
    let estimatedReadingMinutes: Int?
    let publishedAt: Date?
    let updatedAt: Date?
}

/// 兼容 references / references_json 返回字符串、单对象或数组。
nonisolated struct FlexibleReferencesList: Codable, Sendable {
    let items: [PopularScienceReferenceDTO]

    init(items: [PopularScienceReferenceDTO] = []) {
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            items = []
            return
        }
        if let array = try? container.decode([PopularScienceReferenceDTO].self) {
            items = array
            return
        }
        if let object = try? container.decode(PopularScienceReferenceDTO.self) {
            items = [object]
            return
        }
        if let text = try? container.decode(String.self) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                items = []
                return
            }
            if let data = trimmed.data(using: .utf8),
               let parsed = try? JSONDecoder.default.decode([PopularScienceReferenceDTO].self, from: data) {
                items = parsed
                return
            }
            let url = trimmed.lowercased().hasPrefix("http") ? trimmed : nil
            items = [PopularScienceReferenceDTO(title: trimmed, url: url, source: nil, publishedAt: nil)]
            return
        }
        items = []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(items)
    }
}

nonisolated struct PopularScienceShareLinksDTO: Codable, Sendable {
    let shareUrl: String?
    let appSchemeUrl: String?
    let universalLinkUrl: String?
}

nonisolated struct PopularScienceCategoryDTO: Codable, Sendable {
    let id: Int
    let name: String
    let slug: String
}

nonisolated struct PopularScienceTagDTO: Codable, Sendable {
    let id: Int
    let name: String
    let slug: String
}

nonisolated struct PopularScienceReferenceDTO: Codable, Sendable {
    let title: String
    let url: String?
    let source: String?
    let publishedAt: Date?
}

nonisolated struct PopularScienceShareLinkDTO: Decodable, Sendable {
    let shareUrl: String
}

nonisolated struct PopularScienceViewPayload: Encodable, Sendable {
    let clientPlatform: String = "ios"
}

nonisolated struct PopularScienceReadingDurationPayload: Encodable, Sendable {
    let durationSeconds: Int
    let sessionId: String?
    let clientPlatform: String = "ios"
}
