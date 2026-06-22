import SwiftUI

struct MedicalGuideAllergyDetail: Equatable, Codable, Sendable {
    var category: String = ""
    var severity: String = ""
    var reactions: [String] = []
    var notes: String = ""
}

struct AllergyRecordFormDraft: Equatable, Sendable {
    var allergies: [String]
    var details: [String: MedicalGuideAllergyDetail]
    var allergyHistory: String
}

struct MemberMedicalAllergyHistoryStepView: View {
    @Binding var status: MedicalGuideDisclosureStatus
    @Binding var allergies: [String]
    @Binding var allergyDetails: [String: MedicalGuideAllergyDetail]
    @Binding var allergyHistory: String

    @State private var showingManualEntrySheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            allergyScreeningCard

            if status == .none {
                friendlyTipRow
            }

            if status == .have {
                existingAllergiesSection
                MemberSetupAccentAddButton(title: allergies.isEmpty ? "添加过敏记录" : "编辑过敏记录") {
                    showingManualEntrySheet = true
                }
            }
        }
        .sheet(isPresented: $showingManualEntrySheet) {
            CompatibleNavigationContainer {
                AllergyRecordFormView(
                    initial: AllergyRecordFormDraft(
                        allergies: allergies,
                        details: allergyDetails,
                        allergyHistory: allergyHistory
                    ),
                    onSubmit: { draft in
                        allergies = draft.allergies
                        allergyDetails = draft.details
                        allergyHistory = draft.allergyHistory
                        if draft.allergies.isEmpty == false {
                            status = .have
                        }
                    }
                )
            }
        }
        .onChange(of: status) { newValue in
            if newValue == .none {
                allergies.removeAll()
                allergyDetails.removeAll()
                allergyHistory = ""
            }
        }
    }

    private var allergyScreeningCard: some View {
        MemberSetupSection(title: "过敏史筛查") {
            VStack(alignment: .leading, spacing: 14) {
                Text("您过往是否有明确的过敏经历？")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    screeningChoice(
                        title: "无过敏史",
                        isSelected: status == .none,
                        action: { status = .none }
                    )
                    screeningChoice(
                        title: "有过敏史",
                        isSelected: status == .have,
                        action: { status = .have }
                    )
                }
            }
        }
    }

    private var friendlyTipRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("贴心提示：如果没有相关过敏反应，请直接点击下方保存即可。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var existingAllergiesSection: some View {
        Group {
            if allergies.isEmpty == false {
                MemberSetupSection(title: "已录入过敏档案") {
                    VStack(spacing: 10) {
                        ForEach(allergies, id: \.self) { allergen in
                            Button {
                                showingManualEntrySheet = true
                            } label: {
                                allergyCard(allergen)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func allergyCard(_ allergen: String) -> some View {
        let detail = allergyDetails[allergen]
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: AllergyRecordFormSupport.systemImage(for: detail?.category ?? ""))
                .font(.title3.weight(.semibold))
                .foregroundStyle(AllergyRecordFormSupport.tint(for: detail?.category ?? ""))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(allergen)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    if let severity = detail?.severity, severity.isEmpty == false {
                        Text(severity)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AllergyRecordFormSupport.severityTint(severity))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(AllergyRecordFormSupport.severityTint(severity).opacity(0.12)))
                    }
                }

                if let reactions = detail?.reactions, reactions.isEmpty == false {
                    Text("过敏反应：\(reactions.joined(separator: "、"))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let category = detail?.category, category.isEmpty == false {
                    Text("类别：\(category)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 3)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        )
    }

    private func screeningChoice(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(uiColor: .systemBackground))
            )
        }
        .buttonStyle(.plain)
    }
}
