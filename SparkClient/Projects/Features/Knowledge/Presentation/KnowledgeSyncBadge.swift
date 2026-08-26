import SwiftUI

/// 知识文档同步状态标识：固定位置、图标+颜色+文案+无障碍文本齐全，不单靠颜色表达（工单 5.9、11.6）。
///
/// 纯展示组件，不自带手势——`failedRetryable` 的点击重试由调用方在 `List` 行内用独立 `Button`
/// 包裹（`.buttonStyle(.borderless)`），这样才能与同一行的 `NavigationLink` 主操作区分，
/// 否则嵌套手势会被 `NavigationLink` 吞掉。
struct KnowledgeSyncBadge: View {
    let state: KnowledgeSyncState

    var body: some View {
        content
            .font(.caption2)
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(accessibilityText))
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .localOnly:
            badge(systemImage: "icloud.slash", tint: .secondary, text: L10n.text("knowledge.sync.state.local_only"))
        case .pending:
            badge(systemImage: "arrow.up.circle", tint: .secondary, text: L10n.text("knowledge.sync.state.pending"))
        case .syncing:
            HStack(spacing: 3) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .modifier(SpinningIconModifier())
                Text(L10n.text("knowledge.sync.state.syncing"))
            }
            .foregroundStyle(.blue)
        case .synced:
            badge(systemImage: "checkmark.icloud", tint: .green, text: L10n.text("knowledge.sync.state.synced"))
        case .failedRetryable:
            badge(systemImage: "exclamationmark.icloud", tint: .orange, text: L10n.text("knowledge.sync.state.failed_retryable"))
        case .failedPermanent:
            badge(systemImage: "exclamationmark.icloud.fill", tint: .red, text: L10n.text("knowledge.sync.state.failed_permanent"))
        case .resolvedByServer:
            badge(systemImage: "icloud.and.arrow.down", tint: .blue, text: L10n.text("knowledge.sync.state.resolved_by_server"))
        }
    }

    private func badge(systemImage: String, tint: Color, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
            Text(text)
        }
        .foregroundStyle(tint)
    }

    private var accessibilityText: String {
        switch state {
        case .localOnly: return L10n.text("knowledge.sync.accessibility.local_only")
        case .pending: return L10n.text("knowledge.sync.accessibility.pending")
        case .syncing: return L10n.text("knowledge.sync.accessibility.syncing")
        case .synced: return L10n.text("knowledge.sync.accessibility.synced")
        case .failedRetryable: return L10n.text("knowledge.sync.accessibility.failed_retryable")
        case .failedPermanent: return L10n.text("knowledge.sync.accessibility.failed_permanent")
        case .resolvedByServer: return L10n.text("knowledge.sync.accessibility.resolved_by_server")
        }
    }
}

/// Reduced Motion 下不使用持续旋转动画，改为静态图标（工单 11.6）。
private struct SpinningIconModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSpinning = false

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .rotationEffect(.degrees(isSpinning ? 360 : 0))
                .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: isSpinning)
                .onAppear { isSpinning = true }
        }
    }
}
