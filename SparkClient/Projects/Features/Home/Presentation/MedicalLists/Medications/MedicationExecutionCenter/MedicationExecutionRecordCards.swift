import SwiftUI

struct MedicationExecutionPendingCard: View {
    let timeText: String
    let doses: [MedicationExecutionDose]
    let fileTransferService: FileTransferService
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text(timeText)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)

                ForEach(doses) { dose in
                    HStack(spacing: 12) {
                        MedicationImageGlyph(
                            seed: dose.plan.id,
                            attachment: dose.imageAttachment,
                            fileTransferService: fileTransferService
                        )
                        .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dose.displayName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(dose.plannedDose)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .imageScale(.large)
                    .foregroundStyle(Color(uiColor: .systemBlue))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("home.medical.medication_execution.a11y.add_record"))
        }
        .padding(18)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }
}

struct MedicationExecutionAsNeededCard: View {
    let onAdd: () -> Void

    var body: some View {
        HStack {
            Text(L10n.text("home.medical.medication_execution.as_needed"))
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .imageScale(.medium)
                    .foregroundStyle(Color(uiColor: .systemBlue))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 64)
        .background(
            Color(uiColor: .systemTeal).opacity(0.12),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }
}

struct MedicationExecutionAllDoneCard: View {
    var body: some View {
        HStack(spacing: 16) {
            Text(L10n.text("home.medical.medication_execution.all_done"))
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            Image(systemName: "calendar.badge.checkmark")
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color(uiColor: .systemBlue), Color(uiColor: .systemIndigo)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}

struct MedicationExecutionCompletedGroup: View {
    let group: MedicationExecutionTimeGroup
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 14) {
                Text(group.timeText)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .frame(width: 64, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(group.doses) { dose in
                        HStack(spacing: 8) {
                            Image(systemName: dose.status == "taken" ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(dose.status == "taken" ? Color(uiColor: .systemTeal) : Color(uiColor: .systemGray))
                            Text(completedDoseLabel(for: dose))
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(completedGroupAccessibilityLabel)
        .accessibilityHint(L10n.text("home.medical.medication_execution.a11y.edit_record"))
    }

    private var completedGroupAccessibilityLabel: String {
        let names = group.doses.map { dose in
            dose.status == "taken" ? dose.displayName : completedDoseLabel(for: dose)
        }
        return "\(group.timeText), \(names.joined(separator: ", "))"
    }

    private func completedDoseLabel(for dose: MedicationExecutionDose) -> String {
        if dose.status == "taken" {
            return dose.displayName
        }
        return L10n.format("home.medical.medication_execution.skipped_name", dose.displayName)
    }
}
