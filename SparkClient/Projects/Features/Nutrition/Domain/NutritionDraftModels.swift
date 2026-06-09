import Foundation

enum NutritionServingRatio: Double, CaseIterable, Sendable, Equatable, Hashable {
    case oneFifth = 0.2
    case twoFifth = 0.4
    case threeFifth = 0.6
    case fourFifth = 0.8
    case full = 1.0

    static func closest(to value: Double) -> NutritionServingRatio {
        allCases.min { abs($0.rawValue - value) < abs($1.rawValue - value) } ?? .full
    }

    var localizationKey: String {
        switch self {
        case .oneFifth: return "nutrition.serving_ratio.one_fifth"
        case .twoFifth: return "nutrition.serving_ratio.two_fifth"
        case .threeFifth: return "nutrition.serving_ratio.three_fifth"
        case .fourFifth: return "nutrition.serving_ratio.four_fifth"
        case .full: return "nutrition.serving_ratio.full"
        }
    }
}

struct NutritionFoodSelectionItem: Identifiable, Equatable, Sendable {
    let id: UUID
    var searchResult: NutritionFoodSearchResultViewData
    var servingRatio: NutritionServingRatio
    var quantity: Double

    init(
        id: UUID = UUID(),
        searchResult: NutritionFoodSearchResultViewData,
        servingRatio: NutritionServingRatio = .full,
        quantity: Double = 1
    ) {
        self.id = id
        self.searchResult = searchResult
        self.servingRatio = servingRatio
        self.quantity = quantity
    }

    var effectiveServingRatio: Double {
        servingRatio.rawValue * quantity
    }

    var scaledOverview: NutritionOverviewGridData {
        NutritionDraftBuilder.scaledOverview(searchResult.overview, ratio: effectiveServingRatio)
    }

    var scaledCalorieText: String {
        NutritionFormatting.energyKcal(scaledOverview.energyKcal)
    }

    var servingDisplayText: String {
        let description = searchResult.subtitle
        guard servingRatio != .full || quantity != 1 else {
            return description.isEmpty ? "×\(NutritionFormatting.quantity(quantity))" : description
        }

        var parts: [String] = []
        if quantity != 1 {
            parts.append(NutritionFormatting.quantity(quantity))
        }
        if servingRatio != .full {
            parts.append(L10n.text(servingRatio.localizationKey))
        }
        if description.isEmpty == false {
            parts.append(description)
        }
        return parts.joined(separator: " ")
    }
}

struct NutritionFoodDraftItem: Equatable, Sendable {
    var foodItemID: Int
    var name: String
    var servingRatio: NutritionServingRatio
    var servingQuantity: Double?
    var servingUnit: String
    var servingDescription: String
    var overview: NutritionOverviewGridData
}

struct NutritionRecipeDraftItem: Equatable, Sendable {
    var recipeID: Int
    var name: String
    var servingRatio: NutritionServingRatio
    var servingQuantity: Double?
    var servingUnit: String
    var servingDescription: String
    var overview: NutritionOverviewGridData
}

struct NutritionMealDraft: Equatable, Sendable {
    var memberID: Int
    var mealType: NutritionMealType
    var consumedAt: Date
    var source: NutritionRecordSource
    var sourceText: String
    var recognitionID: String?
    var title: String
    var overview: NutritionOverviewGridData?
    var imageFileIDs: [Int]
    var items: [NutritionFoodDraftItem]
    var recipes: [NutritionRecipeDraftItem]
    var aiConfidence: Double?
    var uncertainNotes: [String]
}

enum NutritionFoodAddContentFilter: String, CaseIterable, Identifiable, Sendable {
    case food
    case recipe
    case frequent
    case custom

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .food: return "nutrition.add.filter.food"
        case .recipe: return "nutrition.add.filter.recipe"
        case .frequent: return "nutrition.add.filter.frequent"
        case .custom: return "nutrition.add.filter.custom"
        }
    }

    var searchType: String? {
        switch self {
        case .food, .frequent, .custom: return "food"
        case .recipe: return "recipe"
        }
    }

    var createdByMeOnly: Bool {
        self == .custom
    }
}

extension Notification.Name {
    static let nutritionMealRecordDidSave = Notification.Name("nutritionMealRecordDidSave")
    static let nutritionEnergyBurnDidChange = Notification.Name("nutritionEnergyBurnDidChange")
}

enum NutritionMealRecordMapper {
    static func mealFoodInput(
        from mealFood: SparkNutritionAPI.RemoteMealFood,
        servingRatio: Double
    ) -> SparkNutritionAPI.MealFoodInput {
        SparkNutritionAPI.MealFoodInput(
            foodItemId: mealFood.foodItem.id,
            servingRatio: servingRatio,
            servingQuantity: mealFood.servingQuantity,
            servingUnit: mealFood.servingUnit ?? mealFood.foodItem.servingUnit ?? "",
            servingDescription: mealFood.servingDescription ?? mealFood.foodItem.servingDescription ?? ""
        )
    }
}

enum NutritionDraftBuilder {
    static func scaledOverview(_ overview: NutritionOverviewGridData, ratio: Double) -> NutritionOverviewGridData {
        NutritionOverviewGridData(
            energyKcal: overview.energyKcal * ratio,
            proteinGrams: overview.proteinGrams * ratio,
            carbohydrateGrams: overview.carbohydrateGrams * ratio,
            fatGrams: overview.fatGrams * ratio
        )
    }

    static func aggregateOverview(from items: [NutritionFoodSelectionItem]) -> NutritionOverviewGridData {
        items.reduce(
            NutritionOverviewGridData(energyKcal: 0, proteinGrams: 0, carbohydrateGrams: 0, fatGrams: 0)
        ) { partial, item in
            let scaled = scaledOverview(item.searchResult.overview, ratio: item.effectiveServingRatio)
            return NutritionOverviewGridData(
                energyKcal: partial.energyKcal + scaled.energyKcal,
                proteinGrams: partial.proteinGrams + scaled.proteinGrams,
                carbohydrateGrams: partial.carbohydrateGrams + scaled.carbohydrateGrams,
                fatGrams: partial.fatGrams + scaled.fatGrams
            )
        }
    }

    static func makeCreateRequest(
        memberID: Int,
        mealType: NutritionMealType,
        date: Date,
        items: [NutritionFoodSelectionItem]
    ) -> SparkNutritionAPI.CreateMealRecordRequest {
        var mealFoods: [SparkNutritionAPI.MealFoodInput] = []
        var recipes: [SparkNutritionAPI.RecipeInput] = []

        for item in items {
            let ratio = item.effectiveServingRatio
            let description = item.searchResult.subtitle
            switch item.searchResult.resultType {
            case "recipe":
                recipes.append(
                    SparkNutritionAPI.RecipeInput(
                        recipeId: item.searchResult.targetID,
                        servingRatio: ratio,
                        servingQuantity: nil,
                        servingUnit: "",
                        servingDescription: description
                    )
                )
            default:
                mealFoods.append(
                    SparkNutritionAPI.MealFoodInput(
                        foodItemId: item.searchResult.targetID,
                        servingRatio: ratio,
                        servingQuantity: nil,
                        servingUnit: "",
                        servingDescription: description
                    )
                )
            }
        }

        let title = items.map(\.searchResult.title).joined(separator: ", ")
        return SparkNutritionAPI.CreateMealRecordRequest(
            memberId: memberID,
            mealType: mealType.rawValue,
            consumedAt: consumedAt(for: date),
            source: NutritionRecordSource.manual.rawValue,
            sourceText: "",
            title: title,
            recognitionId: nil,
            fileIds: [],
            mealFoods: mealFoods,
            recipes: recipes,
            manualIntakes: []
        )
    }

    static func consumedAt(for date: Date) -> Date {
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = calendar.component(.hour, from: now)
        components.minute = calendar.component(.minute, from: now)
        components.second = calendar.component(.second, from: now)
        return calendar.date(from: components) ?? date
    }
}
