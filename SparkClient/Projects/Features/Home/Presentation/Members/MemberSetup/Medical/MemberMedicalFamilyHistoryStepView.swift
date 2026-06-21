import SwiftUI

struct MedicalGuideFamilyHistoryDetail: Equatable, Codable, Sendable {
    var relative: String = ""
    var category: String = ""
    var diagnosedAge: String = ""
    var notes: String = ""
}

struct MedicalGuideFamilyHistoryRecord: Equatable, Codable, Sendable {
    var disease: String
    var relative: String
    var category: String
    var diagnosedAge: String
    var notes: String
}

struct FamilyHistoryRecordFormDraft: Equatable, Sendable {
    var familyHistory: [String]
    var details: [String: MedicalGuideFamilyHistoryDetail]
}

struct MemberMedicalFamilyHistoryStepView: View {
    @Binding var status: MedicalGuideDisclosureStatus
    @Binding var familyHistory: [String]
    @Binding var familyHistoryDetails: [String: MedicalGuideFamilyHistoryDetail]

    @State private var showingManualEntrySheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            familyHistoryScreeningCard

            if status == .none {
                friendlyTipRow
            }

            if status == .have {
                existingFamilyHistorySection
                MemberSetupAccentAddButton(title: familyHistory.isEmpty ? "添加家族病史" : "编辑家族病史") {
                    showingManualEntrySheet = true
                }
            }
        }
        .sheet(isPresented: $showingManualEntrySheet) {
            CompatibleNavigationContainer {
                FamilyHistoryRecordFormView(
                    initial: FamilyHistoryRecordFormDraft(
                        familyHistory: familyHistory,
                        details: familyHistoryDetails
                    ),
                    onSubmit: { draft in
                        familyHistory = draft.familyHistory
                        familyHistoryDetails = draft.details
                        if draft.familyHistory.isEmpty == false {
                            status = .have
                        }
                    }
                )
            }
        }
        .onChange(of: status) { newValue in
            if newValue == .none {
                familyHistory.removeAll()
                familyHistoryDetails.removeAll()
            }
        }
    }

    private var familyHistoryScreeningCard: some View {
        MemberSetupSection(title: "家族病史筛查") {
            VStack(alignment: .leading, spacing: 14) {
                Text("您的直系亲属（父母、祖父母、外祖父母、兄弟姐妹）是否有人患有明确的慢性疾病或肿瘤病史？")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    screeningChoice(
                        title: "无已知家族病史",
                        isSelected: status == .none,
                        action: { status = .none }
                    )
                    screeningChoice(
                        title: "有家族病史",
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
            Text("贴心提示：如果直系亲属身体都健康或不了解，请直接点击下方保存。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var existingFamilyHistorySection: some View {
        Group {
            if familyHistory.isEmpty == false {
                MemberSetupSection(title: "已录入家族病史") {
                    VStack(spacing: 10) {
                        ForEach(familyHistory, id: \.self) { disease in
                            Button {
                                showingManualEntrySheet = true
                            } label: {
                                familyHistoryCard(disease)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func familyHistoryCard(_ disease: String) -> some View {
        let detail = familyHistoryDetails[disease]
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: FamilyHistoryRecordFormSupport.systemImage(for: detail?.relative ?? ""))
                .font(.title3.weight(.semibold))
                .foregroundStyle(FamilyHistoryRecordFormSupport.tint(for: detail?.category ?? ""))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(detail?.relative.isEmpty == false ? detail?.relative ?? "直系亲属" : "直系亲属")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(disease)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                }

                if let category = detail?.category, category.isEmpty == false {
                    Text("疾病细分：\(category)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text("风险提示：\(FamilyHistoryRecordFormSupport.riskHint(for: disease))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
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

struct FamilyHistoryRecordFormView: View {
    let initial: FamilyHistoryRecordFormDraft
    let onSubmit: (FamilyHistoryRecordFormDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var familyHistory: [String]
    @State private var details: [String: MedicalGuideFamilyHistoryDetail]
    @State private var selectedRelative: String
    @State private var searchText = ""
    @State private var focusedDisease: String?

    private let relatives = ["父亲", "母亲", "爷爷", "奶奶", "外公", "外婆", "兄弟", "姐妹", "其他直系亲属"]
    private let diagnosisAgeOptions = ["不清楚", "40岁前", "40-49岁", "50-59岁", "60岁及以后"]

    private let diseaseCategories: [FamilyDiseaseCategoryGroup] = [
        .init(
            title: "高发肿瘤 / 癌症",
            systemImage: "cross.case.fill",
            tint: .pink,
            diseases: ["肺癌", "胃癌", "结直肠癌", "乳腺癌", "肝癌", "食管癌"]
        ),
        .init(
            title: "慢性心脑血管",
            systemImage: "heart.fill",
            tint: .red,
            diseases: ["高血压", "冠心病", "脑卒中/脑梗死", "高血脂"]
        ),
        .init(
            title: "代谢与免疫系统",
            systemImage: "drop.fill",
            tint: .orange,
            diseases: ["2型糖尿病", "痛风/高尿酸血症", "阿尔茨海默病/老年痴呆"]
        )
    ]

    init(initial: FamilyHistoryRecordFormDraft, onSubmit: @escaping (FamilyHistoryRecordFormDraft) -> Void) {
        self.initial = initial
        self.onSubmit = onSubmit
        _familyHistory = State(initialValue: initial.familyHistory)
        _details = State(initialValue: initial.details)
        _focusedDisease = State(initialValue: initial.familyHistory.last)
        _selectedRelative = State(initialValue: initial.familyHistory.last.flatMap { initial.details[$0]?.relative }.flatMap { $0.isEmpty ? nil : $0 } ?? "父亲")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                relativeChoiceCard
                diseaseSearchField
                diseaseCategoryGroups
                if familyHistory.isEmpty == false {
                    familyHistoryDetailsCard
                }
            }
            .padding(16)
        }
        .navigationTitle("添加家族病史")
        .navigationBarTitleDisplayMode(.inline)
        .sparkFormBottomBar(
            canSubmit: familyHistory.isEmpty == false,
            saveTitle: "完成",
            onCancel: { dismiss() },
            onSave: { saveNow() }
        )
        .onChange(of: familyHistory) { newValue in
            if let focusedDisease, newValue.contains(focusedDisease) == false {
                self.focusedDisease = newValue.last
            }
            if focusedDisease == nil {
                focusedDisease = newValue.last
            }
            let validKeys = Set(newValue)
            details = details.filter { validKeys.contains($0.key) }
        }
    }

    private var relativeChoiceCard: some View {
        MemberSetupSection(title: "选择患病亲属") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(relatives, id: \.self) { relative in
                    Button {
                        selectedRelative = relative
                        if let focusedDisease {
                            updateDetail(for: focusedDisease) { $0.relative = relative }
                        }
                    } label: {
                        Text(relative)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedRelative == relative ? Color.accentColor : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(selectedRelative == relative ? Color.accentColor.opacity(0.14) : Color(uiColor: .systemGroupedBackground))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var diseaseSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索疾病或肿瘤名称 (如: 肠癌、高血压)", text: $searchText)
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

    private var diseaseCategoryGroups: some View {
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
                        ForEach(category.diseases, id: \.self) { disease in
                            diseaseChip(disease, category: category.title)
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

    private var familyHistoryDetailsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("家族病史详情补全")
                .font(.headline)

            if familyHistory.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(familyHistory, id: \.self) { disease in
                            Button {
                                focusedDisease = disease
                                let relative = detail(for: disease).relative
                                if relative.isEmpty == false {
                                    selectedRelative = relative
                                }
                            } label: {
                                Text(disease)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(focusedDisease == disease ? Color.accentColor : .primary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(focusedDisease == disease ? Color.accentColor.opacity(0.14) : Color(uiColor: .systemBackground))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if let focusedDisease {
                Text(focusedDisease)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("亲属确诊时的大致年龄 (选填)", systemImage: "calendar")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        diagnosisAgePicker(for: focusedDisease)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Label("补充备注 (例如：多位亲属患同类病、发病细节等)...", systemImage: "note.text")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        TextEditor(text: detailNotesBinding(for: focusedDisease))
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

    private var filteredCategories: [FamilyDiseaseCategoryGroup] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return diseaseCategories }

        let query = trimmed.lowercased()
        let queryPinyin = trimmed.toPinyinForSearch().lowercased()

        return diseaseCategories.compactMap { category in
            let matchedDiseases = category.diseases.filter { disease in
                disease.localizedCaseInsensitiveContains(trimmed)
                    || disease.toPinyinForSearch().lowercased().contains(queryPinyin)
                    || disease.toPinyinForSearch().lowercased().contains(query)
            }
            guard matchedDiseases.isEmpty == false else { return nil }
            return FamilyDiseaseCategoryGroup(
                title: category.title,
                systemImage: category.systemImage,
                tint: category.tint,
                diseases: matchedDiseases
            )
        }
    }

    private func diseaseChip(_ disease: String, category: String) -> some View {
        let isSelected = familyHistory.contains(disease)
        return Button {
            if isSelected {
                if focusedDisease == disease {
                    toggle(disease, category: category)
                } else {
                    focusedDisease = disease
                    let relative = detail(for: disease).relative
                    if relative.isEmpty == false {
                        selectedRelative = relative
                    }
                }
            } else {
                toggle(disease, category: category)
            }
        } label: {
            Text(disease)
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

    private func diagnosisAgePicker(for disease: String) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(diagnosisAgeOptions, id: \.self) { option in
                let isSelected = detail(for: disease).diagnosedAge == option
                Button {
                    updateDetail(for: disease) { $0.diagnosedAge = option }
                } label: {
                    Text(option)
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

    private func toggle(_ disease: String, category: String) {
        if familyHistory.contains(disease) {
            familyHistory.removeAll { $0 == disease }
            details.removeValue(forKey: disease)
            if focusedDisease == disease {
                focusedDisease = familyHistory.last
            }
        } else {
            familyHistory.append(disease)
            focusedDisease = disease
            details[disease] = MedicalGuideFamilyHistoryDetail(
                relative: selectedRelative,
                category: category,
                diagnosedAge: "",
                notes: ""
            )
        }
    }

    private func detail(for disease: String) -> MedicalGuideFamilyHistoryDetail {
        details[disease] ?? MedicalGuideFamilyHistoryDetail(relative: selectedRelative)
    }

    private func updateDetail(for disease: String, update: (inout MedicalGuideFamilyHistoryDetail) -> Void) {
        var draft = detail(for: disease)
        update(&draft)
        details[disease] = draft
    }

    private func detailNotesBinding(for disease: String) -> Binding<String> {
        Binding(
            get: { detail(for: disease).notes },
            set: { newValue in
                updateDetail(for: disease) { $0.notes = newValue }
            }
        )
    }

    private func saveNow() {
        onSubmit(
            FamilyHistoryRecordFormDraft(
                familyHistory: familyHistory,
                details: details
            )
        )
        dismiss()
    }
}

private struct FamilyDiseaseCategoryGroup: Identifiable {
    var id: String { title }
    let title: String
    let systemImage: String
    let tint: Color
    let diseases: [String]
}

enum FamilyHistoryRecordFormSupport {
    static func summaryLine(name: String, detail: MedicalGuideFamilyHistoryDetail?) -> String {
        var pieces: [String] = []
        if let relative = detail?.relative, relative.isEmpty == false {
            pieces.append(relative)
        }
        pieces.append(name)
        if let diagnosedAge = detail?.diagnosedAge, diagnosedAge.isEmpty == false {
            pieces.append(diagnosedAge)
        }
        if let notes = detail?.notes, notes.isEmpty == false {
            pieces.append(notes)
        }
        return pieces.joined(separator: " · ")
    }

    static func systemImage(for relative: String) -> String {
        if relative.contains("父") || relative.contains("爷") || relative.contains("外公") {
            return "person.fill"
        }
        if relative.contains("母") || relative.contains("奶") || relative.contains("外婆") {
            return "person.fill"
        }
        if relative.contains("兄") || relative.contains("姐") || relative.contains("妹") {
            return "person.2.fill"
        }
        return "person.3.fill"
    }

    static func tint(for category: String) -> Color {
        if category.contains("肿瘤") || category.contains("癌") { return .pink }
        if category.contains("心脑血管") { return .red }
        if category.contains("代谢") { return .orange }
        return .accentColor
    }

    static func riskHint(for disease: String) -> String {
        if disease.contains("糖尿病") {
            return "建议定期监测空腹血糖与糖化血红蛋白。"
        }
        if disease.contains("乳腺癌") {
            return "建议结合年龄提前开展年度乳腺超声或钼靶筛查。"
        }
        if disease.contains("结直肠癌") || disease.contains("肠癌") {
            return "建议关注肠镜或粪便潜血筛查时机。"
        }
        if disease.contains("肺癌") {
            return "建议结合吸烟史评估低剂量胸部 CT 筛查。"
        }
        if disease.contains("肝癌") {
            return "建议关注肝脏彩超、AFP 及乙肝相关风险。"
        }
        if disease.contains("高血压") || disease.contains("冠心病") || disease.contains("脑卒中") || disease.contains("高血脂") {
            return "建议定期监测血压、血脂和心脑血管风险。"
        }
        return "建议在体检计划中纳入对应风险筛查。"
    }
}
