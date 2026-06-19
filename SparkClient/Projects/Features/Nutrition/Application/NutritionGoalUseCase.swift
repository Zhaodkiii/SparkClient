import Foundation

struct NutritionGoalUseCase: Sendable {
    let repository: NutritionRepository
    let logger: Logger

    private let logModule = LogModule.nutrition

    func loadDefaults(memberID: Int) async throws -> SparkNutritionAPI.RemoteNutritionMacroTarget {
        try await repository.fetchDefaults(memberID: memberID)
    }

    func loadGoalState(memberID: Int) async throws -> SparkNutritionAPI.RemoteNutritionGoalState {
        try await repository.fetchGoalState(memberID: memberID)
    }

    func saveGoal(
        memberID: Int,
        goalType: String,
        heightCm: Double? = nil,
        currentWeightKg: Double? = nil,
        targetWeightKg: Double? = nil,
        biologicalSex: String? = nil,
        ageYears: Int? = nil,
        activityLevel: String? = nil,
        weeklyWeightDeltaKg: Double? = nil,
        bmrKcal: Double? = nil,
        tdeeKcal: Double? = nil,
        energyDeltaKcal: Double? = nil,
        calculationFormula: String? = nil,
        calculationVersion: String? = nil,
        calculationInputs: SparkNutritionAPI.RemoteNutritionCalculationInputs? = nil,
        isEnergyTargetCustom: Bool = false,
        weekendEnergyTargetKcal: Double? = nil,
        isWeekendEnergyEnabled: Bool = false,
        stepTarget: Int? = nil,
        dailyEnergyTargetKcal: Double?,
        carbohydrateTargetG: Double?,
        proteinTargetG: Double?,
        fatTargetG: Double?,
        mealDistribution: [String: Double],
        effectiveFrom: Date? = nil,
        isActive: Bool = true
    ) async throws -> SparkNutritionAPI.RemoteNutritionGoal {
        let startedAt = Date()
        let safeWeeklyDelta = normalizedWeeklyDelta(goalType: goalType, value: weeklyWeightDeltaKg)
        let request = SparkNutritionAPI.RemoteNutritionGoalUpsertRequest(
            memberId: memberID,
            goalType: goalType,
            heightCm: rounded(heightCm),
            currentWeightKg: rounded(currentWeightKg),
            targetWeightKg: rounded(targetWeightKg),
            biologicalSex: biologicalSex,
            ageYears: ageYears,
            activityLevel: activityLevel,
            weeklyWeightDeltaKg: rounded(safeWeeklyDelta),
            bmrKcal: rounded(bmrKcal),
            tdeeKcal: rounded(tdeeKcal),
            energyDeltaKcal: rounded(energyDeltaKcal),
            calculationFormula: calculationFormula,
            calculationVersion: calculationVersion,
            calculationInputs: calculationInputs,
            isEnergyTargetCustom: isEnergyTargetCustom,
            weekendEnergyTargetKcal: rounded(weekendEnergyTargetKcal),
            isWeekendEnergyEnabled: isWeekendEnergyEnabled,
            stepTarget: stepTarget,
            dailyEnergyTargetKcal: rounded(normalizedEnergyTarget(dailyEnergyTargetKcal)),
            carbohydrateTargetG: rounded(normalizedMacroTarget(carbohydrateTargetG)),
            proteinTargetG: rounded(normalizedMacroTarget(proteinTargetG)),
            fatTargetG: rounded(normalizedMacroTarget(fatTargetG)),
            mealDistribution: normalizedMealDistribution(mealDistribution),
            effectiveFrom: effectiveFrom.map { MedicalDateCoding.encodeDateOnly($0) },
            isActive: isActive
        )
        let saved = try await repository.saveGoal(request)
        let cost = String(format: "%.3f", Date().timeIntervalSince(startedAt))
        logger.info(
            "营养目标保存成功 memberID=\(memberID) goalID=\(saved.id) goalType=\(goalType) cost=\(cost)s",
            module: logModule
        )
        return saved
    }

    func calculateBodyMetrics(
        memberID: Int,
        goalType: String,
        activityLevel: String,
        currentWeightKg: Double?,
        heightCm: Double?,
        biologicalSex: String?,
        ageYears: Int?,
        weeklyWeightDeltaKg: Double?,
        targetWeightKg: Double?
    ) async throws -> SparkNutritionAPI.RemoteNutritionBodyMetricsCalculationResponse {
        logger.info(
            "饮食目标计算：开始 memberID=\(memberID) goalType=\(goalType) activityLevel=\(activityLevel)",
            module: logModule
        )
        let safeWeeklyDelta = normalizedWeeklyDelta(goalType: goalType, value: weeklyWeightDeltaKg)
        let request = SparkNutritionAPI.RemoteNutritionGoalCalculationRequest(
            memberId: memberID,
            goalType: goalType,
            activityLevel: activityLevel,
            currentWeightKg: currentWeightKg,
            heightCm: heightCm,
            biologicalSex: biologicalSex,
            ageYears: ageYears,
            weeklyWeightDeltaKg: safeWeeklyDelta,
            targetWeightKg: targetWeightKg
        )
        let result = try await repository.calculateBodyMetrics(request)
        if result.missingFields.isEmpty {
            logger.info(
                "饮食目标计算：成功 memberID=\(memberID) suggestedEnergy=\(result.calorieIntake?.suggestedEnergyKcal ?? 0) bmr=\(result.calorieIntake?.bmrKcal ?? 0) tdee=\(result.calorieIntake?.tdeeKcal ?? 0) riskFlags=\(result.calculationInputs?.riskFlags ?? [])",
                module: logModule
            )
        } else {
            logger.info(
                "饮食目标计算：缺少资料 memberID=\(memberID) missingFields=\(result.missingFields)",
                module: logModule
            )
        }
        return result
    }

    private func rounded(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return (value * 100).rounded() / 100
    }

    private func normalizedWeeklyDelta(goalType: String, value: Double?) -> Double? {
        guard let value else { return nil }
        let clamped = min(max(value, -1), 1)
        switch goalType {
        case "maintain", "control_sugar", "control_salt", "control_fat":
            return 0
        case "lose_weight":
            return min(clamped, 0)
        case "gain_weight", "gain_muscle", "build_muscle":
            return max(clamped, 0)
        default:
            return clamped
        }
    }

    private func normalizedEnergyTarget(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return min(max(value, 0), 10_000)
    }

    private func normalizedMacroTarget(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return min(max(value, 0), 2_000)
    }

    private func normalizedMealDistribution(_ distribution: [String: Double]) -> [String: Double] {
        distribution.mapValues { value in
            let ratio = value > 1 ? value / 100 : value
            return (ratio * 100).rounded() / 100
        }
    }
}
