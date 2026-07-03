import SwiftUI
import UIKit

private enum MedicalCaseAddRecordKind: String, Identifiable {
    case symptom, examination, visit, followUp, surgery

    var id: String { rawValue }
}

/// 病例详情页：时间轴 + 头部摘要卡片，视觉对齐 HealthClient `MedicalRecordDetailView` / `TimelineRow`。
struct MedicalCaseDetailPage: View {
    let item: SparkMedicalSyncAPI.RemoteMedicalCaseSummary
    let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    let workflowAPI: SparkMedicalWorkflowAPI
    let fileTransferService: FileTransferService
    @ObservedObject var memberContextStore: MemberContextStore
    let notificationClient: any NotificationClient
    let onUpdated: (SparkMedicalSyncAPI.RemoteMedicalCaseSummary) -> Void
    let onDeleted: (Int) -> Void
    var logger: Logger? = nil
    var onExaminationReportsUpdated: (([SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments]) -> Void)? = nil

    @State private var showingAttachments = false
    @State private var dismissedTimelineEventIDs: Set<String> = []
    @State private var addRecordSheet: MedicalCaseAddRecordKind?
    @State private var currentItem: SparkMedicalSyncAPI.RemoteMedicalCaseSummary
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var exportFileURL: URL?
    @State private var isExporting = false
    @State private var isDeleting = false
    @State private var shareContext: MedicalCaseShareContext?
    @State private var isPreparingShare = false
    @State private var shareErrorMessage: String?
    @Environment(\.dismiss) private var dismiss

    init(
        item: SparkMedicalSyncAPI.RemoteMedicalCaseSummary,
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?,
        workflowAPI: SparkMedicalWorkflowAPI,
        fileTransferService: FileTransferService,
        memberContextStore: MemberContextStore,
        notificationClient: any NotificationClient,
        onUpdated: @escaping (SparkMedicalSyncAPI.RemoteMedicalCaseSummary) -> Void,
        onDeleted: @escaping (Int) -> Void,
        logger: Logger? = nil,
        onExaminationReportsUpdated: (([SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments]) -> Void)? = nil
    ) {
        self.item = item
        self.completeData = completeData
        self.workflowAPI = workflowAPI
        self.fileTransferService = fileTransferService
        self.memberContextStore = memberContextStore
        self.notificationClient = notificationClient
        self.onUpdated = onUpdated
        self.onDeleted = onDeleted
        self.logger = logger
        self.onExaminationReportsUpdated = onExaminationReportsUpdated
        _currentItem = State(initialValue: item)
    }

    private var timelineEvents: [MedicalCaseTimelineEvent] {
        MedicalCaseTimelineEventBuilder.makeEvents(from: currentItem, completeData: completeData)
            .filter { dismissedTimelineEventIDs.contains($0.id) == false }
    }

    private var attachments: [SparkMedicalSyncAPI.RemoteManagedFile] {
        currentItem.attachments ?? []
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MedicalCasePatientHeaderCard(
                        item: currentItem,
                        attachmentsCount: attachments.count,
                        attachmentsExpanded: showingAttachments,
                        onEdit: { openEditSheet() },
                        onToggleAttachments: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showingAttachments.toggle()
                            }
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                        }
                    )

                    timelineSection

                    if showingAttachments, attachments.isEmpty == false {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.text("common.attachments"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(attachments, id: \.id) { attachment in
                                        MedicalCaseAttachmentPill(
                                            attachment: attachment,
                                            fileTransferService: fileTransferService
                                        )
                                    }
                                }
                                .padding(.vertical, 2)
                            }

                            MedicalAttachmentListView(
                                attachments: attachments,
                                fileTransferService: fileTransferService
                            )
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 96)
            }
            .background(Color(uiColor: .systemGroupedBackground))

            addRecordFloatingButton
        }
        .navigationTitle(currentItem.title?.nonEmpty ?? L10n.text("home.medical.list.medical_cases.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        Task { await prepareShareSheet() }
                    } label: {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        exportMedicalCasePDF()
                    } label: {
                        Label(L10n.text("home.medical.case_detail.action.export", fallback: "导出"), systemImage: "square.and.arrow.up")
                    }

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label(L10n.text("common.delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(isDeleting || isExporting || isPreparingShare)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showingAttachments)
        .sheet(isPresented: $showingEditSheet) {
            CompatibleNavigationContainer {
                MedicalCaseFormView(
                    mode: .serverEdit(currentItem, onSaved: handleUpdatedCase),
                    memberContextStore: memberContextStore,
                    workflowAPI: workflowAPI,
                    notificationClient: notificationClient
                )
            }
        }
        .sheet(isPresented: Binding(
            get: { exportFileURL != nil },
            set: { if $0 == false { exportFileURL = nil } }
        )) {
            if let exportFileURL {
                MedicalCaseActivityView(activityItems: [exportFileURL])
            }
        }
        .alert(L10n.text("home.medical.case_detail.delete.title", fallback: "删除病历"), isPresented: $showingDeleteConfirmation) {
            Button(L10n.text("common.cancel"), role: .cancel) {}
            Button(L10n.text("common.delete"), role: .destructive) {
                Task { await deleteMedicalCase() }
            }
        } message: {
            Text(L10n.text("home.medical.case_detail.delete.message", fallback: "删除后列表中将不再显示该病历。"))
        }
        .fullScreenCover(item: $addRecordSheet) { kind in
            CompatibleNavigationContainer {
                medicalCaseAddRecordDestination(kind)
            }
        }
        .sheet(item: $shareContext) { context in
            MedicalCaseShareSheet(context: context) {
                shareContext = nil
            }
        }
        .alert("分享失败", isPresented: Binding(
            get: { shareErrorMessage != nil },
            set: { if $0 == false { shareErrorMessage = nil } }
        )) {
            Button("确定", role: .cancel) {
                shareErrorMessage = nil
            }
        } message: {
            Text(shareErrorMessage ?? "请稍后重试")
        }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("home.medical.case_detail.timeline"))
                .font(.headline)
                .foregroundStyle(.primary)

            if timelineEvents.isEmpty {
                Text(L10n.text("home.medical.case_detail.timeline.empty"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
            } else {
                ForEach(Array(timelineEvents.enumerated()), id: \.element.id) { index, event in
                    MedicalCaseTimelineRow(
                        event: event,
                        isLast: index == timelineEvents.count - 1,
                        memberID: currentItem.member,
                        medicalCaseID: currentItem.id,
                        completeData: completeData,
                        memberContextStore: memberContextStore,
                        workflowAPI: workflowAPI,
                        fileTransferService: fileTransferService,
                        notificationClient: notificationClient,
                        logger: logger,
                        onExaminationReportsUpdated: onExaminationReportsUpdated,
                        onTimelineEventRemoved: { id in
                            dismissedTimelineEventIDs.insert(id)
                        }
                    )
                }
            }
        }
    }

    private var addRecordFloatingButton: some View {
        Menu {
            Button {
                triggerAddRecordHaptic()
                addRecordSheet = .symptom
            } label: {
                Label(L10n.text("home.medical.case_detail.add.menu.symptom"), systemImage: "heart.text.square.fill")
            }
            Button {
                triggerAddRecordHaptic()
                addRecordSheet = .examination
            } label: {
                Label(L10n.text("home.medical.case_detail.add.menu.examination"), systemImage: "waveform.path.ecg")
            }
            Button {
                triggerAddRecordHaptic()
                addRecordSheet = .visit
            } label: {
                Label(L10n.text("home.medical.case_detail.add.menu.visit"), systemImage: "person.crop.circle.badge.clock")
            }
            Button {
                triggerAddRecordHaptic()
                addRecordSheet = .followUp
            } label: {
                Label(L10n.text("home.medical.case_detail.add.menu.follow_up"), systemImage: "calendar.badge.clock")
            }
            Button {
                triggerAddRecordHaptic()
                addRecordSheet = .surgery
            } label: {
                Label(L10n.text("home.medical.case_detail.add.menu.surgery"), systemImage: "scissors")
            }
        } label: {
            Label {
                Text(L10n.text("home.medical.case_detail.add_record"))
            } icon: {
                Image(systemName: "plus")
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.bottom, 28)
    }

    @ViewBuilder
    private func medicalCaseAddRecordDestination(_ kind: MedicalCaseAddRecordKind) -> some View {
        let service = MedicalRecordFormSubmissionService(workflowAPI: workflowAPI)
        let memberID = currentItem.member
        let medicalCaseID = currentItem.id
        switch kind {
        case .symptom:
            SymptomFormView(
                mode: .create(
                    .init(
                        memberID: memberID,
                        medicalCaseID: medicalCaseID,
                        submissionService: service
                    )
                )
            )
        case .examination:
            ExamReportFormView(
                mode: .create(
                    .init(
                        memberID: memberID,
                        medicalCaseID: medicalCaseID,
                        submissionService: service
                    )
                )
            )
        case .visit:
            VisitFormView(
                mode: .create(
                    .init(
                        memberID: memberID,
                        medicalCaseID: medicalCaseID,
                        submissionService: service
                    )
                )
            )
        case .followUp:
            FollowUpFormView(
                mode: .create(
                    .init(
                        memberID: memberID,
                        medicalCaseID: medicalCaseID,
                        submissionService: service
                    )
                )
            )
        case .surgery:
            SurgeryFormView(
                mode: .create(
                    .init(
                        memberID: memberID,
                        medicalCaseID: medicalCaseID,
                        submissionService: service
                    )
                )
            )
        }
    }

    private func triggerAddRecordHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    private func openEditSheet() {
        performEditFeedback()
        showingEditSheet = true
    }

    private func handleUpdatedCase(_ updated: SparkMedicalSyncAPI.RemoteMedicalCaseSummary) {
        currentItem = updated
        onUpdated(updated)
    }

    private func exportMedicalCasePDF() {
        Task { await exportMedicalCasePDFAsync() }
    }

    @MainActor
    private func exportMedicalCasePDFAsync() async {
        guard isExporting == false else { return }
        isExporting = true
        defer { isExporting = false }

        do {
            exportFileURL = try await MedicalCasePDFExporter.makePDF(
                item: currentItem,
                completeData: completeData,
                timelineEvents: timelineEvents,
                attachments: attachments,
                fileTransferService: fileTransferService
            )
        } catch {
            notificationClient.error(error.localizedDescription, title: L10n.text("home.medical.case_detail.export.failed", fallback: "导出失败"), source: "medical.case.detail")
        }
    }

    @MainActor
    private func deleteMedicalCase() async {
        guard isDeleting == false else { return }
        isDeleting = true
        defer { isDeleting = false }

        do {
            try await MedicalCaseMutationService(workflowAPI: workflowAPI).delete(id: currentItem.id)
            notificationClient.success(L10n.text("home.medical.case_detail.delete.success", fallback: "病历已删除"), source: "medical.case.detail")
            onDeleted(currentItem.id)
            dismiss()
        } catch {
            notificationClient.error(error.localizedDescription, title: L10n.text("home.medical.case_detail.delete.failed", fallback: "删除失败"), source: "medical.case.detail")
        }
    }

    @MainActor
    private func prepareShareSheet() async {
        guard isPreparingShare == false else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }

        do {
            let shareAPI = SparkMedicalShareAPI(configuration: workflowAPI.configuration)
            let response = try await shareAPI.createMedicalCaseShare(caseID: currentItem.id)
            let shareURL = AppEnvironment.current.shareWebBaseURL
                .appendingPathComponent("s")
                .appendingPathComponent(response.shareCode)
            shareContext = MedicalCaseShareContext(
                caseTitle: currentItem.title?.nonEmpty ?? "病例详情",
                memberName: completeData?.member.name ?? memberContextStore.context.members.first(where: { $0.id == currentItem.member })?.name ?? "成员",
                shareURL: shareURL,
                expiresAt: response.expiresAt
            )
        } catch {
            shareErrorMessage = error.localizedDescription.isEmpty ? "生成分享失败" : error.localizedDescription
        }
    }

    /// 执行编辑操作时的触觉反馈（震动效果）
    private func performEditFeedback() {
        // 创建触觉反馈生成器，设置震动样式为中等强度
        let generator = UIImpactFeedbackGenerator(style: .medium)
        // 触发震动反馈
        generator.impactOccurred()
    }
}

// MARK: - Header card（对齐 HealthClient `PatientHeaderCard` 信息层级）

private struct MedicalCasePatientHeaderCard: View {
    let item: SparkMedicalSyncAPI.RemoteMedicalCaseSummary
    let attachmentsCount: Int
    let attachmentsExpanded: Bool
    let onEdit: () -> Void
    let onToggleAttachments: () -> Void

    private var style: MedicalCaseHeaderSeverityStyle {
        MedicalCaseHeaderSeverityStyle(severity: headerSeverity(for: item.status))
    }

    private var recordStatus: MedicalCaseCardStatus {
        guard let status = item.status else { return .empty }
        switch status {
        case 0:
            return .pendingDiagnosis
        case 1:
            return .inTreatment
        case 2:
            return .review
        case 3:
            return .chronicManagement
        case 4:
            return .cured
        default:
            return .unknown
        }
    }

    private var dateText: String {
        let date = item.updatedAt ?? item.createdAt ?? .now
        return Self.dateFormatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "stethoscope")
                    .font(.caption)
                    .foregroundStyle(style.accent)
                Text(L10n.text("home.medical.list.medical_case.chief_complaint"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(style.accent)
                Text(item.title?.nonEmpty ?? L10n.text("home.medical.list.fallback.no_summary"))
                    .font(.subheadline)
                    .foregroundStyle(style.textStrong)
                Spacer(minLength: 0)

                Button(action: onEdit) {
                    Label(L10n.text("home.medical.case_detail.edit"), systemImage: "pencil")
                        .font(.subheadline)
                        .foregroundStyle(style.accent)
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("home.medical.list.medical_case.diagnosis"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(style.textSecondary)
                    Text(item.diagnosisSummary?.nonEmpty ?? L10n.text("home.medical.list.fallback.no_summary"))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(style.textStrong)
                }

                Spacer(minLength: 0)

                if attachmentsCount > 0 {
                    MedicalAttachmentIconView(count: attachmentsCount, isExpanded: attachmentsExpanded) {
                        onToggleAttachments()
                    }
                }
            }

            HStack {
                if recordStatus != .empty {
                    MedicalCaseStatusPill(text: recordStatus.displayName, tint: statusTint(recordStatus))
                }
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                    Text(dateText)
                }
                .font(.footnote)
                .foregroundStyle(style.textSecondary)
                .monospacedDigit()
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(L10n.text("home.medical.list.medical_case.updated_at"))\(dateText)")
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(style.cardBG)
        )
        .overlay(alignment: .leading) {
            Capsule()
                .fill(style.accent)
                .frame(width: 4)
                .padding(.vertical, 10)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    private func headerSeverity(for status: Int?) -> MedicalCaseCardSeverity {
        switch status {
        case 0:
            return .high
        case 4:
            return .low
        default:
            return .medium
        }
    }

    private func statusTint(_ status: MedicalCaseCardStatus) -> Color {
        switch status {
        case .empty:
            return .clear
        case .chronicManagement:
            return Color(uiColor: .systemGray5)
        case .inTreatment:
            return Color(uiColor: .systemBlue).opacity(0.15)
        case .review:
            return Color(uiColor: .systemTeal).opacity(0.15)
        case .cured:
            return Color(uiColor: .systemGreen).opacity(0.15)
        case .pendingDiagnosis:
            return Color(uiColor: .systemOrange).opacity(0.15)
        case .unknown:
            return Color(uiColor: .systemGray5)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct MedicalCaseStatusPill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint)
            )
            .foregroundStyle(.primary)
    }
}

private enum MedicalCaseCardStatus {
    case chronicManagement
    case inTreatment
    case review
    case cured
    case pendingDiagnosis
    case empty
    case unknown

    var displayName: String {
        switch self {
        case .empty:
            return ""
        case .chronicManagement:
            return L10n.text("home.medical.list.medical_case.status.chronic_management")
        case .inTreatment:
            return L10n.text("home.medical.list.medical_case.status.in_treatment")
        case .review:
            return L10n.text("home.medical.list.medical_case.status.review")
        case .cured:
            return L10n.text("home.medical.list.medical_case.status.cured")
        case .pendingDiagnosis:
            return L10n.text("home.medical.list.medical_case.status.pending_diagnosis")
        case .unknown:
            return L10n.text("home.medical.list.medical_case.status.unknown")
        }
    }
}

private enum MedicalCaseCardSeverity {
    case low
    case medium
    case high
}

private struct MedicalCaseHeaderSeverityStyle {
    let severity: MedicalCaseCardSeverity

    var accent: Color {
        switch severity {
        case .low:
            return Color(uiColor: .systemTeal)
        case .medium:
            return Color(uiColor: .systemOrange)
        case .high:
            return Color(uiColor: .systemRed)
        }
    }

    var cardBG: Color { accent.opacity(0.06) }
    var border: Color { accent.opacity(0.25) }
    var textStrong: Color { .primary }
    var textSecondary: Color { .secondary }
}

// MARK: - Preview

private extension SparkMedicalSyncAPI.RemoteMedicalCaseSummary {
    static var previewSample: SparkMedicalSyncAPI.RemoteMedicalCaseSummary {
        SparkMedicalSyncAPI.RemoteMedicalCaseSummary(
            id: 42,
            member: 7,
            recordType: "outpatient",
            status: 1,
            title: "头痛、发热 3 天",
            hospitalName: "仁和医院",
            ageAtVisit: 38,
            diagnosisSummary: "上呼吸道感染",
            extra: nil,
            createdAt: Date(),
            updatedAt: Date(),
            symptoms: ["发热", "咽痛"],
            medications: ["布洛芬缓释胶囊", "维生素C"],
            attachments: []
        )
    }
}

#Preview("Medical case detail — Light") {
    CompatibleNavigationContainer {
        MedicalCaseDetailPage(
            item: .previewSample,
            completeData: nil,
            workflowAPI: AppContainer.preview.backend.medicalWorkflow,
            fileTransferService: AppContainer.preview.fileTransferService,
            memberContextStore: AppContainer.preview.memberContextStore,
            notificationClient: AppContainer.preview.notificationClient,
            onUpdated: { _ in },
            onDeleted: { _ in }
        )
    }
    .preferredColorScheme(.light)
}

#Preview("Medical case detail — Dark") {
    CompatibleNavigationContainer {
        MedicalCaseDetailPage(
            item: .previewSample,
            completeData: nil,
            workflowAPI: AppContainer.preview.backend.medicalWorkflow,
            fileTransferService: AppContainer.preview.fileTransferService,
            memberContextStore: AppContainer.preview.memberContextStore,
            notificationClient: AppContainer.preview.notificationClient,
            onUpdated: { _ in },
            onDeleted: { _ in }
        )
    }
    .preferredColorScheme(.dark)
}
