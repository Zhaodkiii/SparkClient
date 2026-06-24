import SwiftUI

struct MemberMedicalExamIndicatorStepView: View {
    @Binding var examFocus: [String]

    private let options = ["血糖", "血脂", "尿酸", "肝肾功能"]

    var body: some View {
        MemberSetupSection(title: L10n.text("member.setup.medical.general.5567db")) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(options, id: \.self) { option in
                    Toggle(option, isOn: Binding(
                        get: { examFocus.contains(option) },
                        set: { isOn in
                            if isOn {
                                if examFocus.contains(option) == false { examFocus.append(option) }
                            } else {
                                examFocus.removeAll { $0 == option }
                            }
                        }
                    ))
                }
            }
        }
    }
}

