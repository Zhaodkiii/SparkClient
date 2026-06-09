import Foundation

enum SparkNutritionAPI {}

extension SparkNutritionAPI {
    struct RemoteNutritionOverview: Codable, Sendable, Equatable {
        var energyKcal: Double
        var proteinG: Double
        var carbohydrateG: Double
        var fatG: Double
    }

    struct RemoteNutritionMacroTarget: Codable, Sendable, Equatable {
        var energyKcal: Double
        var proteinG: Double
        var carbohydrateG: Double
        var fatG: Double
    }

    struct RemoteNutritionBurnedSummary: Codable, Sendable, Equatable {
        var energyKcal: Double
        var source: String
    }

    struct RemoteNutritionMealDashboard: Codable, Sendable, Equatable, Identifiable {
        var id: String { mealType }
        var mealType: String
        var energyKcal: Double
        var targetEnergyKcal: Double
        var proteinG: Double
        var targetProteinG: Double
        var carbohydrateG: Double
        var targetCarbohydrateG: Double
        var fatG: Double
        var targetFatG: Double
        var foodSummary: String?
        var recordCount: Int
    }

    struct RemoteNutritionDashboard: Codable, Sendable, Equatable {
        var memberId: Int
        var date: Date
        var goal: RemoteNutritionMacroTarget
        var serverIntake: RemoteNutritionOverview
        var appleHealthExternalIntake: RemoteNutritionOverview
        var appleHealthBurned: RemoteNutritionBurnedSummary
        var meals: [RemoteNutritionMealDashboard]
    }

    struct RemoteNutritionIntake: Codable, Sendable, Equatable, Identifiable {
        var id: Int?
        var businessType: String
        var businessId: Int
        var nutrientType: String
        var value: Double
        var unit: String
        var source: String
        var confidence: Double?
        var appleHealthId: String?
    }

    struct RemoteFoodItem: Codable, Sendable, Equatable, Identifiable {
        var id: Int
        var name: String
        var localizedName: String?
        var brandName: String?
        var barcode: String?
        var category: String?
        var servingQuantity: Double?
        var servingUnit: String?
        var servingDescription: String?
        var weightGrams: Double?
        var source: String?
        var foodDatabaseId: String?
        var confidence: Double?
        var isVerified: Bool?
        var isActive: Bool?
        var sortWeight: Int?
    }

    struct RemoteMealFood: Codable, Sendable, Equatable, Identifiable {
        var id: Int
        var foodItem: RemoteFoodItem
        var servingRatio: Double
        var servingQuantity: Double?
        var servingUnit: String?
        var servingDescription: String?
        var displayOrder: Int?
    }

    struct RemoteNutritionAttachment: Codable, Sendable, Equatable, Identifiable {
        var id: Int
        var fileUuid: String?
        var originalName: String?
        var fileSize: Int?
        var mimeType: String?
        var fileMd5: String?
        var businessType: String?
        var businessId: Int?
        var objectKey: String?
        var storageType: String?
        var createdAt: Date?
        var fileUrl: String?
    }

    struct RemoteMealRecord: Codable, Sendable, Equatable, Identifiable {
        var id: Int
        var member: Int?
        var mealType: String
        var consumedAt: Date
        var localDay: Date?
        var title: String?
        var source: String?
        var sourceText: String?
        var isAiEstimated: Bool?
        var aiConfidence: Double?
        var userEdited: Bool?
        var mealFoods: [RemoteMealFood]
        var intakes: [RemoteNutritionIntake]
        var attachments: [RemoteNutritionAttachment]?
        var hasAppleHealthId: Bool?
        var updatedAt: Date?
    }

    struct RemoteNutritionMacroProgress: Codable, Sendable, Equatable {
        var energyKcal: Double
        var targetEnergyKcal: Double
        var proteinG: Double
        var targetProteinG: Double
        var carbohydrateG: Double
        var targetCarbohydrateG: Double
        var fatG: Double
        var targetFatG: Double
    }

    struct RemoteMealRecordListResponse: Codable, Sendable, Equatable {
        var memberId: Int
        var date: Date
        var mealType: String?
        var overview: RemoteNutritionOverview
        var macroProgress: RemoteNutritionMacroProgress
        var records: [RemoteMealRecord]
    }

    struct RemoteMealRecordHistoryResponse: Codable, Sendable, Equatable {
        var memberId: Int
        var dateFrom: Date
        var dateTo: Date
        var records: [RemoteMealRecord]
    }

    struct RemoteRecipeFood: Codable, Sendable, Equatable, Identifiable {
        var id: Int
        var foodItem: RemoteFoodItem
        var servingRatio: Double
        var servingQuantity: Double?
        var servingUnit: String?
        var servingDescription: String?
        var displayOrder: Int?
    }

    struct RemoteRecipe: Codable, Sendable, Equatable, Identifiable {
        var id: Int
        var name: String
        var localizedName: String?
        var category: String?
        var servingQuantity: Double?
        var servingUnit: String?
        var servingDescription: String?
        var source: String?
        var isActive: Bool?
        var sortWeight: Int?
        var recipeFoods: [RemoteRecipeFood]?
        var intakes: [RemoteNutritionIntake]?
    }

    struct RemoteRecipeCreateResponse: Codable, Sendable, Equatable {
        var recipe: RemoteRecipe
        var overview: RemoteNutritionOverview
        var intakes: [RemoteNutritionIntake]
    }

    struct RemoteEnergyBurnRecord: Codable, Sendable, Equatable, Identifiable {
        var id: Int
        var member: Int
        var burnedAt: Date
        var localDay: Date?
        var energyKcal: Double
        var activityType: String?
        var durationSeconds: Int?
        var source: String?
        var note: String?
        var appleHealthId: String?
        var updatedAt: Date?
    }

    struct RemoteAppleHealthIntakeImport: Codable, Sendable, Equatable, Identifiable {
        var id: Int
        var member: Int
        var occurredAt: Date
        var localDay: Date?
        var sourceBundleId: String?
        var sourceName: String?
        var appleHealthId: String?
        var intakes: [RemoteNutritionIntake]
        var updatedAt: Date?
    }

    struct RemoteNutritionSearchResponse: Codable, Sendable, Equatable {
        var mode: String
        var query: String
        var items: [RemoteNutritionSearchResult]
    }

    struct RemoteNutritionSearchResult: Codable, Sendable, Equatable, Identifiable {
        var id: String
        var resultType: String
        var foodItem: RemoteFoodItem?
        var recipe: RemoteRecipe?
        var isFavorite: Bool
        var isCreatedByMe: Bool
        var overview: RemoteNutritionOverview
        var score: Double?
    }

    struct RemoteNutritionRecognitionDraft: Codable, Sendable, Equatable {
        var recognitionId: String
        var source: String
        var title: String
        var imageFileIds: [Int]
        var confidence: Double?
        var overview: RemoteNutritionOverview
        var items: [RemoteNutritionRecognitionItem]
        var intakes: [RemoteNutritionIntake]
        var uncertainNotes: [String]
    }

    struct RemoteNutritionRecognitionItem: Codable, Sendable, Equatable {
        var foodItemId: Int?
        var name: String
        var servingRatio: Double
        var servingDescription: String
        var confidence: Double?
    }

    struct RemoteFavorite: Codable, Sendable, Equatable {
        var targetType: String
        var targetId: Int
    }

    struct RemoteDeleteResult: Codable, Sendable, Equatable {
        var id: Int?
        var deleted: Bool?
    }
}

extension SparkNutritionAPI {
    struct MealFoodInput: Codable, Sendable, Equatable {
        var foodItemId: Int?
        var recipeId: Int?
        var servingRatio: Double
        var servingQuantity: Double?
        var servingUnit: String
        var servingDescription: String
    }

    struct RecipeInput: Codable, Sendable, Equatable {
        var recipeId: Int
        var servingRatio: Double
        var servingQuantity: Double?
        var servingUnit: String
        var servingDescription: String
    }

    struct NutritionIntakeInput: Codable, Sendable, Equatable {
        var nutrientType: String
        var value: Double
        var unit: String
        var source: String
        var confidence: Double?
    }

    struct CreateMealRecordRequest: Codable, Sendable, Equatable {
        var memberId: Int
        var mealType: String
        var consumedAt: Date
        var source: String
        var sourceText: String
        var title: String
        var recognitionId: String?
        var fileIds: [Int]
        var mealFoods: [MealFoodInput]
        var recipes: [RecipeInput]
        var manualIntakes: [NutritionIntakeInput]
    }

    struct UpdateMealRecordRequest: Codable, Sendable, Equatable {
        var mealType: String?
        var consumedAt: Date?
        var source: String?
        var sourceText: String?
        var title: String?
        var fileIds: [Int]?
        var mealFoods: [MealFoodInput]?
        var recipes: [RecipeInput]?
        var manualIntakes: [NutritionIntakeInput]?
    }

    struct CreateNutritionFoodItemRequest: Codable, Sendable, Equatable {
        var name: String
        var localizedName: String
        var brandName: String
        var barcode: String
        var category: String
        var servingQuantity: Double?
        var servingUnit: String
        var servingDescription: String
        var weightGrams: Double?
        var intakes: [NutritionIntakeInput]
    }

    struct CreateNutritionRecipeRequest: Codable, Sendable, Equatable {
        var name: String
        var localizedName: String
        var category: String
        var servingQuantity: Double?
        var servingUnit: String
        var servingDescription: String
        var foods: [MealFoodInput]
    }

    struct NutritionFavoriteRequest: Codable, Sendable, Equatable {
        var targetType: String
        var targetId: Int
    }

    struct CreateEnergyBurnRecordRequest: Codable, Sendable, Equatable {
        var memberId: Int
        var burnedAt: Date
        var energyKcal: Double
        var activityType: String
        var durationSeconds: Int?
        var note: String
    }

    struct UpdateEnergyBurnRecordRequest: Codable, Sendable, Equatable {
        var burnedAt: Date?
        var energyKcal: Double?
        var activityType: String?
        var durationSeconds: Int?
        var source: String?
        var note: String?
    }

    struct AppleHealthIntakeSample: Codable, Sendable, Equatable {
        var appleHealthId: String
        var occurredAt: Date
        var sourceBundleId: String
        var sourceName: String
        var intakes: [NutritionIntakeInput]
    }

    struct AppleHealthIntakeImportRequest: Codable, Sendable, Equatable {
        var memberId: Int
        var samples: [AppleHealthIntakeSample]
    }

    struct AppleHealthEnergyBurnSample: Codable, Sendable, Equatable {
        var appleHealthId: String
        var burnedAt: Date
        var energyKcal: Double
        var activityType: String
        var source: String
    }

    struct AppleHealthEnergyBurnImportRequest: Codable, Sendable, Equatable {
        var memberId: Int
        var samples: [AppleHealthEnergyBurnSample]
    }

    struct AppleHealthIDUpdateRequest: Codable, Sendable, Equatable {
        var appleHealthId: String
    }
}
