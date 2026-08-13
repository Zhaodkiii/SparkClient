import SwiftUI

/// 成员选择胶囊：首页成员列表与导航栏紧凑成员切换共用。
struct MemberSelectorChip: View {
    enum Variant {
        case regular
        case compactToolbar
    }

    let member: Member
    let badgeText: String
    let isSelected: Bool
    let variant: Variant
    let onSelect: () -> Void
    let onViewDetail: () -> Void
    let onShare: () -> Void

    @State private var showActionMenu = false

    init(
        member: Member,
        badgeText: String,
        isSelected: Bool,
        variant: Variant = .regular,
        onSelect: @escaping () -> Void,
        onViewDetail: @escaping () -> Void,
        onShare: @escaping () -> Void
    ) {
        self.member = member
        self.badgeText = badgeText
        self.isSelected = isSelected
        self.variant = variant
        self.onSelect = onSelect
        self.onViewDetail = onViewDetail
        self.onShare = onShare
    }

    var body: some View {
        Button {
            if isSelected {
                showActionMenu = true
            } else {
                onSelect()
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(badgeBackgroundColor)
                    .frame(width: badgeSize, height: badgeSize)
                    .overlay {
                        Text(badgeText)
                            .font(badgeFont)
                            .foregroundStyle(badgeForegroundStyle)
                    }

                Text(member.name)
                    .font(nameFont)
                    .lineLimit(1)
                    .foregroundStyle(nameForegroundStyle)

//                if showsTrailingIcon {
//                    Image(systemName: trailingIconName)
//                        .font(trailingIconFont)
//                        .foregroundStyle(trailingIconColor)
//                }
            }
            .modifier(MemberSelectorChipContainerStyle(variant: variant, isSelected: isSelected))
        }
        .buttonStyle(.plain)
        .confirmationDialog(L10n.text("home.members.action_title"), isPresented: $showActionMenu, titleVisibility: .visible) {
            Button(L10n.text("home.members.action.view_detail"), systemImage: "person.text.rectangle") {
                onViewDetail()
            }
            if member.effectiveBinding.canShare {
                Button(L10n.text("home.members.action.share"), systemImage: "square.and.arrow.up") {
                    onShare()
                }
            }
            Button(L10n.text("common.cancel"), role: .cancel) {}
        }
    }

    private var badgeSize: CGFloat {
        switch variant {
        case .regular:
            return 28
        case .compactToolbar:
            return 34
        }
    }

    private var badgeBackgroundColor: Color {
        switch variant {
        case .regular:
            return Color.accentColor.opacity(isSelected ? 0.25 : 0.14)
        case .compactToolbar:
            return Color.accentColor.opacity(0.18)
        }
    }

    private var badgeFont: Font {
        switch variant {
        case .regular:
            return .caption.weight(.bold)
        case .compactToolbar:
            return .system(size: 17, weight: .bold)
        }
    }

    private var badgeForegroundStyle: Color {
        switch variant {
        case .regular:
            return isSelected ? Color.accentColor.opacity(0.95) : .accentColor
        case .compactToolbar:
            return .accentColor
        }
    }

    private var nameFont: Font {
        switch variant {
        case .regular:
            return .subheadline.weight(.semibold)
        case .compactToolbar:
            return .system(size: 18, weight: .semibold)
        }
    }

    private var nameForegroundStyle: AnyShapeStyle {
        switch variant {
        case .regular:
            return isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary)
        case .compactToolbar:
            return AnyShapeStyle(Color.accentColor)
        }
    }

    private var showsTrailingIcon: Bool {
        switch variant {
        case .regular:
            return isSelected
        case .compactToolbar:
            return true
        }
    }

    private var trailingIconName: String {
        switch variant {
        case .regular:
            return "ellipsis.circle"
        case .compactToolbar:
            return "chevron.down"
        }
    }

    private var trailingIconFont: Font {
        switch variant {
        case .regular:
            return .caption.weight(.semibold)
        case .compactToolbar:
            return .system(size: 16, weight: .semibold)
        }
    }

    private var trailingIconColor: Color {
        switch variant {
        case .regular:
            return .white.opacity(0.95)
        case .compactToolbar:
            return Color.accentColor.opacity(0.55)
        }
    }
}

extension MemberSelectorChip {
    static func badgeText(for member: Member) -> String {
        let display = MemberRelationshipCatalog.displayTitle(for: member.relationship)
        guard let first = display.first else { return "·" }
        return String(first)
    }
}

private struct MemberSelectorChipContainerStyle: ViewModifier {
    let variant: MemberSelectorChip.Variant
    let isSelected: Bool

    func body(content: Content) -> some View {
        switch variant {
        case .regular:
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            isSelected
                            ? Color.clear
                            : Color(uiColor: .quaternaryLabel).opacity(0.24),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(isSelected ? 0.10 : 0.04), radius: isSelected ? 4 : 2, x: 0, y: 2)
        case .compactToolbar:
            content
//                .padding(.leading, 10)
//                .padding(.trailing, 14)
//                .frame(height: 46)
//                .background(
//                    Capsule(style: .continuous)
//                        .fill(Color.white.opacity(0.96))
//                )
//                .shadow(color: Color.black.opacity(0.05), radius: 18, x: 0, y: 8)
        }
    }
}

#if DEBUG
#Preview("Compact Toolbar") {
    let member = Member(
        id: 1,
        name: "赵加富",
        gender: "male",
        relationship: "father",
        isPrimary: false,
        binding: .ownerLike(bindingID: 1)
    )

    return HStack {
        MemberSelectorChip(
            member: member,
            badgeText: MemberSelectorChip.badgeText(for: member),
            isSelected: false,
            variant: .compactToolbar,
            onSelect: {},
            onViewDetail: {},
            onShare: {}
        )
        Spacer()
    }
    .padding(20)
    .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Regular Selected") {
    let member = Member(
        id: 2,
        name: "本人",
        gender: "female",
        relationship: "self",
        isPrimary: true,
        binding: .ownerLike(bindingID: 2)
    )

    return HStack {
        MemberSelectorChip(
            member: member,
            badgeText: MemberSelectorChip.badgeText(for: member),
            isSelected: true,
            onSelect: {},
            onViewDetail: {},
            onShare: {}
        )
        Spacer()
    }
    .padding(20)
    .background(Color(uiColor: .systemGroupedBackground))
}
#endif
