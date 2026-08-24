import SwiftUI

/// 首页医疗信息公共网格：传统首页与 iOS26 首页共用同一套医疗入口卡片。
struct HomeMedicalDashboardGridSection: View {
    let cards: [HomeDashboard.MedicalCard]
    let selectedMemberID: Int?
    let onSelect: (HomeDashboard.MedicalCard.Kind) -> Void
    let onInterpretReport: (() -> Void)?
    let onUploadReport: (() -> Void)?

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L10n.text("home.medical.title"), systemImage: "cross.case")
                    .font(.headline)
                Spacer()
                headerActions
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(cards, id: \.id) { card in
                    Button {
                        onSelect(card.id)
                    } label: {
                        HomeMedicalDashboardCard(card: card, isEnabled: isEnabled(card.id))
                    }
                    .buttonStyle(.plain)
                    .disabled(isEnabled(card.id) == false)
                }
            }
        }
    }

    @ViewBuilder
    private var headerActions: some View {
        HStack(spacing: 8) {
            if let onInterpretReport {
                headerActionButton(
                    title: L10n.text("ios26.home.action.interpret"),
                    systemImage: "sparkles",
                    action: onInterpretReport
                )
            }

            if let onUploadReport {
                headerActionButton(
                    title: L10n.text("ios26.home.action.report_upload.title", fallback: "上传报告"),
                    systemImage: "square.and.arrow.up",
                    action: onUploadReport
                )
            }
        }
    }

    private func headerActionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(selectedMemberID == nil)
    }

    private func isEnabled(_ kind: HomeDashboard.MedicalCard.Kind) -> Bool {
        switch kind {
        case .familyMedicineCabinet:
            return selectedMemberID != nil
        default:
            return true
        }
    }
}

struct HomeMedicalDashboardCard: View {
    let card: HomeDashboard.MedicalCard
    let isEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: card.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isEnabled ? Color.accentColor : Color.secondary.opacity(0.5))
                }

            Text(card.title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(isEnabled ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(L10n.text("home.medical.card.count", fallback: "共\(card.count)份"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if isEnabled == false {
                Text(L10n.text("ios26.home.action.requires_member"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(card.title)
        .accessibilityValue(String(card.count))
        .accessibilityHint(card.subtitle)
    }
}

private extension HomeDashboard.MedicalCard {
    var title: String {
        switch id {
        case .medicalCases:
            return L10n.text("home.medical.card.medical_cases.title")
        case .healthExamReports:
            return L10n.text("home.medical.card.examination_reports.title")
        case .medicalReports:
            return L10n.text("home.medical.card.medical_reports.title")
        case .medication:
            return L10n.text("ios26.home.action.medication.title")
        case .medicationPlans:
            return L10n.text("home.medical.card.medication_plans.title")
        case .familyMedicineCabinet:
            return L10n.text("ios26.home.action.family_medicine_cabinet.title")
        }
    }

    var subtitle: String {
        switch id {
        case .medicalCases:
            return L10n.text("home.medical.card.medical_cases.subtitle")
        case .healthExamReports:
            return L10n.text("home.medical.card.examination_reports.subtitle")
        case .medicalReports:
            return L10n.text("home.medical.card.medical_reports.subtitle")
        case .medication:
            return L10n.text("ios26.home.action.medication.subtitle")
        case .medicationPlans:
            return L10n.text("home.medical.card.medication_plans.subtitle")
        case .familyMedicineCabinet:
            return L10n.text("ios26.home.action.family_medicine_cabinet.subtitle")
        }
    }
}
