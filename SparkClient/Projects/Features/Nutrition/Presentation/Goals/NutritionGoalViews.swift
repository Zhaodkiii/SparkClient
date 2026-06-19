import Combine
import SwiftUI

struct NutritionGoalView: View {
    let goalUseCase: NutritionGoalUseCase
    let memberID: Int
    let member: Member?
    let onSaved: () -> Void

    @StateObject private var viewModel: NutritionGoalViewModel

    init(
        goalUseCase: NutritionGoalUseCase,
        memberID: Int,
        member: Member?,
        onSaved: @escaping () -> Void
    ) {
        self.goalUseCase = goalUseCase
        self.memberID = memberID
        self.member = member
        self.onSaved = onSaved
        _viewModel = StateObject(
            wrappedValue: NutritionGoalViewModel(
                goalUseCase: goalUseCase,
                memberID: memberID,
                member: member
            )
        )
    }

    var body: some View {
        List {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Section {
                NavigationLink {
                    NutritionGoalModePickerView(selection: $viewModel.goalType)
                } label: {
                    valueRow("nutrition.goal.mode", value: viewModel.goalType.title)
                }
                decimalRow("nutrition.goal.height", value: $viewModel.heightCm, unit: "cm")
                decimalRow("nutrition.goal.start_weight", value: $viewModel.startWeightKg, unit: "kg")
                decimalRow("nutrition.goal.current_weight", value: $viewModel.currentWeightKg, unit: "kg")
                decimalRow("nutrition.goal.target_weight", value: $viewModel.targetWeightKg, unit: "kg")
                NavigationLink {
                    NutritionActivityLevelPickerView(selection: $viewModel.activityLevel)
                } label: {
                    valueRow("nutrition.goal.activity_level", value: viewModel.activityLevel.title)
                }
                decimalRow("nutrition.goal.weekly_target", value: $viewModel.weeklyWeightDeltaKg, unit: "kg")
            }

            Section {
                NavigationLink {
                    NutritionCalorieGoalView(viewModel: viewModel)
                } label: {
                    valueRow("nutrition.goal.calorie_target", value: NutritionFormatting.energyKcal(viewModel.dailyEnergyTargetKcal))
                }
                integerRow("nutrition.goal.step_target", value: $viewModel.stepTarget)
                NavigationLink {
                    NutritionMacroGoalEditorView(viewModel: viewModel)
                } label: {
                    valueRow("nutrition.goal.macro_target", value: viewModel.macroSummary)
                }
            }

            if let calculation = viewModel.calculationResult {
                Section(L10n.text("nutrition.goal.last_calculation", fallback: "最近计算")) {
                    NutritionGoalCalculationSummaryView(calculation: calculation)
                }
            }
        }
        .navigationTitle(L10n.text("nutrition.goal.title", fallback: "我的目标"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L10n.text("common.save", fallback: "保存")) {
                    Task {
                        let saved = await viewModel.save()
                        if saved {
                            onSaved()
                        }
                    }
                }
                .disabled(viewModel.isSaving)
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .task { await viewModel.loadIfNeeded() }
    }

    private func valueRow(_ titleKey: String, value: String) -> some View {
        HStack {
            Text(L10n.text(titleKey, fallback: titleFallback(titleKey)))
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func decimalRow(_ titleKey: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(L10n.text(titleKey, fallback: titleFallback(titleKey)))
            Spacer()
            TextField("", value: value, format: .number.precision(.fractionLength(1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 88)
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }

    private func integerRow(_ titleKey: String, value: Binding<Int>) -> some View {
        HStack {
            Text(L10n.text(titleKey, fallback: titleFallback(titleKey)))
            Spacer()
            TextField("", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
        }
    }

    private func titleFallback(_ key: String) -> String {
        switch key {
        case "nutrition.goal.mode": return "目标"
        case "nutrition.goal.height": return "身高"
        case "nutrition.goal.start_weight": return "起始体重"
        case "nutrition.goal.current_weight": return "当前体重"
        case "nutrition.goal.target_weight": return "目标体重"
        case "nutrition.goal.activity_level": return "活跃水平"
        case "nutrition.goal.weekly_target": return "每周目标"
        case "nutrition.goal.calorie_target": return "卡路里目标"
        case "nutrition.goal.step_target": return "步数目标"
        case "nutrition.goal.macro_target": return "营养目标"
        default: return key
        }
    }
}

struct NutritionCalorieGoalView: View {
    @ObservedObject var viewModel: NutritionGoalViewModel

    var body: some View {
        List {
            Section {
                HStack {
                    Text(L10n.text("nutrition.goal.calorie_target", fallback: "卡路里目标"))
                    Spacer()
                    TextField("", value: $viewModel.dailyEnergyTargetKcal, format: .number.precision(.fractionLength(0)))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text("kcal")
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await viewModel.recalculate() }
                } label: {
                    Text(L10n.text("nutrition.goal.recalculate", fallback: "重新计算卡路里目标"))
                }
            }

            if !viewModel.missingFields.isEmpty {
                Section(L10n.text("nutrition.goal.missing_fields", fallback: "需要补充")) {
                    ForEach(viewModel.missingFields, id: \.self) { field in
                        Text(viewModel.missingFieldTitle(field))
                    }
                }
            }

            if let calculation = viewModel.calculationResult {
                Section {
                    NavigationLink {
                        NutritionGoalCalculationResultView(
                            calculation: calculation,
                            onUseSuggestion: {
                                viewModel.useSuggestion(calculation)
                            }
                        )
                    } label: {
                        valueRow(
                            title: L10n.text("nutrition.goal.calculation_result", fallback: "计算结果"),
                            value: calculation.calorieIntake?.suggestedEnergyKcal.map(NutritionFormatting.energyKcal) ?? "-"
                        )
                    }
                }
            }
        }
        .navigationTitle(L10n.text("nutrition.goal.calorie_title", fallback: "卡路里目标"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if viewModel.isCalculating {
                ProgressView()
            }
        }
    }

    private func valueRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

struct NutritionGoalCalculationResultView: View {
    let calculation: SparkNutritionAPI.RemoteNutritionBodyMetricsCalculationResponse
    let onUseSuggestion: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("nutrition.goal.suggested_energy", fallback: "建议卡路里目标"))
                        .font(.headline)
                    Text(calculation.calorieIntake?.suggestedEnergyKcal.map(NutritionFormatting.energyKcal) ?? "-")
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                }
            }

            Section(L10n.text("nutrition.goal.current_status", fallback: "当前状态")) {
                if let bmi = calculation.bmi {
                    valueRow("BMI", "\(String(format: "%.1f", bmi.value)) \(bmi.categoryText)")
                }
                if let ideal = calculation.idealWeight {
                    valueRow(
                        L10n.text("nutrition.goal.ideal_weight", fallback: "理想体重"),
                        "\(format(ideal.minKg)) - \(format(ideal.maxKg)) kg"
                    )
                    valueRow(L10n.text("nutrition.goal.target_weight_status", fallback: "目标体重状态"), ideal.targetWeightStatus)
                }
            }

            Section(L10n.text("nutrition.goal.calculation_basis", fallback: "计算依据")) {
                valueRow(L10n.text("nutrition.goal.bmr", fallback: "基础代谢"), formatEnergy(calculation.calorieIntake?.bmrKcal))
                valueRow(L10n.text("nutrition.goal.tdee", fallback: "维持热量"), formatEnergy(calculation.calorieIntake?.tdeeKcal))
                valueRow(L10n.text("nutrition.goal.energy_delta", fallback: "每日热量差"), formatEnergy(calculation.calorieIntake?.energyDeltaKcal))
            }

            if let burned = calculation.caloriesBurned {
                Section(L10n.text("nutrition.goal.burn_estimate", fallback: "消耗解释")) {
                    valueRow(L10n.text("nutrition.goal.estimated_activity", fallback: "日常活动估算"), formatEnergy(burned.estimatedDailyActivityKcal))
                    valueRow(L10n.text("nutrition.goal.apple_health_active", fallback: "今日 Apple 健康活动消耗"), formatEnergy(burned.appleHealthActiveEnergyKcal))
                    valueRow(L10n.text("nutrition.goal.manual_burn", fallback: "今日手动消耗"), formatEnergy(burned.manualBurnedEnergyKcal))
                }
            }

            if !calculation.warnings.isEmpty {
                Section(L10n.text("nutrition.goal.warnings", fallback: "提示")) {
                    ForEach(calculation.warnings, id: \.self) { warning in
                        Text(warning)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                Button {
                    onUseSuggestion()
                    dismiss()
                } label: {
                    Text(L10n.text("nutrition.goal.use_suggestion", fallback: "使用建议目标"))
                        .frame(maxWidth: .infinity)
                }
                Button(role: .cancel) {
                    dismiss()
                } label: {
                    Text(L10n.text("nutrition.goal.keep_current", fallback: "保留当前目标"))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(L10n.text("nutrition.goal.calculation_result", fallback: "计算结果"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func valueRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.1f", value)
    }

    private func formatEnergy(_ value: Double?) -> String {
        guard let value else { return "-" }
        return NutritionFormatting.energyKcal(value)
    }
}

struct NutritionGoalModePickerView: View {
    @Binding var selection: NutritionGoalViewModel.GoalType

    var body: some View {
        List(NutritionGoalViewModel.GoalType.allCases) { type in
            Button {
                selection = type
            } label: {
                HStack {
                    Text(type.title)
                    Spacer()
                    if selection == type {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        .navigationTitle(L10n.text("nutrition.goal.mode", fallback: "目标"))
    }
}

struct NutritionActivityLevelPickerView: View {
    @Binding var selection: NutritionGoalViewModel.ActivityLevel

    var body: some View {
        List(NutritionGoalViewModel.ActivityLevel.allCases) { level in
            Button {
                selection = level
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(level.title)
                        Text(level.subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selection == level {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        .navigationTitle(L10n.text("nutrition.goal.activity_level", fallback: "活跃水平"))
    }
}

struct NutritionMacroGoalEditorView: View {
    @ObservedObject var viewModel: NutritionGoalViewModel

    var body: some View {
        List {
            percentRow("nutrition.macro.carbohydrate", value: $viewModel.carbohydratePercent)
            percentRow("nutrition.macro.protein", value: $viewModel.proteinPercent)
            percentRow("nutrition.macro.fat", value: $viewModel.fatPercent)
            HStack {
                Text(L10n.text("nutrition.goal.total", fallback: "合计"))
                Spacer()
                Text("\(Int(viewModel.carbohydratePercent + viewModel.proteinPercent + viewModel.fatPercent))%")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(L10n.text("nutrition.goal.macro_target", fallback: "营养目标"))
    }

    private func percentRow(_ key: String, value: Binding<Double>) -> some View {
        HStack {
            Text(L10n.text(key))
            Spacer()
            TextField("", value: value, format: .number.precision(.fractionLength(0)))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
            Text("%")
                .foregroundStyle(.secondary)
        }
    }
}

private struct NutritionGoalCalculationSummaryView: View {
    let calculation: SparkNutritionAPI.RemoteNutritionBodyMetricsCalculationResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let bmi = calculation.bmi {
                Text("BMI \(String(format: "%.1f", bmi.value)) · \(bmi.categoryText)")
            }
            if let energy = calculation.calorieIntake?.suggestedEnergyKcal {
                Text("\(L10n.text("nutrition.goal.suggested_energy", fallback: "建议卡路里目标")) \(NutritionFormatting.energyKcal(energy))")
            }
            if !calculation.missingFields.isEmpty {
                Text("\(L10n.text("nutrition.goal.missing_fields", fallback: "需要补充")) \(calculation.missingFields.joined(separator: ", "))")
                    .foregroundStyle(.orange)
            }
        }
        .font(.subheadline)
    }
}

@MainActor
final class NutritionGoalViewModel: ObservableObject {
    @Published var goalType: GoalType = .maintain
    @Published var heightCm: Double = 160
    @Published var startWeightKg: Double = 60
    @Published var currentWeightKg: Double = 60
    @Published var targetWeightKg: Double = 60
    @Published var activityLevel: ActivityLevel = .medium
    @Published var weeklyWeightDeltaKg: Double = 0
    @Published var dailyEnergyTargetKcal: Double = 1995
    @Published var stepTarget: Int = 10_000
    @Published var carbohydratePercent: Double = 50
    @Published var proteinPercent: Double = 20
    @Published var fatPercent: Double = 30
    @Published var mealDistribution: [String: Double] = ["breakfast": 0.30, "lunch": 0.40, "dinner": 0.25, "snack": 0.05]
    @Published var calculationResult: SparkNutritionAPI.RemoteNutritionBodyMetricsCalculationResponse?
    @Published var missingFields: [String] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var isCalculating = false
    @Published var errorMessage: String?

    private let goalUseCase: NutritionGoalUseCase
    private let memberID: Int
    private let member: Member?

    init(goalUseCase: NutritionGoalUseCase, memberID: Int, member: Member?) {
        self.goalUseCase = goalUseCase
        self.memberID = memberID
        self.member = member
        if let birthDate = member?.birthDate {
            _ = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
        }
    }

    var macroSummary: String {
        "\(Int(carbohydratePercent))% / \(Int(proteinPercent))% / \(Int(fatPercent))%"
    }

    func loadIfNeeded() async {
        guard isLoading == false else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let state = try await goalUseCase.loadGoalState(memberID: memberID)
            if let goal = state.goal {
                apply(goal)
            } else {
                apply(defaults: state.defaults)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func recalculate() async {
        guard isCalculating == false else { return }
        isCalculating = true
        defer { isCalculating = false }
        do {
            normalizeEditableTargets()
            let result = try await goalUseCase.calculateBodyMetrics(
                memberID: memberID,
                goalType: goalType.rawValue,
                activityLevel: activityLevel.rawValue,
                currentWeightKg: currentWeightKg,
                heightCm: heightCm,
                biologicalSex: biologicalSex,
                ageYears: ageYears,
                weeklyWeightDeltaKg: weeklyWeightDeltaKg,
                targetWeightKg: targetWeightKg
            )
            calculationResult = result
            missingFields = result.missingFields
            if result.missingFields.isEmpty {
                useSuggestion(result)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() async -> Bool {
        guard isSaving == false else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            normalizeEditableTargets()
            let calculation = calculationResult
            _ = try await goalUseCase.saveGoal(
                memberID: memberID,
                goalType: goalType.rawValue,
                heightCm: heightCm,
                currentWeightKg: currentWeightKg,
                targetWeightKg: targetWeightKg,
                biologicalSex: biologicalSex,
                ageYears: ageYears,
                activityLevel: activityLevel.rawValue,
                weeklyWeightDeltaKg: weeklyWeightDeltaKg,
                bmrKcal: calculation?.calorieIntake?.bmrKcal,
                tdeeKcal: calculation?.calorieIntake?.tdeeKcal,
                energyDeltaKcal: calculation?.calorieIntake?.energyDeltaKcal,
                calculationFormula: calculation?.calculationFormula ?? calculation?.calorieIntake?.calculationFormula,
                calculationVersion: calculation?.calculationVersion ?? calculation?.calorieIntake?.calculationVersion,
                calculationInputs: calculation?.calculationInputs ?? calculation?.calorieIntake?.calculationInputs,
                isEnergyTargetCustom: calculation == nil,
                stepTarget: stepTarget,
                dailyEnergyTargetKcal: dailyEnergyTargetKcal,
                carbohydrateTargetG: grams(percent: carbohydratePercent),
                proteinTargetG: grams(percent: proteinPercent),
                fatTargetG: fatGrams(percent: fatPercent),
                mealDistribution: mealDistribution,
                effectiveFrom: Date(),
                isActive: true
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func useSuggestion(_ calculation: SparkNutritionAPI.RemoteNutritionBodyMetricsCalculationResponse) {
        calculationResult = calculation
        missingFields = calculation.missingFields
        if let suggested = calculation.calorieIntake?.suggestedEnergyKcal {
            dailyEnergyTargetKcal = suggested
        }
    }

    func missingFieldTitle(_ field: String) -> String {
        switch field {
        case "height_cm": return "身高"
        case "current_weight_kg": return "当前体重"
        case "biological_sex": return "生理性别"
        case "age_years": return "年龄"
        case "activity_level": return "活跃水平"
        default: return field
        }
    }

    private func apply(_ goal: SparkNutritionAPI.RemoteNutritionGoal) {
        goalType = GoalType(rawValue: goal.goalType) ?? .maintain
        if let currentWeight = goal.currentWeightKg {
            currentWeightKg = currentWeight
            startWeightKg = currentWeight
        }
        if let height = goal.heightCm {
            heightCm = height
        }
        if let targetWeight = goal.targetWeightKg {
            targetWeightKg = targetWeight
        }
        if let rawActivity = goal.activityLevel, let value = ActivityLevel(rawValue: rawActivity) {
            activityLevel = value
        }
        if let weeklyDelta = goal.weeklyWeightDeltaKg {
            weeklyWeightDeltaKg = normalizedWeeklyDelta(goalType: goalType, value: weeklyDelta)
        }
        if let energy = goal.dailyEnergyTargetKcal {
            dailyEnergyTargetKcal = normalizedEnergyTarget(energy)
        }
        if let step = goal.stepTarget {
            stepTarget = step
        }
        if let carb = goal.carbohydrateTargetG {
            carbohydratePercent = normalizedMacroTarget(carb) * 4 / max(dailyEnergyTargetKcal, 1) * 100
        }
        if let protein = goal.proteinTargetG {
            proteinPercent = normalizedMacroTarget(protein) * 4 / max(dailyEnergyTargetKcal, 1) * 100
        }
        if let fat = goal.fatTargetG {
            fatPercent = normalizedMacroTarget(fat) * 9 / max(dailyEnergyTargetKcal, 1) * 100
        }
        mealDistribution = goal.mealDistribution.isEmpty ? mealDistribution : goal.mealDistribution
    }

    private func apply(defaults: SparkNutritionAPI.RemoteNutritionMacroTarget) {
        dailyEnergyTargetKcal = normalizedEnergyTarget(defaults.energyKcal)
        carbohydratePercent = normalizedMacroTarget(defaults.carbohydrateG) * 4 / max(dailyEnergyTargetKcal, 1) * 100
        proteinPercent = normalizedMacroTarget(defaults.proteinG) * 4 / max(dailyEnergyTargetKcal, 1) * 100
        fatPercent = normalizedMacroTarget(defaults.fatG) * 9 / max(dailyEnergyTargetKcal, 1) * 100
    }

    private var ageYears: Int? {
        guard let birthDate = member?.birthDate else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
    }

    private var biologicalSex: String {
        let gender = member?.gender.lowercased() ?? ""
        return gender == "male" || gender == "female" ? gender : "unknown"
    }

    private func grams(percent: Double) -> Double {
        dailyEnergyTargetKcal * max(percent, 0) / 100 / 4
    }

    private func fatGrams(percent: Double) -> Double {
        dailyEnergyTargetKcal * max(percent, 0) / 100 / 9
    }

    private func normalizeEditableTargets() {
        weeklyWeightDeltaKg = normalizedWeeklyDelta(goalType: goalType, value: weeklyWeightDeltaKg)
        dailyEnergyTargetKcal = normalizedEnergyTarget(dailyEnergyTargetKcal)
    }

    private func normalizedWeeklyDelta(goalType: GoalType, value: Double) -> Double {
        let clamped = min(max(value, -1), 1)
        switch goalType {
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

extension NutritionGoalViewModel {
    enum GoalType: String, CaseIterable, Identifiable {
        case loseWeight = "lose_weight"
        case maintain
        case gainWeight = "gain_weight"
        case buildMuscle = "build_muscle"
        case controlSugar = "control_sugar"
        case controlSalt = "control_salt"
        case controlFat = "control_fat"
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .loseWeight: return "减重"
            case .maintain: return "保持体重"
            case .gainWeight: return "增重"
            case .buildMuscle: return "打造肌肉"
            case .controlSugar: return "控糖"
            case .controlSalt: return "控盐"
            case .controlFat: return "控脂"
            case .custom: return "自定义"
            }
        }
    }

    enum ActivityLevel: String, CaseIterable, Identifiable {
        case low
        case medium
        case high
        case veryHigh = "very_high"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .low: return "低"
            case .medium: return "中"
            case .high: return "高"
            case .veryHigh: return "很高"
            }
        }

        var subtitle: String {
            switch self {
            case .low: return "久坐或轻体力活动"
            case .medium: return "每周有规律活动"
            case .high: return "高频运动或较多体力活动"
            case .veryHigh: return "高强度训练或重体力劳动"
            }
        }
    }
}
