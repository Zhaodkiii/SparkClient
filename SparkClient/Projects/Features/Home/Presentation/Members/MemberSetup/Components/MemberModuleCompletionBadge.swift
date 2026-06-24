import SwiftUI

struct MemberModuleCompletionBadge: View {
    let isCompleted: Bool

    var body: some View {
        Text(isCompleted ? L10n.text("home.members.save.success") : "待完善")
            .font(.caption.weight(.semibold))
            .foregroundStyle(isCompleted ? .green : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous).fill(isCompleted ? Color.green.opacity(0.12) : Color(uiColor: .tertiarySystemBackground))
            )
    }
}
