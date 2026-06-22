import SwiftUI

struct MemberRelationshipGenderStepView: View {
    @Binding var draft: MemberSetupDraft
    let canAdvance: Bool
    let isLoading: Bool
    let onBack: () -> Void
    let onNext: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MemberSetupHeroView(
                    systemImage: "person.2.fill",
                    accentColor: .systemPurple
                )

                MemberSetupStepperCard(
                    title: L10n.text("home.members.field.relationship"),
                    subtitle: L10n.text("home.members.relationship.subtitle", fallback: "确认与当前账号的关系与性别"),
                    systemImage: "figure.2.and.child.holdinghands"
                ) {
                    VStack(spacing: 12) {
                        ForEach(MemberRelationshipCatalog.rows, id: \.self) { rowCodes in
                            HStack(spacing: 12) {
                                ForEach(rowCodes, id: \.self) { code in
                                    let option = MemberRelationshipCatalog.option(for: code)
                                    relationshipChip(title: option.title, isSelected: draft.relationshipCode == code) {
                                        draft.relationshipCode = code
                                        if let inferredGender = option.inferredGender {
                                            draft.gender = inferredGender
                                        } else {
                                            draft.gender = MemberRelationshipCatalog.unsetGender
                                        }
                                        triggerHaptic(style: .light)
                                    }
                                }
                            }
                        }
                    }
                }

                MemberSetupStepperCard(
                    title: L10n.text("home.members.field.gender"),
                    systemImage: "person.fill"
                ) {
                    HStack(spacing: 12) {
                        genderChip(title: L10n.text("home.members.gender.male"), value: "male", systemImage: "figure.stand")
                        genderChip(title: L10n.text("home.members.gender.female"), value: "female", systemImage: "figure.stand.dress")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("home.members.relationship.title", fallback: "成员关系"))
        .navigationBarTitleDisplayMode(.inline)
        .memberSetupBottomBar(
            primaryTitle: L10n.text("home.members.add.save", fallback: "创建"),
            primaryEnabled: canAdvance,
            isLoading: isLoading,
            onPrimary: onNext,
            secondaryTitle: L10n.text("common.back", fallback: "上一步"),
            onSecondary: onBack
        )
    }

    private func relationshipChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(uiColor: .secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func genderChip(title: String, value: String, systemImage: String) -> some View {
        Button {
            draft.gender = value
            triggerHaptic(style: .light)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: draft.gender == value ? "\(systemImage).fill" : systemImage)
                    .symbolRenderingMode(.hierarchical)
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(draft.gender == value ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(draft.gender == value ? Color.accentColor.opacity(0.14) : Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(draft.gender == value ? Color.accentColor : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func triggerHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
#endif
    }
}
