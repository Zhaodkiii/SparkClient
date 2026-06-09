import Foundation

struct NutritionDashboardUseCase: Sendable {
    let repository: NutritionRepository
    let logger: Logger

    private let logModule = LogModule.nutrition

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

    func loadDashboardDetail(memberID: Int, date: Date) async throws -> NutritionSummaryDetailViewData {
        let dashboard = try await loadDashboard(memberID: memberID, date: date)
        return NutritionViewDataMapper.summaryDetail(from: dashboard)
    }
}

struct NutritionMealRecordUseCase: Sendable {
    let repository: NutritionRepository
    let logger: Logger

    private let logModule = LogModule.nutrition

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

    func createMealRecord(_ request: SparkNutritionAPI.CreateMealRecordRequest) async throws -> SparkNutritionAPI.RemoteMealRecord {
        logger.info(
            "创建饮食记录 memberID=\(request.memberId) mealType=\(request.mealType)",
            module: logModule
        )
        return try await repository.createMealRecord(request)
    }

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

struct NutritionSearchUseCase: Sendable {
    let repository: NutritionRepository
    let logger: Logger

    private let logModule = LogModule.nutrition

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

struct NutritionHealthKitSyncUseCase: Sendable {
    let repository: NutritionRepository
    let healthKitStore: NutritionHealthKitStore
    let logger: Logger

    private let logModule = LogModule.nutrition

    /// 本人成员进入首页时读取 Apple 健康外部营养摄入与能量消耗并上报服务端。
    func syncTodayIfNeeded(member: Member, date: Date) async {
        guard member.isPrimary else {
            logger.debug(
                "跳过 HealthKit 同步：非本人成员 memberID=\(member.id)",
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
            let intakeSamples = try await healthKitStore.fetchExternalIntakeSamples(on: date)
            if intakeSamples.isEmpty == false {
                _ = try await repository.importAppleHealthIntakes(
                    SparkNutritionAPI.AppleHealthIntakeImportRequest(
                        memberId: member.id,
                        samples: intakeSamples
                    )
                )
                logger.info(
                    "HealthKit 外部营养摄入上报成功 count=\(intakeSamples.count) memberID=\(member.id)",
                    module: logModule
                )
            }

            let burnSamples = try await healthKitStore.fetchEnergyBurnSamples(on: date)
            if burnSamples.isEmpty == false {
                _ = try await repository.importAppleHealthEnergyBurns(
                    SparkNutritionAPI.AppleHealthEnergyBurnImportRequest(
                        memberId: member.id,
                        samples: burnSamples
                    )
                )
                logger.info(
                    "HealthKit 能量消耗上报成功 count=\(burnSamples.count) memberID=\(member.id)",
                    module: logModule
                )
            }

            logger.info(
                "HealthKit 同步完成 memberID=\(member.id) date=\(dateLabel) intakes=\(intakeSamples.count) burns=\(burnSamples.count)",
                module: logModule
            )
        } catch {
            logger.warning(
                "HealthKit 同步失败 memberID=\(member.id) date=\(dateLabel) error=\(error.localizedDescription)",
                module: logModule
            )
        }
    }

    /// 服务端保存成功后写入 Apple 健康并按 intake 回写 HealthKit sample UUID。
    func writeMealRecordIfNeeded(member: Member, record: SparkNutritionAPI.RemoteMealRecord) async {
        guard member.isPrimary else {
            logger.debug(
                "跳过 HealthKit 写入：非本人成员 memberID=\(member.id)",
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

    func writeEnergyBurnIfNeeded(
        member: Member,
        record: SparkNutritionAPI.RemoteEnergyBurnRecord
    ) async {
        guard member.isPrimary else {
            logger.debug(
                "跳过 HealthKit 能量消耗写入：非本人成员 memberID=\(member.id)",
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
