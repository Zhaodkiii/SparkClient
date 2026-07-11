import Foundation

nonisolated struct ChatHealthCardPayload: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let energyKilocalories: Double?
    let proteinGrams: Double?
    let carbohydratesGrams: Double?
    let fatGrams: Double?
    let dateText: String?

    init(
        id: UUID = UUID(),
        title: String,
        energyKilocalories: Double? = nil,
        proteinGrams: Double? = nil,
        carbohydratesGrams: Double? = nil,
        fatGrams: Double? = nil,
        dateText: String? = nil
    ) {
        self.id = id
        self.title = title
        self.energyKilocalories = energyKilocalories
        self.proteinGrams = proteinGrams
        self.carbohydratesGrams = carbohydratesGrams
        self.fatGrams = fatGrams
        self.dateText = dateText
    }
}
