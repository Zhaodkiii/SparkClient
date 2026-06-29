import Combine
import SwiftUI

@MainActor
final class NutritionRecipeCreateViewModel: ObservableObject {
    @Published var descriptionText: String
    @Published var foods: [NutritionRecipeDraftFood]
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessageKey: String?
    @Published private(set) var createdRecipeID: Int?
    @Published private(set) var createdOverview: NutritionOverviewGridData?

    private let searchUseCase: NutritionSearchUseCase
    private let notificationStore: NotificationStore

    init(initialFoods: [NutritionRecipeDraftFood], dependencies: NutritionFeatureDependencies) {
        self.foods = initialFoods
        self.descriptionText = ""
        self.searchUseCase = dependencies.searchUseCase
        self.notificationStore = dependencies.notificationStore
    }

    var totalEnergyKcal: Double {
        foods.reduce(0) { $0 + $1.energyKcal * $1.servingRatio.rawValue }
    }

    var canSave: Bool {
        foods.isEmpty == false && isSaving == false
    }

    func removeFood(id: Int) {
        foods.removeAll { $0.foodItemID == id }
    }

    func addFood(_ food: NutritionRecipeDraftFood) {
        guard foods.contains(where: { $0.foodItemID == food.foodItemID }) == false else { return }
        foods.append(food)
    }

    func save(onSuccess: @escaping () -> Void) async {
        guard canSave else { return }
        isSaving = true
        errorMessageKey = nil
        defer { isSaving = false }

        do {
            let response = try await searchUseCase.createRecipe(
                from: foods,
                description: descriptionText
            )
            createdRecipeID = response.recipe.id
            createdOverview = NutritionOverviewGridData(
                energyKcal: response.overview.energyKcal,
                proteinGrams: response.overview.proteinG,
                carbohydrateGrams: response.overview.carbohydrateG,
                fatGrams: response.overview.fatG
            )
            NutritionNotificationPresenter.presentSuccess(
                store: notificationStore,
                message: L10n.text("nutrition.recipe_create.success"),
                source: "nutrition.recipe_create.save"
            )
            onSuccess()
        } catch {
            errorMessageKey = NutritionErrorMapper.messageKey(for: error)
            NutritionNotificationPresenter.presentError(
                store: notificationStore,
                messageKey: errorMessageKey ?? "nutrition.error.generic",
                source: "nutrition.recipe_create.save"
            )
        }
    }

    func clearError() {
        errorMessageKey = nil
    }
}

struct NutritionRecipeCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: NutritionRecipeCreateViewModel

    private let dependencies: NutritionFeatureDependencies
    private let memberID: Int

    @State private var showsPicker = false

    init(
        initialFoods: [NutritionRecipeDraftFood],
        dependencies: NutritionFeatureDependencies,
        memberID: Int = 0
    ) {
        self.dependencies = dependencies
        self.memberID = memberID
        _viewModel = StateObject(
            wrappedValue: NutritionRecipeCreateViewModel(
                initialFoods: initialFoods,
                dependencies: dependencies
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                descriptionField
                foodList
                addMoreButton
                saveButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("nutrition.recipe_create.title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showsPicker) {
            NutritionRecipeFoodPickerView(
                memberID: memberID > 0 ? memberID : dependencies.memberContextStore.context.selectedMemberID ?? 0,
                searchUseCase: dependencies.searchUseCase,
                notificationStore: dependencies.notificationStore,
                existingFoodIDs: Set(viewModel.foods.map(\.foodItemID))
            ) { food in
                viewModel.addFood(food)
            }
            .hidesMainTabBarWhenPushed()
        }
        .alert(
            L10n.text("nutrition.confirm.save_failed.title"),
            isPresented: errorAlertBinding
        ) {
            Button(L10n.text("common.ok"), role: .cancel) {}
        } message: {
            if let key = viewModel.errorMessageKey {
                Text(L10n.text(key))
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "takeoutbag.and.cup.and.straw.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color(uiColor: .systemTeal))
            Text(NutritionFormatting.energyKcal(viewModel.totalEnergyKcal))
                .font(.title2.weight(.bold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("nutrition.recipe_create.description"))
                .font(.subheadline.weight(.semibold))
            TextField(L10n.text("nutrition.recipe_create.description_placeholder"), text: $viewModel.descriptionText)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var foodList: some View {
        NutritionCardContainer(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(viewModel.foods.enumerated()), id: \.element.id) { index, food in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(food.title)
                                .font(.subheadline.weight(.semibold))
                            Text(food.servingText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            viewModel.removeFood(id: food.foodItemID)
                        } label: {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                    if index < viewModel.foods.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
    }

    private var addMoreButton: some View {
        Button {
            showsPicker = true
        } label: {
            HStack {
                Image(systemName: "plus")
                Text(L10n.text("nutrition.recipe_create.add_more"))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color(uiColor: .systemTeal))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(uiColor: .systemTeal), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var saveButton: some View {
        Button {
            Task {
                await viewModel.save {
                    dismiss()
                }
            }
        } label: {
            Group {
                if viewModel.isSaving {
                    ProgressView().tint(.white)
                } else {
                    Text(L10n.text("nutrition.recipe_create.save"))
                }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(viewModel.canSave ? Color.black : Color(uiColor: .systemGray3))
            )
        }
        .disabled(viewModel.canSave == false)
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessageKey != nil },
            set: { if $0 == false { viewModel.clearError() } }
        )
    }
}
