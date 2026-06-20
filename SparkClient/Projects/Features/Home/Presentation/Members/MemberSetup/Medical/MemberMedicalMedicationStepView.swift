import SwiftUI

struct MemberMedicalMedicationStepView: View {
    @Binding var longTermMedications: [String]
    @Binding var medicationNotes: String
    @Binding var medicationPlanSummary: String
    let onAddMedicationPlan: () -> Void
    /// 是否展示页面内的“长期用药”开关；病史引导页外层如果已经问过，可以关闭它避免重复提问。
    let showsStatusToggle: Bool
    @State private var draftMedication: String = ""

    init(
        longTermMedications: Binding<[String]>,
        medicationNotes: Binding<String>,
        medicationPlanSummary: Binding<String>,
        onAddMedicationPlan: @escaping () -> Void,
        showsStatusToggle: Bool = true
    ) {
        _longTermMedications = longTermMedications
        _medicationNotes = medicationNotes
        _medicationPlanSummary = medicationPlanSummary
        self.onAddMedicationPlan = onAddMedicationPlan
        self.showsStatusToggle = showsStatusToggle
    }

    var body: some View {
        MemberSetupSection(title: "用药") {
            VStack(alignment: .leading, spacing: 12) {
                if showsStatusToggle {
                    Toggle("有长期用药", isOn: Binding(
                        get: { longTermMedications.isEmpty == false },
                        set: { isOn in
                            if isOn == false {
                                longTermMedications.removeAll()
                            }
                        }
                    ))
                }

                HStack {
                    TextField("输入药名后添加", text: $draftMedication)
                        .textInputAutocapitalization(.sentences)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(uiColor: .systemBackground)))
                    Button("添加") {
                        let trimmed = draftMedication.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.isEmpty == false else { return }
                        longTermMedications.append(trimmed)
                        draftMedication = ""
                    }
                    .buttonStyle(.borderedProminent)
                }

                if longTermMedications.isEmpty == false {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(longTermMedications.indices, id: \.self) { index in
                            HStack {
                                Text(longTermMedications[index])
                                Spacer()
                                Button("删除") {
                                    longTermMedications.remove(at: index)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                    }
                }

                Button(action: onAddMedicationPlan) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("添加用药计划")
                                .font(.subheadline.weight(.semibold))
                            Text(medicationPlanSummary.isEmpty ? "使用用药计划 Stepper 分页维护" : medicationPlanSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 8) {
                    Text("用药说明 / 提醒备注")
                    TextEditor(text: $medicationNotes)
                        .frame(minHeight: 88)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(uiColor: .systemBackground)))
                }
            }
        }
    }
}
