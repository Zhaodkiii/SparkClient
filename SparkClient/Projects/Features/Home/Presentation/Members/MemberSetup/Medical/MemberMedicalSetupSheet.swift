import SwiftUI

struct MemberMedicalSetupSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: MemberMedicalSetupViewModel
    @State private var path: [MedicalSetupRoute] = []
    @State private var showMedicationPlanStepper = false
    let homeDependencies: HomeFeatureDependencies?
    let onCompleted: (String) -> Void

    init(
        member: Member?,
        medicalQueryAPI: SparkMedicalQueryAPI,
        setupUseCase: MemberModuleSetupUseCase,
        homeDependencies: HomeFeatureDependencies? = nil,
        onCompleted: @escaping (String) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: MemberMedicalSetupViewModel(member: member, medicalQueryAPI: medicalQueryAPI, setupUseCase: setupUseCase))
        self.homeDependencies = homeDependencies
        self.onCompleted = onCompleted
    }

    var body: some View {
        CompatibleRouteNavigationContainer(path: $path, legacyStackStyle: true) {
            chronicConditionStep
        } destination: { route in
            switch route {
            case .medications:
                medicationStep
            case .examIndicators:
                examIndicatorStep
            case .symptomFollowUp:
                symptomFollowUpStep
            case .summary:
                summaryPage
            case .chronicConditions:
                chronicConditionStep
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .task {
            await viewModel.loadIfNeeded()
        }
        .sheet(isPresented: $showMedicationPlanStepper) {
            medicationPlanStepperSheet
        }
    }

    private var chronicConditionStep: some View {
        MedicalStepShell(
            title: "慢病档案",
            subtitle: "选择需要维护的慢病信息",
            step: 1,
            total: 4,
            onSkip: { goNext(from: .chronicConditions) },
            onNext: { goNext(from: .chronicConditions) }
        ) {
            MemberMedicalChronicConditionStepView(chronicConditions: $viewModel.chronicConditions)
        }
    }

    private var medicationStep: some View {
        MedicalStepShell(
            title: "用药",
            subtitle: "填写长期用药和提醒相关信息",
            step: 2,
            total: 4,
            onSkip: { goNext(from: .medications) },
            onNext: { goNext(from: .medications) }
        ) {
            MemberMedicalMedicationStepView(
                longTermMedications: $viewModel.longTermMedications,
                medicationNotes: $viewModel.medicationNotes,
                medicationPlanSummary: $viewModel.medicationPlanSummary,
                onAddMedicationPlan: {
                    showMedicationPlanStepper = true
                }
            )
        }
    }

    private var examIndicatorStep: some View {
        MedicalStepShell(
            title: "体检指标",
            subtitle: "记录需要重点关注的体检项目",
            step: 3,
            total: 4,
            onSkip: { goNext(from: .examIndicators) },
            onNext: { goNext(from: .examIndicators) }
        ) {
            MemberMedicalExamIndicatorStepView(examFocus: $viewModel.examFocus)
        }
    }

    private var symptomFollowUpStep: some View {
        MedicalStepShell(
            title: "症状/随访",
            subtitle: "补充症状观察和随访计划",
            step: 4,
            total: 4,
            onSkip: { goNext(from: .symptomFollowUp) },
            onNext: { goNext(from: .symptomFollowUp) }
        ) {
            MemberMedicalSymptomFollowUpStepView(
                symptomFollowUpFocus: $viewModel.symptomFollowUpFocus,
                notes: $viewModel.notes
            )
        }
    }

    private var summaryPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                MemberSetupStepHeaderView(
                    title: "医疗模块",
                    subtitle: "分步维护慢病、用药、体检和症状随访",
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
                    MedicalSummaryRow(
                        title: "慢病档案",
                        subtitle: chronicOverviewSubtitle,
                        isCompleted: isChronicCompleted
                    ) {
                        path.append(.chronicConditions)
                    }
                    MedicalSummaryRow(
                        title: "用药",
                        subtitle: medicationOverviewSubtitle,
                        isCompleted: isMedicationCompleted
                    ) {
                        path.append(.medications)
                    }
                    MedicalSummaryRow(
                        title: "体检指标",
                        subtitle: examOverviewSubtitle,
                        isCompleted: isExamCompleted
                    ) {
                        path.append(.examIndicators)
                    }
                    MedicalSummaryRow(
                        title: "症状/随访",
                        subtitle: symptomOverviewSubtitle,
                        isCompleted: isSymptomCompleted
                    ) {
                        path.append(.symptomFollowUp)
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
        .navigationTitle("医疗模块")
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

    @ViewBuilder
    private var medicationPlanStepperSheet: some View {
        if let member = viewModel.member, let homeDependencies {
            MedicationPlanStepperView(
                mode: .create,
                memberID: member.id,
                medicineBoxes: [],
                workflowAPI: homeDependencies.medicalWorkflowAPI,
                fileTransferService: homeDependencies.fileTransferService,
                notificationClient: homeDependencies.notificationClient,
                onMedicineBoxSaved: { _ in },
                onServerSaved: { saved in
                    viewModel.medicationPlanSummary = saved.drugName.nilIfBlank ?? "已添加 1 个用药计划"
                },
                homeDependencies: homeDependencies,
                memberContextStore: homeDependencies.memberContextStore
            )
        } else {
            Text("缺少成员或依赖，无法打开用药计划")
                .foregroundStyle(.secondary)
        }
    }

    private var summaryText: String {
        [
            chronicOverviewSubtitle,
            medicationOverviewSubtitle,
            examOverviewSubtitle,
            symptomOverviewSubtitle
        ].joined(separator: " · ")
    }

    private var isChronicCompleted: Bool {
        viewModel.chronicConditions.isEmpty == false
    }

    private var isMedicationCompleted: Bool {
        viewModel.longTermMedications.isEmpty == false
            || viewModel.medicationNotes.isEmpty == false
            || viewModel.medicationPlanSummary.isEmpty == false
    }

    private var isExamCompleted: Bool {
        viewModel.examFocus.isEmpty == false
    }

    private var isSymptomCompleted: Bool {
        viewModel.symptomFollowUpFocus.isEmpty == false || viewModel.notes.isEmpty == false
    }

    private var chronicOverviewSubtitle: String {
        viewModel.chronicConditions.isEmpty ? "未填写" : viewModel.chronicConditions.joined(separator: "、")
    }

    private var medicationOverviewSubtitle: String {
        if viewModel.medicationPlanSummary.isEmpty == false {
            return viewModel.medicationPlanSummary
        }
        let count = viewModel.longTermMedications.count
        if count == 0 && viewModel.medicationNotes.isEmpty {
            return "未填写"
        }
        if count == 0 { return viewModel.medicationNotes }
        return "\(count) 项长期用药"
    }

    private var examOverviewSubtitle: String {
        viewModel.examFocus.isEmpty ? "未填写" : viewModel.examFocus.joined(separator: "、")
    }

    private var symptomOverviewSubtitle: String {
        if viewModel.symptomFollowUpFocus.isEmpty && viewModel.notes.isEmpty {
            return "未填写"
        }
        if viewModel.symptomFollowUpFocus.isEmpty == false {
            return viewModel.symptomFollowUpFocus.joined(separator: "、")
        }
        return viewModel.notes
    }

    private func goNext(from route: MedicalSetupRoute) {
        switch route {
        case .chronicConditions:
            path.append(.medications)
        case .medications:
            path.append(.examIndicators)
        case .examIndicators:
            path.append(.symptomFollowUp)
        case .symptomFollowUp:
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

private enum MedicalSetupRoute: Hashable {
    case chronicConditions
    case medications
    case examIndicators
    case symptomFollowUp
    case summary
}

private struct MedicalSummaryRow: View {
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

private struct MedicalStepShell<Content: View>: View {
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
