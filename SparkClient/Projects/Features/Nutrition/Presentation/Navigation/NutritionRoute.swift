import Foundation

enum NutritionRoute: Hashable, Sendable {
    case home
}

enum NutritionNavigationDestination: Hashable, Sendable {
    case summaryDetail
    case nutritionDetail
    case mealDetail(NutritionMealType)
    case foodAdd(NutritionMealType)
    case history
    case energyBurnDetail
}
