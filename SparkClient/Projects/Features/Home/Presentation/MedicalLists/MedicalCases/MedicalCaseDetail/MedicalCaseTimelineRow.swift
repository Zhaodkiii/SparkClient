import SwiftUI
import UIKit

/// 对齐 HealthClient `TimelineRow`：左侧色环图标 + 竖线 + 右侧强调卡片。
struct MedicalCaseTimelineRow: View {
    let event: MedicalCaseTimelineEvent
    let isLast: Bool
    let memberID: Int
    let medicalCaseID: Int
    let workflowAPI: SparkMedicalWorkflowAPI
    let fileTransferService: FileTransferService
    var onTimelineEventRemoved: ((String) -> Void)?

    private var shell: MedicalCaseTimelinePalette {
        event.kind.palette
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private var dateText: String {
        Self.dateFormatter.string(from: event.date)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(shell.tint)
                Image(systemName: shell.iconName)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 40, height: 40)
            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
            .overlay(
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 2)
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(dateText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Spacer(minLength: 0)

                    if let badge = event.statusBadgeText, badge.isEmpty == false {
                        MedicalCaseSeverityBadge(
                            text: badge,
                            tint: Color(uiColor: .systemOrange)
                        )
                    }

                    if let route = event.editRoute {
                        NavigationLink {
                            MedicalCaseTimelineEditDestination(
                                route: route,
                                memberID: memberID,
                                medicalCaseID: medicalCaseID,
                                workflowAPI: workflowAPI,
                                eventID: event.id,
                                onRecordRemoved: { id in
                                    onTimelineEventRemoved?(id)
                                }
                            )
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(6)
                                .background(Color(uiColor: .secondarySystemFill))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.text("home.medical.case_detail.edit"))
                    }
                }

                timelineCard
            }
        }
        .overlay(alignment: .leading) {
            if isLast == false {
                let centerX: CGFloat = 20
                Rectangle()
                    .fill(Color.secondary.opacity(0.22))
                    .frame(width: 1)
                    .offset(x: centerX)
                    .padding(.top, 52)
            }
        }
    }

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(event.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            if event.kind == .prescription, let prescription = event.prescription {
                prescriptionBody(prescription: prescription, medications: event.nestedMedications ?? [])
            } else {
                if event.detail.isEmpty == false {
                    Text(event.detail)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(shell.border, lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(shell.tint, lineWidth: 3)
                        .mask(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(lineWidth: 3)
                                .padding(.leading, -200)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        )
                        .opacity(0.9)
                )
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    private func prescriptionBody(
        prescription: SparkMedicalSyncAPI.RemotePrescriptionBatchComplete,
        medications: [SparkMedicalSyncAPI.RemoteMedication]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if (prescription.diagnosis ?? "").isEmpty == false {
                Text((prescription.diagnosis ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let count = medications.count
            if count > 0 {
                Text(String(format: L10n.text("home.medical.timeline.prescription.medication_count"), count))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    ForEach(medications, id: \.id) { med in
                        MedicalCaseMedicationInlineRow(medication: med)
                    }
                }
            }

            if let attachments = prescription.attachments, attachments.isEmpty == false {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachments, id: \.id) { attachment in
                            MedicalCaseAttachmentPill(
                                attachment: attachment,
                                fileTransferService: fileTransferService
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct MedicalCaseMedicationInlineRow: View {
    let medication: SparkMedicalSyncAPI.RemoteMedication

    private var secondaryLine: String {
        [medication.strength.nilIfBlank, medication.frequencyText.nilIfBlank]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "pills.fill")
                .font(.caption)
                .foregroundStyle(Color(uiColor: .systemIndigo))
            VStack(alignment: .leading, spacing: 2) {
                Text(medication.drugName.nilIfBlank ?? medication.genericName.nilIfBlank ?? "—")
                    .font(.callout)
                    .foregroundStyle(.primary)
                if secondaryLine.isEmpty == false {
                    Text(secondaryLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color(uiColor: .systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

#Preview("Timeline row — Light") {
    let event = MedicalCaseTimelineEvent(
        id: "1",
        kind: .symptom,
        title: "头痛",
        detail: "持续 3 天，伴发热",
        date: Date(),
        statusBadgeText: "治疗中"
    )
    MedicalCaseTimelineRow(
        event: event,
        isLast: false,
        memberID: 1,
        medicalCaseID: 1,
        workflowAPI: AppContainer.preview.backend.medicalWorkflow,
        fileTransferService: AppContainer.preview.fileTransferService,
        onTimelineEventRemoved: nil
    )
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Timeline row — Dark") {
    let event = MedicalCaseTimelineEvent(
        id: "1",
        kind: .symptom,
        title: "头痛",
        detail: "持续 3 天，伴发热",
        date: Date(),
        statusBadgeText: "治疗中"
    )
    MedicalCaseTimelineRow(
        event: event,
        isLast: false,
        memberID: 1,
        medicalCaseID: 1,
        workflowAPI: AppContainer.preview.backend.medicalWorkflow,
        fileTransferService: AppContainer.preview.fileTransferService,
        onTimelineEventRemoved: nil
    )
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Timeline row — prescription — Light") {
    let med = SparkMedicalSyncAPI.RemoteMedication(
        id: 9,
        member: 1,
        batch: 3,
        genericName: "布洛芬",
        brandName: "",
        drugName: "布洛芬缓释胶囊",
        dosageForm: "胶囊",
        strength: "300mg",
        route: "口服",
        dosePerTime: "1 粒",
        doseValue: 1,
        doseUnit: "粒",
        frequencyCode: "BID",
        period: "日",
        timesPerPeriod: 2,
        frequencyText: "每日 2 次",
        durationDays: 5,
        instructions: "饭后服",
        reminderEnabled: false,
        reminderTimes: [],
        sortOrder: 0,
        extra: nil,
        updatedAt: Date()
    )
    let batch = SparkMedicalSyncAPI.RemotePrescriptionBatchComplete(
        id: 3,
        member: 1,
        medicalCase: 42,
        prescriberName: "王医生",
        institutionName: "仁和医院",
        prescribedAt: Date(),
        diagnosis: "上呼吸道感染",
        batchNo: "RX-1001",
        status: "active",
        auditorName: nil,
        auditedAt: nil,
        extra: nil,
        createdAt: Date(),
        updatedAt: Date(),
        medications: [med],
        attachments: []
    )
    let event = MedicalCaseTimelineEvent(
        id: "prescription-3",
        kind: .prescription,
        title: batch.institutionName ?? "",
        detail: batch.diagnosis ?? "",
        date: Date(),
        statusBadgeText: "治疗中",
        prescription: batch,
        nestedMedications: batch.medications,
        editRoute: .prescription(batch)
    )
    MedicalCaseTimelineRow(
        event: event,
        isLast: true,
        memberID: 1,
        medicalCaseID: 42,
        workflowAPI: AppContainer.preview.backend.medicalWorkflow,
        fileTransferService: AppContainer.preview.fileTransferService,
        onTimelineEventRemoved: nil
    )
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Timeline row — prescription — Dark") {
    let med = SparkMedicalSyncAPI.RemoteMedication(
        id: 9,
        member: 1,
        batch: 3,
        genericName: "布洛芬",
        brandName: "",
        drugName: "布洛芬缓释胶囊",
        dosageForm: "胶囊",
        strength: "300mg",
        route: "口服",
        dosePerTime: "1 粒",
        doseValue: 1,
        doseUnit: "粒",
        frequencyCode: "BID",
        period: "日",
        timesPerPeriod: 2,
        frequencyText: "每日 2 次",
        durationDays: 5,
        instructions: "饭后服",
        reminderEnabled: false,
        reminderTimes: [],
        sortOrder: 0,
        extra: nil,
        updatedAt: Date()
    )
    let batch = SparkMedicalSyncAPI.RemotePrescriptionBatchComplete(
        id: 3,
        member: 1,
        medicalCase: 42,
        prescriberName: "王医生",
        institutionName: "仁和医院",
        prescribedAt: Date(),
        diagnosis: "上呼吸道感染",
        batchNo: "RX-1001",
        status: "active",
        auditorName: nil,
        auditedAt: nil,
        extra: nil,
        createdAt: Date(),
        updatedAt: Date(),
        medications: [med],
        attachments: []
    )
    let event = MedicalCaseTimelineEvent(
        id: "prescription-3",
        kind: .prescription,
        title: batch.institutionName ?? "",
        detail: batch.diagnosis ?? "",
        date: Date(),
        statusBadgeText: "治疗中",
        prescription: batch,
        nestedMedications: batch.medications,
        editRoute: .prescription(batch)
    )
    MedicalCaseTimelineRow(
        event: event,
        isLast: true,
        memberID: 1,
        medicalCaseID: 42,
        workflowAPI: AppContainer.preview.backend.medicalWorkflow,
        fileTransferService: AppContainer.preview.fileTransferService,
        onTimelineEventRemoved: nil
    )
    .padding()
    .preferredColorScheme(.dark)
}
