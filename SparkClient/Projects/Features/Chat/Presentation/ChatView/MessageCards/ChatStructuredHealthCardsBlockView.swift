import SwiftUI

/// 对话内四类结构化医疗卡片容器（保存按钮 + 摘要展示），数据来自 `structured_health_cards` 附件。
struct ChatStructuredHealthCardsBlockView: View {
    let blob: StructuredHealthCardsBlob
    let isSavingIDs: Set<UUID>
    let onSaveMedication: (MedicationChatCardPayload) -> Void
    let onSavePrescription: (PrescriptionChatCardPayload) -> Void
    let onSaveExamReport: (ExamReportChatCardPayload) -> Void
    let onSaveMedicalCase: (MedicalCaseChatCardPayload) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if blob.medications.isEmpty == false {
                sectionHeader("chat.medical_card.section.medications", systemImage: "pills.fill", tint: .green)
                ForEach(blob.medications) { card in
                    medicalRow(
                        title: card.displayName,
                        subtitle: [card.specification, card.dosageLine].compactMap { $0 }.joined(separator: "\n"),
                        isSaved: card.isSaved,
                        isSaving: isSavingIDs.contains(card.id)
                    ) {
                        onSaveMedication(card)
                    }
                }
            }
            if blob.prescriptions.isEmpty == false {
                sectionHeader("chat.medical_card.section.prescriptions", systemImage: "doc.text.fill", tint: .blue)
                ForEach(blob.prescriptions) { card in
                    medicalRow(
                        title: card.title,
                        subtitle: card.subtitle,
                        isSaved: card.isSaved,
                        isSaving: isSavingIDs.contains(card.id)
                    ) {
                        onSavePrescription(card)
                    }
                }
            }
            if blob.examReports.isEmpty == false {
                sectionHeader("chat.medical_card.section.exam_reports", systemImage: "cross.case.fill", tint: .orange)
                ForEach(blob.examReports) { card in
                    medicalRow(
                        title: card.title,
                        subtitle: [card.hospital, card.dateText].compactMap { $0 }.joined(separator: " · "),
                        isSaved: card.isSaved,
                        isSaving: isSavingIDs.contains(card.id)
                    ) {
                        onSaveExamReport(card)
                    }
                }
            }
            if blob.medicalCases.isEmpty == false {
                sectionHeader("chat.medical_card.section.cases", systemImage: "heart.text.square.fill", tint: .purple)
                ForEach(blob.medicalCases) { card in
                    medicalRow(
                        title: card.title,
                        subtitle: card.diagnosisLine,
                        isSaved: card.isSaved,
                        isSaving: isSavingIDs.contains(card.id)
                    ) {
                        onSaveMedicalCase(card)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionHeader(_ key: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(L10n.text(key))
                .font(.subheadline.weight(.semibold))
            Spacer()
        }
    }

    private func medicalRow(
        title: String,
        subtitle: String?,
        isSaved: Bool,
        isSaving: Bool,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            if let subtitle, subtitle.isEmpty == false {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                if isSaved {
                    Label(L10n.text("chat.medical_card.saved"), systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Button(action: action) {
                        HStack {
                            if isSaving {
                                ProgressView().scaleEffect(0.85)
                            } else {
                                Image(systemName: "square.and.arrow.down")
                                Text(L10n.text("chat.medical_card.save_to_health"))
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                }
            }
        }
        .padding(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }
}
