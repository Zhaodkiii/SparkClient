import Combine
import Foundation

@MainActor
final class MemberMedicalModuleSummaryViewModel: ObservableObject {
    @Published var sections: [MemberModuleSectionProgress] = []
    @Published var isLoading = false
    @Published var isPersisting = false
    @Published var loadError: String?
    @Published var refreshNotice: String?

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
        "为\(member.name)完善医疗健康档案"
    }

    func loadIfNeeded() async {
        guard isLoading == false else { return }

        if let completeData = flowViewModel.moduleSetupCache(for: member.id)?.completeData {
            flowViewModel.homeDependencies.logger.info(
                "医疗模块汇总：命中缓存 memberID=\(member.id) hasProfile=\(completeData.memberMedicalProfile == nil ? 0 : 1)",
                module: .medical
            )
            loadStoredProgress(from: completeData)
            rebuildSections(from: completeData)
            return
        }

        isLoading = true
        loadError = nil
        defer { isLoading = false }

        await flowViewModel.preloadModuleSetupCacheIfNeeded()

        if let completeData = flowViewModel.moduleSetupCache(for: member.id)?.completeData {
            loadStoredProgress(from: completeData)
            rebuildSections(from: completeData)
            if flowViewModel.moduleSetupCache?.completeDataLoadError != nil {
                refreshNotice = "医疗资料暂未刷新"
            }
            return
        }

        loadError = flowViewModel.moduleSetupCache?.completeDataLoadError
            ?? L10n.text("member.module.medical.load_failed", fallback: "医疗资料加载失败，请稍后重试")
    }

    func retryLoad() async {
        loadError = nil
        refreshNotice = nil
        isLoading = true
        defer { isLoading = false }
        await flowViewModel.preloadModuleSetupCacheIfNeeded(forceRefresh: true)
        if let completeData = flowViewModel.moduleSetupCache(for: member.id)?.completeData {
            loadStoredProgress(from: completeData)
            rebuildSections(from: completeData)
            loadError = nil
        } else {
            loadError = flowViewModel.moduleSetupCache?.completeDataLoadError
                ?? L10n.text("member.module.medical.load_failed", fallback: "医疗资料加载失败，请稍后重试")
        }
    }

    func rebuildSections() {
        guard let completeData = flowViewModel.moduleSetupCache(for: member.id)?.completeData else { return }
        rebuildSections(from: completeData)
    }

    func rebuildSectionsFromCache() {
        rebuildSections()
    }

    private func rebuildSections(from completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData) {
        sections = MemberMedicalModuleSectionBuilder.buildSections(
            completeData: completeData,
            storedProgress: storedProgress
        )
    }

    private func loadStoredProgress(from completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData) {
        let medicalSetting = completeData.memberModuleSettings?
            .first(where: { $0.moduleCode == MemberSetupModule.medical.rawValue })
        storedProgress = MemberModuleSectionProgressCodec.decode(from: medicalSetting?.extra)
    }

    func openSection(_ section: MemberModuleSectionProgress) {
        guard let code = MemberMedicalSectionCode(rawValue: section.sectionCode) else { return }
        flowViewModel.openMedicalSheet(mode: code.entryMode)
    }

    func openFullFlow() {
        flowViewModel.openMedicalSheet(mode: .full)
    }

    func skipModule() async {
        await flowViewModel.markModuleSelected(.medical)
    }

    func finishModule() async {
        if isModuleCompleted {
            let summary = sections
                .filter { $0.status == .completed }
                .map(\.summary)
                .joined(separator: " · ")
            await flowViewModel.markModuleCompleted(.medical, summaryText: summary)
        } else {
            await flowViewModel.markModuleSelected(.medical)
        }
    }

    private var isModuleCompleted: Bool {
        MemberMedicalSectionCode.allCases.allSatisfy { code in
            sections.first(where: { $0.sectionCode == code.rawValue })?.status == .completed
        }
    }
}
