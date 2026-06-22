import SwiftUI

struct MemberBirthDateStepView: View {
    @Binding var draft: MemberSetupDraft
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MemberSetupHeroView(
                    systemImage: "calendar.badge.clock",
                    accentColor: .systemGreen
                )

                MemberSetupStepperCard(
                    title: L10n.text("home.members.field.birth_date"),
                    subtitle: L10n.text("home.members.birth_date.subtitle", fallback: "年龄会影响健康建议与模块推荐"),
                    systemImage: "calendar"
                ) {
                    VStack(spacing: 16) {
                        DatePicker(
                            L10n.text("home.members.field.birth_date"),
                            selection: birthDateBinding,
                            in: ...Date(),
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()

                        if let ageYears {
                            Label("年龄：\(ageYears) 岁", systemImage: "clock.badge.checkmark")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .symbolRenderingMode(.hierarchical)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("home.members.field.birth_date"))
        .navigationBarTitleDisplayMode(.inline)
        .memberSetupBottomBar(
            primaryTitle: L10n.text("common.next", fallback: "下一步"),
            primaryEnabled: true,
            onPrimary: onNext,
            secondaryTitle: L10n.text("common.skip", fallback: "跳过"),
            onSecondary: onSkip
        )
    }

    private var birthDateBinding: Binding<Date> {
        Binding(
            get: { draft.birthDate ?? defaultBirthDate },
            set: { draft.birthDate = $0 }
        )
    }

    private var defaultBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: -24, to: Date()) ?? Date()
    }

    private var ageYears: Int? {
        guard let birthDate = draft.birthDate else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
    }
}
