import Combine
import Foundation

@MainActor
final class MemberMedicalModuleSummaryViewModel: ObservableObject {
    @Published var sections: [MemberModuleSectionProgress] = []
    @Published var isLoading = false
    @Published var isPersisting = false

    let member: Member
    let flowViewModel: MemberSetupFlowViewModel
    private let medicalSetupViewModel: MemberMedicalSetupViewModel
    private var storedProgress: [String: MemberModuleSectionProgressRecord] = [:]

    init(member: Member, flowViewModel: MemberSetupFlowViewModel) {
        self.member = member
        self.flowViewModel = flowViewModel
        self.medicalSetupViewModel = MemberMedicalSetupViewModel(
            member: member,
            medicalQueryAPI: flowViewModel.homeDependencies.medicalQueryAPI,
            setupUseCase: flowViewModel.homeDependencies.memberModuleSetupUseCase,
            homeDependencies: flowViewModel.homeDependencies
        )
    }

    var completedCount: Int {
        sections.filter { $0.status == .completed }.count
    }

    var headerSubtitle: String {
        "为\(member.name)完善医疗健康档案"
    }

    func loadIfNeeded() async {
        guard isLoading == false else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            storedProgress = try await flowViewModel.homeDependencies.memberModuleSetupUseCase.sectionProgressMap(
                memberID: member.id,
                module: .medical
            )
        } catch {
            flowViewModel.alertMessage = error.localizedDescription
        }

        await medicalSetupViewModel.loadIfNeeded()
        rebuildSections()
    }

    func rebuildSections() {
        sections = MemberMedicalSectionCode.allCases.map { code in
            let inferredSummary = summary(for: code)
            let inferredStatus = status(for: code, summary: inferredSummary)
            if let stored = storedProgress[code.rawValue] {
                return MemberModuleSectionProgress(
                    module: .medical,
                    sectionCode: code.rawValue,
                    title: code.title,
                    subtitle: code.subtitle,
                    iconName: code.iconName,
                    summary: stored.summary.isEmpty ? inferredSummary : stored.summary,
                    status: stored.status == .completed ? .completed : inferredStatus
                )
            }
            return MemberModuleSectionProgress(
                module: .medical,
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
        if completedCount > 0 {
            let summary = sections
                .filter { $0.status == .completed }
                .map(\.summary)
                .joined(separator: " · ")
            await flowViewModel.markModuleCompleted(.medical, summaryText: summary)
        } else {
            await flowViewModel.markModuleSelected(.medical)
        }
    }

    private func summary(for code: MemberMedicalSectionCode) -> String {
        switch code {
        case .basicProfile:
            return medicalSetupViewModel.basicInfoSummaryText
        case .healthHistory:
            return medicalSetupViewModel.historySummary == "未填写" ? "待补充" : medicalSetupViewModel.historySummary
        case .lifestyle:
            return medicalSetupViewModel.lifestyleSummary
        case .examArchive:
            return medicalSetupViewModel.examArchiveSummary == "未填写" ? "未填写" : medicalSetupViewModel.examArchiveSummary
        case .riskAssessment:
            return medicalSetupViewModel.riskAssessmentSummary.isEmpty ? "待生成" : medicalSetupViewModel.riskAssessmentSummary
        }
    }

    private func status(for code: MemberMedicalSectionCode, summary: String) -> MemberModuleSectionStatus {
        switch code {
        case .basicProfile:
            if medicalSetupViewModel.isBasicProfileSectionCompleted { return .completed }
            if medicalSetupViewModel.hasBasicInfo { return .incomplete }
            return .notStarted
        case .healthHistory:
            if medicalSetupViewModel.isHealthHistorySectionCompleted { return .completed }
            if medicalSetupViewModel.hasHistory || medicalSetupViewModel.hasFamilyHistory || medicalSetupViewModel.hasSymptomFollowUpContent {
                return .incomplete
            }
            return .notStarted
        case .lifestyle:
            if medicalSetupViewModel.hasLifestyle { return .completed }
            return .notStarted
        case .examArchive:
            if medicalSetupViewModel.hasExamArchive || medicalSetupViewModel.examPlanLines.isEmpty == false {
                return .completed
            }
            if medicalSetupViewModel.hasExamHistory { return .incomplete }
            return .notStarted
        case .riskAssessment:
            if medicalSetupViewModel.riskAssessmentLines.isEmpty == false { return .completed }
            return .notStarted
        }
    }
}

private extension MemberMedicalSetupViewModel {
    var isBasicProfileSectionCompleted: Bool {
        gender != "unknown"
            && birthDate != nil
            && heightCm > 0
            && weightKg > 0
            && sedentaryLevel != nil
    }

    var isHealthHistorySectionCompleted: Bool {
        symptomFollowUpStatus != .unknown
            || chronicConditionStatus != .unknown
            || longTermMedicationStatus != .unknown
            || surgeryStatus != .unknown
            || allergyStatus != .unknown
            || familyHistoryStatus != .unknown
    }
}
