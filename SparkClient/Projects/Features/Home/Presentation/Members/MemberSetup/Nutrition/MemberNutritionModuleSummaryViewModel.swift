import Combine
import Foundation

@MainActor
final class MemberNutritionModuleSummaryViewModel: ObservableObject {
    @Published var sections: [MemberModuleSectionProgress] = []
    @Published var isLoading = false
    @Published var isPersisting = false

    let member: Member
    let flowViewModel: MemberSetupFlowViewModel
    private let nutritionSetupViewModel: MemberNutritionSetupViewModel
    private var storedProgress: [String: MemberModuleSectionProgressRecord] = [:]

    init(member: Member, flowViewModel: MemberSetupFlowViewModel) {
        self.member = member
        self.flowViewModel = flowViewModel
        self.nutritionSetupViewModel = MemberNutritionSetupViewModel(
            member: member,
            goalUseCase: flowViewModel.homeDependencies.nutritionDependencies.goalUseCase,
            setupUseCase: flowViewModel.homeDependencies.memberModuleSetupUseCase
        )
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

        do {
            storedProgress = try await flowViewModel.homeDependencies.memberModuleSetupUseCase.sectionProgressMap(
                memberID: member.id,
                module: .nutrition
            )
        } catch {
            flowViewModel.alertMessage = error.localizedDescription
        }

        await nutritionSetupViewModel.loadIfNeeded()
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

    private var basicInfoSummary: String {
        let height = nutritionSetupViewModel.heightCm > 0 ? String(format: "%.0fcm", nutritionSetupViewModel.heightCm) : "未填写"
        let weight = nutritionSetupViewModel.weightKg > 0 ? String(format: "%.0fkg", nutritionSetupViewModel.weightKg) : "未填写"
        let goal = nutritionSetupViewModel.goalMode.title
        let kcal = nutritionSetupViewModel.targetCalories > 0 ? "\(Int(nutritionSetupViewModel.targetCalories))千卡" : "未填写"
        if height == "未填写", weight == "未填写" {
            return "未填写"
        }
        return [height, weight, goal, kcal].joined(separator: " · ")
    }

    private var basicInfoStatus: MemberModuleSectionStatus {
        let hasHeight = nutritionSetupViewModel.heightCm > 0
        let hasWeight = nutritionSetupViewModel.weightKg > 0
        let hasGoal = nutritionSetupViewModel.targetCalories > 0
        if hasHeight && hasWeight && hasGoal {
            return .completed
        }
        if hasHeight || hasWeight {
            return .incomplete
        }
        return .notStarted
    }
}
