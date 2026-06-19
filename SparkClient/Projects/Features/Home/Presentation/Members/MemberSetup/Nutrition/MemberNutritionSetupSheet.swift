import SwiftUI

struct MemberNutritionSetupSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: MemberNutritionSetupViewModel
    @State private var path: [NutritionSetupRoute] = []
    let onCompleted: (String) -> Void

    init(
        member: Member?,
        goalUseCase: NutritionGoalUseCase,
        setupUseCase: MemberModuleSetupUseCase,
        onCompleted: @escaping (String) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: MemberNutritionSetupViewModel(member: member, goalUseCase: goalUseCase, setupUseCase: setupUseCase))
        self.onCompleted = onCompleted
    }

    var body: some View {
        CompatibleRouteNavigationContainer(path: $path, legacyStackStyle: true) {
            heightStep
        } destination: { route in
            switch route {
            case .height:
                heightStep
            case .weight:
                weightStep
            case .goal:
                goalStep
            case .energy:
                energyStep
            case .macroGoal:
                macroGoalStep
            case .summary:
                summaryPage
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    private var heightStep: some View {
        NutritionStepShell(
            title: "身高",
            subtitle: "设置成员身高，用于估算基础代谢和每日能量目标",
            step: 1,
            total: 5,
            onSkip: { goNext(from: .height) },
            onNext: { goNext(from: .height) }
        ) {
            MemberNutritionHeightStepView(
                heightCm: $viewModel.heightCm
            )
        }
    }

    private var weightStep: some View {
        NutritionStepShell(
            title: "体重",
            subtitle: "设置当前体重，用于计算摄入建议和体重目标",
            step: 2,
            total: 5,
            onSkip: { goNext(from: .weight) },
            onNext: { goNext(from: .weight) }
        ) {
            MemberNutritionWeightStepView(
                weightKg: $viewModel.weightKg
            )
        }
    }

    private var goalStep: some View {
        NutritionStepShell(
            title: "目标模式",
            subtitle: "选择目标模式、活跃水平和每周体重变化范围",
            step: 3,
            total: 5,
            onSkip: { goNext(from: .goal) },
            onNext: { goNext(from: .goal) }
        ) {
            MemberNutritionGoalStepView(
                goalMode: $viewModel.goalMode,
                activityLevel: $viewModel.activityLevel,
                weeklyTargetKg: $viewModel.weeklyTargetKg
            )
        }
    }

    private var energyStep: some View {
        NutritionStepShell(
            title: "摄入与消耗",
            subtitle: "根据基础信息计算建议摄入，支持手动调整到合理范围",
            step: 4,
            total: 5,
            onSkip: { goNext(from: .energy) },
            onNext: { goNext(from: .energy) }
        ) {
            MemberNutritionEnergyStepView(
                targetCalories: $viewModel.targetCalories,
                suggestedCalories: viewModel.suggestedCalories,
                bmrKcal: viewModel.bmrKcal,
                tdeeKcal: viewModel.tdeeKcal,
                activityBurnKcal: viewModel.estimatedActivityKcal,
                energyDeltaKcal: viewModel.energyDeltaKcalValue,
                warnings: viewModel.calculationWarnings
            ) {
                Task { await viewModel.refreshCalculationIfPossible() }
            }
        }
        .task {
            await viewModel.refreshCalculationIfPossible()
        }
    }

    private var macroGoalStep: some View {
        NutritionStepShell(
            title: "营养目标",
            subtitle: "设置三大营养素比例与餐次分配",
            step: 5,
            total: 5,
            onSkip: { goNext(from: .macroGoal) },
            onNext: { goNext(from: .macroGoal) }
        ) {
            MemberNutritionMacroGoalStepView(
                targetCalories: $viewModel.targetCalories,
                carbohydratePercent: $viewModel.carbohydratePercent,
                proteinPercent: $viewModel.proteinPercent,
                fatPercent: $viewModel.fatPercent,
                mealDistribution: $viewModel.mealDistribution
            )
        }
    }

    private var summaryPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                MemberSetupStepHeaderView(
                    title: "饮食健康",
                    subtitle: "分步维护饮食目标、营养和体重管理",
                    step: 1,
                    total: 1
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("已填写内容")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(summaryText)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 44)

                VStack(spacing: 28) {
                    NutritionSummaryRow(
                        title: "身高",
                        subtitle: heightSubtitle,
                        isCompleted: hasHeight
                    ) {
                        path.append(.height)
                    }
                    NutritionSummaryRow(
                        title: "体重",
                        subtitle: weightSubtitle,
                        isCompleted: hasWeight
                    ) {
                        path.append(.weight)
                    }
                    NutritionSummaryRow(
                        title: "目标模式",
                        subtitle: goalSubtitle,
                        isCompleted: isGoalCompleted
                    ) {
                        path.append(.goal)
                    }
                    NutritionSummaryRow(
                        title: "摄入与消耗",
                        subtitle: energySubtitle,
                        isCompleted: isEnergyCompleted
                    ) {
                        path.append(.energy)
                    }
                    NutritionSummaryRow(
                        title: "营养目标",
                        subtitle: macroSubtitle,
                        isCompleted: isMacroCompleted
                    ) {
                        path.append(.macroGoal)
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

            }
            .padding(24)
            .padding(.bottom, 120)
        }
        .navigationTitle("饮食健康")
        .navigationBarTitleDisplayMode(.inline)
        .memberSetupBottomBar(
            primaryTitle: "保存",
            primaryEnabled: viewModel.isSaving == false,
            isLoading: viewModel.isSaving,
            onPrimary: {
                Task { await saveAndDismiss() }
            },
            secondaryTitle: "跳过",
            onSecondary: {
                dismiss()
            }
        )
    }

    private var hasBodyInfo: Bool {
        viewModel.heightCm > 0 && viewModel.weightKg > 0
    }

    private var hasHeight: Bool {
        viewModel.heightCm > 0
    }

    private var hasWeight: Bool {
        viewModel.weightKg > 0
    }

    private var isGoalCompleted: Bool {
        hasBodyInfo
    }

    private var isEnergyCompleted: Bool {
        viewModel.targetCalories > 0
    }

    private var isMacroCompleted: Bool {
        viewModel.carbohydratePercent > 0 && viewModel.proteinPercent > 0 && viewModel.fatPercent > 0
    }

    private var heightSubtitle: String {
        guard hasHeight else { return "未填写" }
        return String(format: "%.0fcm", viewModel.heightCm)
    }

    private var weightSubtitle: String {
        guard hasWeight else { return "未填写" }
        return String(format: "%.1fkg", viewModel.weightKg)
    }

    private var goalSubtitle: String {
        guard isGoalCompleted else { return "未填写" }
        let weekly = String(format: "%.2f", viewModel.weeklyTargetKg)
        return "\(viewModel.goalMode.title) · \(viewModel.activityLevel.title) · 每周 \(weekly) kg"
    }

    private var energySubtitle: String {
        guard isEnergyCompleted else { return "未填写" }
        if let suggested = viewModel.suggestedCalories {
            return "目标 \(String(format: "%.0f", viewModel.targetCalories)) 千卡 · 建议 \(String(format: "%.0f", suggested)) 千卡"
        }
        return "目标 \(String(format: "%.0f", viewModel.targetCalories)) 千卡"
    }

    private var macroSubtitle: String {
        guard isMacroCompleted else { return "未填写" }
        return "碳水 \(String(format: "%.0f", viewModel.carbohydratePercent))% · 蛋白质 \(String(format: "%.0f", viewModel.proteinPercent))% · 脂肪 \(String(format: "%.0f", viewModel.fatPercent))%"
    }

    private var summaryText: String {
        [heightSubtitle, weightSubtitle, goalSubtitle, energySubtitle, macroSubtitle].joined(separator: " · ")
    }

    private func goNext(from route: NutritionSetupRoute) {
        switch route {
        case .height:
            path.append(.weight)
        case .weight:
            path.append(.goal)
        case .goal:
            path.append(.energy)
        case .energy:
            path.append(.macroGoal)
        case .macroGoal:
            path.append(.summary)
        case .summary:
            break
        }
    }

    private func saveAndDismiss() async {
        if let summary = await viewModel.save() {
            onCompleted(summary)
            dismiss()
        }
    }
}

private enum NutritionSetupRoute: Hashable {
    case height
    case weight
    case goal
    case energy
    case macroGoal
    case summary
}

private struct NutritionSummaryRow: View {
    let title: String
    let subtitle: String
    let isCompleted: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline.weight(.bold))
                    if isCompleted {
                        Text("已完成")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule(style: .continuous).fill(Color.accentColor.opacity(0.12)))
                    }
                }

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button("去完善", action: action)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NutritionStepShell<Content: View>: View {
    let title: String
    let subtitle: String
    let step: Int
    let total: Int
    let onSkip: () -> Void
    let onNext: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MemberSetupStepHeaderView(
                    title: title,
                    subtitle: subtitle,
                    step: step,
                    total: total
                )

                content()

            }
            .padding(24)
            .padding(.bottom, 120)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .memberSetupBottomBar(
            primaryTitle: "下一步",
            primaryEnabled: true,
            onPrimary: onNext,
            secondaryTitle: "跳过",
            onSecondary: onSkip
        )
    }
}

private extension MemberNutritionSetupViewModel.ActivityLevel {
    var title: String {
        switch self {
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        }
    }
}
