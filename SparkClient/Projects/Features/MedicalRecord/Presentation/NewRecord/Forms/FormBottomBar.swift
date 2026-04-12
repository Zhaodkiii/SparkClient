import SwiftUI

// MARK: - 底部主操作条样式（与 HealthClient FormBottomBar 视觉对齐，供病历草稿表单复用）

private struct SparkFormBorderButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.secondary.opacity(scheme == .dark ? 0.35 : 0.22), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

private struct SparkFormPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(configuration.isPressed ? Color.accentColor.opacity(0.85) : Color.accentColor)
            .foregroundStyle(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// 吸底的「取消 + 主操作」条：与 `sparkFormBottomBar`（`safeAreaInset`）搭配使用。
struct SparkFormBottomBar: View {
    @Environment(\.colorScheme) private var scheme

    let canSubmit: Bool
    let cancelTitle: String?
    let saveTitle: String
    let saveSystemImage: String?
    let onCancel: () -> Void
    let onSave: () -> Void

    init(
        canSubmit: Bool,
        cancelTitle: String?,
        saveTitle: String,
        saveSystemImage: String? = "checkmark.circle.fill",
        onCancel: @escaping () -> Void,
        onSave: @escaping () -> Void
    ) {
        self.canSubmit = canSubmit
        self.cancelTitle = cancelTitle
        self.saveTitle = saveTitle
        self.saveSystemImage = saveSystemImage
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        HStack(spacing: 12) {
            if let cancelTitle {
                Button(action: onCancel) {
                    Text(cancelTitle)
                }
                .buttonStyle(SparkFormBorderButtonStyle())
            }

            Button(action: onSave) {
                if let sys = saveSystemImage {
                    Label(saveTitle, systemImage: sys)
                        .labelStyle(.titleAndIcon)
                } else {
                    Text(saveTitle)
                }
            }
            .buttonStyle(SparkFormPrimaryButtonStyle())
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.6)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(scheme == .dark ? 0.35 : 0.12), radius: 10, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

extension View {
    /// 使用 `safeAreaInset(edge: .bottom)` 固定底部操作条，滚动内容自动留白，避免与 Home 指示条重叠。
    func sparkFormBottomBar(
        canSubmit: Bool,
        cancelTitle: String? = L10n.text("common.cancel"),
        saveTitle: String,
        saveSystemImage: String? = "checkmark.circle.fill",
        onCancel: @escaping () -> Void,
        onSave: @escaping () -> Void
    ) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            SparkFormBottomBar(
                canSubmit: canSubmit,
                cancelTitle: cancelTitle,
                saveTitle: saveTitle,
                saveSystemImage: saveSystemImage,
                onCancel: onCancel,
                onSave: onSave
            )
        }
    }
}
