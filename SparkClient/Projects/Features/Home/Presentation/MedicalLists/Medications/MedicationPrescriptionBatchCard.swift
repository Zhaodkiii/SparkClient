import SwiftUI

/// 处方卡片：与 HealthClient 结构保持一致，优先展示头部、诊断、药品列表、附件与关联病例区。
struct MedicationPrescriptionBatchCard: View {
    let item: SparkMedicalSyncAPI.RemotePrescriptionBatchComplete
    let fileTransferService: FileTransferService

    @State private var showMedications = true

    private var medications: [SparkMedicalSyncAPI.RemoteMedication] {
        item.medications ?? []
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    private var dateText: String {
        guard let prescribedAt = item.prescribedAt else { return "" }
        return Self.dateFormatter.string(from: prescribedAt)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(16)
                .background(Color(uiColor: .systemBackground))
                .overlay(alignment: .bottom) {
                    Divider()
                        .background(Color(uiColor: .separator).opacity(0.12))
                }

            contentSection
                .padding(16)
                .background(Color(uiColor: .systemBackground))

            linkedMedicalCaseSection
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .systemBackground).opacity(0.72))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 2)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showMedications)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(uiColor: .systemPurple), Color(uiColor: .systemIndigo)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)

                Image(systemName: "doc.text.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(item.institutionName?.nonEmpty ?? "")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let prescriberName = item.prescriberName?.nonEmpty {
                        Text(prescriberName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(uiColor: .systemPurple).opacity(0.18), in: Capsule())
                    }

                    if let batchNo = item.batchNo?.nonEmpty {
                        Text(String(format: L10n.text("home.medical.list.medications.batch_no"), batchNo))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Text(dateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                NavigationLink {
                    PrescriptionBatchDetailPage(
                        item: item,
                        fileTransferService: fileTransferService
                    )
                    .hidesMainTabBarWhenPushed()
                } label: {
                    HStack(spacing: 4) {
                        Text(L10n.text("home.medical.list.medications.view_detail"))
                            .font(.caption.weight(.medium))
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Content

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let diagnosis = item.diagnosis?.nonEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("home.medical.list.medications.diagnosis"))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    Text(diagnosis)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineSpacing(2)
                }
                .padding(10)
                .background(Color(uiColor: .systemBlue).opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(uiColor: .systemBlue).opacity(0.2), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Divider()
                .padding(.vertical, 8)

            HStack {
                Text(String(format: L10n.text("home.medical.list.medications.in_batch_count"), medications.count))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    showMedications.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet.clipboard")
                            .font(.footnote)
                        Text(L10n.text("home.medical.list.medications.manage"))
                            .font(.footnote)
                    }
                    .foregroundStyle(Color(uiColor: .systemPurple))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Color(uiColor: .systemPurple).opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 4)

            if showMedications, medications.isEmpty == false {
                VStack(spacing: 8) {
                    ForEach(medications, id: \.id) { medication in
                        MedicationBatchItemCard(item: medication)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let attachments = item.attachments, attachments.isEmpty == false {
                Divider()
                    .padding(.vertical, 8)

                HStack(spacing: 8) {
                    Image(systemName: "paperclip")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(String(format: L10n.text("home.medical.list.medications.attachments_count"), attachments.count))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                MedicalAttachmentListView(
                    attachments: attachments,
                    fileTransferService: fileTransferService
                )
            }
        }
    }

    // MARK: - Link Section

    private var linkedMedicalCaseSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .opacity(0.35)
                .padding(.horizontal, 16)

            HStack(spacing: 14) {
                Image(systemName: item.medicalCase != nil ? "link.circle.fill" : "link.badge.plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(item.medicalCase != nil ? Color.accentColor : Color.secondary)
                    .frame(width: 40, height: 40)
                    .background(
                        (item.medicalCase != nil ? Color.accentColor : Color.secondary).opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        item.medicalCase != nil
                            ? L10n.text("home.medical.list.medications.linked_case.title")
                            : L10n.text("home.medical.list.medications.unlinked_case.title")
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                    Text(
                        item.medicalCase != nil
                            ? L10n.text("home.medical.list.medications.linked_case.subtitle")
                            : L10n.text("home.medical.list.medications.unlinked_case.subtitle")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.secondary.opacity(0.8))
            }
            .padding(16)
        }
    }
}

private struct MedicationBatchItemCard: View {
    let item: SparkMedicalSyncAPI.RemoteMedication

    private var statusTint: Color {
        if item.durationDays == 0 {
            return Color(uiColor: .systemGray)
        }
        if item.reminderEnabled == false && item.reminderTimes.isEmpty {
            return Color(uiColor: .systemOrange)
        }
        return Color(uiColor: .systemGreen)
    }

    private var statusText: String {
        if item.durationDays == 0 {
            return L10n.text("home.medical.list.medications.status.completed")
        }
        if item.reminderEnabled == false && item.reminderTimes.isEmpty {
            return L10n.text("home.medical.list.medications.status.paused")
        }
        return L10n.text("home.medical.list.medications.status.active")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.drugName.nonEmpty ?? item.genericName.nonEmpty ?? "")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                Spacer()

                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusTint.opacity(0.15), in: Capsule())
                    .foregroundStyle(statusTint)
            }

            HStack {
                Text(String(format: L10n.text("home.medical.list.medications.specification_value"), item.strength.nonEmpty ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(String(format: L10n.text("home.medical.list.medications.dose_value"), item.dosePerTime.nonEmpty ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if item.frequencyText.nonEmpty != nil {
                Text(String(format: L10n.text("home.medical.list.medications.frequency_value"), item.frequencyText))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            Color(uiColor: .systemGray6),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }
}
