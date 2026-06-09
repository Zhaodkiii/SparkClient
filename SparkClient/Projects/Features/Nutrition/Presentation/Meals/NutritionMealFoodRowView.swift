import SwiftUI

struct NutritionMealFoodRowView: View {
    let row: NutritionMealFoodRowViewData

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.subheadline.weight(.medium))
                if row.servingText.isEmpty == false {
                    Text(row.servingText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(NutritionFormatting.energyKcal(row.energyKcal))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }
}
