import Foundation

struct NutritionRepository: Sendable {
    let api: NutritionAPI

    func fetchDashboard(memberID: Int, date: Date) async throws -> SparkNutritionAPI.RemoteNutritionDashboard {
        try await api.fetchDashboard(memberID: memberID, date: date)
    }

    func listMealRecords(
        memberID: Int,
        date: Date,
        mealType: NutritionMealType? = nil
    ) async throws -> SparkNutritionAPI.RemoteMealRecordListResponse {
        try await api.listMealRecords(memberID: memberID, date: date, mealType: mealType)
    }

    func listMealRecordsHistory(
        memberID: Int,
        dateFrom: Date,
        dateTo: Date
    ) async throws -> SparkNutritionAPI.RemoteMealRecordHistoryResponse {
        try await api.listMealRecordsHistory(memberID: memberID, dateFrom: dateFrom, dateTo: dateTo)
    }

    func createMealRecord(_ request: SparkNutritionAPI.CreateMealRecordRequest) async throws -> SparkNutritionAPI.RemoteMealRecord {
        try await api.createMealRecord(request)
    }

    func updateMealRecord(
        recordID: Int,
        request: SparkNutritionAPI.UpdateMealRecordRequest
    ) async throws -> SparkNutritionAPI.RemoteMealRecord {
        try await api.updateMealRecord(recordID: recordID, request: request)
    }

    func deleteMealRecord(recordID: Int) async throws {
        try await api.deleteMealRecord(recordID: recordID)
    }

    func search(
        memberID: Int,
        mode: String,
        query: String,
        resultType: String = "all",
        favoriteOnly: Bool = false,
        createdByMeOnly: Bool = false
    ) async throws -> SparkNutritionAPI.RemoteNutritionSearchResponse {
        try await api.search(
            memberID: memberID,
            mode: mode,
            query: query,
            resultType: resultType,
            favoriteOnly: favoriteOnly,
            createdByMeOnly: createdByMeOnly
        )
    }

    func addFavorite(_ request: SparkNutritionAPI.NutritionFavoriteRequest) async throws -> SparkNutritionAPI.RemoteFavorite {
        try await api.addFavorite(request)
    }

    func removeFavorite(targetType: String, targetID: Int) async throws {
        try await api.removeFavorite(targetType: targetType, targetID: targetID)
    }

    func createFoodItem(_ request: SparkNutritionAPI.CreateNutritionFoodItemRequest) async throws -> SparkNutritionAPI.RemoteFoodItem {
        try await api.createFoodItem(request)
    }

    func createRecipe(_ request: SparkNutritionAPI.CreateNutritionRecipeRequest) async throws -> SparkNutritionAPI.RemoteRecipeCreateResponse {
        try await api.createRecipe(request)
    }

    func listEnergyBurnRecords(memberID: Int, date: Date) async throws -> [SparkNutritionAPI.RemoteEnergyBurnRecord] {
        try await api.listEnergyBurnRecords(memberID: memberID, date: date)
    }

    func createEnergyBurnRecord(_ request: SparkNutritionAPI.CreateEnergyBurnRecordRequest) async throws -> SparkNutritionAPI.RemoteEnergyBurnRecord {
        try await api.createEnergyBurnRecord(request)
    }

    func updateEnergyBurnRecord(
        recordID: Int,
        request: SparkNutritionAPI.UpdateEnergyBurnRecordRequest
    ) async throws -> SparkNutritionAPI.RemoteEnergyBurnRecord {
        try await api.updateEnergyBurnRecord(recordID: recordID, request: request)
    }

    func deleteEnergyBurnRecord(recordID: Int) async throws {
        try await api.deleteEnergyBurnRecord(recordID: recordID)
    }

    func importAppleHealthIntakes(_ request: SparkNutritionAPI.AppleHealthIntakeImportRequest) async throws -> [SparkNutritionAPI.RemoteAppleHealthIntakeImport] {
        try await api.importAppleHealthIntakes(request)
    }

    func importAppleHealthEnergyBurns(_ request: SparkNutritionAPI.AppleHealthEnergyBurnImportRequest) async throws -> [SparkNutritionAPI.RemoteEnergyBurnRecord] {
        try await api.importAppleHealthEnergyBurns(request)
    }

    func writeIntakeAppleHealthID(intakeID: Int, request: SparkNutritionAPI.AppleHealthIDUpdateRequest) async throws {
        try await api.writeIntakeAppleHealthID(intakeID: intakeID, request: request)
    }

    func writeEnergyBurnAppleHealthID(recordID: Int, request: SparkNutritionAPI.AppleHealthIDUpdateRequest) async throws {
        try await api.writeEnergyBurnAppleHealthID(recordID: recordID, request: request)
    }
}
