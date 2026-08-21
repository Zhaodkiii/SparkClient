import Foundation

// MARK: - 营养模块 Use Case 层
//
// 本文件封装营养功能的应用层业务编排，职责包括：
// 1. 调用 NutritionRepository 完成网络 I/O
// 2. 通过 NutritionViewDataMapper / NutritionDraftBuilder 等将 Remote 模型转为 View 层可用的 ViewData
// 3. 统一记录结构化日志（耗时、条数、关键 ID）
// 4. 协调 HealthKit 与服务端的双向同步（仅本人成员）
//
// 各 UseCase 按功能域拆分，均为无状态 struct + Sendable，便于在 SwiftUI / Actor 间传递。

// MARK: - 营养看板

/// 营养首页看板：加载某日某成员的摄入汇总、目标进度、各餐次卡片
struct NutritionDashboardUseCase: Sendable {
    let repository: NutritionRepository
    let logger: Logger

    private let logModule = LogModule.nutrition

    /// 拉取远程看板并映射为首页展示数据
    func loadDashboard(memberID: Int, date: Date) async throws -> NutritionDashboardViewData {
        let startedAt = Date()
        logger.info(
            "看板加载开始 memberID=\(memberID) date=\(MedicalDateCoding.encodeDateOnly(date))",
            module: logModule
        )
        let remote = try await repository.fetchDashboard(memberID: memberID, date: date)
        let viewData = NutritionViewDataMapper.dashboard(from: remote)
        let cost = Date().timeIntervalSince(startedAt)
        logger.info(
            "看板加载成功 cost=\(String(format: "%.3f", cost))s memberID=\(memberID) consumed=\(Int(viewData.consumedEnergyKcal)) remaining=\(Int(viewData.remainingEnergyKcal))",
            module: logModule
        )
        return viewData
    }

    /// 在看板基础上生成「营养详情」页所需的更细粒度汇总（宏量进度、来源拆分等）
    func loadDashboardDetail(memberID: Int, date: Date) async throws -> NutritionSummaryDetailViewData {
        let dashboard = try await loadDashboard(memberID: memberID, date: date)
        return NutritionViewDataMapper.summaryDetail(from: dashboard)
    }
}

// MARK: - 用餐记录

/// 用餐记录的查询、创建、更新、删除及批量编辑（改份量、删食物、复制到其他餐次）
struct NutritionMealRecordUseCase: Sendable {
    let repository: NutritionRepository
    let logger: Logger

    private let logModule = LogModule.nutrition

    /// 原始 API 响应：某日用餐记录列表（可选按餐次筛选）
    func fetchMealRecordPage(
        memberID: Int,
        date: Date,
        mealType: NutritionMealType? = nil
    ) async throws -> SparkNutritionAPI.RemoteMealRecordListResponse {
        logger.info(
            "餐次列表加载开始 memberID=\(memberID) date=\(MedicalDateCoding.encodeDateOnly(date))",
            module: logModule
        )
        return try await repository.listMealRecords(memberID: memberID, date: date, mealType: mealType)
    }

    /// 按餐次分组后的列表 ViewData，供首页或历史列表展示
    func loadMealRecords(memberID: Int, date: Date) async throws -> [NutritionMealGroupViewData] {
        let startedAt = Date()
        let response = try await fetchMealRecordPage(memberID: memberID, date: date)
        let groups = NutritionViewDataMapper.mealGroups(from: response)
        let cost = Date().timeIntervalSince(startedAt)
        logger.info(
            "餐次列表加载成功 cost=\(String(format: "%.3f", cost))s groups=\(groups.count) records=\(response.records.count)",
            module: logModule
        )
        return groups
    }

    /// 某一餐次（如午餐）的详情页：食物列表、营养小计、进度条等
    func loadMealDetail(
        memberID: Int,
        date: Date,
        mealType: NutritionMealType
    ) async throws -> NutritionMealDetailViewData {
        let startedAt = Date()
        logger.info(
            "餐次详情加载开始 memberID=\(memberID) mealType=\(mealType.rawValue)",
            module: logModule
        )
        let response = try await repository.listMealRecords(
            memberID: memberID,
            date: date,
            mealType: mealType
        )
        let viewData = NutritionViewDataMapper.mealDetail(
            mealType: mealType,
            date: date,
            response: response
        )
        let cost = Date().timeIntervalSince(startedAt)
        logger.info(
            "餐次详情加载成功 cost=\(String(format: "%.3f", cost))s foods=\(viewData.foods.count)",
            module: logModule
        )
        return viewData
    }

    /// 使用完整请求体创建用餐记录（识别确认、手动录入等统一入口）
    func createMealRecord(_ request: SparkNutritionAPI.CreateMealRecordRequest) async throws -> SparkNutritionAPI.RemoteMealRecord {
        logger.info(
            "创建饮食记录 memberID=\(request.memberId) mealType=\(request.mealType)",
            module: logModule
        )
        return try await repository.createMealRecord(request)
    }

    /// 从 UI 选中的食物条目构建请求并创建记录（简化调用方）
    func createMealRecord(
        memberID: Int,
        mealType: NutritionMealType,
        date: Date,
        items: [NutritionFoodSelectionItem]
    ) async throws -> SparkNutritionAPI.RemoteMealRecord {
        let request = NutritionDraftBuilder.makeCreateRequest(
            memberID: memberID,
            mealType: mealType,
            date: date,
            items: items
        )
        return try await createMealRecord(request)
    }

    /// 部分或全量更新已有用餐记录
    func updateMealRecord(
        recordID: Int,
        request: SparkNutritionAPI.UpdateMealRecordRequest
    ) async throws -> SparkNutritionAPI.RemoteMealRecord {
        logger.info("更新饮食记录 recordID=\(recordID)", module: logModule)
        return try await repository.updateMealRecord(recordID: recordID, request: request)
    }

    func deleteMealRecord(recordID: Int) async throws {
        logger.info("删除饮食记录 recordID=\(recordID)", module: logModule)
        try await repository.deleteMealRecord(recordID: recordID)
    }

    /// 修改单条 mealFood 的份量：effectiveRatio = 预设份量枚举 × 用户输入数量
    func updateMealFoodServing(
        record: SparkNutritionAPI.RemoteMealRecord,
        mealFoodID: Int,
        servingRatio: NutritionServingRatio,
        quantity: Double
    ) async throws -> SparkNutritionAPI.RemoteMealRecord {
        let effectiveRatio = servingRatio.rawValue * quantity
        let mealFoods = record.mealFoods.map { mealFood in
            NutritionMealRecordMapper.mealFoodInput(
                from: mealFood,
                servingRatio: mealFood.id == mealFoodID ? effectiveRatio : mealFood.servingRatio
            )
        }
        return try await updateMealRecord(
            recordID: record.id,
            request: SparkNutritionAPI.UpdateMealRecordRequest(mealFoods: mealFoods)
        )
    }

    /// 批量删除选中的 mealFood：若某条记录下食物删光则整记录删除，否则 PATCH 剩余列表
    func deleteMealFoods(
        mealFoodIDs: Set<Int>,
        records: [SparkNutritionAPI.RemoteMealRecord]
    ) async throws {
        for record in records {
            let remaining = record.mealFoods.filter { mealFoodIDs.contains($0.id) == false }
            guard remaining.count < record.mealFoods.count else { continue }

            if remaining.isEmpty {
                try await deleteMealRecord(recordID: record.id)
            } else {
                let mealFoods = remaining.map {
                    NutritionMealRecordMapper.mealFoodInput(from: $0, servingRatio: $0.servingRatio)
                }
                _ = try await updateMealRecord(
                    recordID: record.id,
                    request: SparkNutritionAPI.UpdateMealRecordRequest(mealFoods: mealFoods)
                )
            }
        }
    }

    /// 将编辑页选中的食物复制到目标日期/餐次，生成一条新的手动录入记录
    func copyMealFoods(
        items: [NutritionMealFoodEditItemViewData],
        memberID: Int,
        targetDate: Date,
        targetMealType: NutritionMealType
    ) async throws -> SparkNutritionAPI.RemoteMealRecord {
        let mealFoods = items.map { item in
            SparkNutritionAPI.MealFoodInput(
                foodItemId: item.foodItemID,
                servingRatio: item.servingRatio.rawValue,
                servingQuantity: nil,
                servingUnit: item.servingUnit,
                servingDescription: item.servingDescription
            )
        }
        let title = items.map(\.title).joined(separator: ", ")
        let request = SparkNutritionAPI.CreateMealRecordRequest(
            memberId: memberID,
            mealType: targetMealType.rawValue,
            consumedAt: NutritionDraftBuilder.consumedAt(for: targetDate),
            source: NutritionRecordSource.manual.rawValue,
            sourceText: "",
            title: title,
            recognitionId: nil,
            fileIds: [],
            mealFoods: mealFoods,
            recipes: [],
            manualIntakes: []
        )
        return try await createMealRecord(request)
    }

    /// 按日期区间加载历史，并按自然日聚合为 NutritionHistoryDayViewData
    func loadHistory(
        memberID: Int,
        dateFrom: Date,
        dateTo: Date
    ) async throws -> [NutritionHistoryDayViewData] {
        let startedAt = Date()
        logger.info(
            "历史记录加载开始 memberID=\(memberID) from=\(MedicalDateCoding.encodeDateOnly(dateFrom)) to=\(MedicalDateCoding.encodeDateOnly(dateTo))",
            module: logModule
        )
        let response = try await repository.listMealRecordsHistory(
            memberID: memberID,
            dateFrom: dateFrom,
            dateTo: dateTo
        )
        let days = NutritionViewDataMapper.historyDays(from: response.records, dateFrom: dateFrom, dateTo: dateTo)
        let cost = Date().timeIntervalSince(startedAt)
        logger.info(
            "历史记录加载成功 cost=\(String(format: "%.3f", cost))s days=\(days.count) records=\(response.records.count)",
            module: logModule
        )
        return days
    }
}

// MARK: - 食物搜索与自定义

/// 食物/食谱搜索、收藏、用户自建食物与食谱
struct NutritionSearchUseCase: Sendable {
    let repository: NutritionRepository
    let logger: Logger

    private let logModule = LogModule.nutrition

    /// 按筛选条件搜索，结果映射为列表 Cell 所需的 ViewData
    func search(
        memberID: Int,
        filters: NutritionFoodSearchFilterState
    ) async throws -> [NutritionFoodSearchResultViewData] {
        logger.info(
            "搜索开始 memberID=\(memberID) mode=\(filters.mode.rawValue) query=\(LogMessageSanitizer.singleLineSnippet(filters.query))",
            module: logModule
        )
        let response = try await repository.search(
            memberID: memberID,
            mode: filters.mode.rawValue,
            query: filters.query,
            resultType: filters.type ?? "all",
            favoriteOnly: filters.favoriteOnly,
            createdByMeOnly: filters.createdByMeOnly
        )
        let items = response.items.map { mapSearchResult($0, mode: filters.mode) }
        logger.info("搜索完成 count=\(items.count)", module: logModule)
        return items
    }

    /// 空关键词 + type=food，用于首页推荐/常用食物列表
    func loadRecommendedFoods(memberID: Int) async throws -> [NutritionFoodSearchResultViewData] {
        let filters = NutritionFoodSearchFilterState(
            mode: .text,
            query: "",
            type: "food",
            favoriteOnly: false,
            createdByMeOnly: false
        )
        return try await search(memberID: memberID, filters: filters)
    }

    /// 切换收藏状态：`isFavorite == true` 表示当前已收藏，执行取消；否则添加
    func toggleFavorite(
        targetType: String,
        targetID: Int,
        isFavorite: Bool
    ) async throws {
        let request = SparkNutritionAPI.NutritionFavoriteRequest(targetType: targetType, targetId: targetID)
        if isFavorite {
            try await repository.removeFavorite(targetType: targetType, targetID: targetID)
        } else {
            _ = try await repository.addFavorite(request)
        }
    }

    func createCustomFood(_ request: SparkNutritionAPI.CreateNutritionFoodItemRequest) async throws -> SparkNutritionAPI.RemoteFoodItem {
        logger.info("创建自定义食物 name=\(LogMessageSanitizer.singleLineSnippet(request.name))", module: logModule)
        return try await repository.createFoodItem(request)
    }

    /// 使用完整请求体创建用户食谱（含组成食物与营养汇总）
    func createRecipe(_ request: SparkNutritionAPI.CreateNutritionRecipeRequest) async throws -> SparkNutritionAPI.RemoteRecipeCreateResponse {
        logger.info(
            "创建膳食 name=\(LogMessageSanitizer.singleLineSnippet(request.name)) foods=\(request.foods.count)",
            module: logModule
        )
        let response = try await repository.createRecipe(request)
        logger.info(
            "创建膳食成功 recipeID=\(response.recipe.id) intakes=\(response.intakes.count) energyKcal=\(Int(response.overview.energyKcal))",
            module: logModule
        )
        return response
    }

    /// 从草稿食物列表快速创建食谱：名称为描述或食物名拼接
    func createRecipe(
        from foods: [NutritionRecipeDraftFood],
        description: String
    ) async throws -> SparkNutritionAPI.RemoteRecipeCreateResponse {
        let defaultName = foods.map(\.title).joined(separator: ", ")
        let name = description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultName : description
        let request = SparkNutritionAPI.CreateNutritionRecipeRequest(
            name: name,
            localizedName: name,
            category: "custom",
            servingQuantity: 1,
            servingUnit: "",
            servingDescription: L10n.text("nutrition.recipe_create.default_serving"),
            foods: foods.map { food in
                SparkNutritionAPI.MealFoodInput(
                    foodItemId: food.foodItemID,
                    servingRatio: food.servingRatio.rawValue,
                    servingQuantity: nil,
                    servingUnit: food.servingUnit,
                    servingDescription: food.servingDescription
                )
            }
        )
        return try await createRecipe(request)
    }

    /// 将 RemoteNutritionSearchResult 转为 UI 列表项（统一食物/食谱的标题、副标题、营养网格）
    private func mapSearchResult(
        _ result: SparkNutritionAPI.RemoteNutritionSearchResult,
        mode: NutritionFoodSearchMode
    ) -> NutritionFoodSearchResultViewData {
        let title: String
        let subtitle: String
        let isVerified: Bool

        if let food = result.foodItem {
            title = food.localizedName?.isEmpty == false ? food.localizedName! : food.name
            subtitle = food.servingDescription ?? food.brandName ?? ""
            isVerified = food.isVerified ?? false
        } else if let recipe = result.recipe {
            title = recipe.localizedName?.isEmpty == false ? recipe.localizedName! : recipe.name
            subtitle = recipe.servingDescription ?? ""
            isVerified = false
        } else {
            title = result.id
            subtitle = ""
            isVerified = false
        }

        let targetID: Int
        if let food = result.foodItem {
            targetID = food.id
        } else if let recipe = result.recipe {
            targetID = recipe.id
        } else {
            targetID = 0
        }

        return NutritionFoodSearchResultViewData(
            id: result.id,
            mode: mode,
            resultType: result.resultType,
            targetID: targetID,
            title: title,
            subtitle: subtitle,
            badgeText: result.resultType,
            isFavorite: result.isFavorite,
            isVerified: isVerified,
            isCreatedByMe: result.isCreatedByMe,
            overview: NutritionOverviewGridData(
                energyKcal: result.overview.energyKcal,
                proteinGrams: result.overview.proteinG,
                carbohydrateGrams: result.overview.carbohydrateG,
                fatGrams: result.overview.fatG
            ),
            calorieText: NutritionFormatting.energyKcal(result.overview.energyKcal)
        )
    }
}

// MARK: - Apple Health 双向同步

/// 协调 HealthKit 与服务端：读外部数据上报、写本 App 数据并回传 UUID
///
/// 安全策略：仅 `member.relationship` 表示本人时才读写 HealthKit，家庭成员数据不同步。
struct NutritionHealthKitSyncUseCase: Sendable {
    let repository: NutritionRepository
    let healthKitStore: NutritionHealthKitStore
    let logger: Logger

    private let logModule = LogModule.nutrition

    /// 本人成员进入首页时，读取 Apple 健康中的**第三方**营养摄入与能量消耗并上报服务端。
    ///
    /// 失败仅打 warning，不向上抛错，避免阻塞首页加载。
    func syncTodayIfNeeded(member: Member, date: Date) async {
        guard member.isSelfMember else {
            logger.debug(
                "跳过 HealthKit 同步：非本人成员 memberID=\(member.id) relationship=\(member.relationship)",
                module: logModule
            )
            return
        }

        let dateLabel = MedicalDateCoding.encodeDateOnly(date)
        logger.info(
            "HealthKit 同步开始 memberID=\(member.id) date=\(dateLabel)",
            module: logModule
        )

        do {
//            let intakeSamples = try await healthKitStore.fetchExternalIntakeSamples(on: date)
//            if intakeSamples.isEmpty == false {
//                let response = try await repository.importAppleHealthIntakes(
//                    SparkNutritionAPI.AppleHealthIntakeImportRequest(
//                        memberId: member.id,
//                        samples: intakeSamples
//                    )
//                )
//                logger.info(
//                    "HealthKit 外部营养摄入上报成功 samples=\(intakeSamples.count) imported=\(response.imported.count) duplicates=\(response.duplicates.count) memberID=\(member.id)",
//                    module: logModule
//                )
//            }
//
//            let burnSamples = try await healthKitStore.fetchEnergyBurnSamples(on: date)
//            if burnSamples.isEmpty == false {
//                let response = try await repository.importAppleHealthEnergyBurns(
//                    SparkNutritionAPI.AppleHealthEnergyBurnImportRequest(
//                        memberId: member.id,
//                        samples: burnSamples
//                    )
//                )
//                logger.info(
//                    "HealthKit 能量消耗上报成功 samples=\(burnSamples.count) imported=\(response.imported.count) duplicates=\(response.duplicates.count) memberID=\(member.id)",
//                    module: logModule
//                )
//            }
//
//            logger.info(
//                "HealthKit 同步完成 memberID=\(member.id) date=\(dateLabel) intakes=\(intakeSamples.count) burns=\(burnSamples.count)",
//                module: logModule
//            )
        } catch {
            logger.warning(
                "HealthKit 同步失败 memberID=\(member.id) date=\(dateLabel) error=\(error.localizedDescription)",
                module: logModule
            )
        }
    }

    /// 用餐记录服务端保存成功后，将营养素写入 Apple 健康，并按 intake 粒度回写 HealthKit sample UUID。
    ///
    /// 已有关联 `appleHealthId` 的 intake 由 HealthKitStore 内部跳过，保证幂等。
    func writeMealRecordIfNeeded(member: Member, record: SparkNutritionAPI.RemoteMealRecord) async {
        guard member.isSelfMember else {
            logger.debug(
                "跳过 HealthKit 写入：非本人成员 memberID=\(member.id) relationship=\(member.relationship)",
                module: logModule
            )
            return
        }

        logger.info(
            "HealthKit 饮食写入开始 recordID=\(record.id) memberID=\(member.id)",
            module: logModule
        )

        do {
            let writeResults = try await healthKitStore.writeMealIntakes(from: record)
            for result in writeResults {
                guard let appleHealthID = result.appleHealthID else { continue }
                try await repository.writeIntakeAppleHealthID(
                    intakeID: result.intakeID,
                    request: SparkNutritionAPI.AppleHealthIDUpdateRequest(appleHealthId: appleHealthID)
                )
                logger.info(
                    "HealthKit intake 回写成功 recordID=\(record.id) intakeID=\(result.intakeID) appleHealthID=\(appleHealthID)",
                    module: logModule
                )
            }
            logger.info(
                "HealthKit 饮食写入完成 recordID=\(record.id) writebacks=\(writeResults.count)",
                module: logModule
            )
        } catch {
            logger.warning(
                "HealthKit 饮食写入失败 recordID=\(record.id) error=\(error.localizedDescription)",
                module: logModule
            )
        }
    }

    /// 手动创建的能量消耗记录写入 HealthKit（仅 source=manual 且尚未关联 UUID 时）
    func writeEnergyBurnIfNeeded(
        member: Member,
        record: SparkNutritionAPI.RemoteEnergyBurnRecord
    ) async {
        guard member.isSelfMember else {
            logger.debug(
                "跳过 HealthKit 能量消耗写入：非本人成员 memberID=\(member.id) relationship=\(member.relationship)",
                module: logModule
            )
            return
        }
        guard record.source == "manual" else { return }
        if let existingID = record.appleHealthId, existingID.isEmpty == false { return }

        logger.info(
            "HealthKit 能量消耗写入开始 recordID=\(record.id) memberID=\(member.id)",
            module: logModule
        )

        do {
            guard let appleHealthID = try await healthKitStore.writeEnergyBurn(
                energyKcal: record.energyKcal,
                burnedAt: record.burnedAt,
                activityType: record.activityType ?? "manual"
            ) else {
                return
            }
            try await repository.writeEnergyBurnAppleHealthID(
                recordID: record.id,
                request: SparkNutritionAPI.AppleHealthIDUpdateRequest(appleHealthId: appleHealthID)
            )
            logger.info(
                "HealthKit 能量消耗回写成功 recordID=\(record.id) appleHealthID=\(appleHealthID)",
                module: logModule
            )
        } catch {
            logger.warning(
                "HealthKit 能量消耗写入失败 recordID=\(record.id) error=\(error.localizedDescription)",
                module: logModule
            )
        }
    }
}

// MARK: - 能量消耗 CRUD

/// 本 App 内手动录入的能量消耗记录（与 HealthKit 导入的 burn 记录区分管理）
struct NutritionEnergyBurnUseCase: Sendable {
    let repository: NutritionRepository
    let logger: Logger

    private let logModule = LogModule.nutrition

    func listRecords(memberID: Int, date: Date) async throws -> [SparkNutritionAPI.RemoteEnergyBurnRecord] {
        logger.info(
            "能量消耗列表 memberID=\(memberID) date=\(MedicalDateCoding.encodeDateOnly(date))",
            module: logModule
        )
        return try await repository.listEnergyBurnRecords(memberID: memberID, date: date)
    }

    func createRecord(_ request: SparkNutritionAPI.CreateEnergyBurnRecordRequest) async throws -> SparkNutritionAPI.RemoteEnergyBurnRecord {
        logger.info("创建能量消耗 memberID=\(request.memberId)", module: logModule)
        return try await repository.createEnergyBurnRecord(request)
    }

    func updateRecord(
        recordID: Int,
        request: SparkNutritionAPI.UpdateEnergyBurnRecordRequest
    ) async throws -> SparkNutritionAPI.RemoteEnergyBurnRecord {
        logger.info("更新能量消耗 recordID=\(recordID)", module: logModule)
        return try await repository.updateEnergyBurnRecord(recordID: recordID, request: request)
    }

    func deleteRecord(recordID: Int) async throws {
        logger.info("删除能量消耗 recordID=\(recordID)", module: logModule)
        try await repository.deleteEnergyBurnRecord(recordID: recordID)
    }
}
