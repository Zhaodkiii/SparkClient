import Combine
import SwiftUI

@MainActor
final class NutritionRecipeFoodPickerViewModel: ObservableObject {
    @Published private(set) var results: [NutritionFoodSearchResultViewData] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessageKey: String?
    @Published var contentFilter: NutritionFoodAddContentFilter = .food

    private let memberID: Int
    private let searchUseCase: NutritionSearchUseCase
    private let notificationStore: NotificationStore
    private var reloadGeneration = 0

    init(
        memberID: Int,
        searchUseCase: NutritionSearchUseCase,
        notificationStore: NotificationStore
    ) {
        self.memberID = memberID
        self.searchUseCase = searchUseCase
        self.notificationStore = notificationStore
    }

    func loadIfNeeded() async {
        guard results.isEmpty, isLoading == false else { return }
        await reload()
    }

    func reload() async {
        reloadGeneration += 1
        let generation = reloadGeneration
        isLoading = true
        errorMessageKey = nil
        defer {
            if generation == reloadGeneration {
                isLoading = false
            }
        }

        let filters = NutritionFoodSearchFilterState(
            mode: .text,
            query: "",
            type: contentFilter.searchType,
            favoriteOnly: contentFilter == .frequent,
            createdByMeOnly: contentFilter.createdByMeOnly
        )

        do {
            let nextResults = try await searchUseCase.search(memberID: memberID, filters: filters)
            guard Task.isCancelled == false, generation == reloadGeneration else { return }
            results = nextResults
        } catch {
            guard Task.isCancelled == false, generation == reloadGeneration else { return }
            results = []
            errorMessageKey = NutritionErrorMapper.messageKey(for: error)
        }
    }

}

struct NutritionRecipeFoodPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: NutritionRecipeFoodPickerViewModel

    let existingFoodIDs: Set<Int>
    let onAddFood: (NutritionRecipeDraftFood) -> Void

    init(
        memberID: Int,
        searchUseCase: NutritionSearchUseCase,
        notificationStore: NotificationStore,
        existingFoodIDs: Set<Int>,
        onAddFood: @escaping (NutritionRecipeDraftFood) -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: NutritionRecipeFoodPickerViewModel(
                memberID: memberID,
                searchUseCase: searchUseCase,
                notificationStore: notificationStore
            )
        )
        self.existingFoodIDs = existingFoodIDs
        self.onAddFood = onAddFood
    }

    var body: some View {
        VStack(spacing: 0) {
            filterRow
            Divider()
            content
        }
        .navigationTitle(L10n.text("nutrition.recipe_picker.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L10n.text("nutrition.recipe_picker.done")) {
                    dismiss()
                }
            }
        }
        .task(id: viewModel.contentFilter) {
            await viewModel.reload()
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach([NutritionFoodAddContentFilter.food, .recipe, .frequent], id: \.id) { filter in
                    Button {
                        viewModel.contentFilter = filter
                    } label: {
                        Text(L10n.text(filter.localizationKey))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(
                                        viewModel.contentFilter == filter
                                            ? Color(uiColor: .systemTeal).opacity(0.15)
                                            : Color(uiColor: .tertiarySystemFill)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.results.isEmpty {
            ProgressView(L10n.text("nutrition.add.loading"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorKey = viewModel.errorMessageKey, viewModel.results.isEmpty {
            NutritionErrorStateView(
                messageKey: errorKey,
                retryTitleKey: "nutrition.common.retry"
            ) {
                Task { await viewModel.reload() }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, result in
                        resultRow(result)
                        if index < viewModel.results.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func resultRow(_ result: NutritionFoodSearchResultViewData) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                if result.subtitle.isEmpty == false {
                    Text(result.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(result.calorieText)
                .font(.headline.weight(.medium))
                .foregroundStyle(.secondary)
            Button {
                guard existingFoodIDs.contains(result.targetID) == false else { return }
                onAddFood(NutritionViewDataMapper.recipeDraftFood(from: result))
            } label: {
                Image(systemName: "plus")
                    .font(.title3.bold())
                    .foregroundStyle(Color(uiColor: .systemTeal))
                    .frame(width: 36, height: 36)
                    .background {
                        Circle()
                            .stroke(Color(uiColor: .systemTeal), lineWidth: 2)
                    }
            }
            .buttonStyle(.plain)
            .disabled(existingFoodIDs.contains(result.targetID))
        }
        .padding(.vertical, 10)
    }
}
