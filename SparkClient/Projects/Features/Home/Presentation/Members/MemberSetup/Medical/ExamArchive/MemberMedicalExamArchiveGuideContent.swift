import SwiftUI

// MARK: - 5.1 入口：路径分流（内容区，外壳由 MedicalGuideStepShell / Intro 承载）

enum MemberMedicalExamArchiveGuideContent {
    @ViewBuilder
    static func entryPathChoices(
        onSelectHasReport: @escaping () -> Void,
        onSelectNoReport: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("medical.exam_archive.entry.prompt"))
                .font(.headline.weight(.semibold))

            MemberMedicalExamPathChoiceCard(
                icon: "📑",
                title: L10n.text("medical.exam_archive.path.has_report.title"),
                subtitle: L10n.text("medical.exam_archive.path.has_report.subtitle"),
                action: onSelectHasReport
            )

            MemberMedicalExamPathChoiceCard(
                icon: "✨",
                title: L10n.text("medical.exam_archive.path.no_report.title"),
                subtitle: L10n.text("medical.exam_archive.path.no_report.subtitle"),
                action: onSelectNoReport
            )
        }
    }

    // MARK: - 5.2 报告选择

    @ViewBuilder
    static func reportPicker(
        reports: [SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments],
        onSelectReport: @escaping (SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments) -> Void,
        onUploadTapped: @escaping () -> Void,
        onReportAppear: ((Int) -> Void)? = nil,
        isReportLoadingDetails: ((Int) -> Bool)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("medical.exam_archive.report_picker.existing"))
                .font(.headline.weight(.semibold))

            if reports.isEmpty {
                Text(L10n.text("medical.exam_archive.report_picker.empty"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(reports, id: \.id) { report in
                    MemberMedicalExamReportChoiceCard(
                        title: reportTitle(report),
                        subtitle: reportSubtitle(report),
                        detail: report.summary,
                        isLoading: isReportLoadingDetails?(report.id) == true
                    ) {
                        onSelectReport(report)
                    }
                    .task {
                        onReportAppear?(report.id)
                    }
                }
            }

            Button(action: onUploadTapped) {
                Label(L10n.text("medical.exam_archive.report_picker.upload"), systemImage: "camera.viewfinder")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
    }

    // MARK: - 5.3 异常项确认

    @ViewBuilder
    static func abnormalItemsConfirm(
        flowViewModel: MemberMedicalExamArchiveFlowViewModel,
        onEditTapped: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("medical.exam_archive.extract.headline"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(String(format: L10n.text("medical.exam_archive.extract.count"), flowViewModel.abnormalItems.count))
                .font(.headline.weight(.semibold))

            if case .failed(let message) = flowViewModel.loadState {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if flowViewModel.abnormalItems.isEmpty,
               case .loading = flowViewModel.loadState {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }

            ForEach(flowViewModel.abnormalItems) { item in
                MemberMedicalExamAbnormalItemCard(
                    item: item,
                    isSelected: flowViewModel.selectedAbnormalItemIDs.contains(item.id)
                ) {
                    toggleAbnormal(item.id, in: flowViewModel)
                }
            }

            if let onEditTapped {
                Button(L10n.text("medical.exam_archive.action.edit_abnormal")) {
                    onEditTapped()
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - 5.4 随访建议

    @ViewBuilder
    static func followUpTasks(flowViewModel: MemberMedicalExamArchiveFlowViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("medical.exam_archive.follow_up.headline"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(flowViewModel.followUpTasks) { task in
                MemberMedicalExamFollowUpTaskCard(
                    task: task,
                    isSelected: flowViewModel.selectedFollowUpTaskIDs.contains(task.id)
                ) {
                    toggleFollowUp(task.id, in: flowViewModel)
                }
            }
        }
    }

    // MARK: - 5.5 生成中

    @ViewBuilder
    static func planGenerating(isLoading: Bool) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "target")
                .font(.system(size: 52))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 12) {
                checklistRow(L10n.text("medical.exam_archive.generating.item.abnormal"))
                checklistRow(L10n.text("medical.exam_archive.generating.item.lifestyle"))
                checklistRow(L10n.text("medical.exam_archive.generating.item.history"))
                checklistRow(L10n.text("medical.exam_archive.generating.item.symptoms"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isLoading {
                ProgressView()
            }

            Text(L10n.text("medical.exam_archive.generating.hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 12)
    }

    // MARK: - 5.6 无报告价值说明

    @ViewBuilder
    static func baselineIntro() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 10) {
                Text("💡")
                    .font(.title3)
                Text(L10n.text("medical.exam_archive.baseline.headline"))
                    .font(.title3.weight(.bold))
            }

            Text(L10n.text("medical.exam_archive.baseline.profile_hint"))
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                checklistRow(L10n.text("medical.exam_archive.baseline.item.lifestyle"))
                checklistRow(L10n.text("medical.exam_archive.baseline.item.symptoms"))
                checklistRow(L10n.text("medical.exam_archive.baseline.item.history"))
                checklistRow(L10n.text("medical.exam_archive.baseline.item.family"))
            }

            Text(L10n.text("medical.exam_archive.baseline.body"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 5.7 画像依据

    @ViewBuilder
    static func evidenceConfirm(evidence: SparkMedicalExamArchiveAPI.EvidenceSnapshot?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("medical.exam_archive.evidence.subheadline"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            MemberMedicalExamEvidenceCard(
                title: L10n.text("medical.exam_archive.evidence.basic"),
                value: evidence?.basicProfile ?? ""
            )
            MemberMedicalExamEvidenceCard(
                title: L10n.text("medical.exam_archive.evidence.history"),
                value: evidence?.healthHistory ?? ""
            )
            MemberMedicalExamEvidenceCard(
                title: L10n.text("medical.exam_archive.evidence.symptoms"),
                value: evidence?.symptoms ?? ""
            )
            MemberMedicalExamEvidenceCard(
                title: L10n.text("medical.exam_archive.evidence.lifestyle"),
                value: evidence?.lifestyle ?? ""
            )
        }
    }

    // MARK: - 5.8 体检单结果

    @ViewBuilder
    static func planResult(
        plan: SparkMedicalExamArchiveAPI.ExamPlanDraft,
        evidence: SparkMedicalExamArchiveAPI.EvidenceSnapshot?,
        abnormalItems: [SparkMedicalExamArchiveAPI.AbnormalItem],
        sourceReportTitle: String?
    ) -> some View {
        let rationaleRows = MemberMedicalExamArchiveRationaleSupport.buildRows(
            rationale: plan.rationale,
            evidence: evidence,
            abnormalItems: abnormalItems,
            sourceReportTitle: sourceReportTitle
        )

        VStack(alignment: .leading, spacing: 16) {
            if rationaleRows.isEmpty == false {
                MemberMedicalExamPlanRationaleSection(rows: rationaleRows)
            }
            MemberMedicalExamPlanSectionCard(
                title: L10n.text("medical.exam_archive.result.must"),
                items: plan.mustItems
            )
            MemberMedicalExamPlanSectionCard(
                title: L10n.text("medical.exam_archive.result.recommended"),
                items: plan.recommendedItems
            )
            if plan.followUpItems.isEmpty == false {
                MemberMedicalExamPlanSectionCard(
                    title: L10n.text("medical.exam_archive.result.follow_up"),
                    items: plan.followUpItems
                )
            }
            MemberSetupSection(title: L10n.text("medical.exam_archive.result.notice")) {
                Text(plan.riskNotice)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Helpers

    static func reportTitle(_ report: SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments) -> String {
        if let date = report.examDate {
            let year = Calendar.current.component(.year, from: date)
            return String(format: L10n.text("medical.exam_archive.report.title_year"), year)
        }
        return (report.institutionName ?? "").isEmpty
            ? L10n.text("medical.exam_archive.report.title_default")
            : (report.institutionName ?? "")
    }

    static func reportSubtitle(_ report: SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments) -> String {
        let institution = (report.institutionName ?? "").isEmpty
            ? L10n.text("medical.exam_archive.report.unknown_institution")
            : (report.institutionName ?? "")
        if let date = report.examDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM"
            return "\(institution) · \(formatter.string(from: date))"
        }
        return institution
    }

    @ViewBuilder
    private static func checklistRow(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.subheadline)
            .foregroundStyle(.primary)
    }

    private static func toggleAbnormal(_ id: String, in viewModel: MemberMedicalExamArchiveFlowViewModel) {
        if viewModel.selectedAbnormalItemIDs.contains(id) {
            viewModel.selectedAbnormalItemIDs.remove(id)
        } else {
            viewModel.selectedAbnormalItemIDs.insert(id)
        }
    }

    private static func toggleFollowUp(_ id: String, in viewModel: MemberMedicalExamArchiveFlowViewModel) {
        if viewModel.selectedFollowUpTaskIDs.contains(id) {
            viewModel.selectedFollowUpTaskIDs.remove(id)
        } else {
            viewModel.selectedFollowUpTaskIDs.insert(id)
        }
    }
}
