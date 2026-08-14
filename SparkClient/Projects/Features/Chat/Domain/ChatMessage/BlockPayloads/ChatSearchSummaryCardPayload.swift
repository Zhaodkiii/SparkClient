import Foundation

nonisolated struct ChatSearchSummaryReference: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let url: String
    let snippet: String?
    let sourceName: String?
    let publishedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        url: String,
        snippet: String? = nil,
        sourceName: String? = nil,
        publishedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.snippet = snippet
        self.sourceName = sourceName
        self.publishedAt = publishedAt
    }
}

nonisolated struct ChatSearchSummaryCardPayload: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: UUID
    let providerName: String
    let query: String
    let keywords: [String]
    let references: [ChatSearchSummaryReference]
    let totalEstimatedMatches: Int?

    init(
        id: UUID = UUID(),
        providerName: String,
        query: String,
        keywords: [String],
        references: [ChatSearchSummaryReference],
        totalEstimatedMatches: Int? = nil
    ) {
        self.id = id
        self.providerName = providerName
        self.query = query
        self.keywords = keywords
        self.references = references
        self.totalEstimatedMatches = totalEstimatedMatches
    }
}
