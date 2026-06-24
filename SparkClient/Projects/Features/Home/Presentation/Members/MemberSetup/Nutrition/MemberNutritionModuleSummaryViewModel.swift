import Combine
import Foundation

@MainActor
final class MemberNutritionModuleSummaryViewModel: ObservableObject {
    @Published var sections: [MemberModuleSectionProgress] = []
    @Published var isLoading = false
    @Published var isPersisting = false

    let member: Member
    let flowViewModel: MemberSetupFlowViewModel
    private var storedProgress: [String: MemberModuleSectionProgressRecord] = [:]

    init(member: Member, flowViewModel: MemberSetupFlowViewModel) {
        self.member = member
        self.flowViewModel = flowViewModel
    }

    var completedCount: Int {
        sections.filter { $0.status == .completed }.count
    }

    var headerSubtitle: String {
        "为\(member.name)完善饮食目标与身体指标"
    }

    func loadIfNeeded() async {
        guard isLoading == false else { return }
        isLoading = true
        defer { isLoading = false }

        if flowViewModel.moduleSetupCache(for: member.id)?.completeData == nil {
            await flowViewModel.preloadModuleSetupCacheIfNeeded()
        }

        if let completeData = flowViewModel.moduleSetupCache(for: member.id)?.completeData {
            let nutritionSetting = completeData.memberModuleSettings?
                .first(where: { $0.moduleCode == MemberSetupModule.nutrition.rawValue })
            storedProgress = MemberModuleSectionProgressCodec.decode(from: nutritionSetting?.extra)
        } else {
            do {
                storedProgress = try await flowViewModel.homeDependencies.memberModuleSetupUseCase.sectionProgressMap(
                    memberID: member.id,
                    module: .nutrition
                )
            } catch {
                flowViewModel.alertMessage = error.localizedDescription
            }
        }

        rebuildSections()
    }

    func rebuildSections() {
        sections = MemberNutritionSectionCode.allCases.map { code in
            let inferredSummary = basicInfoSummary
            let inferredStatus = basicInfoStatus
            if let stored = storedProgress[code.rawValue] {
                return MemberModuleSectionProgress(
                    module: .nutrition,
                    sectionCode: code.rawValue,
                    title: code.title,
                    subtitle: code.subtitle,
                    iconName: code.iconName,
                    summary: stored.summary.isEmpty ? inferredSummary : stored.summary,
                    status: stored.status == .completed ? .completed : inferredStatus
                )
            }
            return MemberModuleSectionProgress(
                module: .nutrition,
                sectionCode: code.rawValue,
                title: code.title,
                subtitle: code.subtitle,
                iconName: code.iconName,
                summary: inferredSummary,
                status: inferredStatus
            )
        }
    }

    func openSection(_ section: MemberModuleSectionProgress) {
        guard let code = MemberNutritionSectionCode(rawValue: section.sectionCode) else { return }
        flowViewModel.openNutritionSheet(mode: code.entryMode)
    }

    func skipModule() async {
        await flowViewModel.markModuleSelected(.nutrition)
    }

    func finishModule() async {
        if completedCount > 0 {
            let summary = sections
                .filter { $0.status == .completed }
                .map(\.summary)
                .joined(separator: " · ")
            await flowViewModel.markModuleCompleted(.nutrition, summaryText: summary)
        } else {
            await flowViewModel.markModuleSelected(.nutrition)
        }
    }

    private var goalState: SparkNutritionAPI.RemoteNutritionGoalState? {
        let cache = flowViewModel.moduleSetupCache(for: member.id)
        return cache?.completeData?.nutritionGoalState ?? cache?.nutritionGoalState
    }

    private var basicInfoSummary: String {
        guard let goal = goalState?.goal else { return L10n.text("member.setup.common.not_filled");}
        let height = (goal.heightCm ?? 0) > 0 ? String(format: "%.0fcm", goal.heightCm ?? 0) : L10n.text("member.setup.common.not_filled")
        let weight = (goal.currentWeightKg ?? 0) > 0 ? String(format: "%.0fkg", goal.currentWeightKg ?? 0) : L10n.text("member.setup.common.not_filled")
        let goalMode = MemberNutritionSetupViewModel.GoalMode(rawValue: goal.goalType)?.title ?? L10n.text("member.setup.common.not_filled")
        let kcal = (goal.dailyEnergyTargetKcal ?? 0) > 0 ? "\(Int(goal.dailyEnergyTargetKcal ?? 0))千卡" : L10n.text("member.setup.common.not_filled")
        if height == L10n.text("member.setup.common.not_filled"), weight == L10n.text("member.setup.common.not_filled") {
            return L10n.text("member.setup.common.not_filled");        }
        return [height, weight, goalMode, kcal].joined(separator: " · ")
    }

    private var basicInfoStatus: MemberModuleSectionStatus {
        guard let goal = goalState?.goal else { return .notStarted }
        let hasHeight = (goal.heightCm ?? 0) > 0
        let hasWeight = (goal.currentWeightKg ?? 0) > 0
        let hasGoal = (goal.dailyEnergyTargetKcal ?? 0) > 0
        if hasHeight && hasWeight && hasGoal {
            return .completed
        }
        if hasHeight || hasWeight {
            return .incomplete
        }
        return .notStarted
    }
}
