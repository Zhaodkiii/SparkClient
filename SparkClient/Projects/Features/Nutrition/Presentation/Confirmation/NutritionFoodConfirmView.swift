import SwiftUI

struct NutritionFoodConfirmView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: NutritionFoodConfirmViewModel

    let onSaveSuccess: () -> Void

    init(
        dependencies: NutritionFeatureDependencies,
        memberID: Int,
        date: Date,
        mealType: NutritionMealType,
        items: [NutritionFoodSelectionItem],
        onSaveSuccess: @escaping () -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: NutritionFoodConfirmViewModel(
                dependencies: dependencies,
                memberID: memberID,
                date: date,
                mealType: mealType,
                items: items
            )
        )
        self.onSaveSuccess = onSaveSuccess
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                mealHeader
                NutritionOverviewGridCard(data: viewModel.overview)
                selectedItemsSection
                confirmButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("nutrition.confirm.title"))
        .navigationBarTitleDisplayMode(.inline)
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

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessageKey != nil },
            set: { if $0 == false { viewModel.clearError() } }
        )
    }

    private var mealHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text("nutrition.confirm.meal_label"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(L10n.text(viewModel.mealType.localizationKey))
                .font(.title3.weight(.semibold))
        }
    }

    private var selectedItemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("nutrition.confirm.selected_items"))
                .font(.headline)

            NutritionCardContainer(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                        itemRow(item)
                        if index < viewModel.items.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    private func itemRow(_ item: NutritionFoodSelectionItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.searchResult.title)
                        .font(.subheadline.weight(.semibold))
                    if item.searchResult.subtitle.isEmpty == false {
                        Text(item.searchResult.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(item.scaledCalorieText)
                .font(.caption.weight(.semibold))
            }

            NutritionServingRatioPicker(
                selection: ratioBinding(for: item.id)
            )
        }
        .padding(16)
    }

    private func ratioBinding(for itemID: UUID) -> Binding<NutritionServingRatio> {
        Binding(
            get: {
                viewModel.items.first(where: { $0.id == itemID })?.servingRatio ?? .full
            },
            set: { newValue in
                viewModel.updateServingRatio(for: itemID, ratio: newValue)
            }
        )
    }

    private var confirmButton: some View {
        Button {
            Task {
                await viewModel.save {
                    dismiss()
                    onSaveSuccess()
                }
            }
        } label: {
            Group {
                if viewModel.isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(L10n.text("nutrition.confirm.save"))
                }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black)
            )
        }
        .disabled(viewModel.isSaving)
    }
}

#Preview("Food Confirm") {
    CompatibleNavigationContainer {
        NutritionFoodConfirmView(
            dependencies: .preview,
            memberID: 1,
            date: .now,
            mealType: .breakfast,
            items: [
                NutritionFoodSelectionItem(
                    searchResult: NutritionFoodSearchResultViewData(
                        id: "food_1",
                        mode: .text,
                        resultType: "food_item",
                        targetID: 1,
                        title: "Coffee",
                        subtitle: "1 cup",
                        badgeText: "food_item",
                        isFavorite: false,
                        isVerified: true,
                        isCreatedByMe: false,
                        overview: NutritionOverviewGridData(
                            energyKcal: 2,
                            proteinGrams: 0.3,
                            carbohydrateGrams: 0,
                            fatGrams: 0
                        ),
                        calorieText: "2 kcal"
                    )
                )
            ],
            onSaveSuccess: {}
        )
    }
}
