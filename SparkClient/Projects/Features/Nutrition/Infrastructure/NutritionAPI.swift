import Foundation

// MARK: - NutritionAPI 网络层
//
// 饮食营养模块的 REST API 客户端，路径与 `SparkService/nutrition/urls.py` 一一对应。
// 职责：
// - 封装 HTTP 方法、路径、Query 参数与请求/响应类型
// - 通过 SparkBackendConfiguration 统一鉴权、重试、ETag 缓存与序列化
// - 上层 NutritionRepository 调用本 struct，不直接拼 URL
//
// 响应体经 APIResponseDecoder.decodeWrappedData 解包（服务端统一 `{ data: ... }` 包装）。

/// 饮食营养 REST API 客户端
struct NutritionAPI: @unchecked Sendable {
    let configuration: SparkBackendConfiguration

    init(configuration: SparkBackendConfiguration) {
        self.configuration = configuration
    }

    /// API 版本前缀，所有营养接口均在此路径下
    private static let basePath = "/api/v1/nutrition"
    /// 与医疗模块共用的 JSON 解码策略（日期、蛇形命名等）
    private static let decoder = JSONDecoder.medicalAPI

    // MARK: - Health & defaults

    /// 模块健康检查，用于探测服务端 nutrition 应用是否可用
    func healthCheck() async throws -> String {
        struct HealthPayload: Decodable, Sendable {
            var module: String
            var status: String
        }
        let payload: HealthPayload = try await get(path: "\(Self.basePath)/health/", name: "Health")
        return payload.status
    }

    /// 获取成员默认宏量营养素目标（未单独设置目标时的回退值）
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

    /// 获取成员当前营养目标（含已有目标与默认回退值）。
    func fetchGoalState(memberID: Int) async throws -> SparkNutritionAPI.RemoteNutritionGoalState {
        try await get(
            path: "\(Self.basePath)/goals/",
            query: [URLQueryItem(name: "member_id", value: "\(memberID)")],
            name: "Goals.State",
            responseType: SparkNutritionAPI.RemoteNutritionGoalState.self
        )
    }

    /// 保存成员营养目标。
    func saveGoal(_ request: SparkNutritionAPI.RemoteNutritionGoalUpsertRequest) async throws -> SparkNutritionAPI.RemoteNutritionGoal {
        try await post(
            path: "\(Self.basePath)/goals/",
            body: request,
            name: "Goals.Upsert",
            responseType: SparkNutritionAPI.RemoteNutritionGoal.self
        )
    }

    /// 重新计算卡路里目标：返回 BMR/TDEE/建议摄入与缺失字段。
    func calculateEnergyGoal(
        _ request: SparkNutritionAPI.RemoteNutritionGoalCalculationRequest
    ) async throws -> SparkNutritionAPI.RemoteNutritionEnergyCalculationResponse {
        try await post(
            path: "\(Self.basePath)/goals/calculate-energy/",
            body: request,
            name: "Goals.CalculateEnergy",
            responseType: SparkNutritionAPI.RemoteNutritionEnergyCalculationResponse.self
        )
    }

    /// 统一身体指标计算：BMI、理想体重范围、BMR/TDEE、建议摄入、消耗估算。
    func calculateBodyMetrics(
        _ request: SparkNutritionAPI.RemoteNutritionGoalCalculationRequest
    ) async throws -> SparkNutritionAPI.RemoteNutritionBodyMetricsCalculationResponse {
        try await post(
            path: "\(Self.basePath)/goals/calculate-body-metrics/",
            body: request,
            name: "Goals.CalculateBodyMetrics",
            responseType: SparkNutritionAPI.RemoteNutritionBodyMetricsCalculationResponse.self
        )
    }

    // MARK: - Dashboard

    /// 营养首页看板：某日摄入汇总、目标、各餐次卡片、Apple Health 外部数据等
    func fetchDashboard(memberID: Int, date: Date) async throws -> SparkNutritionAPI.RemoteNutritionDashboard {
        try await get(
            path: "\(Self.basePath)/dashboard/",
            query: memberDateQuery(memberID: memberID, date: date),
            name: "Dashboard",
            responseType: SparkNutritionAPI.RemoteNutritionDashboard.self
        )
    }

    // MARK: - Meal records

    /// 查询某日用餐记录；可选 `mealType` 筛选单餐（早餐/午餐等）
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

    /// 历史用餐记录：同一 list 端点，用 date_from / date_to 区间查询
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

    /// 创建用餐记录（手动录入、AI 识别确认等）
    func createMealRecord(_ request: SparkNutritionAPI.CreateMealRecordRequest) async throws -> SparkNutritionAPI.RemoteMealRecord {
        try await post(
            path: "\(Self.basePath)/meal-records/",
            body: request,
            name: "MealRecords.Create",
            responseType: SparkNutritionAPI.RemoteMealRecord.self
        )
    }

    /// 部分或全量更新用餐记录
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

    /// 食物/食谱搜索
    /// - Parameters:
    ///   - mode: 搜索模式，如 `text` / `barcode`
    ///   - query: 关键词或条码
    ///   - resultType: `food` / `recipe` / `all`
    ///   - favoriteOnly: 仅收藏
    ///   - createdByMeOnly: 仅当前用户创建
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

    /// 取消收藏：DELETE 带 query target_type + target_id（无 path 参数）
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

    /// 用户自建食物条目（含每份营养素）
    func createFoodItem(_ request: SparkNutritionAPI.CreateNutritionFoodItemRequest) async throws -> SparkNutritionAPI.RemoteFoodItem {
        try await post(
            path: "\(Self.basePath)/food-items/",
            body: request,
            name: "FoodItems.Create",
            responseType: SparkNutritionAPI.RemoteFoodItem.self
        )
    }

    /// 用户自建食谱；响应含服务端计算的营养汇总
    func createRecipe(_ request: SparkNutritionAPI.CreateNutritionRecipeRequest) async throws -> SparkNutritionAPI.RemoteRecipeCreateResponse {
        try await post(
            path: "\(Self.basePath)/recipes/",
            body: request,
            name: "Recipes.Create",
            responseType: SparkNutritionAPI.RemoteRecipeCreateResponse.self
        )
    }

    // MARK: - Energy burn

    /// 某日能量消耗列表（手动录入 + Apple Health 导入）
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

    /// 批量上报 HealthKit 读取的第三方 App 饮食摄入（服务端按 apple_health_id 去重）
    /// 对应 Django `import_apple_health_intakes`，仅本人成员可调用
    func importAppleHealthIntakes(_ request: SparkNutritionAPI.AppleHealthIntakeImportRequest) async throws -> SparkNutritionAPI.RemoteAppleHealthImportResponse {
        try await post(
            path: "\(Self.basePath)/apple-health/intake-imports/",
            body: request,
            name: "AppleHealth.IntakeImport",
            responseType: SparkNutritionAPI.RemoteAppleHealthImportResponse.self
        )
    }

    /// 批量上报 HealthKit 活动消耗与基础代谢样本
    func importAppleHealthEnergyBurns(_ request: SparkNutritionAPI.AppleHealthEnergyBurnImportRequest) async throws -> SparkNutritionAPI.RemoteAppleHealthImportResponse {
        try await post(
            path: "\(Self.basePath)/apple-health/energy-burn-imports/",
            body: request,
            name: "AppleHealth.EnergyBurnImport",
            responseType: SparkNutritionAPI.RemoteAppleHealthImportResponse.self
        )
    }

    /// 用餐营养素写入 HealthKit 后，将 HKSample UUID 回写到服务端 intake 记录
    func writeIntakeAppleHealthID(intakeID: Int, request: SparkNutritionAPI.AppleHealthIDUpdateRequest) async throws {
        _ = try await post(
            path: "\(Self.basePath)/intakes/\(intakeID)/apple-health-id/",
            body: request,
            name: "AppleHealth.IntakeIDWriteback",
            responseType: SparkNutritionAPI.RemoteNutritionIntake.self
        )
    }

    /// 手动能量消耗写入 HealthKit 后，回写 apple_health_id 到 burn 记录
    func writeEnergyBurnAppleHealthID(recordID: Int, request: SparkNutritionAPI.AppleHealthIDUpdateRequest) async throws {
        _ = try await post(
            path: "\(Self.basePath)/energy-burn-records/\(recordID)/apple-health-id/",
            body: request,
            name: "AppleHealth.EnergyBurnIDWriteback",
            responseType: SparkNutritionAPI.RemoteEnergyBurnRecord.self
        )
    }

    // MARK: - Transport helpers

    /// 按成员 + 自然日查询的通用 Query 参数（date 为 YYYY-MM-DD 本地日）
    private func memberDateQuery(memberID: Int, date: Date) -> [URLQueryItem] {
        [
            URLQueryItem(name: "member_id", value: "\(memberID)"),
            URLQueryItem(name: "date", value: MedicalDateCoding.encodeDateOnly(date))
        ]
    }

    /// GET 请求：启用 ETag 缓存与幂等重试，默认缓存 TTL 24 小时
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

    /// POST 写操作：高优先级队列，不缓存，非幂等
    private func post<T: Encodable & Sendable, R: Decodable>(
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

    /// PATCH 部分更新：策略同 POST
    private func patch<T: Encodable & Sendable, R: Decodable>(
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

    /// DELETE：支持 query 参数（如取消收藏）；高优先级、非幂等
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
