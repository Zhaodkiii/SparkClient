import SwiftUI

/// 对话内营养卡片：展示 AI 估算的营养数据，并支持写入 Apple 健康。
struct ChatNutritionCardsBlockView: View {
    let blockID: UUID
    let cards: [ChatNutritionCardPayload]
    let savingCardIDs: Set<UUID>
    let onAction: (ChatNutritionCardAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(cards) { card in
                nutritionCard(card)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func nutritionCard(_ card: ChatNutritionCardPayload) -> some View {
        let isSaving = savingCardIDs.contains(card.id)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "fork.knife.circle.fill")
                    .foregroundStyle(.orange)
                    .imageScale(.medium)
                Text(card.mealName?.isEmpty == false ? card.mealName! : L10n.text("chat.nutrition_card.title"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(formatRecordTime(card.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            nutrientGrid(for: card)

            Text(L10n.text("chat.nutrition_card.ai_estimate_hint"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            writeButton(for: card, isSaving: isSaving)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func nutrientGrid(for card: ChatNutritionCardPayload) -> some View {
        let items = nutrientItems(for: card)
        if items.isEmpty == false {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ],
                spacing: 10
            ) {
                ForEach(items) { item in
                    nutrientCell(item)
                }
            }
        }
    }

    private struct NutrientItem: Identifiable {
        let id: String
        let icon: String
        let label: String
        let value: Double
        let unit: String
    }

    private func nutrientItems(for card: ChatNutritionCardPayload) -> [NutrientItem] {
        var items: [NutrientItem] = []
        if let value = card.carbohydratesGrams {
            items.append(.init(
                id: "carbohydrates",
                icon: "popcorn.fill",
                label: L10n.text("chat.nutrition_card.carbohydrates"),
                value: value,
                unit: "g"
            ))
        }
        if let value = card.fatGrams {
            items.append(.init(
                id: "fat",
                icon: "drop.fill",
                label: L10n.text("chat.nutrition_card.fat"),
                value: value,
                unit: "g"
            ))
        }
        if let value = card.proteinGrams {
            items.append(.init(
                id: "protein",
                icon: "fish.fill",
                label: L10n.text("chat.nutrition_card.protein"),
                value: value,
                unit: "g"
            ))
        }
        if let value = card.energyKilocalories {
            items.append(.init(
                id: "energy",
                icon: "flame.fill",
                label: L10n.text("chat.nutrition_card.energy"),
                value: value,
                unit: "kcal"
            ))
        }
        return items
    }

    private func nutrientCell(_ item: NutrientItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(formatNutrientValue(item.value)) \(item.unit)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func writeButton(for card: ChatNutritionCardPayload, isSaving: Bool) -> some View {
        if card.isWritten {
            Label(
                L10n.text("chat.nutrition_card.written"),
                systemImage: "checkmark.circle.fill"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            Button {
                onAction(.writeToHealth(blockID: blockID, cardID: card.id))
            } label: {
                HStack(spacing: 6) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.text("chat.nutrition_card.writing"))
                    } else {
                        Image(systemName: "heart.text.square.fill")
                        Text(L10n.text("chat.nutrition_card.write_to_health"))
                    }
                }
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.15))
                )
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
        }
    }

    private func formatNutrientValue(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if abs(rounded.rounded() - rounded) < 0.05 {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.1f", rounded)
    }

    private func formatRecordTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale.current
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.dateFormat = "HH:mm"
        let timeText = timeFormatter.string(from: date)

        if calendar.isDateInToday(date) {
            return String(format: L10n.text("chat.nutrition_card.time.today"), timeText)
        }
        if calendar.isDateInYesterday(date) {
            return String(format: L10n.text("chat.nutrition_card.time.yesterday"), timeText)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale.current
        dateFormatter.timeZone = calendar.timeZone
        dateFormatter.dateFormat = "M/d HH:mm"
        return dateFormatter.string(from: date)
    }
}
