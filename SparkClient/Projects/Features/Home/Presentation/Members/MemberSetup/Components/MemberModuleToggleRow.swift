import SwiftUI

struct MemberModuleToggleRow: View {
    let module: MemberSetupModule
    let isSelected: Bool
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Button(action: onOpen) {
                HStack(alignment: .center, spacing: 18) {
                    moduleIcon

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(module.title)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.primary)

                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(Color(uiColor: .systemGreen))
                            }
                        }

                        Text(module.subtitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(uiColor: .systemBlue))

                        Text(description)
                            .font(.subheadline)
                            .lineSpacing(4)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onOpen) {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? Color(uiColor: .systemGreen) : Color(uiColor: .systemGray2))
                    .frame(width: 36, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(isSelected ? Color(uiColor: .systemGreen) : .clear, lineWidth: 1.5)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 14, x: 0, y: 8)
    }

    private var moduleIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(iconColor)
                .frame(width: 76, height: 76)

            Image(systemName: iconName)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var iconName: String {
        switch module {
        case .medical:
            return "heart.fill"
        case .nutrition:
            return "fork.knife"
        case .dailyHealth:
            return "figure.walk"
        }
    }

    private var iconColor: Color {
        switch module {
        case .medical:
            return Color(red: 1.0, green: 0.33, blue: 0.38)
        case .nutrition:
            return Color(red: 0.29, green: 0.79, blue: 0.39)
        case .dailyHealth:
            return Color(uiColor: .systemBlue)
        }
    }

    private var description: String {
        switch module {
        case .medical:
            return "记录慢性病史、用药计划与体检报告，持续追踪症状变化，辅助健康随访与病情管理。"
        case .nutrition:
            return "制定个性化饮食计划，追踪每日营养摄入与热量，科学管理体重与体脂变化。"
        case .dailyHealth:
            return "记录运动、睡眠、饮水和照护提醒，帮助形成稳定的日常健康习惯。"
        }
    }
}
