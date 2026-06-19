import SwiftUI

struct MemberRelationshipGenderStepView: View {
    @Binding var draft: MemberSetupDraft
    let canAdvance: Bool
    let isLoading: Bool
    let onBack: () -> Void
    let onNext: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MemberSetupStepHeaderView(
                    title: L10n.text("home.members.relationship.title", fallback: "成员关系"),
                    subtitle: L10n.text("home.members.relationship.subtitle", fallback: "确认与当前账号的关系与性别"),
                    step: 2,
                    total: 3
                )

                MemberSetupSection(title: L10n.text("home.members.field.relationship")) {
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

                MemberSetupSection(title: L10n.text("home.members.field.gender")) {
                    HStack(spacing: 12) {
                        genderChip(title: L10n.text("home.members.gender.male"), value: "male")
                        genderChip(title: L10n.text("home.members.gender.female"), value: "female")
                    }
                }

            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
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
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(uiColor: .secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func genderChip(title: String, value: String) -> some View {
        Button {
            draft.gender = value
            triggerHaptic(style: .light)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: draft.gender == value ? "record.circle.fill" : "circle")
                    .symbolRenderingMode(.hierarchical)
                Text(title)
            }
            .foregroundStyle(draft.gender == value ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(draft.gender == value ? Color.accentColor.opacity(0.12) : Color.clear)
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
