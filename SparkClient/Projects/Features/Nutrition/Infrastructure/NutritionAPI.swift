import Foundation

/// 饮食营养 REST API，路径与 `SparkService/nutrition/urls.py` 一一对应。
struct NutritionAPI: @unchecked Sendable {
    let configuration: SparkBackendConfiguration

    init(configuration: SparkBackendConfiguration) {
        self.configuration = configuration
    }

    private static let basePath = "/api/v1/nutrition"
    private static let decoder = JSONDecoder.medicalAPI
    // MARK: - Health & defaults

    func healthCheck() async throws -> String {
        struct HealthPayload: Decodable, Sendable {
            var module: String
            var status: String
        }
        let payload: HealthPayload = try await get(path: "\(Self.basePath)/health/", name: "Health")
        return payload.status
    }

    func fetchDefaults(memberID: Int) async throws -> SparkNutritionAPI.RemoteNutritionMacroTarget {
        struct DefaultsPayload: Decodable, Sendable {
            var goal: SparkNutritionAPI.RemoteNutritionMacroTarget
        }
        let payload: DefaultsPayload = try await get(
            path: "\(Self.basePath)/defaults/",
            query: [URLQueryItem(name: "member_id", value: "\(memberID)")],
            name: "Defaults"
        )
        return payload.goal
    }

    // MARK: - Dashboard

    func fetchDashboard(memberID: Int, date: Date) async throws -> SparkNutritionAPI.RemoteNutritionDashboard {
        try await get(
            path: "\(Self.basePath)/dashboard/",
            query: memberDateQuery(memberID: memberID, date: date),
            name: "Dashboard",
            responseType: SparkNutritionAPI.RemoteNutritionDashboard.self
        )
    }

    // MARK: - Meal records

    func listMealRecords(
        memberID: Int,
        date: Date,
        mealType: NutritionMealType? = nil
    ) async throws -> SparkNutritionAPI.RemoteMealRecordListResponse {
        var query = memberDateQuery(memberID: memberID, date: date)
        if let mealType {
            query.append(URLQueryItem(name: "meal_type", value: mealType.rawValue))
        }
        return try await get(
            path: "\(Self.basePath)/meal-records/",
            query: query,
            name: "MealRecords.List",
            responseType: SparkNutritionAPI.RemoteMealRecordListResponse.self
        )
    }

    func listMealRecordsHistory(
        memberID: Int,
        dateFrom: Date,
        dateTo: Date
    ) async throws -> SparkNutritionAPI.RemoteMealRecordHistoryResponse {
        try await get(
            path: "\(Self.basePath)/meal-records/",
            query: [
                URLQueryItem(name: "member_id", value: "\(memberID)"),
                URLQueryItem(name: "date_from", value: MedicalDateCoding.encodeDateOnly(dateFrom)),
                URLQueryItem(name: "date_to", value: MedicalDateCoding.encodeDateOnly(dateTo))
            ],
            name: "MealRecords.History",
            responseType: SparkNutritionAPI.RemoteMealRecordHistoryResponse.self
        )
    }

    func createMealRecord(_ request: SparkNutritionAPI.CreateMealRecordRequest) async throws -> SparkNutritionAPI.RemoteMealRecord {
        try await post(
            path: "\(Self.basePath)/meal-records/",
            body: request,
            name: "MealRecords.Create",
            responseType: SparkNutritionAPI.RemoteMealRecord.self
        )
    }

    func updateMealRecord(
        recordID: Int,
        request: SparkNutritionAPI.UpdateMealRecordRequest
    ) async throws -> SparkNutritionAPI.RemoteMealRecord {
        try await patch(
            path: "\(Self.basePath)/meal-records/\(recordID)/",
            body: request,
            name: "MealRecords.Update",
            responseType: SparkNutritionAPI.RemoteMealRecord.self
        )
    }

    func deleteMealRecord(recordID: Int) async throws {
        _ = try await delete(
            path: "\(Self.basePath)/meal-records/\(recordID)/",
            name: "MealRecords.Delete",
            responseType: SparkNutritionAPI.RemoteDeleteResult.self
        )
    }

    // MARK: - Search & favorites

    func search(
        memberID: Int,
        mode: String,
        query: String,
        resultType: String = "all",
        favoriteOnly: Bool = false,
        createdByMeOnly: Bool = false
    ) async throws -> SparkNutritionAPI.RemoteNutritionSearchResponse {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "member_id", value: "\(memberID)"),
            URLQueryItem(name: "mode", value: mode),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: resultType)
        ]
        if favoriteOnly {
            queryItems.append(URLQueryItem(name: "favorite", value: "true"))
        }
        if createdByMeOnly {
            queryItems.append(URLQueryItem(name: "created_by_me", value: "true"))
        }
        return try await get(
            path: "\(Self.basePath)/search/",
            query: queryItems,
            name: "Search",
            responseType: SparkNutritionAPI.RemoteNutritionSearchResponse.self
        )
    }

    func addFavorite(_ request: SparkNutritionAPI.NutritionFavoriteRequest) async throws -> SparkNutritionAPI.RemoteFavorite {
        try await post(
            path: "\(Self.basePath)/favorites/",
            body: request,
            name: "Favorites.Add",
            responseType: SparkNutritionAPI.RemoteFavorite.self
        )
    }

    func removeFavorite(targetType: String, targetID: Int) async throws {
        _ = try await delete(
            path: "\(Self.basePath)/favorites/",
            query: [
                URLQueryItem(name: "target_type", value: targetType),
                URLQueryItem(name: "target_id", value: "\(targetID)")
            ],
            name: "Favorites.Remove",
            responseType: SparkNutritionAPI.RemoteDeleteResult.self
        )
    }

    // MARK: - Custom food & recipe

    func createFoodItem(_ request: SparkNutritionAPI.CreateNutritionFoodItemRequest) async throws -> SparkNutritionAPI.RemoteFoodItem {
        try await post(
            path: "\(Self.basePath)/food-items/",
            body: request,
            name: "FoodItems.Create",
            responseType: SparkNutritionAPI.RemoteFoodItem.self
        )
    }

    func createRecipe(_ request: SparkNutritionAPI.CreateNutritionRecipeRequest) async throws -> SparkNutritionAPI.RemoteRecipeCreateResponse {
        try await post(
            path: "\(Self.basePath)/recipes/",
            body: request,
            name: "Recipes.Create",
            responseType: SparkNutritionAPI.RemoteRecipeCreateResponse.self
        )
    }

    // MARK: - Energy burn

    func listEnergyBurnRecords(memberID: Int, date: Date) async throws -> [SparkNutritionAPI.RemoteEnergyBurnRecord] {
        struct ListPayload: Decodable, Sendable {
            var records: [SparkNutritionAPI.RemoteEnergyBurnRecord]
        }
        let payload: ListPayload = try await get(
            path: "\(Self.basePath)/energy-burn-records/",
            query: memberDateQuery(memberID: memberID, date: date),
            name: "EnergyBurn.List",
            responseType: ListPayload.self
        )
        return payload.records
    }

    func createEnergyBurnRecord(_ request: SparkNutritionAPI.CreateEnergyBurnRecordRequest) async throws -> SparkNutritionAPI.RemoteEnergyBurnRecord {
        try await post(
            path: "\(Self.basePath)/energy-burn-records/",
            body: request,
            name: "EnergyBurn.Create",
            responseType: SparkNutritionAPI.RemoteEnergyBurnRecord.self
        )
    }

    func updateEnergyBurnRecord(
        recordID: Int,
        request: SparkNutritionAPI.UpdateEnergyBurnRecordRequest
    ) async throws -> SparkNutritionAPI.RemoteEnergyBurnRecord {
        try await patch(
            path: "\(Self.basePath)/energy-burn-records/\(recordID)/",
            body: request,
            name: "EnergyBurn.Update",
            responseType: SparkNutritionAPI.RemoteEnergyBurnRecord.self
        )
    }

    func deleteEnergyBurnRecord(recordID: Int) async throws {
        _ = try await delete(
            path: "\(Self.basePath)/energy-burn-records/\(recordID)/",
            name: "EnergyBurn.Delete",
            responseType: SparkNutritionAPI.RemoteDeleteResult.self
        )
    }

    // MARK: - Apple Health imports

    func importAppleHealthIntakes(_ request: SparkNutritionAPI.AppleHealthIntakeImportRequest) async throws -> [SparkNutritionAPI.RemoteAppleHealthIntakeImport] {
        try await post(
            path: "\(Self.basePath)/apple-health/intake-imports/",
            body: request,
            name: "AppleHealth.IntakeImport",
            responseType: [SparkNutritionAPI.RemoteAppleHealthIntakeImport].self
        )
    }

    func importAppleHealthEnergyBurns(_ request: SparkNutritionAPI.AppleHealthEnergyBurnImportRequest) async throws -> [SparkNutritionAPI.RemoteEnergyBurnRecord] {
        try await post(
            path: "\(Self.basePath)/apple-health/energy-burn-imports/",
            body: request,
            name: "AppleHealth.EnergyBurnImport",
            responseType: [SparkNutritionAPI.RemoteEnergyBurnRecord].self
        )
    }

    func writeIntakeAppleHealthID(intakeID: Int, request: SparkNutritionAPI.AppleHealthIDUpdateRequest) async throws {
        _ = try await post(
            path: "\(Self.basePath)/intakes/\(intakeID)/apple-health-id/",
            body: request,
            name: "AppleHealth.IntakeIDWriteback",
            responseType: SparkNutritionAPI.RemoteNutritionIntake.self
        )
    }

    func writeEnergyBurnAppleHealthID(recordID: Int, request: SparkNutritionAPI.AppleHealthIDUpdateRequest) async throws {
        _ = try await post(
            path: "\(Self.basePath)/energy-burn-records/\(recordID)/apple-health-id/",
            body: request,
            name: "AppleHealth.EnergyBurnIDWriteback",
            responseType: SparkNutritionAPI.RemoteEnergyBurnRecord.self
        )
    }

    // MARK: - Transport helpers

    private func memberDateQuery(memberID: Int, date: Date) -> [URLQueryItem] {
        [
            URLQueryItem(name: "member_id", value: "\(memberID)"),
            URLQueryItem(name: "date", value: MedicalDateCoding.encodeDateOnly(date))
        ]
    }

    private func get<T: Decodable>(
        path: String,
        query: [URLQueryItem] = [],
        name: String,
        responseType: T.Type = T.self,
        etagTTL: TimeInterval = 86400
    ) async throws -> T {
        let operation = CacheableSparkNetworkOperation(
            name: "Nutrition.\(name)",
            apiName: "NutritionAPI",
            request: SparkNetworkRequest(
                method: .get,
                path: path,
                queryItems: query,
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: true,
                    serialKey: "nutrition.\(name)",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .normal,
                    etagTTL: etagTTL
                )
            )
        )
        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedData(T.self, from: response, decoder: Self.decoder)
    }

    private func post<T: Encodable, R: Decodable>(
        path: String,
        body: T,
        name: String,
        responseType: R.Type
    ) async throws -> R {
        let operation = CacheableSparkNetworkOperation(
            name: "Nutrition.\(name)",
            apiName: "NutritionAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: path,
                body: .json(AnyEncodable(body)),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "nutrition.\(name)",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .high
                )
            )
        )
        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedData(R.self, from: response, decoder: Self.decoder)
    }

    private func patch<T: Encodable, R: Decodable>(
        path: String,
        body: T,
        name: String,
        responseType: R.Type
    ) async throws -> R {
        let operation = CacheableSparkNetworkOperation(
            name: "Nutrition.\(name)",
            apiName: "NutritionAPI",
            request: SparkNetworkRequest(
                method: .patch,
                path: path,
                body: .json(AnyEncodable(body)),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "nutrition.\(name)",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .high
                )
            )
        )
        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedData(R.self, from: response, decoder: Self.decoder)
    }

    private func delete<R: Decodable>(
        path: String,
        query: [URLQueryItem] = [],
        name: String,
        responseType: R.Type
    ) async throws -> R {
        let operation = CacheableSparkNetworkOperation(
            name: "Nutrition.\(name)",
            apiName: "NutritionAPI",
            request: SparkNetworkRequest(
                method: .delete,
                path: path,
                queryItems: query,
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "nutrition.\(name)",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .high
                )
            )
        )
        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedData(R.self, from: response, decoder: Self.decoder)
    }
}
