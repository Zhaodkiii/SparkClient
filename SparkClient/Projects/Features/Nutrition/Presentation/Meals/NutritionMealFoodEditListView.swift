import Combine
import SwiftUI

@MainActor
final class NutritionMealFoodEditListViewModel: ObservableObject {
    @Published var items: [NutritionMealFoodEditItemViewData]
    @Published var selectedIDs: Set<Int> = []
    @Published var showDeleteConfirmation = false
    @Published private(set) var isDeleting = false
    @Published private(set) var errorMessageKey: String?

    let records: [SparkNutritionAPI.RemoteMealRecord]
    let memberID: Int
    let date: Date
    let mealType: NutritionMealType?

    private let mealRecordUseCase: NutritionMealRecordUseCase
    private let notificationStore: NotificationStore

    init(
        records: [SparkNutritionAPI.RemoteMealRecord],
        memberID: Int,
        date: Date,
        mealType: NutritionMealType? = nil,
        dependencies: NutritionFeatureDependencies
    ) {
        self.records = records
        self.memberID = memberID
        self.date = date
        self.mealType = mealType
        self.items = NutritionViewDataMapper.mealFoodEditItems(from: records)
        self.mealRecordUseCase = dependencies.mealRecordUseCase
        self.notificationStore = dependencies.notificationStore
    }

    var isAllSelected: Bool {
        items.isEmpty == false && selectedIDs.count == items.count
    }

    var canPerformAction: Bool { selectedIDs.isEmpty == false }

    var canCreateRecipe: Bool { selectedIDs.count >= 2 }

    var selectedItems: [NutritionMealFoodEditItemViewData] {
        items.filter { selectedIDs.contains($0.mealFoodID) }
    }

    var selectedHasAppleHealth: Bool {
        selectedItems.contains(where: \.hasAppleHealthLinkedRecord)
    }

    func toggleSelectAll() {
        if isAllSelected {
            selectedIDs.removeAll()
        } else {
            selectedIDs = Set(items.map(\.mealFoodID))
        }
    }

    func toggleSelection(for itemID: Int) {
        if selectedIDs.contains(itemID) {
            selectedIDs.remove(itemID)
        } else {
            selectedIDs.insert(itemID)
        }
    }

    func prepareDelete() {
        guard canPerformAction else { return }
        showDeleteConfirmation = true
    }

    func confirmDelete(onSuccess: @escaping () -> Void) async {
        guard isDeleting == false else { return }
        isDeleting = true
        errorMessageKey = nil
        defer { isDeleting = false }

        do {
            try await mealRecordUseCase.deleteMealFoods(
                mealFoodIDs: selectedIDs,
                records: records
            )
            NotificationCenter.default.post(name: .nutritionMealRecordDidSave, object: nil)
            onSuccess()
        } catch {
            errorMessageKey = NutritionErrorMapper.messageKey(for: error)
            NutritionNotificationPresenter.presentError(
                store: notificationStore,
                messageKey: errorMessageKey ?? "nutrition.error.generic",
                source: "nutrition.meal_food_edit.delete"
            )
        }
    }

    func clearError() {
        errorMessageKey = nil
    }
}

struct NutritionMealFoodEditListView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: NutritionMealFoodEditListViewModel

    private let dependencies: NutritionFeatureDependencies

    @State private var showsCopy = false
    @State private var showsCreateRecipe = false

    init(
        records: [SparkNutritionAPI.RemoteMealRecord],
        memberID: Int,
        date: Date,
        mealType: NutritionMealType? = nil,
        dependencies: NutritionFeatureDependencies
    ) {
        self.dependencies = dependencies
        _viewModel = StateObject(
            wrappedValue: NutritionMealFoodEditListViewModel(
                records: records,
                memberID: memberID,
                date: date,
                mealType: mealType,
                dependencies: dependencies
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.items.isEmpty {
                NutritionEmptyStateView(
                    titleKey: "nutrition.meal.empty.title",
                    subtitleKey: "nutrition.meal.empty.subtitle"
                )
                .frame(maxHeight: .infinity)
            } else {
                itemList
            }
            bottomBar
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(L10n.text("nutrition.meal_food_edit.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(viewModel.isAllSelected ? L10n.text("nutrition.meal_food_edit.deselect_all") : L10n.text("nutrition.meal_food_edit.select_all")) {
                    viewModel.toggleSelectAll()
                }
                .disabled(viewModel.items.isEmpty)
            }
        }
        .background {
            NavigationLink(
                destination: NutritionMealFoodCopyView(
                    items: viewModel.selectedItems,
                    memberID: viewModel.memberID,
                    sourceDate: viewModel.date,
                    sourceMealType: viewModel.mealType,
                    dependencies: dependencies
                )
                .hidesMainTabBarWhenPushed(),
                isActive: $showsCopy
            ) {
                EmptyView()
            }
            .hidden()

            NavigationLink(
                destination: NutritionRecipeCreateView(
                    initialFoods: viewModel.selectedItems.map(NutritionViewDataMapper.recipeDraftFood),
                    dependencies: dependencies,
                    memberID: viewModel.memberID
                )
                .hidesMainTabBarWhenPushed(),
                isActive: $showsCreateRecipe
            ) {
                EmptyView()
            }
            .hidden()
        }
        .alert(
            L10n.text("nutrition.meal_food_edit.delete_confirm.title"),
            isPresented: $viewModel.showDeleteConfirmation
        ) {
            Button(L10n.text("nutrition.common.cancel"), role: .cancel) {}
            Button(L10n.text("nutrition.common.delete"), role: .destructive) {
                Task {
                    await viewModel.confirmDelete {
                        dismiss()
                    }
                }
            }
        } message: {
            if viewModel.selectedHasAppleHealth {
                Text(L10n.text("nutrition.apple_health.delete_hint"))
            } else {
                Text(L10n.text("nutrition.meal_food_edit.delete_confirm.message"))
            }
        }
    }

    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                    itemRow(item)
                    if index < viewModel.items.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func itemRow(_ item: NutritionMealFoodEditItemViewData) -> some View {
        Button {
            viewModel.toggleSelection(for: item.mealFoodID)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: viewModel.selectedIDs.contains(item.mealFoodID) ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(
                        viewModel.selectedIDs.contains(item.mealFoodID)
                            ? Color(uiColor: .systemTeal)
                            : .secondary
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(NutritionFormatting.energyKcal(item.energyKcal))
                            .font(.headline.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Text(item.servingText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            bottomAction(
                titleKey: "nutrition.meal_food_edit.delete",
                isEnabled: viewModel.canPerformAction && viewModel.isDeleting == false
            ) {
                viewModel.prepareDelete()
            }

            Divider().frame(height: 24)

            bottomAction(
                titleKey: "nutrition.meal_food_edit.copy",
                isEnabled: viewModel.canPerformAction
            ) {
                showsCopy = true
            }

            Divider().frame(height: 24)

            bottomAction(
                titleKey: "nutrition.meal_food_edit.create_recipe",
                isEnabled: viewModel.canCreateRecipe
            ) {
                showsCreateRecipe = true
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private func bottomAction(
        titleKey: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(L10n.text(titleKey))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isEnabled ? Color(uiColor: .systemTeal) : Color(uiColor: .systemGray3))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(isEnabled == false)
    }
}
