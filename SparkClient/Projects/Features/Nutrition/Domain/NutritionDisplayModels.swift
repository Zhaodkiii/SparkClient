import Foundation

struct NutritionDashboardViewData: Equatable, Sendable {
    var memberID: Int
    var date: Date
    var consumedEnergyKcal: Double
    var remainingEnergyKcal: Double
    var burnedEnergyKcal: Double
    var targetEnergyKcal: Double
    var intakeProgress: Double
    var overview: NutritionOverviewGridData
    var carbohydrate: NutritionMacroProgress
    var protein: NutritionMacroProgress
    var fat: NutritionMacroProgress
    var macroRatioChart: NutritionMacroRatioChartData
    var meals: [NutritionMealSectionViewData]
}

struct NutritionOverviewGridData: Equatable, Hashable, Sendable {
    var energyKcal: Double
    var proteinGrams: Double
    var carbohydrateGrams: Double
    var fatGrams: Double
}

struct NutritionMealSectionViewData: Identifiable, Equatable, Sendable {
    var id: String { mealType.rawValue }
    var mealType: NutritionMealType
    var consumedEnergyKcal: Double
    var targetEnergyKcal: Double
    var carbohydrate: NutritionMacroProgress
    var protein: NutritionMacroProgress
    var fat: NutritionMacroProgress
    var foodSummary: String?
    var recordCount: Int
}

struct NutritionMacroProgress: Equatable, Sendable {
    var current: Double
    var target: Double
    var unit: String
}

struct NutritionMacroProgressCardData: Equatable, Sendable {
    var energy: NutritionMacroProgress
    var carbohydrate: NutritionMacroProgress
    var protein: NutritionMacroProgress
    var fat: NutritionMacroProgress
}

struct NutritionMacroRatioChartData: Equatable, Sendable {
    var carbohydrate: NutritionMacroRatioPair
    var protein: NutritionMacroRatioPair
    var fat: NutritionMacroRatioPair
}

struct NutritionMacroRatioPair: Equatable, Sendable {
    var currentPercent: Double
    var targetPercent: Double
}

struct NutritionDetailInfoData: Equatable, Sendable {
    var groups: [NutritionDetailInfoGroup]
}

struct NutritionDetailInfoGroup: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var rows: [NutritionDetailInfoRow]
}

struct NutritionDetailInfoRow: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var valueText: String
}

struct NutritionSummaryDetailViewData: Equatable, Sendable {
    var date: Date
    var macroProgress: NutritionMacroProgressCardData
    var macroRatioChart: NutritionMacroRatioChartData
    var detailInfo: NutritionDetailInfoData
    var mealSections: [NutritionMealSectionViewData]
}

struct NutritionMealGroupViewData: Identifiable, Equatable, Sendable {
    var id: String { mealType.rawValue }
    var mealType: NutritionMealType
    var totalEnergyKcal: Double
    var foods: [NutritionMealFoodRowViewData]
}

enum NutritionMealFoodItemType: String, Sendable, Equatable, Hashable {
    case food
    case recipe
}

struct NutritionMealFoodRowViewData: Identifiable, Equatable, Sendable, Hashable {
    var id: String
    var mealFoodID: Int
    var recordID: Int
    var foodItemID: Int
    var title: String
    var servingText: String
    var energyKcal: Double
    var servingRatio: Double
    var servingUnit: String
    var overview: NutritionOverviewGridData
    var isVerified: Bool
    var hasAppleHealthLinkedRecord: Bool
    var itemType: NutritionMealFoodItemType
}

struct NutritionMealFoodEditItemViewData: Identifiable, Equatable, Sendable, Hashable {
    var id: Int { mealFoodID }
    var mealFoodID: Int
    var recordID: Int
    var foodItemID: Int
    var title: String
    var servingText: String
    var energyKcal: Double
    var servingRatio: NutritionServingRatio
    var servingUnit: String
    var servingDescription: String
    var hasAppleHealthLinkedRecord: Bool
}

struct NutritionRecipeDraftFood: Identifiable, Equatable, Sendable, Hashable {
    var id: Int { foodItemID }
    var foodItemID: Int
    var title: String
    var servingText: String
    var servingRatio: NutritionServingRatio
    var servingUnit: String
    var servingDescription: String
    var energyKcal: Double
}

struct NutritionMealDetailViewData: Equatable, Sendable {
    var mealType: NutritionMealType
    var date: Date
    var imageURL: URL?
    var overview: NutritionOverviewGridData
    var macroProgress: NutritionMacroProgressCardData
    var detailInfo: NutritionDetailInfoData
    var foods: [NutritionMealFoodRowViewData]
    var records: [SparkNutritionAPI.RemoteMealRecord]
    var hasAppleHealthLinkedRecords: Bool
}

struct NutritionEditableMealFood: Identifiable, Equatable, Sendable {
    var id: Int
    var recordID: Int
    var foodItemID: Int
    var title: String
    var servingDescription: String
    var servingRatio: NutritionServingRatio
    var servingUnit: String
}

struct NutritionHistoryDayViewData: Identifiable, Equatable, Sendable {
    var id: String { MedicalDateCoding.encodeDateOnly(date) }
    var date: Date
    var totalEnergyKcal: Double
    var records: [NutritionHistoryRecordViewData]
}

struct NutritionHistoryRecordViewData: Identifiable, Equatable, Sendable {
    var id: Int
    var mealType: NutritionMealType
    var title: String
    var consumedAt: Date
    var energyKcal: Double
    var foodCount: Int
}

struct NutritionEnergyBurnViewData: Equatable, Sendable {
    var totalEnergyKcal: Double
    var appleHealthEnergyKcal: Double
    var manualEnergyKcal: Double
    var records: [NutritionEnergyBurnRowViewData]
}

struct NutritionEnergyBurnRowViewData: Identifiable, Equatable, Sendable {
    var id: Int
    var burnedAt: Date
    var energyKcal: Double
    var activityType: String
    var source: String
    var note: String
    var isManual: Bool
    var hasAppleHealthID: Bool
}

struct NutritionEnergyBurnEditorState: Equatable, Sendable {
    var recordID: Int?
    var burnedAt: Date
    var energyKcal: String
    var activityType: String
    var durationMinutes: String
    var note: String
}

enum NutritionFoodSearchMode: String, Sendable {
    case text
    case barcode
}

struct NutritionFoodSearchFilterState: Equatable, Sendable {
    var mode: NutritionFoodSearchMode
    var query: String
    var type: String?
    var favoriteOnly: Bool
    var createdByMeOnly: Bool
}

struct NutritionFoodSearchResultViewData: Identifiable, Equatable, Sendable {
    var id: String
    var mode: NutritionFoodSearchMode
    var resultType: String
    var targetID: Int
    var title: String
    var subtitle: String
    var badgeText: String
    var isFavorite: Bool
    var isVerified: Bool
    var isCreatedByMe: Bool
    var overview: NutritionOverviewGridData
    var calorieText: String

    var isRecipe: Bool { resultType == "recipe" }

    var favoriteTargetType: String {
        isRecipe ? "nutrition_recipe" : "nutrition_food_item"
    }
}
