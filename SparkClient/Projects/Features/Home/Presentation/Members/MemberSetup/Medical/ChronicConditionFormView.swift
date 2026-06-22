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
    @State private var customDiseaseText = ""
    @State private var focusedCondition: String?

    private let controlStatusOptions = ["控制良好", "治疗中", "已治愈"]

    private var filteredCategories: [ChronicDiseaseCategoryGroup] {
        ChronicConditionFormSupport.filteredCategories(matching: searchText)
    }

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
            VStack(alignment: .leading, spacing: 20) {
                introSection
                quickSelectionSection
                customDiseaseSection
                if chronicConditions.isEmpty == false {
                    conditionDetailsCard
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("既往疾病史")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            prompt: Text("搜索疾病名称 (支持拼音/首字母)")
        )
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

    private var introSection: some View {
        Text(ChronicConditionFormSupport.introText)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var quickSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("常见疾病快速勾选")
                .font(.headline.weight(.semibold))

            VStack(spacing: 0) {
                if filteredCategories.isEmpty {
                    Text("未找到匹配疾病，可在下方自定义录入")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                } else {
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
            }
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
        }
    }

    private var customDiseaseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("自定义疾病录入")
                .font(.headline.weight(.semibold))

            VStack(alignment: .leading, spacing: 14) {
                Label("添加其他未列出的疾病", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Label("请输入疾病准确名称", systemImage: "pencil.line")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("例如：青光眼、慢性荨麻疹...", text: $customDiseaseText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(uiColor: .systemBackground))
                        )
                        .submitLabel(.done)
                        .onSubmit { addCustomDisease() }
                }

                Button(action: addCustomDisease) {
                    Label("确认添加", systemImage: "plus")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(canAddCustomDisease ? Color.white : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(canAddCustomDisease ? Color.accentColor : Color(uiColor: .systemGray4))
                        )
                }
                .buttonStyle(.plain)
                .disabled(canAddCustomDisease == false)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
        }
    }

    private var canAddCustomDisease: Bool {
        resolvedCustomDiseaseName.isEmpty == false
    }

    private var resolvedCustomDiseaseName: String {
        let custom = customDiseaseText.trimmingCharacters(in: .whitespacesAndNewlines)
        if custom.isEmpty == false { return custom }
        return searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var conditionDetailsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("疾病详情补全")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                Text("已选疾病")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                SparkTagFlowLayout(spacing: 8) {
                    ForEach(chronicConditions, id: \.self) { disease in
                        selectedDiseaseTag(disease)
                    }
                }
            }

            if let focusedCondition {
                Divider()

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
                .fill(Color(uiColor: .secondarySystemBackground))
        )
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

    private func selectedDiseaseTag(_ disease: String) -> some View {
        let isFocused = focusedCondition == disease
        return HStack(spacing: 6) {
            Button {
                focusedCondition = disease
            } label: {
                Text(disease)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isFocused ? Color.accentColor : .primary)
            }
            .buttonStyle(.plain)

            Button {
                removeDisease(disease)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(isFocused ? Color.accentColor.opacity(0.14) : Color(uiColor: .systemBackground))
        )
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
            removeDisease(disease)
        } else {
            chronicConditions.append(disease)
            focusedCondition = disease
            if conditionDetails[disease] == nil {
                conditionDetails[disease] = MedicalGuideChronicConditionDetail()
            }
        }
    }

    private func removeDisease(_ disease: String) {
        chronicConditions.removeAll { $0 == disease }
        conditionDetails.removeValue(forKey: disease)
        if focusedCondition == disease {
            focusedCondition = chronicConditions.last
        }
    }

    private func addCustomDisease() {
        let name = resolvedCustomDiseaseName
        guard name.isEmpty == false else { return }
        guard chronicConditions.contains(name) == false else {
            customDiseaseText = ""
            focusedCondition = name
            return
        }
        chronicConditions.append(name)
        focusedCondition = name
        if conditionDetails[name] == nil {
            conditionDetails[name] = MedicalGuideChronicConditionDetail()
        }
        customDiseaseText = ""
        searchText = ""
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
