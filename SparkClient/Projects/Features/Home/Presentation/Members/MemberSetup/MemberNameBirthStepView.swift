import SwiftUI

struct MemberNameBirthStepView: View {
    @Binding var draft: MemberSetupDraft
    let canAdvance: Bool
    let onNext: () -> Void

    @State private var keyboardVisible = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MemberSetupHeroView(
                    systemImage: "person.crop.circle.fill",
                    accentColor: .systemBlue
                )

                MemberSetupStepperCard(
                    title: L10n.text("home.members.field.basic_info", fallback: "基本信息"),
                    subtitle: L10n.text("home.members.add.subtitle", fallback: "先填写成员的基础信息"),
                    systemImage: "person.text.rectangle"
                ) {
                    MemberSetupStepperTextField(
                        title: L10n.text("home.members.field.name"),
                        text: $draft.name,
                        placeholder: L10n.text("home.members.field.name_placeholder"),
                        required: true,
                        keyboardVisible: $keyboardVisible
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("home.members.add.title"))
        .navigationBarTitleDisplayMode(.inline)
        .memberSetupBottomBar(
            primaryTitle: L10n.text("common.next", fallback: "下一步"),
            primaryEnabled: canAdvance,
            keyboardVisible: keyboardVisible,
            onPrimary: onNext
        )
    }
}
