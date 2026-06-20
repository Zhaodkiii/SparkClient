import SwiftUI

struct MemberMedicalChronicConditionStepView: View {
    @Binding var status: MedicalGuideDisclosureStatus
    @Binding var chronicConditions: [String]

    private let options = ["糖尿病", "高血压", "高血脂", "痛风", "脂肪肝", "肾病", "其他"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("是否有慢病？")
                .font(.headline.weight(.semibold))

            Text("如高血压、糖尿病、高血脂、痛风、脂肪肝、肾病等。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            MedicalGuideDisclosureChoiceRow(status: $status)

            if status == .have {
                MemberSetupSection(title: "慢病类型") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 10)], alignment: .leading, spacing: 10) {
                        ForEach(options, id: \.self) { condition in
                            chip(title: condition, isSelected: chronicConditions.contains(condition)) {
                                toggle(condition)
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: status) { newValue in
            if newValue != .have {
                chronicConditions.removeAll()
            }
        }
    }

    private func toggle(_ condition: String) {
        if chronicConditions.contains(condition) {
            chronicConditions.removeAll { $0 == condition }
        } else {
            chronicConditions.append(condition)
        }
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(uiColor: .secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct MedicalGuideDisclosureChoiceRow: View {
    @Binding var status: MedicalGuideDisclosureStatus

    private let items: [(title: String, value: String)] = [
        ("有", MedicalGuideDisclosureStatus.have.rawValue),
        ("无", MedicalGuideDisclosureStatus.none.rawValue)
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(items, id: \.value) { item in
                Button {
                    status = MedicalGuideDisclosureStatus(rawValue: item.value) ?? .unknown
                } label: {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(status.rawValue == item.value ? Color.accentColor : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule(style: .continuous)
                                .fill(status.rawValue == item.value ? Color.accentColor.opacity(0.14) : Color(uiColor: .systemBackground))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
