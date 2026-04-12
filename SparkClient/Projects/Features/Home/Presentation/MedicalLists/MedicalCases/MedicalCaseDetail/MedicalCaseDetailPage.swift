import SwiftUI
import UIKit

/// 病例详情页：时间轴 + 头部摘要卡片，视觉对齐 HealthClient `MedicalRecordDetailView` / `TimelineRow`。
struct MedicalCaseDetailPage: View {
    let item: SparkMedicalSyncAPI.RemoteMedicalCaseSummary
    let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    let workflowAPI: SparkMedicalWorkflowAPI
    let fileTransferService: FileTransferService

    @State private var showingAttachments = false
    @State private var dismissedTimelineEventIDs: Set<String> = []

    private var timelineEvents: [MedicalCaseTimelineEvent] {
        MedicalCaseTimelineEventBuilder.makeEvents(from: item, completeData: completeData)
            .filter { dismissedTimelineEventIDs.contains($0.id) == false }
    }

    private var attachments: [SparkMedicalSyncAPI.RemoteManagedFile] {
        item.attachments ?? []
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MedicalCasePatientHeaderCard(
                        item: item,
                        attachmentsCount: attachments.count,
                        attachmentsExpanded: showingAttachments,
                        onEdit: { performEditFeedback() },
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
                            Text(L10n.text("home.medical.attachments.title"))
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
        .navigationTitle(item.title?.nonEmpty ?? L10n.text("home.medical.list.medical_cases.title"))
        .navigationBarTitleDisplayMode(.inline)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showingAttachments)
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
                        memberID: item.member,
                        medicalCaseID: item.id,
                        workflowAPI: workflowAPI,
                        fileTransferService: fileTransferService,
                        onTimelineEventRemoved: { id in
                            dismissedTimelineEventIDs.insert(id)
                        }
                    )
                }
            }
        }
    }

    private var addRecordFloatingButton: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
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

    private func performEditFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
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
    NavigationView {
        MedicalCaseDetailPage(
            item: .previewSample,
            completeData: nil,
            workflowAPI: AppContainer.preview.backend.medicalWorkflow,
            fileTransferService: AppContainer.preview.fileTransferService
        )
    }
    .preferredColorScheme(.light)
}

#Preview("Medical case detail — Dark") {
    NavigationView {
        MedicalCaseDetailPage(
            item: .previewSample,
            completeData: nil,
            workflowAPI: AppContainer.preview.backend.medicalWorkflow,
            fileTransferService: AppContainer.preview.fileTransferService
        )
    }
    .preferredColorScheme(.dark)
}
