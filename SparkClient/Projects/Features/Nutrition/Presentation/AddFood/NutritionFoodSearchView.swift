import SwiftUI

struct NutritionFoodSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: NutritionFoodSearchViewModel

    let onAddResult: (NutritionFoodSearchResultViewData) -> Void
    let onOpenDetail: (NutritionFoodSearchResultViewData) -> Void

    init(
        memberID: Int,
        searchUseCase: NutritionSearchUseCase,
        notificationStore: NotificationStore,
        mode: NutritionFoodSearchMode,
        initialQuery: String = "",
        onAddResult: @escaping (NutritionFoodSearchResultViewData) -> Void,
        onOpenDetail: @escaping (NutritionFoodSearchResultViewData) -> Void = { _ in }
    ) {
        _viewModel = StateObject(
            wrappedValue: NutritionFoodSearchViewModel(
                memberID: memberID,
                searchUseCase: searchUseCase,
                notificationStore: notificationStore,
                mode: mode,
                initialQuery: initialQuery
            )
        )
        self.onAddResult = onAddResult
        self.onOpenDetail = onOpenDetail
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                searchField
                filterRow
                Divider()
                content
            }
            .navigationBarHidden(true)
            .task {
                await viewModel.loadInitialIfNeeded()
            }
        }
        .navigationViewStyle(.stack)
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L10n.text("nutrition.search.placeholder"), text: $viewModel.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { viewModel.submitSearch() }
                    .onChange(of: viewModel.query) { _ in
                        viewModel.queryChanged()
                    }
                if viewModel.query.isEmpty == false {
                    Button {
                        viewModel.clearQuery()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )

            Button(L10n.text("common.cancel")) {
                dismiss()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var filterRow: some View {
        HStack(spacing: 12) {
            filterChip(
                titleKey: "nutrition.search.filter.favorite",
                isActive: viewModel.favoriteOnly
            ) {
                viewModel.favoriteOnly.toggle()
                viewModel.submitSearch()
            }
            filterChip(
                titleKey: "nutrition.search.filter.created_by_me",
                isActive: viewModel.createdByMeOnly
            ) {
                viewModel.createdByMeOnly.toggle()
                viewModel.submitSearch()
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func filterChip(titleKey: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(L10n.text(titleKey))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(isActive ? Color.primary : Color(uiColor: .secondarySystemGroupedBackground))
                )
                .foregroundStyle(isActive ? Color(uiColor: .systemBackground) : .primary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.results.isEmpty {
            ProgressView(L10n.text("nutrition.search.loading"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorKey = viewModel.errorMessageKey, viewModel.results.isEmpty {
            emptyState(
                titleKey: errorKey,
                subtitleKey: "nutrition.search.empty.subtitle",
                showsReset: true
            )
        } else if viewModel.results.isEmpty && viewModel.hasSearched {
            emptyState(
                titleKey: "nutrition.search.empty.title",
                subtitleKey: "nutrition.search.empty.subtitle",
                showsReset: true
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, result in
                        NutritionFoodSearchResultCard(
                            result: result,
                            showsExpandedOverview: index == 0,
                            onOpenDetail: {
                                onOpenDetail(result)
                            },
                            onAdd: {
                                onAddResult(result)
                            },
                            onToggleFavorite: {
                                viewModel.toggleFavorite(for: result)
                            }
                        )
                        if index < viewModel.results.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    private func emptyState(titleKey: String, subtitleKey: String, showsReset: Bool) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Text(L10n.text("nutrition.search.empty.heading"))
                .font(.headline)
            Text(L10n.text(titleKey))
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(L10n.text(subtitleKey))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if showsReset {
                Button(L10n.text("nutrition.search.reset_filters")) {
                    viewModel.resetFilters()
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .padding(32)
    }
}
