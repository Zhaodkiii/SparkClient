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

struct AllergyRecordFormView: View {
    let initial: AllergyRecordFormDraft
    let onSubmit: (AllergyRecordFormDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var allergies: [String]
    @State private var details: [String: MedicalGuideAllergyDetail]
    @State private var allergyHistory: String
    @State private var searchText = ""
    @State private var focusedAllergy: String?

    private let severityOptions = ["轻度", "中度", "严重"]
    private let reactionOptions = ["皮疹/发痒", "红肿", "恶心呕吐", "腹痛/腹泻", "呼吸困难/哮喘", "头晕/休克"]

    private let allergyCategories: [AllergyCategoryGroup] = [
        .init(
            title: "药物过敏",
            systemImage: "pills.fill",
            tint: .red,
            allergens: ["青霉素/阿莫西林", "头孢菌素", "阿司匹林", "磺胺类药物"]
        ),
        .init(
            title: "食物过敏",
            systemImage: "fork.knife",
            tint: .orange,
            allergens: ["鱼/虾/蟹海鲜", "花生/坚果", "鸡蛋", "牛奶/乳制品"]
        ),
        .init(
            title: "环境与吸入性过敏",
            systemImage: "leaf.fill",
            tint: .green,
            allergens: ["花粉/柳絮", "尘螨", "动物皮毛/猫狗屑", "霉菌"]
        ),
        .init(
            title: "接触性与其它",
            systemImage: "hand.raised.fill",
            tint: .purple,
            allergens: ["乳胶制品", "油漆", "紫外线/日光", "金属镍"]
        )
    ]

    init(initial: AllergyRecordFormDraft, onSubmit: @escaping (AllergyRecordFormDraft) -> Void) {
        self.initial = initial
        self.onSubmit = onSubmit
        _allergies = State(initialValue: initial.allergies)
        _details = State(initialValue: initial.details)
        _allergyHistory = State(initialValue: initial.allergyHistory)
        _focusedAllergy = State(initialValue: initial.allergies.last)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                allergySearchField
                allergyCategoryGroups
                if allergies.isEmpty == false {
                    allergyDetailsCard
                }
            }
            .padding(16)
        }
        .navigationTitle("添加过敏记录")
        .navigationBarTitleDisplayMode(.inline)
        .sparkFormBottomBar(
            canSubmit: allergies.isEmpty == false,
            saveTitle: "完成",
            onCancel: { dismiss() },
            onSave: { saveNow() }
        )
        .onChange(of: allergies) { newValue in
            if let focusedAllergy, newValue.contains(focusedAllergy) == false {
                self.focusedAllergy = newValue.last
            }
            if focusedAllergy == nil {
                focusedAllergy = newValue.last
            }
            let validKeys = Set(newValue)
            details = details.filter { validKeys.contains($0.key) }
        }
    }

    private var allergySearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索过敏原名称 (如: 头孢、花粉、鸡蛋)", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .systemGroupedBackground))
        )
    }

    private var allergyCategoryGroups: some View {
        VStack(spacing: 0) {
            ForEach(Array(filteredCategories.enumerated()), id: \.element.id) { index, category in
                VStack(alignment: .leading, spacing: 10) {
                    Label(category.title, systemImage: category.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 112), spacing: 10)],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(category.allergens, id: \.self) { allergen in
                            allergenChip(allergen, category: category.title)
                        }
                    }
                }
                .padding(.vertical, 12)

                if index < filteredCategories.count - 1 {
                    Divider()
                }
            }
        }
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .systemGroupedBackground))
        )
    }

    private var allergyDetailsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("过敏详情补全")
                .font(.headline)

            if allergies.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(allergies, id: \.self) { allergen in
                            Button {
                                focusedAllergy = allergen
                            } label: {
                                Text(allergen)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(focusedAllergy == allergen ? Color.accentColor : .primary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(focusedAllergy == allergen ? Color.accentColor.opacity(0.14) : Color(uiColor: .systemBackground))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if let focusedAllergy {
                Text(focusedAllergy)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("严重程度评估", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        severityPicker(for: focusedAllergy)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Label("发生过的过敏反应", systemImage: "allergens")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        reactionPicker(for: focusedAllergy)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Label("补充备注 (例如：确诊时间、首次发作表现、抢救史等)...", systemImage: "note.text")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        TextEditor(text: detailNotesBinding(for: focusedAllergy))
                            .frame(minHeight: 88)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(uiColor: .systemBackground))
                            )
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .systemGroupedBackground))
        )
    }

    private var filteredCategories: [AllergyCategoryGroup] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return allergyCategories }

        let query = trimmed.lowercased()
        let queryPinyin = trimmed.toPinyinForSearch().lowercased()

        return allergyCategories.compactMap { category in
            let matchedAllergens = category.allergens.filter { allergen in
                allergen.localizedCaseInsensitiveContains(trimmed)
                    || allergen.toPinyinForSearch().lowercased().contains(queryPinyin)
                    || allergen.toPinyinForSearch().lowercased().contains(query)
            }
            guard matchedAllergens.isEmpty == false else { return nil }
            return AllergyCategoryGroup(
                title: category.title,
                systemImage: category.systemImage,
                tint: category.tint,
                allergens: matchedAllergens
            )
        }
    }

    private func allergenChip(_ allergen: String, category: String) -> some View {
        let isSelected = allergies.contains(allergen)
        return Button {
            if isSelected {
                if focusedAllergy == allergen {
                    toggle(allergen, category: category)
                } else {
                    focusedAllergy = allergen
                }
            } else {
                toggle(allergen, category: category)
            }
        } label: {
            Text(allergen)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(uiColor: .systemBackground))
                )
        }
        .buttonStyle(.plain)
    }

    private func severityPicker(for allergen: String) -> some View {
        HStack(spacing: 8) {
            ForEach(severityOptions, id: \.self) { option in
                let isSelected = detail(for: allergen).severity == option
                Button {
                    updateDetail(for: allergen) { $0.severity = option }
                } label: {
                    Text(option)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? AllergyRecordFormSupport.severityTint(option) : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? AllergyRecordFormSupport.severityTint(option).opacity(0.14) : Color(uiColor: .systemBackground))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func reactionPicker(for allergen: String) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(reactionOptions, id: \.self) { reaction in
                let isSelected = detail(for: allergen).reactions.contains(reaction)
                Button {
                    updateDetail(for: allergen) { detail in
                        if detail.reactions.contains(reaction) {
                            detail.reactions.removeAll { $0 == reaction }
                        } else {
                            detail.reactions.append(reaction)
                        }
                    }
                } label: {
                    Text(reaction)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(uiColor: .systemBackground))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggle(_ allergen: String, category: String) {
        if allergies.contains(allergen) {
            allergies.removeAll { $0 == allergen }
            details.removeValue(forKey: allergen)
            if focusedAllergy == allergen {
                focusedAllergy = allergies.last
            }
        } else {
            allergies.append(allergen)
            focusedAllergy = allergen
            if details[allergen] == nil {
                details[allergen] = MedicalGuideAllergyDetail(category: category)
            } else {
                details[allergen]?.category = category
            }
        }
    }

    private func detail(for allergen: String) -> MedicalGuideAllergyDetail {
        details[allergen] ?? MedicalGuideAllergyDetail()
    }

    private func updateDetail(for allergen: String, update: (inout MedicalGuideAllergyDetail) -> Void) {
        var draft = detail(for: allergen)
        update(&draft)
        details[allergen] = draft
    }

    private func detailNotesBinding(for allergen: String) -> Binding<String> {
        Binding(
            get: { detail(for: allergen).notes },
            set: { newValue in
                updateDetail(for: allergen) { $0.notes = newValue }
            }
        )
    }

    private func saveNow() {
        allergyHistory = allergies
            .compactMap { allergen in
                let summary = AllergyRecordFormSupport.summaryLine(name: allergen, detail: details[allergen])
                return summary == allergen ? nil : summary
            }
            .joined(separator: " / ")
        onSubmit(
            AllergyRecordFormDraft(
                allergies: allergies,
                details: details,
                allergyHistory: allergyHistory
            )
        )
        dismiss()
    }
}

private struct AllergyCategoryGroup: Identifiable {
    var id: String { title }
    let title: String
    let systemImage: String
    let tint: Color
    let allergens: [String]
}

enum AllergyRecordFormSupport {
    static func summaryLine(name: String, detail: MedicalGuideAllergyDetail?) -> String {
        var pieces = [name]
        if let detail {
            if detail.severity.isEmpty == false {
                pieces.append(detail.severity)
            }
            if detail.reactions.isEmpty == false {
                pieces.append(detail.reactions.joined(separator: "、"))
            }
            if detail.category.isEmpty == false {
                pieces.append(detail.category)
            }
            if detail.notes.isEmpty == false {
                pieces.append(detail.notes)
            }
        }
        return pieces.joined(separator: " · ")
    }

    static func systemImage(for category: String) -> String {
        if category.contains("药物") { return "pills.fill" }
        if category.contains("食物") { return "fork.knife" }
        if category.contains("环境") { return "leaf.fill" }
        if category.contains("接触") { return "hand.raised.fill" }
        return "allergens"
    }

    static func tint(for category: String) -> Color {
        if category.contains("药物") { return .red }
        if category.contains("食物") { return .orange }
        if category.contains("环境") { return .green }
        if category.contains("接触") { return .purple }
        return .accentColor
    }

    static func severityTint(_ severity: String) -> Color {
        switch severity {
        case "严重":
            return .red
        case "中度":
            return .yellow
        default:
            return .green
        }
    }
}
