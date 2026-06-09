import SwiftUI

struct NutritionFoodSearchResultCard: View {
    let result: NutritionFoodSearchResultViewData
    let showsExpandedOverview: Bool
    let onOpenDetail: () -> Void
    let onAdd: () -> Void
    let onToggleFavorite: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onOpenDetail) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if result.subtitle.isEmpty == false {
                            Text(result.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                VStack(alignment: .trailing, spacing: 8) {
                    Text(result.calorieText)
                        .font(.caption.weight(.semibold))
                    Button(action: onAdd) {
                        Image(systemName: "plus.circle")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.text("nutrition.search.add_item"))
                }
            }

            HStack(spacing: 8) {
                badgeLabel
                if result.isVerified {
                    Text(L10n.text("nutrition.search.verified"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if result.isFavorite {
                    Text(L10n.text("nutrition.search.favorite"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if result.isCreatedByMe {
                    Text(L10n.text("nutrition.search.created_by_me"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let onToggleFavorite {
                    Button(action: onToggleFavorite) {
                        Image(systemName: result.isFavorite ? "heart.fill" : "heart")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }

            if showsExpandedOverview {
                HStack {
                    macroColumn(titleKey: "nutrition.macro.carbohydrate", value: result.overview.carbohydrateGrams)
                    Spacer()
                    macroColumn(titleKey: "nutrition.macro.protein", value: result.overview.proteinGrams)
                    Spacer()
                    macroColumn(titleKey: "nutrition.macro.fat", value: result.overview.fatGrams)
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    private var badgeLabel: some View {
        Text(badgeText)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))
            )
    }

    private var badgeText: String {
        switch result.resultType {
        case "recipe":
            return L10n.text("nutrition.search.type.recipe")
        default:
            return L10n.text("nutrition.search.type.food")
        }
    }

    private func macroColumn(titleKey: String, value: Double) -> some View {
        VStack(spacing: 2) {
            Text(NutritionFormatting.grams(value))
                .font(.caption.weight(.semibold))
            Text(L10n.text(titleKey))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
