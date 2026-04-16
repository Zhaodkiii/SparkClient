import SwiftUI

struct ChatMedicationCardListView: View {
    let cards: [ChatMedicationCardPayload]
    let isSaving: (UUID) -> Bool
    let onSave: (ChatMedicationCardPayload) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("chat.medical.card.medication.title"))
                .font(.headline)
            ForEach(cards) { card in
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.name).font(.subheadline.weight(.semibold))
                    if let dosage = card.dosage, dosage.isEmpty == false {
                        Text("\(L10n.text("chat.medical.card.field.dosage"))：\(dosage)").font(.caption).foregroundStyle(.secondary)
                    }
                    if let frequency = card.frequency, frequency.isEmpty == false {
                        Text("\(L10n.text("chat.medical.card.field.frequency"))：\(frequency)").font(.caption).foregroundStyle(.secondary)
                    }
                    if let instructions = card.instructions, instructions.isEmpty == false {
                        Text(instructions).font(.caption).foregroundStyle(.secondary)
                    }
                    saveButton(card: card)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: .systemBackground)))
            }
        }
    }

    @ViewBuilder
    private func saveButton(card: ChatMedicationCardPayload) -> some View {
        let saving = isSaving(card.id)
        let saved = card.isSaved
        Button {
            onSave(card)
        } label: {
            HStack(spacing: 4) {
                if saving {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: saved ? "checkmark.circle.fill" : "square.and.arrow.down")
                }
                Text(saved ? L10n.text("chat.medical.card.action.saved") : L10n.text("chat.medical.card.action.save_bind_current_member"))
            }
            .font(.caption)
            .foregroundStyle(saved ? Color.blue : Color.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(saved ? Color.blue.opacity(0.12) : Color.blue))
        }
        .buttonStyle(.plain)
        .disabled(saved || saving)
        .padding(.top, 4)
    }
}

struct ChatPrescriptionCardListView: View {
    let cards: [ChatPrescriptionCardPayload]
    let isSaving: (UUID) -> Bool
    let onSave: (ChatPrescriptionCardPayload) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("chat.medical.card.prescription.title"))
                .font(.headline)
            ForEach(cards) { card in
                VStack(alignment: .leading, spacing: 4) {
                    Text((card.batchNo?.isEmpty == false ? card.batchNo : L10n.text("chat.medical.card.prescription.fallback")) ?? L10n.text("chat.medical.card.prescription.fallback")).font(.subheadline.weight(.semibold))
                    if let institutionName = card.institutionName, institutionName.isEmpty == false {
                        Text(institutionName).font(.caption).foregroundStyle(.secondary)
                    }
                    if let prescribedAt = card.prescribedAt, prescribedAt.isEmpty == false {
                        Text("\(L10n.text("chat.medical.card.field.prescribed_at"))：\(prescribedAt)").font(.caption).foregroundStyle(.secondary)
                    }
                    if let diagnosis = card.diagnosis, diagnosis.isEmpty == false {
                        Text("\(L10n.text("chat.medical.card.field.diagnosis"))：\(diagnosis)").font(.caption).foregroundStyle(.secondary)
                    }
                    if card.medications.isEmpty == false {
                        Text("\(L10n.text("chat.medical.card.field.medication_count"))：\(card.medications.count)").font(.caption2).foregroundStyle(.tertiary)
                    }
                    saveButton(card: card)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: .systemBackground)))
            }
        }
    }

    @ViewBuilder
    private func saveButton(card: ChatPrescriptionCardPayload) -> some View {
        let saving = isSaving(card.id)
        let saved = card.isSaved
        Button {
            onSave(card)
        } label: {
            HStack(spacing: 4) {
                if saving {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: saved ? "checkmark.circle.fill" : "square.and.arrow.down")
                }
                Text(saved ? L10n.text("chat.medical.card.action.saved") : L10n.text("chat.medical.card.action.save_bind_current_member"))
            }
            .font(.caption)
            .foregroundStyle(saved ? Color.blue : Color.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(saved ? Color.blue.opacity(0.12) : Color.blue))
        }
        .buttonStyle(.plain)
        .disabled(saved || saving)
        .padding(.top, 4)
    }
}

struct ChatExamReportCardListView: View {
    let cards: [ChatExamReportCardPayload]
    let isSaving: (UUID) -> Bool
    let onSave: (ChatExamReportCardPayload) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("chat.medical.card.exam_report.title"))
                .font(.headline)
            ForEach(cards) { card in
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.title).font(.subheadline.weight(.semibold))
                    if let hospital = card.hospital, hospital.isEmpty == false {
                        Text(hospital).font(.caption).foregroundStyle(.secondary)
                    }
                    if let date = card.date, date.isEmpty == false {
                        Text("\(L10n.text("chat.medical.card.field.date"))：\(date)").font(.caption).foregroundStyle(.secondary)
                    }
                    if let conclusion = card.conclusion, conclusion.isEmpty == false {
                        Text(conclusion).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                    saveButton(card: card)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: .systemBackground)))
            }
        }
    }

    @ViewBuilder
    private func saveButton(card: ChatExamReportCardPayload) -> some View {
        let saving = isSaving(card.id)
        let saved = card.isSaved
        Button {
            onSave(card)
        } label: {
            HStack(spacing: 4) {
                if saving {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: saved ? "checkmark.circle.fill" : "square.and.arrow.down")
                }
                Text(saved ? L10n.text("chat.medical.card.action.saved") : L10n.text("chat.medical.card.action.save_bind_current_member"))
            }
            .font(.caption)
            .foregroundStyle(saved ? Color.blue : Color.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(saved ? Color.blue.opacity(0.12) : Color.blue))
        }
        .buttonStyle(.plain)
        .disabled(saved || saving)
        .padding(.top, 4)
    }
}

struct ChatMedicalCaseCardListView: View {
    let cards: [ChatMedicalCaseCardPayload]
    let isSaving: (UUID) -> Bool
    let onSave: (ChatMedicalCaseCardPayload) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("chat.medical.card.medical_case.title"))
                .font(.headline)
            ForEach(cards) { card in
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.title).font(.subheadline.weight(.semibold))
                    if let summary = card.summary, summary.isEmpty == false {
                        Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                    if let diagnosis = card.diagnosis, diagnosis.isEmpty == false {
                        Text("\(L10n.text("chat.medical.card.field.diagnosis"))：\(diagnosis)").font(.caption).foregroundStyle(.secondary)
                    }
                    if let hospitalName = card.hospitalName, hospitalName.isEmpty == false {
                        Text("\(L10n.text("chat.medical.card.field.hospital"))：\(hospitalName)").font(.caption).foregroundStyle(.secondary)
                    }
                    saveButton(card: card)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: .systemBackground)))
            }
        }
    }

    @ViewBuilder
    private func saveButton(card: ChatMedicalCaseCardPayload) -> some View {
        let saving = isSaving(card.id)
        let saved = card.isSaved
        Button {
            onSave(card)
        } label: {
            HStack(spacing: 4) {
                if saving {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: saved ? "checkmark.circle.fill" : "square.and.arrow.down")
                }
                Text(saved ? L10n.text("chat.medical.card.action.saved") : L10n.text("chat.medical.card.action.save_bind_current_member"))
            }
            .font(.caption)
            .foregroundStyle(saved ? Color.blue : Color.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(saved ? Color.blue.opacity(0.12) : Color.blue))
        }
        .buttonStyle(.plain)
        .disabled(saved || saving)
        .padding(.top, 4)
    }
}
