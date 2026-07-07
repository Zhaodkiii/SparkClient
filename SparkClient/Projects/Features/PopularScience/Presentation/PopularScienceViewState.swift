import Foundation

enum PopularScienceListPhase: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case failed(String)
}

enum PopularScienceDetailPhase: Equatable {
    case loading
    case loaded
    case failed(String)
}

enum PopularScienceReadingEndReason: Sendable {
    case viewDisappear
    case appBackground
}

struct PopularScienceArticleShareContext: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let summary: String?
    let shareURL: URL
}

