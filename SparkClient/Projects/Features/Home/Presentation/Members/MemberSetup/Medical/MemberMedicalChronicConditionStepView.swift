import SwiftUI

struct MemberMedicalChronicConditionStepView: View {
    @Binding var chronicConditions: [String]

    private let options = ["糖尿病", "高血压", "高血脂", "痛风", "脂肪肝", "肾病", "其他"]

    var body: some View {
        MemberSetupSection(title: "慢病档案") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(options, id: \.self) { condition in
                    chip(title: condition, isSelected: chronicConditions.contains(condition)) {
                        toggle(condition)
                    }
                }
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
