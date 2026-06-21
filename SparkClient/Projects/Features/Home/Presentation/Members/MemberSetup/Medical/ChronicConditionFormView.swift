import SwiftUI

struct ChronicConditionFormDraft: Equatable, Sendable {
    var conditions: [String]
    var details: [String: MedicalGuideChronicConditionDetail]
}

/// 既往疾病手动录入表单（仅本地编辑，保存后通过回调返回）。
struct ChronicConditionFormView: View {
    let initial: ChronicConditionFormDraft
    let onSubmit: (ChronicConditionFormDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var chronicConditions: [String]
    @State private var conditionDetails: [String: MedicalGuideChronicConditionDetail]
    @State private var searchText = ""
    @State private var focusedCondition: String?

    private let controlStatusOptions = ["控制良好", "治疗中", "已治愈"]

    private let diseaseCategories: [ChronicDiseaseCategoryGroup] = [
        .init(
            title: "心脑血管系统",
            systemImage: "heart.fill",
            diseases: ["高血压", "冠心病", "高血脂", "脑卒中/中风"]
        ),
        .init(
            title: "内分泌与代谢",
            systemImage: "drop.fill",
            diseases: ["糖尿病", "痛风 / 高尿酸", "甲状腺结节/甲亢"]
        ),
        .init(
            title: "消化与呼吸",
            systemImage: "lungs.fill",
            diseases: ["脂肪肝", "慢性胃炎/溃疡", "哮喘"]
        ),
        .init(
            title: "泌尿与骨骼",
            systemImage: "figure.walk",
            diseases: ["慢性肾病", "肾结石", "颈椎/腰椎病"]
        )
    ]

    private var diagnosisYearRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let end = Date()
        let start = calendar.date(from: DateComponents(year: 1950, month: 1, day: 1)) ?? end
        return start ... end
    }

    init(initial: ChronicConditionFormDraft, onSubmit: @escaping (ChronicConditionFormDraft) -> Void) {
        self.initial = initial
        self.onSubmit = onSubmit
        _chronicConditions = State(initialValue: initial.conditions)
        _conditionDetails = State(initialValue: initial.details)
        _focusedCondition = State(initialValue: initial.conditions.last)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                diseaseSearchField
                diseaseCategoryGroups
                if chronicConditions.isEmpty == false {
                    conditionDetailsCard
                }
            }
            .padding(16)
        }
        .navigationTitle("手动添加既往疾病")
        .navigationBarTitleDisplayMode(.inline)
        .sparkFormBottomBar(
            canSubmit: chronicConditions.isEmpty == false,
            saveTitle: "完成",
            onCancel: { dismiss() },
            onSave: { saveNow() }
        )
        .onChange(of: chronicConditions) { newValue in
            if let focusedCondition, newValue.contains(focusedCondition) == false {
                self.focusedCondition = newValue.last
            }
            if focusedCondition == nil {
                focusedCondition = newValue.last
            }
            let validKeys = Set(newValue)
            conditionDetails = conditionDetails.filter { validKeys.contains($0.key) }
        }
    }

    private var diseaseSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索疾病名称 (支持拼音/首字母)", text: $searchText)
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
                        columns: [GridItem(.adaptive(minimum: 96), spacing: 10)],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(category.diseases, id: \.self) { disease in
                            diseaseChip(disease)
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

    private var conditionDetailsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("疾病详情补全")
                .font(.headline)

            if chronicConditions.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chronicConditions, id: \.self) { disease in
                            Button {
                                focusedCondition = disease
                            } label: {
                                Text(disease)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(focusedCondition == disease ? Color.accentColor : .primary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(focusedCondition == disease ? Color.accentColor.opacity(0.14) : Color(uiColor: .systemBackground))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if let focusedCondition {
                Text(focusedCondition)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)

                VStack(spacing: 0) {
                    HStack {
                        Label("确诊时间", systemImage: "calendar")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        DatePicker(
                            "",
                            selection: diagnosedDateBinding(for: focusedCondition),
                            in: diagnosisYearRange,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)
                        .labelsHidden()
                    }

                    Divider().padding(.vertical, 10)

                    VStack(alignment: .leading, spacing: 10) {
                        Label("当前控制状态", systemImage: "stethoscope")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        controlStatusPicker(for: focusedCondition)
                    }
                    .padding(.bottom, 10)

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Label("补充备注 (例如：并发症、主治医院等)...", systemImage: "note.text")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        TextEditor(text: detailNotesBinding(for: focusedCondition))
                            .frame(minHeight: 88)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(uiColor: .systemBackground))
                            )
                    }
                    .padding(.top, 10)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .systemGroupedBackground))
        )
    }

    private var filteredCategories: [ChronicDiseaseCategoryGroup] {
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
            return ChronicDiseaseCategoryGroup(
                title: category.title,
                systemImage: category.systemImage,
                diseases: matchedDiseases
            )
        }
    }

    private func diseaseChip(_ disease: String) -> some View {
        let isSelected = chronicConditions.contains(disease)
        return Button {
            if isSelected {
                if focusedCondition == disease {
                    toggle(disease)
                } else {
                    focusedCondition = disease
                }
            } else {
                toggle(disease)
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

    private func controlStatusPicker(for disease: String) -> some View {
        HStack(spacing: 8) {
            ForEach(controlStatusOptions, id: \.self) { option in
                let isSelected = detail(for: disease).controlStatus == option
                Button {
                    updateDetail(for: disease) { $0.controlStatus = option }
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

    private func toggle(_ disease: String) {
        if chronicConditions.contains(disease) {
            chronicConditions.removeAll { $0 == disease }
            conditionDetails.removeValue(forKey: disease)
            if focusedCondition == disease {
                focusedCondition = chronicConditions.last
            }
        } else {
            chronicConditions.append(disease)
            focusedCondition = disease
            if conditionDetails[disease] == nil {
                conditionDetails[disease] = MedicalGuideChronicConditionDetail()
            }
        }
    }

    private func detail(for disease: String) -> MedicalGuideChronicConditionDetail {
        conditionDetails[disease] ?? MedicalGuideChronicConditionDetail()
    }

    private func diagnosedDateBinding(for disease: String) -> Binding<Date> {
        Binding(
            get: {
                let yearString = detail(for: disease).diagnosedYear
                if let year = Int(yearString),
                   let date = Calendar.current.date(from: DateComponents(year: year, month: 1, day: 1)) {
                    return date
                }
                return Date()
            },
            set: { newValue in
                let year = Calendar.current.component(.year, from: newValue)
                updateDetail(for: disease) { $0.diagnosedYear = String(year) }
            }
        )
    }

    private func updateDetail(for disease: String, update: (inout MedicalGuideChronicConditionDetail) -> Void) {
        var draft = detail(for: disease)
        update(&draft)
        conditionDetails[disease] = draft
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
            ChronicConditionFormDraft(
                conditions: chronicConditions,
                details: conditionDetails
            )
        )
        dismiss()
    }
}

private struct ChronicDiseaseCategoryGroup: Identifiable {
    var id: String { title }
    let title: String
    let systemImage: String
    let diseases: [String]
}

enum ChronicConditionFormSupport {
    static func summaryLine(name: String, detail: MedicalGuideChronicConditionDetail?) -> String {
        var pieces = [name]
        if let detail {
            if detail.diagnosedYear.isEmpty == false {
                pieces.append("\(detail.diagnosedYear)年确诊")
            }
            if detail.controlStatus.isEmpty == false {
                pieces.append(detail.controlStatus)
            }
            if detail.notes.isEmpty == false {
                pieces.append(detail.notes)
            }
        }
        return pieces.joined(separator: " · ")
    }
}
