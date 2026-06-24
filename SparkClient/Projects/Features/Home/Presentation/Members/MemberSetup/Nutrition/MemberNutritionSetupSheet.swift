import SwiftUI

struct MemberNutritionSetupSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: MemberNutritionSetupViewModel
    @State private var path: [NutritionSetupRoute] = []
    let entryMode: NutritionSetupEntryMode
    let onCompleted: (String) -> Void
    let onSectionCompleted: (NutritionSetupEntryMode, String) -> Void

    init(
        member: Member?,
        goalUseCase: NutritionGoalUseCase,
        setupUseCase: MemberModuleSetupUseCase,
        entryMode: NutritionSetupEntryMode = .full,
        onCompleted: @escaping (String) -> Void,
        onSectionCompleted: @escaping (NutritionSetupEntryMode, String) -> Void = { _, _ in }
    ) {
        _viewModel = StateObject(wrappedValue: MemberNutritionSetupViewModel(member: member, goalUseCase: goalUseCase, setupUseCase: setupUseCase))
        self.entryMode = entryMode
        self.onCompleted = onCompleted
        self.onSectionCompleted = onSectionCompleted
    }

    private var isSectionMode: Bool {
        entryMode.isSectionMode
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
            title: L10n.text("member.setup.medical.nutrition.19a854"),
            subtitle: L10n.text("member.setup.nutrition.nutrition.2a1890"),
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
            title: L10n.text("member.setup.medical.nutrition.440093"),
            subtitle: L10n.text("member.setup.nutrition.nutrition.de81a2"),
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
            title: L10n.text("member.setup.nutrition.nutrition.5a8094"),
            subtitle: L10n.text("member.setup.nutrition.nutrition.84e2cf"),
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
            title: L10n.text("member.setup.nutrition.nutrition.5f3406"),
            subtitle: L10n.text("member.setup.nutrition.nutrition.85eda8"),
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
            title: L10n.text("member.setup.nutrition.nutrition.3bad9a"),
            subtitle: L10n.text("member.setup.nutrition.nutrition.6337f4"),
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
                    title: L10n.text("member.module.nutrition.title"),
                    subtitle: L10n.text("member.setup.nutrition.nutrition.32ad06"),
                    step: 1,
                    total: 1
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.text("member.setup.medical.nutrition.519b61"))
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
                        title: L10n.text("member.setup.medical.nutrition.19a854"),
                        subtitle: heightSubtitle,
                        isCompleted: hasHeight
                    ) {
                        path.append(.height)
                    }
                    NutritionSummaryRow(
                        title: L10n.text("member.setup.medical.nutrition.440093"),
                        subtitle: weightSubtitle,
                        isCompleted: hasWeight
                    ) {
                        path.append(.weight)
                    }
                    NutritionSummaryRow(
                        title: L10n.text("member.setup.nutrition.nutrition.5a8094"),
                        subtitle: goalSubtitle,
                        isCompleted: isGoalCompleted
                    ) {
                        path.append(.goal)
                    }
                    NutritionSummaryRow(
                        title: L10n.text("member.setup.nutrition.nutrition.5f3406"),
                        subtitle: energySubtitle,
                        isCompleted: isEnergyCompleted
                    ) {
                        path.append(.energy)
                    }
                    NutritionSummaryRow(
                        title: L10n.text("member.setup.nutrition.nutrition.3bad9a"),
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
        .navigationTitle(L10n.text("member.module.nutrition.title"))
        .navigationBarTitleDisplayMode(.inline)
        .memberSetupBottomBar(
            primaryTitle: L10n.text("common.save"),
            primaryEnabled: viewModel.isSaving == false,
            isLoading: viewModel.isSaving,
            onPrimary: {
                Task { await saveAndDismiss() }
            },
            secondaryTitle: isSectionMode ? L10n.text("member.setup.medical.nutrition.2e16ac") : "跳过",
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
        guard hasHeight else { return L10n.text("member.setup.common.not_filled");}
        return String(format: "%.0fcm", viewModel.heightCm)
    }

    private var weightSubtitle: String {
        guard hasWeight else { return L10n.text("member.setup.common.not_filled");}
        return String(format: "%.1fkg", viewModel.weightKg)
    }

    private var goalSubtitle: String {
        guard isGoalCompleted else { return L10n.text("member.setup.common.not_filled");}
        let weekly = String(format: "%.2f", viewModel.weeklyTargetKg)
        return "\(viewModel.goalMode.title) · \(viewModel.activityLevel.title) · 每周 \(weekly) kg"
    }

    private var energySubtitle: String {
        guard isEnergyCompleted else { return L10n.text("member.setup.common.not_filled");}
        if let suggested = viewModel.suggestedCalories {
            return "目标 \(String(format: "%.0f", viewModel.targetCalories)) 千卡 · 建议 \(String(format: "%.0f", suggested)) 千卡"
        }
        return "目标 \(String(format: "%.0f", viewModel.targetCalories)) 千卡"
    }

    private var macroSubtitle: String {
        guard isMacroCompleted else { return L10n.text("member.setup.common.not_filled");}
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
        let markModuleCompleted = entryMode == .full
        if let summary = await viewModel.save(markModuleCompleted: markModuleCompleted) {
            if isSectionMode {
                onSectionCompleted(entryMode, summary)
            } else {
                onCompleted(summary)
            }
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
                        Text(L10n.text("home.members.save.success"))
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
            primaryTitle: L10n.text("common.next"),
            primaryEnabled: true,
            onPrimary: onNext,
            secondaryTitle: L10n.text("common.skip"),
            onSecondary: onSkip
        )
    }
}

private extension MemberNutritionSetupViewModel.ActivityLevel {
    var title: String {
        switch self {
        case .low: return L10n.text("member.setup.medical.nutrition.19ac67");
        case .medium: return L10n.text("member.setup.medical.nutrition.aed1df");
        case .high: return L10n.text("member.setup.medical.nutrition.4296d7");        }
    }
}
