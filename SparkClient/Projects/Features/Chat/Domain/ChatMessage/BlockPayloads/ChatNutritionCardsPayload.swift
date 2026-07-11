import Foundation

nonisolated struct ChatNutritionCardsPayload: Codable, Equatable, Sendable {
    var cards: [ChatNutritionCardPayload]

    init(cards: [ChatNutritionCardPayload]) {
        self.cards = cards
    }
}

nonisolated struct ChatNutritionCardPayload: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var date: Date
    var proteinGrams: Double?
    var carbohydratesGrams: Double?
    var fatGrams: Double?
    var energyKilocalories: Double?
    var mealName: String?
    var sourceText: String?
    var isWritten: Bool
    var writtenAt: Date?

    init(
        id: UUID = UUID(),
        date: Date,
        proteinGrams: Double? = nil,
        carbohydratesGrams: Double? = nil,
        fatGrams: Double? = nil,
        energyKilocalories: Double? = nil,
        mealName: String? = nil,
        sourceText: String? = nil,
        isWritten: Bool = false,
        writtenAt: Date? = nil
    ) {
        self.id = id
        self.date = date
        self.proteinGrams = proteinGrams
        self.carbohydratesGrams = carbohydratesGrams
        self.fatGrams = fatGrams
        self.energyKilocalories = energyKilocalories
        self.mealName = mealName
        self.sourceText = sourceText
        self.isWritten = isWritten
        self.writtenAt = writtenAt
    }

    func sparkNutritionCard() -> SparkNutritionCard {
        SparkNutritionCard(
            date: date,
            proteinGrams: proteinGrams,
            carbohydratesGrams: carbohydratesGrams,
            fatGrams: fatGrams,
            energyKilocalories: energyKilocalories,
            isWritten: isWritten
        )
    }
}

enum ChatNutritionCardAction: Equatable, Sendable {
    case writeToHealth(blockID: UUID, cardID: UUID)
}

extension SparkNutritionCard {
    func chatNutritionCardPayload(
        mealName: String? = nil,
        sourceText: String? = nil
    ) -> ChatNutritionCardPayload {
        ChatNutritionCardPayload(
            date: date,
            proteinGrams: proteinGrams,
            carbohydratesGrams: carbohydratesGrams,
            fatGrams: fatGrams,
            energyKilocalories: energyKilocalories,
            mealName: mealName,
            sourceText: sourceText,
            isWritten: isWritten
        )
    }
}
