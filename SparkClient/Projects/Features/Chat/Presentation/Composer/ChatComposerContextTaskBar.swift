import SwiftUI

struct ChatComposerContextTaskBar: View {
    let boundMemberID: Int?
    let isSending: Bool
    let smallTasks: [SmallTask]
    let healthResourceRefs: [HealthResourceRef]
    let onAskReport: () -> Void
    let onSmallTaskTapped: (SmallTask) -> Void
    let onHealthResourceTapped: (HealthResourceRef) -> Void
    let onRemoveHealthResourceRef: (HealthResourceRef) -> Void
    let onClearHealthResourceRefs: () -> Void

    private var shouldShowAskReportButton: Bool {
        guard let id = boundMemberID, id > 0 else { return false }
        return isSending == false
    }

    private var hasContent: Bool {
        shouldShowAskReportButton
            || smallTasks.isEmpty == false
            || healthResourceRefs.isEmpty == false
    }

    var body: some View {
        if hasContent {
            HStack(spacing: 5) {
                if shouldShowAskReportButton {
                    Button(action: onAskReport) {
                        ChatComposerContextPill(
                            icon: "doc.text.magnifyingglass",
                            title: L10n.text("chat.ask_report.entry.title"),
                            tint: .teal
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.text("chat.ask_report.entry.accessibility"))
                    .disabled(isSending)
                }
                Spacer(minLength: 0)

                if healthResourceRefs.isEmpty == false {
                    healthResourcePreviewStrip
                } else if smallTasks.isEmpty == false {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(smallTasks) { task in
                                Button {
                                    onSmallTaskTapped(task)
                                } label: {
                                    ChatComposerContextPill(
                                        icon: iconName(for: task),
                                        title: task.name,
                                        tint: task.source == .local ? .orange : .blue
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.leading, 8)
//            .padding(.horizontal, 16)
//            .padding(.vertical, 8)
        }
    }

    private var healthResourcePreviewStrip: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(healthResourceRefs.enumerated()), id: \.element.id) { index, ref in
                        HanlinHealthResourceThumbnail(
                            ref: ref,
                            index: index + 1,
                            total: healthResourceRefs.count,
                            onTap: { onHealthResourceTapped(ref) },
                            onRemove: { onRemoveHealthResourceRef(ref) }
                        )
                    }
                }
                .padding(.horizontal, 2)
            }

            if healthResourceRefs.count > 1 {
                Button(action: onClearHealthResourceRefs) {
                    Text(L10n.text("chat.ask_report.strip.clear_all"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("chat.ask_report.strip.clear_all"))
            }
        }
    }

    private func iconName(for task: SmallTask) -> String {
        let trimmed = task.icon.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "checklist" : trimmed
    }
}

private struct ChatComposerContextPill: View {
    let icon: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))

            Text(title)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(
            Capsule()
                .fill(tint.opacity(0.12))
        )
        .overlay(
            Capsule()
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }
}
