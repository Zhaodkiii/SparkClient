import Combine
import Foundation

@MainActor
final class PopularScienceArticleDetailViewModel: ObservableObject {
    @Published private(set) var phase: PopularScienceDetailPhase = .loading
    @Published private(set) var article: PopularScienceArticleDetail?
    @Published private(set) var offlineNotice: String?
    @Published var shareContext: PopularScienceArticleShareContext?

    private let articleID: Int
    private let locale: String
    private let loadDetailUseCase: LoadPopularScienceArticleDetailUseCase
    private let reportReadingUseCase: ReportPopularScienceReadingUseCase

    private var didReportView = false
    private var didEndReading = false
    private var readingStartedAt: Date?
    private var readingSessionID = UUID().uuidString

    init(
        articleID: Int,
        locale: String = PopularScienceLocale.current,
        loadDetailUseCase: LoadPopularScienceArticleDetailUseCase,
        reportReadingUseCase: ReportPopularScienceReadingUseCase
    ) {
        self.articleID = articleID
        self.locale = locale
        self.loadDetailUseCase = loadDetailUseCase
        self.reportReadingUseCase = reportReadingUseCase
    }

    func load() async {
        phase = .loading
        offlineNotice = nil
        do {
            let loaded = try await loadDetailUseCase.execute(id: articleID, locale: locale)
            article = loaded
            if loaded.contentFormat.lowercased() != "markdown" {
                offlineNotice = PopularScienceError.unsupportedContentFormat(loaded.contentFormat).localizedDescription
            }
            phase = .loaded
            beginReading()
            await reportViewIfNeeded()
        } catch {
            phase = .failed(userFacingMessage(for: error))
        }
    }

    func retry() async {
        await load()
    }

    func beginReading() {
        guard readingStartedAt == nil else { return }
        readingStartedAt = Date()
    }

    func endReading(reason: PopularScienceReadingEndReason) {
        _ = reason
        guard didEndReading == false else { return }
        didEndReading = true
        guard let readingStartedAt else { return }
        let rawSeconds = Int(Date().timeIntervalSince(readingStartedAt))
        guard rawSeconds >= 3 else { return }
        let seconds = min(rawSeconds, 1800)
        let articleID = articleID
        let sessionID = readingSessionID
        let reportReadingUseCase = reportReadingUseCase
        Task {
            try? await reportReadingUseCase.reportDuration(
                articleID: articleID,
                durationSeconds: seconds,
                sessionID: sessionID
            )
        }
    }

    func share() {
        guard let article else { return }
        let shareURL = AppEnvironment.current.openWebBaseURL
            .appendingPathComponent("content")
            .appendingPathComponent(article.slug)
        shareContext = PopularScienceArticleShareContext(
            title: article.title,
            summary: article.summary,
            shareURL: shareURL
        )
    }

    private func reportViewIfNeeded() async {
        guard didReportView == false else { return }
        didReportView = true
        try? await reportReadingUseCase.reportView(articleID: articleID)
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return L10n.text("popular_science.error.load_failed", fallback: "Unable to load content. Pull to retry.")
    }
}
