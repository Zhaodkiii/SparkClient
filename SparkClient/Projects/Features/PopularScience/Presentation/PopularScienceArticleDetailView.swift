import SwiftUI

struct PopularScienceArticleDetailView: View {
    @StateObject private var viewModel: PopularScienceArticleDetailViewModel
    @Environment(\.scenePhase) private var scenePhase

    init(viewModel: PopularScienceArticleDetailViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                PopularScienceErrorView(message: message) {
                    Task { await viewModel.retry() }
                }
            case .loaded:
                detailContent
            }
        }
        .navigationTitle(viewModel.article?.title ?? L10n.text("popular_science.title", fallback: "Learn"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.share()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(L10n.text("popular_science.share", fallback: "Share"))
                .disabled(viewModel.article == nil)
            }
        }
        .sheet(item: $viewModel.shareContext) { context in
            PopularScienceArticleShareSheet(context: context) {
                viewModel.shareContext = nil
            }
        }
        .task {
            await viewModel.load()
        }
        .onDisappear {
            viewModel.endReading(reason: .viewDisappear)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                viewModel.endReading(reason: .appBackground)
            }
        }
    }

    private var detailContent: some View {
        ScrollView {
            if let article = viewModel.article {
                VStack(alignment: .leading, spacing: 18) {
//                    header(article)
//
//                    if let offlineNotice = viewModel.offlineNotice {
//                        Text(offlineNotice)
//                            .font(.footnote)
//                            .foregroundStyle(.secondary)
//                    }
//
//                    cover(article.coverImageURL)

                    Markdown(article.content)

                    PopularScienceReferenceSection(article: article)
                }
                .padding()
            }
        }
    }

    private func header(_ article: PopularScienceArticleDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(article.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)

            if let summary = article.summary, summary.isEmpty == false {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if let category = article.category {
                    Text(category.name)
                }
                if let minutes = article.estimatedReadingMinutes {
                    Text("\(minutes) min")
                }
                if let publishedAt = article.publishedAt {
                    Text(publishedAt, style: .date)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func cover(_ url: URL?) -> some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Color.secondary.opacity(0.12)
                case .empty:
                    ProgressView()
                @unknown default:
                    Color.secondary.opacity(0.12)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
        }
    }
}

struct PopularScienceReferenceSection: View {
    let article: PopularScienceArticleDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("popular_science.medical_disclaimer", fallback: "This content is for reference only and does not replace medical advice."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(10)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            if article.sourceURL != nil || article.references.isEmpty == false {
                Text(L10n.text("popular_science.references", fallback: "References"))
                    .font(.headline)

                if let sourceURL = article.sourceURL {
                    Link(sourceURL.absoluteString, destination: sourceURL)
                        .font(.footnote)
                }

                ForEach(Array(article.references.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.subheadline.weight(.medium))
                        if let source = item.source {
                            Text(source)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let url = item.url {
                            Link(url.absoluteString, destination: url)
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }
}


