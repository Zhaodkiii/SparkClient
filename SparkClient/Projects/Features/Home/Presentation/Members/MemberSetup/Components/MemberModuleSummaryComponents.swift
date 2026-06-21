import SwiftUI

struct MemberModuleProgressBadge: View {
    let status: MemberModuleSectionStatus

    var body: some View {
        Text(status.displayTitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(backgroundColor)
            )
    }

    private var foregroundColor: Color {
        switch status {
        case .notStarted: return .secondary
        case .incomplete: return Color.orange
        case .completed: return Color(uiColor: .systemGreen)
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .notStarted: return Color(uiColor: .tertiarySystemBackground)
        case .incomplete: return Color.orange.opacity(0.12)
        case .completed: return Color(uiColor: .systemGreen).opacity(0.12)
        }
    }
}

struct MemberModuleSummaryHeaderView: View {
    let iconName: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let completedCount: Int
    let totalCount: Int
    var emptyHint: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(iconColor)
                        .frame(width: 52, height: 52)
                    Image(systemName: iconName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title3.weight(.bold))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("已完成 \(completedCount) / \(totalCount)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .systemBlue))
                }
            }

            if let emptyHint, completedCount == 0 {
                Text(emptyHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

struct MemberModuleSectionCard: View {
    let section: MemberModuleSectionProgress
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .frame(width: 44, height: 44)
                    Image(systemName: section.iconName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .systemBlue))
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(section.title)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.primary)
                        MemberModuleProgressBadge(status: section.status)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(section.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(section.summary)
                        .font(.footnote)
                        .foregroundStyle(section.status == .notStarted ? .tertiary : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

struct MemberModuleStartAllCard: View {
    let title: String
    let subtitle: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .systemBlue).opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "play.fill")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Color(uiColor: .systemBlue))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }
}
