import Foundation

struct NutritionPhotoRecognitionInput: Sendable, Equatable {
    var memberID: Int
    var mealType: NutritionMealType
    var imageJPEGData: Data
    var imageFileIDs: [Int]
}

struct NutritionTextRecognitionInput: Sendable, Equatable {
    var memberID: Int
    var mealType: NutritionMealType
    var userText: String
}

struct NutritionIntakeExtractionInput: Sendable, Equatable {
    var memberID: Int
    var mealType: NutritionMealType
    var source: NutritionRecordSource
    var text: String
    var recognitionID: String
    var retryFeedback: NutritionExtractionRetryFeedback?
}

struct NutritionFoodDescriptionResult: Sendable, Equatable {
    var recognitionID: String
    var descriptionText: String
    var modelName: String
    var durationSeconds: TimeInterval
}

struct NutritionIntakeExtractionResult: Sendable, Equatable {
    var recognitionID: String
    var draft: SparkNutritionAPI.RemoteNutritionRecognitionDraft
    var foodDescription: String?
    var modelName: String
    var durationSeconds: TimeInterval
    var retryCount: Int
}

struct NutritionRecognitionResult: Sendable, Equatable {
    var recognitionID: String
    var clientRecognitionID: String
    var source: NutritionRecordSource
    var mealType: NutritionMealType
    var foodDescription: String?
    var draft: SparkNutritionAPI.RemoteNutritionRecognitionDraft
}

struct NutritionExtractionRetryFeedback: Sendable, Equatable {
    var errorSummary: String
    var outputPreview: String
}

/// AI 营养抽取 JSON（camelCase）。
struct NutritionRecognitionDraftResponse: Codable, Sendable, Equatable {
    var title: String
    var mealType: String?
    var confidence: Double?
    var overview: NutritionRecognitionOverviewResponse
    var items: [NutritionRecognitionItemResponse]
    var intakes: [NutritionRecognitionIntakeResponse]?
    var uncertainNotes: String?
    var foodDescription: String?
}

struct NutritionRecognitionOverviewResponse: Codable, Sendable, Equatable {
    var energyKcal: Double?
    var proteinG: Double?
    var carbohydrateG: Double?
    var fatG: Double?
}

struct NutritionRecognitionItemResponse: Codable, Sendable, Equatable {
    var foodItemId: Int?
    var name: String
    var servingRatio: Double?
    var servingDescription: String?
    var confidence: Double?
}

struct NutritionRecognitionIntakeResponse: Codable, Sendable, Equatable {
    var nutrientType: String
    var value: Double?
    var unit: String
    var confidence: Double?
}

enum NutritionRecognitionMapper {
    static func makeRecognitionID() -> String {
        let stamp = ISO8601DateFormatter().string(from: Date())
        return "client_\(stamp)_\(UUID().uuidString.prefix(8))"
    }

    static func mapDraft(
        _ response: NutritionRecognitionDraftResponse,
        recognitionID: String,
        source: NutritionRecordSource,
        mealType: NutritionMealType,
        imageFileIDs: [Int],
        foodDescription: String?
    ) -> SparkNutritionAPI.RemoteNutritionRecognitionDraft {
        let resolvedMealType = NutritionMealType(rawValue: response.mealType ?? "") ?? mealType
        _ = resolvedMealType

        let items = response.items.map { item in
            SparkNutritionAPI.RemoteNutritionRecognitionItem(
                foodItemId: item.foodItemId,
                name: item.name,
                servingRatio: item.servingRatio ?? 1,
                servingDescription: item.servingDescription ?? "",
                confidence: item.confidence
            )
        }

        let intakes = (response.intakes ?? []).map { intake in
            SparkNutritionAPI.RemoteNutritionIntake(
                id: nil,
                businessType: "",
                businessId: 0,
                nutrientType: intake.nutrientType,
                value: intake.value ?? 0,
                unit: intake.unit,
                source: source.rawValue,
                confidence: intake.confidence,
                appleHealthId: nil
            )
        }

        return SparkNutritionAPI.RemoteNutritionRecognitionDraft(
            recognitionId: recognitionID,
            source: source.rawValue,
            title: response.title,
            imageFileIds: imageFileIDs,
            confidence: response.confidence,
            overview: SparkNutritionAPI.RemoteNutritionOverview(
                energyKcal: response.overview.energyKcal ?? 0,
                proteinG: response.overview.proteinG ?? 0,
                carbohydrateG: response.overview.carbohydrateG ?? 0,
                fatG: response.overview.fatG ?? 0
            ),
            items: items,
            intakes: intakes,
            uncertainNotes: response.uncertainNotes.map { [$0] } ?? []
        )
    }

    static func toRecognitionResult(
        extraction: NutritionIntakeExtractionResult,
        source: NutritionRecordSource,
        mealType: NutritionMealType,
        foodDescription: String?
    ) -> NutritionRecognitionResult {
        NutritionRecognitionResult(
            recognitionID: extraction.recognitionID,
            clientRecognitionID: extraction.recognitionID,
            source: source,
            mealType: mealType,
            foodDescription: foodDescription ?? extraction.foodDescription,
            draft: extraction.draft
        )
    }
}

extension NutritionDraftBuilder {
    static func makeCreateRequest(
        memberID: Int,
        date: Date,
        mealType: NutritionMealType,
        recognition: NutritionRecognitionResult,
        servingRatios: [String: NutritionServingRatio] = [:]
    ) -> SparkNutritionAPI.CreateMealRecordRequest {
        var mealFoods: [SparkNutritionAPI.MealFoodInput] = []
        var manualIntakes: [SparkNutritionAPI.NutritionIntakeInput] = []

        for item in recognition.draft.items {
            let ratio = servingRatios[item.name]?.rawValue ?? item.servingRatio
            if let foodItemID = item.foodItemId {
                mealFoods.append(
                    SparkNutritionAPI.MealFoodInput(
                        foodItemId: foodItemID,
                        servingRatio: ratio,
                        servingQuantity: nil,
                        servingUnit: "",
                        servingDescription: item.servingDescription
                    )
                )
            }
        }

        if mealFoods.isEmpty {
            manualIntakes = recognition.draft.intakes.map {
                SparkNutritionAPI.NutritionIntakeInput(
                    nutrientType: $0.nutrientType,
                    value: $0.value,
                    unit: $0.unit,
                    source: recognition.source.rawValue,
                    confidence: $0.confidence
                )
            }
        }

        return SparkNutritionAPI.CreateMealRecordRequest(
            memberId: memberID,
            mealType: mealType.rawValue,
            consumedAt: NutritionDraftBuilder.consumedAt(for: date),
            source: recognition.source.rawValue,
            sourceText: recognition.foodDescription ?? "",
            title: recognition.draft.title,
            recognitionId: recognition.recognitionID,
            fileIds: recognition.draft.imageFileIds,
            mealFoods: mealFoods,
            recipes: [],
            manualIntakes: manualIntakes
        )
    }
}
