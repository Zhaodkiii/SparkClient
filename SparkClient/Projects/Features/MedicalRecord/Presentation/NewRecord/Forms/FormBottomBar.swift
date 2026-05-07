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
    /// 非 `nil` 且为 `true` 时展示右下角「完成」并收起键盘；与表单内 `SparkFormTextRow` / `SparkFormTextAreaRow` 传入同一绑定即可联动。
    let keyboardVisible: Binding<Bool>?
    let onCancel: () -> Void
    let onSave: () -> Void

    init(
        canSubmit: Bool,
        cancelTitle: String?,
        saveTitle: String,
        saveSystemImage: String? = "checkmark.circle.fill",
        keyboardVisible: Binding<Bool>? = nil,
        onCancel: @escaping () -> Void,
        onSave: @escaping () -> Void
    ) {
        self.canSubmit = canSubmit
        self.cancelTitle = cancelTitle
        self.saveTitle = saveTitle
        self.saveSystemImage = saveSystemImage
        self.keyboardVisible = keyboardVisible
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        ZStack(alignment: .bottom) {
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

            if let keyboardVisible, keyboardVisible.wrappedValue {
                HStack {
                    Spacer()
                    Button {
                        SparkKeyboardDismiss.endEditing()
                    } label: {
                        Text(L10n.text("common.done"))
                            .font(.system(size: 16, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.borderless)
                    .padding(.trailing, 10)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: keyboardVisible?.wrappedValue ?? false)
    }
}

extension View {
    /// 使用 `safeAreaInset(edge: .bottom)` 固定底部操作条，滚动内容自动留白，避免与 Home 指示条重叠。
    func sparkFormBottomBar(
        canSubmit: Bool,
        cancelTitle: String? = L10n.text("common.cancel"),
        saveTitle: String,
        saveSystemImage: String? = "checkmark.circle.fill",
        keyboardVisible: Binding<Bool>? = nil,
        onCancel: @escaping () -> Void,
        onSave: @escaping () -> Void
    ) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            SparkFormBottomBar(
                canSubmit: canSubmit,
                cancelTitle: cancelTitle,
                saveTitle: saveTitle,
                saveSystemImage: saveSystemImage,
                keyboardVisible: keyboardVisible,
                onCancel: onCancel,
                onSave: onSave
            )
        }
    }
}
