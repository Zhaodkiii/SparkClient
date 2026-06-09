import SwiftUI

struct NutritionSelectionPreviewView: View {
    let items: [NutritionFoodSelectionItem]
    let mealType: NutritionMealType
    let searchUseCase: NutritionSearchUseCase
    let notificationStore: NotificationStore
    let onClose: () -> Void
    let onUpdateSelection: (UUID, NutritionServingRatio, Double) -> Void
    let onRemove: (UUID) -> Void

    @State private var detailAddContext: NutritionFoodDetailAddContext?

    var body: some View {
        NavigationView {
            Group {
                if items.isEmpty {
                    emptyState
                } else {
                    itemList
                }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(L10n.text("nutrition.selection_preview.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.text("nutrition.selection_preview.close")) {
                        onClose()
                    }
                }
            }
            .sheet(item: $detailAddContext) { context in
                NutritionFoodDetailAddView(
                    context: context,
                    mealType: mealType,
                    searchUseCase: searchUseCase,
                    notificationStore: notificationStore
                ) { servingRatio, quantity in
                    if let editingItemID = context.editingItemID {
                        onUpdateSelection(editingItemID, servingRatio, quantity)
                    }
                    detailAddContext = nil
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Text(L10n.text("nutrition.selection_preview.empty"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(32)
    }

    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    itemRow(item)

                    if index < items.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func itemRow(_ item: NutritionFoodSelectionItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.searchResult.title)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(item.scaledCalorieText)
                        .font(.headline.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(item.servingDisplayText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Button {
                detailAddContext = NutritionFoodDetailAddContext(
                    searchResult: item.searchResult,
                    editingItemID: item.id,
                    initialServingRatio: item.servingRatio,
                    initialQuantity: item.quantity
                )
            } label: {
                Image(systemName: "pencil")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .systemTeal))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("nutrition.selection_preview.edit"))

            Button {
                onRemove(item.id)
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("nutrition.selection_preview.remove"))
        }
        .padding(.vertical, 12)
    }
}
