import Foundation

enum NutritionViewDataMapper {
    static func dashboard(from remote: SparkNutritionAPI.RemoteNutritionDashboard) -> NutritionDashboardViewData {
        let consumedOverview = mergeOverview(remote.serverIntake, remote.appleHealthExternalIntake)
        let consumedEnergy = consumedOverview.energyKcal
        let burnedEnergy = remote.appleHealthBurned.energyKcal
        let targetEnergy = remote.goal.energyKcal
        let remaining = targetEnergy - consumedEnergy + burnedEnergy
        let intakeProgress = targetEnergy > 0 ? Swift.min(consumedEnergy / targetEnergy, 1.5) : 0

        let meals = remote.meals.compactMap { meal -> NutritionMealSectionViewData? in
            guard let mealType = NutritionMealType(rawValue: meal.mealType) else { return nil }
            return NutritionMealSectionViewData(
                mealType: mealType,
                consumedEnergyKcal: meal.energyKcal,
                targetEnergyKcal: meal.targetEnergyKcal,
                carbohydrate: NutritionMacroProgress(
                    current: meal.carbohydrateG,
                    target: meal.targetCarbohydrateG,
                    unit: "g"
                ),
                protein: NutritionMacroProgress(
                    current: meal.proteinG,
                    target: meal.targetProteinG,
                    unit: "g"
                ),
                fat: NutritionMacroProgress(
                    current: meal.fatG,
                    target: meal.targetFatG,
                    unit: "g"
                ),
                foodSummary: meal.foodSummary,
                recordCount: meal.recordCount
            )
        }

        return NutritionDashboardViewData(
            memberID: remote.memberId,
            date: remote.date,
            consumedEnergyKcal: consumedEnergy,
            remainingEnergyKcal: remaining,
            burnedEnergyKcal: burnedEnergy,
            targetEnergyKcal: targetEnergy,
            intakeProgress: intakeProgress,
            overview: overviewGrid(from: consumedOverview),
            carbohydrate: macroProgress(current: consumedOverview.carbohydrateG, target: remote.goal.carbohydrateG),
            protein: macroProgress(current: consumedOverview.proteinG, target: remote.goal.proteinG),
            fat: macroProgress(current: consumedOverview.fatG, target: remote.goal.fatG),
            macroRatioChart: macroRatioChart(
                current: consumedOverview,
                target: remote.goal
            ),
            meals: orderedMeals(meals)
        )
    }

    static func summaryDetail(from dashboard: NutritionDashboardViewData) -> NutritionSummaryDetailViewData {
        NutritionSummaryDetailViewData(
            date: dashboard.date,
            macroProgress: NutritionMacroProgressCardData(
                energy: NutritionMacroProgress(
                    current: dashboard.consumedEnergyKcal,
                    target: dashboard.targetEnergyKcal,
                    unit: "kcal"
                ),
                carbohydrate: dashboard.carbohydrate,
                protein: dashboard.protein,
                fat: dashboard.fat
            ),
            macroRatioChart: dashboard.macroRatioChart,
            detailInfo: detailInfoFromOverviewGrid(from: dashboard.overview),
            mealSections: dashboard.meals
        )
    }

    static func summaryDetail(
        dashboard: NutritionDashboardViewData,
        selectedMeal: NutritionMealType
    ) -> NutritionMealSectionViewData? {
        dashboard.meals.first(where: { $0.mealType == selectedMeal })
    }

    static func mealGroups(from response: SparkNutritionAPI.RemoteMealRecordListResponse) -> [NutritionMealGroupViewData] {
        var grouped: [NutritionMealType: [NutritionMealFoodRowViewData]] = [:]
        var totals: [NutritionMealType: Double] = [:]

        for record in response.records {
            guard let mealType = NutritionMealType(rawValue: record.mealType) else { continue }
            let recordEnergy = energyKcal(from: record.intakes)
            totals[mealType, default: 0] += recordEnergy
            for mealFood in record.mealFoods {
                let row = foodRow(from: mealFood, record: record)
                grouped[mealType, default: []].append(row)
            }
        }

        return NutritionMealType.allCases.compactMap { mealType in
            let foods = grouped[mealType] ?? []
            guard foods.isEmpty == false else { return nil }
            return NutritionMealGroupViewData(
                mealType: mealType,
                totalEnergyKcal: totals[mealType] ?? 0,
                foods: foods
            )
        }
    }

    static func mealDetail(
        mealType: NutritionMealType,
        date: Date,
        response: SparkNutritionAPI.RemoteMealRecordListResponse
    ) -> NutritionMealDetailViewData {
        let overview = overviewGrid(from: response.overview)
        let macroProgress = NutritionMacroProgressCardData(
            energy: NutritionMacroProgress(
                current: response.macroProgress.energyKcal,
                target: response.macroProgress.targetEnergyKcal,
                unit: "kcal"
            ),
            carbohydrate: NutritionMacroProgress(
                current: response.macroProgress.carbohydrateG,
                target: response.macroProgress.targetCarbohydrateG,
                unit: "g"
            ),
            protein: NutritionMacroProgress(
                current: response.macroProgress.proteinG,
                target: response.macroProgress.targetProteinG,
                unit: "g"
            ),
            fat: NutritionMacroProgress(
                current: response.macroProgress.fatG,
                target: response.macroProgress.targetFatG,
                unit: "g"
            )
        )

        let foods = response.records.flatMap { record in
            record.mealFoods.map { foodRow(from: $0, record: record) }
        }

        let imageURL = response.records
            .flatMap { $0.attachments ?? [] }
            .compactMap { (attachment: SparkNutritionAPI.RemoteNutritionAttachment) in attachment.fileUrl }
            .compactMap(URL.init(string:))
            .first

        return NutritionMealDetailViewData(
            mealType: mealType,
            date: date,
            imageURL: imageURL,
            overview: overview,
            macroProgress: macroProgress,
            detailInfo: detailInfo(from: response.overview),
            foods: foods,
            records: response.records,
            hasAppleHealthLinkedRecords: response.records.contains(where: { $0.hasAppleHealthId == true })
        )
    }

    static func historyDays(
        from records: [SparkNutritionAPI.RemoteMealRecord],
        dateFrom: Date,
        dateTo: Date
    ) -> [NutritionHistoryDayViewData] {
        let calendar = Calendar.current
        var grouped: [Date: [SparkNutritionAPI.RemoteMealRecord]] = [:]
        for record in records {
            let day = calendar.startOfDay(for: record.localDay ?? record.consumedAt)
            grouped[day, default: []].append(record)
        }

        var days: [NutritionHistoryDayViewData] = []
        var cursor = calendar.startOfDay(for: dateTo)
        let start = calendar.startOfDay(for: dateFrom)
        while cursor >= start {
            let dayRecords = grouped[cursor] ?? []
            if dayRecords.isEmpty == false {
                days.append(
                    NutritionHistoryDayViewData(
                        date: cursor,
                        totalEnergyKcal: dayRecords.reduce(0) { $0 + energyKcal(from: $1.intakes) },
                        records: dayRecords.map(historyRecord(from:))
                    )
                )
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return days
    }

    static func energyBurnViewData(from records: [SparkNutritionAPI.RemoteEnergyBurnRecord]) -> NutritionEnergyBurnViewData {
        var appleHealthTotal = 0.0
        var manualTotal = 0.0
        let rows = records.map { record -> NutritionEnergyBurnRowViewData in
            let isManual = record.source == "manual"
            if isManual {
                manualTotal += record.energyKcal
            } else {
                appleHealthTotal += record.energyKcal
            }
            return NutritionEnergyBurnRowViewData(
                id: record.id,
                burnedAt: record.burnedAt,
                energyKcal: record.energyKcal,
                activityType: record.activityType ?? "",
                source: record.source ?? "",
                note: record.note ?? "",
                isManual: isManual,
                hasAppleHealthID: record.appleHealthId?.isEmpty == false
            )
        }
        return NutritionEnergyBurnViewData(
            totalEnergyKcal: appleHealthTotal + manualTotal,
            appleHealthEnergyKcal: appleHealthTotal,
            manualEnergyKcal: manualTotal,
            records: rows
        )
    }

    static func editableFoods(from records: [SparkNutritionAPI.RemoteMealRecord]) -> [NutritionEditableMealFood] {
        records.flatMap { record in
            record.mealFoods.map { mealFood in
                let food = mealFood.foodItem
                return NutritionEditableMealFood(
                    id: mealFood.id,
                    recordID: record.id,
                    foodItemID: food.id,
                    title: food.localizedName?.isEmpty == false ? food.localizedName! : food.name,
                    servingDescription: mealFood.servingDescription ?? food.servingDescription ?? "",
                    servingRatio: NutritionServingRatio.closest(to: mealFood.servingRatio),
                    servingUnit: mealFood.servingUnit ?? food.servingUnit ?? ""
                )
            }
        }
    }

    static func macroProgressCard(from section: NutritionMealSectionViewData) -> NutritionMacroProgressCardData {
        NutritionMacroProgressCardData(
            energy: NutritionMacroProgress(
                current: section.consumedEnergyKcal,
                target: section.targetEnergyKcal,
                unit: "kcal"
            ),
            carbohydrate: section.carbohydrate,
            protein: section.protein,
            fat: section.fat
        )
    }

    static func macroRatioChart(for section: NutritionMealSectionViewData) -> NutritionMacroRatioChartData {
        macroRatioChart(
            current: SparkNutritionAPI.RemoteNutritionOverview(
                energyKcal: section.consumedEnergyKcal,
                proteinG: section.protein.current,
                carbohydrateG: section.carbohydrate.current,
                fatG: section.fat.current
            ),
            target: SparkNutritionAPI.RemoteNutritionMacroTarget(
                energyKcal: section.targetEnergyKcal,
                proteinG: section.protein.target,
                carbohydrateG: section.carbohydrate.target,
                fatG: section.fat.target
            )
        )
    }

    // MARK: - Private helpers

    private static func mergeOverview(
        _ lhs: SparkNutritionAPI.RemoteNutritionOverview,
        _ rhs: SparkNutritionAPI.RemoteNutritionOverview
    ) -> SparkNutritionAPI.RemoteNutritionOverview {
        SparkNutritionAPI.RemoteNutritionOverview(
            energyKcal: lhs.energyKcal + rhs.energyKcal,
            proteinG: lhs.proteinG + rhs.proteinG,
            carbohydrateG: lhs.carbohydrateG + rhs.carbohydrateG,
            fatG: lhs.fatG + rhs.fatG
        )
    }

    private static func overviewGrid(from overview: SparkNutritionAPI.RemoteNutritionOverview) -> NutritionOverviewGridData {
        NutritionOverviewGridData(
            energyKcal: overview.energyKcal,
            proteinGrams: overview.proteinG,
            carbohydrateGrams: overview.carbohydrateG,
            fatGrams: overview.fatG
        )
    }

    private static func macroProgress(current: Double, target: Double) -> NutritionMacroProgress {
        NutritionMacroProgress(current: current, target: target, unit: "g")
    }

    private static func macroRatioChart(
        current: SparkNutritionAPI.RemoteNutritionOverview,
        target: SparkNutritionAPI.RemoteNutritionMacroTarget
    ) -> NutritionMacroRatioChartData {
        NutritionMacroRatioChartData(
            carbohydrate: ratioPair(current: current.carbohydrateG, target: target.carbohydrateG),
            protein: ratioPair(current: current.proteinG, target: target.proteinG),
            fat: ratioPair(current: current.fatG, target: target.fatG)
        )
    }

    private static func ratioPair(current: Double, target: Double) -> NutritionMacroRatioPair {
        let currentPercent = target > 0 ? (current / target) * 100 : 0
        return NutritionMacroRatioPair(currentPercent: currentPercent, targetPercent: 100)
    }

    static func detailInfo(from overview: NutritionOverviewGridData) -> NutritionDetailInfoData {
        detailInfo(
            from: SparkNutritionAPI.RemoteNutritionOverview(
                energyKcal: overview.energyKcal,
                proteinG: overview.proteinGrams,
                carbohydrateG: overview.carbohydrateGrams,
                fatG: overview.fatGrams
            )
        )
    }

    private static func detailInfoFromOverviewGrid(from overview: NutritionOverviewGridData) -> NutritionDetailInfoData {
        detailInfo(from: overview)
    }

    private static func detailInfo(from overview: SparkNutritionAPI.RemoteNutritionOverview) -> NutritionDetailInfoData {
        NutritionDetailInfoData(
            groups: [
                NutritionDetailInfoGroup(
                    id: "macros",
                    title: "nutrition.detail.group.macros",
                    rows: [
                        row("energy", titleKey: "nutrition.macro.energy", value: overview.energyKcal, unit: "kcal"),
                        row("carbohydrate", titleKey: "nutrition.macro.carbohydrate", value: overview.carbohydrateG, unit: "g"),
                        row("protein", titleKey: "nutrition.macro.protein", value: overview.proteinG, unit: "g"),
                        row("fat", titleKey: "nutrition.macro.fat", value: overview.fatG, unit: "g")
                    ]
                )
            ]
        )
    }

    private static func row(_ id: String, titleKey: String, value: Double, unit: String) -> NutritionDetailInfoRow {
        NutritionDetailInfoRow(
            id: id,
            title: titleKey,
            valueText: NutritionFormatting.valueWithUnit(value, unit: unit)
        )
    }

    static func mealFoodEditItems(from records: [SparkNutritionAPI.RemoteMealRecord]) -> [NutritionMealFoodEditItemViewData] {
        records.flatMap { record in
            record.mealFoods.map { mealFood in
                let food = mealFood.foodItem
                let title = food.localizedName?.isEmpty == false ? food.localizedName! : food.name
                let servingDescription = mealFood.servingDescription ?? food.servingDescription ?? ""
                return NutritionMealFoodEditItemViewData(
                    mealFoodID: mealFood.id,
                    recordID: record.id,
                    foodItemID: food.id,
                    title: title,
                    servingText: servingDescription,
                    energyKcal: energyKcal(for: mealFood, in: record.intakes),
                    servingRatio: NutritionServingRatio.closest(to: mealFood.servingRatio),
                    servingUnit: mealFood.servingUnit ?? food.servingUnit ?? "",
                    servingDescription: servingDescription,
                    hasAppleHealthLinkedRecord: record.hasAppleHealthId == true
                )
            }
        }
    }

    static func searchResult(from row: NutritionMealFoodRowViewData) -> NutritionFoodSearchResultViewData {
        NutritionFoodSearchResultViewData(
            id: "meal_food_\(row.mealFoodID)",
            mode: .text,
            resultType: row.itemType == .recipe ? "recipe" : "food_item",
            targetID: row.foodItemID,
            title: row.title,
            subtitle: row.servingText,
            badgeText: row.itemType.rawValue,
            isFavorite: false,
            isVerified: row.isVerified,
            isCreatedByMe: false,
            overview: row.overview,
            calorieText: NutritionFormatting.energyKcal(row.overview.energyKcal)
        )
    }

    static func recipeDraftFood(from item: NutritionMealFoodEditItemViewData) -> NutritionRecipeDraftFood {
        NutritionRecipeDraftFood(
            foodItemID: item.foodItemID,
            title: item.title,
            servingText: item.servingText,
            servingRatio: item.servingRatio,
            servingUnit: item.servingUnit,
            servingDescription: item.servingDescription,
            energyKcal: item.energyKcal
        )
    }

    static func recipeDraftFood(from result: NutritionFoodSearchResultViewData) -> NutritionRecipeDraftFood {
        NutritionRecipeDraftFood(
            foodItemID: result.targetID,
            title: result.title,
            servingText: result.subtitle,
            servingRatio: .full,
            servingUnit: "",
            servingDescription: result.subtitle,
            energyKcal: result.overview.energyKcal
        )
    }

    private static func foodRow(
        from mealFood: SparkNutritionAPI.RemoteMealFood,
        record: SparkNutritionAPI.RemoteMealRecord
    ) -> NutritionMealFoodRowViewData {
        let food = mealFood.foodItem
        let title = food.localizedName?.isEmpty == false ? food.localizedName! : food.name
        let serving = mealFood.servingDescription ?? food.servingDescription ?? ""
        let energy = energyKcal(for: mealFood, in: record.intakes)
        let overview = overview(for: mealFood, in: record.intakes, fallbackEnergy: energy)
        return NutritionMealFoodRowViewData(
            id: "\(record.id)-\(mealFood.id)",
            mealFoodID: mealFood.id,
            recordID: record.id,
            foodItemID: food.id,
            title: title,
            servingText: serving,
            energyKcal: energy,
            servingRatio: mealFood.servingRatio,
            servingUnit: mealFood.servingUnit ?? food.servingUnit ?? "",
            overview: overview,
            isVerified: food.isVerified ?? false,
            hasAppleHealthLinkedRecord: record.hasAppleHealthId == true,
            itemType: .food
        )
    }

    private static func overview(
        for mealFood: SparkNutritionAPI.RemoteMealFood,
        in intakes: [SparkNutritionAPI.RemoteNutritionIntake],
        fallbackEnergy: Double
    ) -> NutritionOverviewGridData {
        let foodIntakes = intakes.filter {
            $0.businessType == "meal_food" && $0.businessId == mealFood.id
        }
        if foodIntakes.isEmpty {
            return NutritionOverviewGridData(
                energyKcal: fallbackEnergy,
                proteinGrams: 0,
                carbohydrateGrams: 0,
                fatGrams: 0
            )
        }
        func value(for nutrient: String) -> Double {
            foodIntakes.first(where: { $0.nutrientType == nutrient })?.value ?? 0
        }
        let energy = value(for: "energy_kcal")
        return NutritionOverviewGridData(
            energyKcal: energy > 0 ? energy : fallbackEnergy,
            proteinGrams: value(for: "protein") + value(for: "protein_g"),
            carbohydrateGrams: value(for: "carbohydrate") + value(for: "carbohydrate_g"),
            fatGrams: value(for: "fat") + value(for: "fat_g")
        )
    }

    private static func energyKcal(from intakes: [SparkNutritionAPI.RemoteNutritionIntake]) -> Double {
        intakes.first(where: { $0.nutrientType == "energy_kcal" || $0.nutrientType == "energy" })?.value ?? 0
    }

    private static func historyRecord(from record: SparkNutritionAPI.RemoteMealRecord) -> NutritionHistoryRecordViewData {
        NutritionHistoryRecordViewData(
            id: record.id,
            mealType: NutritionMealType(rawValue: record.mealType) ?? .snack,
            title: record.title ?? "",
            consumedAt: record.consumedAt,
            energyKcal: energyKcal(from: record.intakes),
            foodCount: record.mealFoods.count
        )
    }

    private static func energyKcal(
        for mealFood: SparkNutritionAPI.RemoteMealFood,
        in intakes: [SparkNutritionAPI.RemoteNutritionIntake]
    ) -> Double {
        let foodIntakes = intakes.filter {
            $0.businessType == "meal_food" && $0.businessId == mealFood.id
        }
        if let energy = foodIntakes.first(where: {
            $0.nutrientType == "energy_kcal" || $0.nutrientType == "energy"
        })?.value {
            return energy
        }
        return overview(for: mealFood, in: intakes, fallbackEnergy: 0).energyKcal
    }

    private static func orderedMeals(_ meals: [NutritionMealSectionViewData]) -> [NutritionMealSectionViewData] {
        NutritionMealType.allCases.map { mealType in
            meals.first(where: { $0.mealType == mealType })
                ?? NutritionMealSectionViewData(
                    mealType: mealType,
                    consumedEnergyKcal: 0,
                    targetEnergyKcal: 0,
                    carbohydrate: NutritionMacroProgress(current: 0, target: 0, unit: "g"),
                    protein: NutritionMacroProgress(current: 0, target: 0, unit: "g"),
                    fat: NutritionMacroProgress(current: 0, target: 0, unit: "g"),
                    foodSummary: nil,
                    recordCount: 0
                )
        }
    }
}

enum NutritionFormatting {
    static func energyKcal(_ value: Double) -> String {
        valueWithUnit(value, unit: L10n.text("nutrition.unit.kcal"))
    }

    static func grams(_ value: Double) -> String {
        valueWithUnit(value, unit: L10n.text("nutrition.unit.g"))
    }

    static func milligrams(_ value: Double) -> String {
        valueWithUnit(value, unit: L10n.text("nutrition.unit.mg"))
    }

    static func micrograms(_ value: Double) -> String {
        valueWithUnit(value, unit: L10n.text("nutrition.unit.mcg"))
    }

    static func milliliters(_ value: Double) -> String {
        valueWithUnit(value, unit: L10n.text("nutrition.unit.ml"))
    }

    static func valueWithUnit(_ value: Double, unit: String) -> String {
        let formatted = NumberFormatter.nutritionDecimal.string(from: NSNumber(value: value)) ?? "0"
        return "\(formatted) \(unit)"
    }

    static func compactEnergy(_ value: Double) -> String {
        let formatted = NumberFormatter.nutritionInteger.string(from: NSNumber(value: value)) ?? "0"
        return formatted
    }

    static func quantity(_ value: Double) -> String {
        if value.rounded() == value {
            return NumberFormatter.nutritionInteger.string(from: NSNumber(value: value)) ?? "1"
        }
        return NumberFormatter.nutritionDecimal.string(from: NSNumber(value: value)) ?? "1"
    }

    static func mealEnergyProgress(consumed: Double, target: Double) -> String {
        "\(compactEnergy(consumed)) / \(compactEnergy(target)) \(L10n.text("nutrition.unit.kcal"))"
    }
}

private extension NumberFormatter {
    static let nutritionDecimal: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    static let nutritionInteger: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}
