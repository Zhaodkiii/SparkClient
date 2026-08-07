import SwiftUI

struct TaskRepeatEditSheet: View {
    let onSelectInstance: () -> Void
    let onSelectPlan: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(NSLocalizedString("task.repeat.edit.title", comment: "修改重复任务"))
                .font(.headline)

            Text(NSLocalizedString("task.repeat.edit.message", comment: "请选择修改范围"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: onSelectInstance) {
                Text(NSLocalizedString("task.repeat.edit.instance", comment: "修改本次实例"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button(action: onSelectPlan) {
                Text(NSLocalizedString("task.repeat.edit.plan", comment: "修改整个周期计划"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(role: .cancel, action: onCancel) {
                Text(NSLocalizedString("common.cancel", comment: "取消"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
        .presentationDetents([.medium])
    }
}

struct TaskExecutionActionSheet: View {
    let isSubmitting: Bool
    let onDone: () -> Void
    let onSkip: () -> Void
    let onFail: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            executionButton(
                title: NSLocalizedString("task.action.done", comment: "完成"),
                systemImage: "checkmark.circle.fill",
                tint: .green,
                action: onDone
            )
            executionButton(
                title: NSLocalizedString("task.action.skip", comment: "跳过"),
                systemImage: "forward.fill",
                tint: Color(uiColor: .systemTeal),
                action: onSkip
            )
            executionButton(
                title: NSLocalizedString("task.action.fail", comment: "失败"),
                systemImage: "xmark.circle.fill",
                tint: .red,
                action: onFail
            )
        }
        .disabled(isSubmitting)
        .opacity(isSubmitting ? 0.6 : 1)
    }

    private func executionButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }
}
