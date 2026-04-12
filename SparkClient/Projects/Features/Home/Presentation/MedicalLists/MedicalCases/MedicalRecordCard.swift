import SwiftUI

/// 病例卡片：视觉结构对齐 HealthClient `MedicalRecordCard`，颜色改用系统近似色。
struct MedicalRecordCard: View {
    let item: SparkMedicalSyncAPI.RemoteMedicalCaseSummary
    let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    let workflowAPI: SparkMedicalWorkflowAPI
    let fileTransferService: FileTransferService
    var maxChips: Int = 8

    private var chiefComplaintText: String {
        item.title?.nonEmpty ?? ""
    }

    private var diagnosisText: String {
        item.diagnosisSummary?.nonEmpty ?? ""
    }

    private var dateText: String {
        let date = item.updatedAt ?? item.createdAt ?? .now
        return Self.dateFormatter.string(from: date)
    }

    private var style: SeverityStyle { SeverityStyle(severity: .medium) }

    private var recordStatus: CardStatus {
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

    private let noteText: String? = nil

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var body: some View {
        NavigationLink {
            MedicalCaseDetailPage(
                item: item,
                completeData: completeData,
                workflowAPI: workflowAPI,
                fileTransferService: fileTransferService
            )
        } label: {
            VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "stethoscope")
                    .font(.caption)
                    .foregroundStyle(style.accent)
                Text(L10n.text("home.medical.list.medical_case.chief_complaint"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(style.accent)
                Text(chiefComplaintText)
                    .font(.subheadline)
                    .foregroundStyle(style.textStrong)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text("home.medical.list.medical_case.diagnosis"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(style.textSecondary)
                Text(diagnosisText)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(style.textStrong)
                    .lineLimit(2)
            }

            if let symptoms = item.symptoms, symptoms.isEmpty == false {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("home.medical.list.medical_case.symptoms"))
                        .font(.subheadline)
                        .foregroundStyle(style.textSecondary)
                    MedicalFlowTagView(
                        items: limitedList(symptoms, max: maxChips),
                        extraCount: max(0, symptoms.count - maxChips),
                        tint: style.chipBG,
                        foreground: style.chipFG
                    )
                }
            }

            if let medications = item.medications, medications.isEmpty == false {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "pills.fill")
                        Text(L10n.text("home.medical.list.medical_case.medications"))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(style.textSecondary)

                    MedicalFlowTagView(
                        items: limitedList(medications, max: maxChips),
                        extraCount: max(0, medications.count - maxChips),
                        tint: Color(uiColor: .systemBlue).opacity(0.12),
                        foreground: Color(uiColor: .systemBlue)
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                if let noteText {
                    Text(noteText)
                        .font(.footnote)
                        .italic()
                        .foregroundStyle(style.accent)
                }

                HStack {
                    StatusPill(text: recordStatus.displayName, tint: statusTint(recordStatus))
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                        Text(dateText)
                    }
                    .font(.footnote)
                    .foregroundStyle(style.textSecondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(L10n.text("home.medical.list.medical_case.updated_at"))\(dateText)")
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(style.cardBG)
        )
        .overlay(alignment: .leading) {
            Capsule()
                .fill(style.accent)
                .frame(width: 4)
                .padding(.vertical, 10)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style.border, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
        }
        .buttonStyle(.plain)
    }

    private func limitedList(_ items: [String], max: Int) -> [String] {
        Array(items.prefix(max))
    }

    private func statusTint(_ status: CardStatus) -> Color {
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

    private var accessibilitySummary: String {
        [
            chiefComplaintText,
            diagnosisText,
            recordStatus.displayName,
            dateText
        ].joined(separator: "，")
    }
}

private struct MedicalFlowTagView: View {
    let items: [String]
    let extraCount: Int
    let tint: Color
    let foreground: Color

    private let columns = [GridItem(.adaptive(minimum: 60), spacing: 8, alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                tag(item)
            }
            if extraCount > 0 {
                tag("+\(extraCount)")
            }
        }
    }

    private func tag(_ title: String) -> some View {
        Text(title)
            .font(.footnote)
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint)
            )
    }
}

private struct StatusPill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint)
            )
            .foregroundStyle(.primary)
    }
}

private enum CardStatus {
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

private enum CardSeverity {
    case low
    case medium
    case high
}

private struct SeverityStyle {
    let severity: CardSeverity

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
    var chipBG: Color { accent.opacity(0.12) }
    var chipFG: Color { accent }
    var textStrong: Color { .primary }
    var textSecondary: Color { .secondary }
}
