import Combine
import Foundation

@MainActor
final class MemberNutritionSetupViewModel: ObservableObject {
    @Published var heightCm: Double = 160
    @Published var weightKg: Double = 60
    @Published var activityLevel: ActivityLevel = .medium
    @Published var goalMode: GoalMode = .maintain
    @Published var weeklyTargetKg: Double = 0
    @Published var targetCalories: Double = 2000
    @Published var carbohydratePercent: Double = 50
    @Published var proteinPercent: Double = 20
    @Published var fatPercent: Double = 30
    @Published var mealDistribution: [String: Double] = ["breakfast": 30, "lunch": 35, "dinner": 25, "snack": 10]
    @Published var note: String = ""
    @Published var calculationResult: SparkNutritionAPI.RemoteNutritionBodyMetricsCalculationResponse?
    @Published var isLoading = false
    @Published var hasLoaded = false
    @Published var isSaving = false
    @Published var errorMessage: String?

    let member: Member?
    private let goalUseCase: NutritionGoalUseCase
    private let setupUseCase: MemberModuleSetupUseCase

    init(member: Member?, goalUseCase: NutritionGoalUseCase, setupUseCase: MemberModuleSetupUseCase) {
        self.member = member
        self.goalUseCase = goalUseCase
        self.setupUseCase = setupUseCase
        applyMemberDefaults()
    }

    func loadIfNeeded() async {
        guard let member else { return }
        guard isLoading == false, hasLoaded == false else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let state = try await goalUseCase.loadGoalState(memberID: member.id)
            if let goal = state.goal {
                applyGoal(goal)
            } else {
                applyDefaults(state.defaults)
            }
            await refreshCalculationIfPossible()
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(markModuleCompleted: Bool = true) async -> String? {
        guard let member else { return nil }
        guard isSaving == false else { return nil }
        isSaving = true
        defer { isSaving = false }
        do {
            normalizeEditableTargets()
            let calculation = try? await calculateAndApplySuggestion()
            let savedGoal = try await goalUseCase.saveGoal(
                memberID: member.id,
                goalType: goalMode.rawValue,
                heightCm: heightCm,
                currentWeightKg: weightKg,
                targetWeightKg: nil,
                biologicalSex: normalizedSex,
                ageYears: ageYears,
                activityLevel: activityLevel.rawValue,
                weeklyWeightDeltaKg: weeklyTargetKg,
                bmrKcal: calculation?.calorieIntake?.bmrKcal,
                tdeeKcal: calculation?.calorieIntake?.tdeeKcal,
                energyDeltaKcal: calculation?.calorieIntake?.energyDeltaKcal,
                calculationFormula: calculation?.calculationFormula ?? calculation?.calorieIntake?.calculationFormula,
                calculationVersion: calculation?.calculationVersion ?? calculation?.calorieIntake?.calculationVersion,
                calculationInputs: calculation?.calculationInputs ?? calculation?.calorieIntake?.calculationInputs,
                dailyEnergyTargetKcal: targetCalories,
                carbohydrateTargetG: grams(fromPercent: carbohydratePercent),
                proteinTargetG: grams(fromPercent: proteinPercent),
                fatTargetG: fatGrams(fromPercent: fatPercent),
                mealDistribution: mealDistribution,
                effectiveFrom: Date(),
                isActive: true
            )
            if markModuleCompleted {
                _ = try await setupUseCase.saveModuleSetting(
                    memberID: member.id,
                    moduleCode: MemberSetupModule.nutrition.rawValue,
                    isEnabled: true,
                    isCompleted: true,
                    displayOrder: MemberSetupModule.nutrition.displayOrder,
                    summaryText: summaryText(for: savedGoal),
                    detailData: detailData,
                    completedAt: Date()
                )
            }
            return summaryText(for: savedGoal)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func applyMemberDefaults() {
        if let member, let birthDate = member.birthDate {
            let age = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 30
            targetCalories = defaultCalories(age: age, weightKg: weightKg, heightCm: heightCm, gender: member.gender)
        }
    }

    private func applyGoal(_ goal: SparkNutritionAPI.RemoteNutritionGoal) {
        goalMode = GoalMode(rawValue: goal.goalType) ?? .maintain
        if let height = goal.heightCm {
            heightCm = height
        }
        if let weight = goal.currentWeightKg {
            weightKg = weight
        }
        if let rawActivityLevel = goal.activityLevel, let savedActivityLevel = ActivityLevel(rawValue: rawActivityLevel) {
            activityLevel = savedActivityLevel
        }
        if let weeklyDelta = goal.weeklyWeightDeltaKg {
            weeklyTargetKg = normalizedWeeklyTarget(weeklyDelta)
        }
        if let kcal = goal.dailyEnergyTargetKcal {
            targetCalories = normalizedEnergyTarget(kcal)
        }
        if let carbohydrateTargetG = goal.carbohydrateTargetG, targetCalories > 0 {
            carbohydratePercent = percent(fromGrams: normalizedMacroTarget(carbohydrateTargetG))
        }
        if let proteinTargetG = goal.proteinTargetG, targetCalories > 0 {
            proteinPercent = percent(fromGrams: normalizedMacroTarget(proteinTargetG))
        }
        if let fatTargetG = goal.fatTargetG, targetCalories > 0 {
            fatPercent = percent(fromGrams: normalizedMacroTarget(fatTargetG))
        }
        mealDistribution = goal.mealDistribution
    }

    private func applyDefaults(_ defaults: SparkNutritionAPI.RemoteNutritionMacroTarget) {
        targetCalories = normalizedEnergyTarget(defaults.energyKcal)
        carbohydratePercent = ratio(fromGrams: normalizedMacroTarget(defaults.carbohydrateG))
        proteinPercent = ratio(fromGrams: normalizedMacroTarget(defaults.proteinG))
        fatPercent = ratio(fromGrams: normalizedMacroTarget(defaults.fatG))
    }

    private func summaryText(for goal: SparkNutritionAPI.RemoteNutritionGoal) -> String {
        let kcal = Int(goal.dailyEnergyTargetKcal ?? targetCalories)
        return "\(goalMode.title) · \(kcal)千卡"
    }

    var suggestedCalories: Double? {
        calculationResult?.calorieIntake?.suggestedEnergyKcal
    }

    var bmrKcal: Double? {
        calculationResult?.calorieIntake?.bmrKcal
    }

    var tdeeKcal: Double? {
        calculationResult?.calorieIntake?.tdeeKcal
    }

    var estimatedActivityKcal: Double? {
        calculationResult?.caloriesBurned?.estimatedDailyActivityKcal
    }

    var energyDeltaKcalValue: Double? {
        calculationResult?.calorieIntake?.energyDeltaKcal
    }

    var calculationWarnings: [String] {
        calculationResult?.warnings ?? []
    }

    private var detailData: [String: String] {
        [
            "height_cm": String(format: "%.1f", heightCm),
            "weight_kg": String(format: "%.1f", weightKg),
            "activity_level": activityLevel.rawValue,
            "goal_mode": goalMode.rawValue,
            "weekly_target_kg": String(format: "%.2f", weeklyTargetKg),
            "target_calories": String(format: "%.1f", targetCalories),
            "carbohydrate_percent": String(format: "%.1f", carbohydratePercent),
            "protein_percent": String(format: "%.1f", proteinPercent),
            "fat_percent": String(format: "%.1f", fatPercent)
        ]
    }

    private func grams(fromPercent percent: Double) -> Double {
        (targetCalories * max(percent, 0) / 100.0) / 4.0
    }

    private func fatGrams(fromPercent percent: Double) -> Double {
        (targetCalories * max(percent, 0) / 100.0) / 9.0
    }

    private func percent(fromGrams grams: Double) -> Double {
        guard targetCalories > 0 else { return 0 }
        return grams * 4.0 / targetCalories * 100.0
    }

    private func ratio(fromGrams grams: Double) -> Double {
        guard targetCalories > 0 else { return 0 }
        return max(0, grams * 4.0 / targetCalories * 100.0)
    }

    private func defaultCalories(age: Int, weightKg: Double, heightCm: Double, gender: String) -> Double {
        let bmr: Double
        switch gender.lowercased() {
        case "female":
            bmr = 10 * weightKg + 6.25 * heightCm - 5 * Double(age) - 161
        default:
            bmr = 10 * weightKg + 6.25 * heightCm - 5 * Double(age) + 5
        }
        return bmr * activityLevel.multiplier + goalMode.energyAdjustment
    }

    private var ageYears: Int? {
        guard let birthDate = member?.birthDate else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
    }

    private var normalizedSex: String {
        let gender = member?.gender.lowercased() ?? ""
        return gender == "male" || gender == "female" ? gender : "unknown"
    }

    func refreshCalculationIfPossible() async {
        guard member != nil else { return }
        guard heightCm > 0, weightKg > 0 else { return }
        do {
            _ = try await calculateAndApplySuggestion()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func calculateAndApplySuggestion() async throws -> SparkNutritionAPI.RemoteNutritionBodyMetricsCalculationResponse {
        guard let member else {
            throw CancellationError()
        }
        normalizeEditableTargets()
        let result = try await goalUseCase.calculateBodyMetrics(
            memberID: member.id,
            goalType: goalMode.rawValue,
            activityLevel: activityLevel.rawValue,
            currentWeightKg: weightKg,
            heightCm: heightCm,
            biologicalSex: normalizedSex,
            ageYears: ageYears,
            weeklyWeightDeltaKg: weeklyTargetKg,
            targetWeightKg: nil
        )
        calculationResult = result
        if result.missingFields.isEmpty, let suggested = result.calorieIntake?.suggestedEnergyKcal {
            targetCalories = normalizedEnergyTarget(suggested)
        }
        return result
    }

    private func normalizeEditableTargets() {
        weeklyTargetKg = normalizedWeeklyTarget(weeklyTargetKg)
        targetCalories = normalizedEnergyTarget(targetCalories)
        carbohydratePercent = min(max(carbohydratePercent, 0), 100)
        proteinPercent = min(max(proteinPercent, 0), 100)
        fatPercent = min(max(fatPercent, 0), 100)
        for key in mealDistribution.keys {
            mealDistribution[key] = min(max(mealDistribution[key] ?? 0, 0), 100)
        }
    }

    private func normalizedWeeklyTarget(_ value: Double) -> Double {
        let clamped = min(max(value, -1), 1)
        switch goalMode {
        case .maintain, .controlSugar, .controlSalt, .controlFat:
            return 0
        case .loseWeight:
            return min(clamped, 0)
        case .gainWeight, .buildMuscle:
            return max(clamped, 0)
        case .custom:
            return clamped
        }
    }

    private func normalizedEnergyTarget(_ value: Double) -> Double {
        min(max(value, 0), 10_000)
    }

    private func normalizedMacroTarget(_ value: Double) -> Double {
        min(max(value, 0), 2_000)
    }
}

extension MemberNutritionSetupViewModel {
    enum ActivityLevel: String, CaseIterable, Identifiable, Sendable {
        case low
        case medium
        case high

        var id: String { rawValue }

        var multiplier: Double {
            switch self {
            case .low: return 1.2
            case .medium: return 1.45
            case .high: return 1.7
            }
        }
    }

    enum GoalMode: String, CaseIterable, Identifiable, Sendable {
        case loseWeight = "lose_weight"
        case maintain = "maintain"
        case gainWeight = "gain_weight"
        case buildMuscle = "build_muscle"
        case controlSugar = "control_sugar"
        case controlSalt = "control_salt"
        case controlFat = "control_fat"
        case custom = "custom"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .loseWeight: return L10n.text("member.setup.nutrition.nutrition.9b2401");
        case .maintain: return L10n.text("member.setup.nutrition.nutrition.d861ae");
        case .gainWeight: return L10n.text("member.setup.nutrition.nutrition.be62bd");
        case .buildMuscle: return L10n.text("member.setup.nutrition.nutrition.a0ccc4");
        case .controlSugar: return L10n.text("member.setup.nutrition.nutrition.53e4b7");
        case .controlSalt: return L10n.text("member.setup.nutrition.nutrition.c28e60");
        case .controlFat: return L10n.text("member.setup.nutrition.nutrition.de0619");
        case .custom: return L10n.text("member.setup.nutrition.nutrition.f1d4ff");            }
        }

        var energyAdjustment: Double {
            switch self {
            case .loseWeight: return -350
            case .gainWeight, .buildMuscle: return 250
            default: return 0
            }
        }
    }
}
