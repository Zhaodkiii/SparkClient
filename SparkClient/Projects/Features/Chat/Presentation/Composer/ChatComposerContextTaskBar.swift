import SwiftUI

struct ChatComposerContextTaskBar: View {
    let smallTasks: [SmallTask]
    let onSmallTaskTapped: (SmallTask) -> Void

    private var hasContent: Bool {
        smallTasks.isEmpty == false
    }

    var body: some View {
        if hasContent {
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
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
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
