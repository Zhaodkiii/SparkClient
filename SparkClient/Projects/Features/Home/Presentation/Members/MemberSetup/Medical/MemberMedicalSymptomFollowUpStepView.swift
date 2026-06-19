import SwiftUI

struct MemberMedicalSymptomFollowUpStepView: View {
    @Binding var symptomFollowUpFocus: [String]
    @Binding var notes: String

    private let options = ["胃肠不适", "浮肿", "血压波动", "血糖波动"]

    var body: some View {
        MemberSetupSection(title: "症状 / 随访") {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(options, id: \.self) { option in
                        Button {
                            toggle(option)
                        } label: {
                            Text(option)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(symptomFollowUpFocus.contains(option) ? Color.accentColor : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(symptomFollowUpFocus.contains(option) ? Color.accentColor.opacity(0.14) : Color(uiColor: .secondarySystemBackground))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("症状随访备注")
                    TextEditor(text: $notes)
                        .frame(minHeight: 88)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(uiColor: .systemBackground)))
                }
            }
        }
    }

    private func toggle(_ option: String) {
        if symptomFollowUpFocus.contains(option) {
            symptomFollowUpFocus.removeAll { $0 == option }
        } else {
            symptomFollowUpFocus.append(option)
        }
    }
}
