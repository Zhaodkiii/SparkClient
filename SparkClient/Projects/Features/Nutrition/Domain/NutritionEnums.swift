import Foundation

nonisolated enum NutritionMealType: String, CaseIterable, Codable, Sendable, Equatable, Hashable {
    case breakfast
    case lunch
    case dinner
    case snack

    nonisolated var localizationKey: String {
        switch self {
        case .breakfast:
            return "nutrition.meal.breakfast"
        case .lunch:
            return "nutrition.meal.lunch"
        case .dinner:
            return "nutrition.meal.dinner"
        case .snack:
            return "nutrition.meal.snack"
        }
    }
}

nonisolated enum NutritionRecordSource: String, Codable, Sendable, Equatable {
    case manual
    case photoAI = "photo_ai"
    case textAI = "text_ai"
    case chatAI = "chat_ai"
    case appleHealthImport = "apple_health_import"
}
