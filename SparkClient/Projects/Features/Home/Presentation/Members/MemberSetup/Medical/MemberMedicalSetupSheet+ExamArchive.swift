import SwiftUI

extension MemberMedicalSetupSheetView {
    var isExamArchiveFlowLoading: Bool {
        if case .loading = examArchiveFlowViewModel.loadState { return true }
        return viewModel.isSaving
    }

    // MARK: - 体检档案表单（介绍页见 MemberMedicalSetupSheet.examArchiveIntroPage）

    var examArchiveStep: some View {
        MedicalGuideStepShell(
            title: L10n.text("medical.exam_archive.title"),
            subtitle: L10n.text("medical.exam_archive.entry.prompt"),
            step: 24,
            total: viewModel.totalGuideSteps,
            isLoading: isExamArchiveFlowLoading,
            primaryTitle: examArchiveStepPrimaryTitle,
            secondaryTitle: L10n.text("medical.exam_archive.action.skip"),
            onSkip: skipExamArchiveFlow,
            onNext: handleExamArchiveIntroNext
        ) {
            MemberMedicalExamArchiveFormContent(
                viewModel: viewModel,
                flowViewModel: examArchiveFlowViewModel,
                hasExamHistory: $viewModel.hasExamHistory,
                fileTransferService: homeDependencies.fileTransferService,
                medicalQueryAPI: homeDependencies.medicalQueryAPI,
                memberContextStore: homeDependencies.memberContextStore,
                medicalDocumentUploadViewModel: homeDependencies.memberFlowMedicalDocumentUploadViewModel,
                aiSettingsViewModel: homeDependencies.aiSettingsViewModel,
                workflowAPI: viewModel.medicalWorkflowAPI,
                notificationClient: homeDependencies.notificationClient,
                onReportSelected: selectExamReportForAIFlow
            )
        }
    }

    // MARK: - 5.x AI 闭环步骤

    var examArchiveAIExtractConfirmStep: some View {
        MedicalGuideStepShell(
            title: L10n.text("medical.exam_archive.extract.title"),
            subtitle: L10n.text("medical.exam_archive.extract.subtitle"),
            step: 25,
            total: viewModel.totalGuideSteps,
            isLoading: isExamArchiveFlowLoading,
            primaryTitle: L10n.text("medical.exam_archive.action.confirm_continue"),
            secondaryTitle: L10n.text("medical.exam_archive.action.edit_abnormal"),
            onSkip: { path.append(.keyIndicators) },
            onNext: {
                Task {
                    guard await examArchiveFlowViewModel.confirmAbnormalItems() else { return }
                    if examArchiveFlowViewModel.followUpTasks.isEmpty {
                        path.append(.examArchivePlanGenerating)
                        await generateExamArchivePlan(createTasks: false)
                    } else {
                        path.append(.examArchiveFollowUpPlan)
                    }
                }
            }
        ) {
            MemberMedicalExamArchiveGuideContent.abnormalItemsConfirm(
                flowViewModel: examArchiveFlowViewModel,
                onEditTapped: { path.append(.keyIndicators) }
            )
        }
        .task(id: examArchiveFlowViewModel.selectedReport?.id) {
            guard let reportID = examArchiveFlowViewModel.selectedReport?.id else { return }
            guard examArchiveFlowViewModel.abnormalItems.isEmpty else { return }
            _ = await examArchiveFlowViewModel.previewAbnormalItems(reportID: reportID)
        }
    }

    var examArchiveFollowUpPlanStep: some View {
        MedicalGuideStepShell(
            title: L10n.text("medical.exam_archive.follow_up.title"),
            subtitle: L10n.text("medical.exam_archive.follow_up.subtitle"),
            step: 26,
            total: viewModel.totalGuideSteps,
            isLoading: isExamArchiveFlowLoading,
            primaryTitle: L10n.text("medical.exam_archive.action.add_follow_up"),
            secondaryTitle: L10n.text("medical.exam_archive.action.not_now"),
            onSkip: {
                path.append(.examArchivePlanGenerating)
                Task { await generateExamArchivePlan(createTasks: false) }
            },
            onNext: {
                path.append(.examArchivePlanGenerating)
                Task { await generateExamArchivePlan(createTasks: true) }
            }
        ) {
            MemberMedicalExamArchiveGuideContent.followUpTasks(flowViewModel: examArchiveFlowViewModel)
        }
    }

    var examArchivePlanGeneratingStep: some View {
        MedicalGuideStepShell(
            title: L10n.text("medical.exam_archive.generating.nav_title"),
            subtitle: L10n.text("medical.exam_archive.generating.subtitle"),
            step: 27,
            total: viewModel.totalGuideSteps,
            isLoading: isExamArchiveFlowLoading,
            showsPrimaryButton: false,
            showsSkipButton: false,
            onSkip: {},
            onNext: {}
        ) {
            MemberMedicalExamArchiveGuideContent.planGenerating(isLoading: isExamArchiveFlowLoading)
        }
    }

    var examArchivePlanResultStep: some View {
        Group {
            if let plan = examArchiveFlowViewModel.generatedPlan {
                MedicalGuideStepShell(
                    title: L10n.text("medical.exam_archive.result.title"),
                    subtitle: L10n.text("medical.exam_archive.result.subtitle"),
                    step: 28,
                    total: viewModel.totalGuideSteps,
                    isLoading: isExamArchiveFlowLoading,
                    primaryTitle: L10n.text("medical.exam_archive.action.save_plan"),
                    secondaryTitle: L10n.text("medical.exam_archive.action.add_reminder"),
                    onSkip: completeExamArchiveFlow,
                    onNext: completeExamArchiveFlow
                ) {
                    MemberMedicalExamArchiveGuideContent.planResult(
                        plan: plan,
                        evidence: examArchiveFlowViewModel.evidenceSnapshot,
                        abnormalItems: examArchiveFlowViewModel.planRationaleAbnormalItems,
                        sourceReportTitle: examArchiveFlowViewModel.selectedReport.map {
                            MemberMedicalExamArchiveGuideContent.reportTitle($0)
                        }
                    )
                }
                .task {
                    if examArchiveFlowViewModel.evidenceSnapshot == nil {
                        _ = await examArchiveFlowViewModel.loadEvidence()
                    }
                }
            } else {
                ProgressView()
            }
        }
    }

    var examArchiveBaselineIntroStep: some View {
        MedicalGuideStepShell(
            title: L10n.text("medical.exam_archive.baseline.title"),
            subtitle: L10n.text("medical.exam_archive.baseline.subtitle"),
            step: 24,
            total: viewModel.totalGuideSteps,
            isLoading: isExamArchiveFlowLoading,
            primaryTitle: L10n.text("medical.exam_archive.action.generate_plan"),
            secondaryTitle: L10n.text("medical.exam_archive.action.skip_generate"),
            onSkip: skipExamArchiveFlow,
            onNext: { path.append(.examArchiveEvidenceConfirm) }
        ) {
            MemberMedicalExamArchiveGuideContent.baselineIntro()
        }
    }

    var examArchiveEvidenceConfirmStep: some View {
        MedicalGuideStepShell(
            title: L10n.text("medical.exam_archive.evidence.title"),
            subtitle: L10n.text("medical.exam_archive.evidence.subtitle"),
            step: 25,
            total: viewModel.totalGuideSteps,
            isLoading: isExamArchiveFlowLoading,
            primaryTitle: L10n.text("medical.exam_archive.action.confirm_generate"),
            secondaryTitle: L10n.text("medical.exam_archive.action.edit_profile"),
            onSkip: skipExamArchiveFlow,
            onNext: {
                path.append(.examArchivePlanGenerating)
                Task { await generateExamArchivePlan(createTasks: false) }
            }
        ) {
            MemberMedicalExamArchiveGuideContent.evidenceConfirm(evidence: examArchiveFlowViewModel.evidenceSnapshot)
        }
        .task { _ = await examArchiveFlowViewModel.loadEvidence() }
    }

    // MARK: - Actions

    func startExamArchiveForm() {
        if viewModel.shouldSkipExamArchiveStep {
            path.append(.examArchiveSummary)
        } else {
            path.append(.examArchive)
        }
    }

    private var examArchiveStepPrimaryTitle: String {
        viewModel.hasExamHistory
            ? L10n.text("member.setup.medical.exam_archive.action.continue_after_select")
            : L10n.text("member.setup.medical.exam_archive.action.generate_plan_short")
    }

    func configureExamArchiveFlowIfNeeded() {
        examArchiveFlowViewModel.onFlowCompleted = { response in
            viewModel.applyExamArchiveFlowResult(response)
        }
        examArchiveFlowViewModel.onReportsWithDetailsUpdated = { reports in
            viewModel.syncHealthExamReportsCache(reports)
        }
        if let memberID = viewModel.member?.id {
            examArchiveFlowViewModel.syncMemberID(memberID)
        }
    }

    func handleExamArchiveIntroNext() {
        if viewModel.hasExamHistory {
            if examArchiveFlowViewModel.selectedReport != nil {
                path.append(.examArchiveAIExtractConfirm)
            }
        } else {
            examArchiveFlowViewModel.selectPath(.noHistoryReport)
            path.append(.examArchiveBaselineIntro)
        }
    }

    func selectExamReportForAIFlow(_ report: SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments) {
        examArchiveFlowViewModel.selectPath(.hasHistoryReport)
        examArchiveFlowViewModel.selectReport(report)
        Task {
            guard await examArchiveFlowViewModel.previewAbnormalItems(reportID: report.id) else { return }
            path.append(.examArchiveAIExtractConfirm)
        }
    }

    @MainActor
    func generateExamArchivePlan(createTasks: Bool) async {
        let success = await examArchiveFlowViewModel.generatePlan(createFollowUpTasks: createTasks)
        if success {
            path.append(.examArchivePlanResult)
        }
    }

    func skipExamArchiveFlow() {
        examArchiveFlowViewModel.skipFlow()
        path.append(.summary)
    }

    func completeExamArchiveFlow() {
        examArchiveFlowViewModel.finishFlow()
        path.append(.examArchiveSummary)
    }
}
