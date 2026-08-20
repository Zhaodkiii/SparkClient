import SwiftUI

struct IOS26HomeTaskSummaryView: View {
    let summary: IOS26HomeTaskSummary
    let onOpenTaskCenter: () -> Void
    let onOpenTaskItem: (IOS26HomeTaskSummaryItem) -> Void
    let onRetrySync: () -> Void

    private var headerSubtitle: String {
        if let lastSyncTime = summary.lastSyncTime {
            let formatted = DateFormatter.localizedString(from: lastSyncTime, dateStyle: .short, timeStyle: .short)
            return String(format: L10n.text("ios26.home.tasks.last_sync"), formatted)
        }
        return L10n.text("ios26.home.tasks.subtitle.default")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("ios26.home.tasks.title"))
                        .font(.headline.weight(.semibold))
                    Text(headerSubtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.text("ios26.home.tasks.view_all")) {
                    onOpenTaskCenter()
                }
                .font(.footnote.weight(.semibold))
            }

            HStack(spacing: 12) {
                metricPill(
                    title: L10n.text("ios26.home.tasks.metric.pending"),
                    value: "\(summary.pendingCount)",
                    emphasis: summary.pendingCount > 0
                )
                metricPill(
                    title: L10n.text("ios26.home.tasks.metric.overdue"),
                    value: "\(summary.overdueCount)",
                    emphasis: summary.overdueCount > 0,
                    emphasisColor: .red
                )
                metricPill(
                    title: L10n.text("ios26.home.tasks.metric.today"),
                    value: "\(summary.todayCount)",
                    emphasis: summary.todayCount > 0,
                    emphasisColor: .orange
                )
            }

            if summary.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let errorMessage = summary.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(L10n.text("ios26.home.tasks.retry")) {
                    onRetrySync()
                }
                .buttonStyle(.bordered)
            } else if summary.items.isEmpty {
                Text(L10n.text("ios26.home.tasks.empty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(L10n.text("ios26.home.tasks.view_all")) {
                    onOpenTaskCenter()
                }
                .font(.footnote.weight(.semibold))
            } else {
                VStack(spacing: 10) {
                    ForEach(summary.items) { item in
                        Button {
                            onOpenTaskItem(item)
                        } label: {
                            taskPreviewRow(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }

    private func metricPill(title: String, value: String, emphasis: Bool, emphasisColor: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(emphasis ? emphasisColor : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func taskPreviewRow(_ item: IOS26HomeTaskSummaryItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: iconName(for: item.taskType))
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let badgeText = item.badgeText {
                        Text(badgeText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.12)))
                    }
                }
                Text("\(item.subtitle) · \(item.timeText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func iconName(for type: HealthTask.TaskType) -> String {
        switch type {
        case .medical:
            return "cross.case.fill"
        case .exercise:
            return "figure.run"
        case .diet:
            return "fork.knife"
        }
    }
}
