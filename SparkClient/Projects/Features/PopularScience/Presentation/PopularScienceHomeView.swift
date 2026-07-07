import SwiftUI

struct PopularScienceHomeView: View {
    @ObservedObject var viewModel: PopularScienceHomeViewModel

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                PopularScienceEmptyStateView(
                    title: L10n.text("popular_science.empty.title", fallback: "No articles yet"),
                    subtitle: L10n.text("popular_science.empty.subtitle", fallback: "Check back later for health guides and tips."),
                    actionTitle: L10n.text("popular_science.retry", fallback: "Retry")
                ) {
                    Task { await viewModel.refresh() }
                }
            case .failed(let message):
                PopularScienceErrorView(message: message) {
                    Task { await viewModel.refresh() }
                }
            case .loaded:
                content
            }
        }
        .navigationTitle(L10n.text("popular_science.title", fallback: "Learn"))
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    private var content: some View {
        List {
            if let offlineNotice = viewModel.offlineNotice {
                Text(offlineNotice)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            PopularScienceCategoryFilterBar(
                categories: viewModel.categories,
                selectedCategoryID: viewModel.selectedCategoryID,
                onSelect: { category in
                    Task { await viewModel.selectCategory(category) }
                }
            )
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowSeparator(.hidden)

            ForEach(viewModel.articles) { article in
                PopularScienceArticleRowView(article: article)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.openArticle(article)
                    }
                    .onAppear {
                        Task {
                            await viewModel.loadNextPageIfNeeded(currentItem: article)
                        }
                    }
            }

            if viewModel.isLoadingNextPage {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .listStyle(.plain)
    }
}

struct PopularScienceCategoryFilterBar: View {
    let categories: [PopularScienceCategory]
    let selectedCategoryID: Int?
    let onSelect: (PopularScienceCategory?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterButton(
                    title: L10n.text("popular_science.category.all", fallback: "All"),
                    isSelected: selectedCategoryID == nil
                ) {
                    onSelect(nil)
                }

                ForEach(categories) { category in
                    filterButton(
                        title: category.name,
                        isSelected: selectedCategoryID == category.id
                    ) {
                        onSelect(category)
                    }
                }
            }
        }
    }

    private func filterButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }
}

struct PopularScienceArticleRowView: View {
    let article: PopularScienceArticleSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if article.coverImageURL != nil {
                thumbnail
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if article.isTop {
                        badge(L10n.text("popular_science.badge.top", fallback: "Top"))
                    }
                    if article.isRecommended {
                        badge(L10n.text("popular_science.badge.recommended", fallback: "Recommended"))
                    }
                }

                Text(article.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if let summary = article.summary, summary.isEmpty == false {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                metadata
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = article.coverImageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 82, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                case .failure:
                    EmptyView()
                case .empty:
                    ProgressView()
                        .frame(width: 82, height: 64)
                @unknown default:
                    EmptyView()
                }
            }
        }
    }

    private var metadata: some View {
        HStack(spacing: 6) {
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
    }

    private func badge(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
    }
}

struct PopularScienceEmptyStateView: View {
    let title: String
    let subtitle: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.pages")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PopularScienceErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(L10n.text("popular_science.retry", fallback: "Retry"), action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

