import SwiftUI

/// 公共底部操作区尺寸（拍摄 / 完成 / 删除），报告类与药盒共用。
struct MedicalDocumentBottomActionMetrics {
    let panelHeight: CGFloat

    var topPadding: CGFloat { clamp(panelHeight * 0.08, min: 12, max: 18) }
    var rowSpacing: CGFloat { clamp(panelHeight * 0.10, min: 14, max: 20) }
    var captureButtonOuter: CGFloat { clamp(panelHeight * 0.33, min: 72, max: 84) }
    var captureButtonInner: CGFloat { captureButtonOuter * 0.81 }
    var captureStrokeWidth: CGFloat { 5 }
    var captureIconSize: CGFloat { captureButtonInner * 0.38 }
    var sideActionWidth: CGFloat { clamp(panelHeight * 0.83, min: 72, max: 188) }
    var titleIconSize: CGFloat { clamp(panelHeight * 0.07, min: 16, max: 18) }
    var finishHorizontalPadding: CGFloat { 18 }
    var finishVerticalPadding: CGFloat { 10 }
    var finishCornerRadius: CGFloat { 12 }
    var deleteButtonSize: CGFloat { clamp(panelHeight * 0.11, min: 22, max: 28) }
    var deleteIconSize: CGFloat { deleteButtonSize * 0.40 }
    var deleteButtonOffset: CGFloat { deleteButtonSize * 0.20 }

    /// 防连拍间隔（纳秒）。
    static let captureCooldownNanoseconds: UInt64 = 1_200_000_000

    private func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.min(maxValue, Swift.max(minValue, value))
    }
}

/// 公共拍摄按钮、完成按钮、删除按钮与底部面板背景。
enum MedicalDocumentCameraChrome {
    static func captureButton(
        accentColor: Color,
        metrics: MedicalDocumentBottomActionMetrics,
        isEnabled: Bool,
        isCapturing: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(accentColor.opacity(0.35), lineWidth: metrics.captureStrokeWidth)
                    .frame(width: metrics.captureButtonOuter, height: metrics.captureButtonOuter)

                Circle()
                    .fill(accentColor)
                    .frame(width: metrics.captureButtonInner, height: metrics.captureButtonInner)

                Image(systemName: "camera.fill")
                    .font(.system(size: metrics.captureIconSize, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isCapturing)
        .opacity(!isEnabled || isCapturing ? 0.55 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCapturing)
    }

    static func finishButton(
        accentColor: Color,
        metrics: MedicalDocumentBottomActionMetrics,
        canFinish: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(L10n.text("common.done", fallback: "完成"))
                .font(.system(.headline, design: .default).weight(.semibold))
                .foregroundColor(
                    canFinish
                        ? Color(uiColor: .systemBackground)
                        : Color(uiColor: .tertiaryLabel)
                )
                .padding(.horizontal, metrics.finishHorizontalPadding)
                .padding(.vertical, metrics.finishVerticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: metrics.finishCornerRadius, style: .continuous)
                        .fill(
                            canFinish
                                ? accentColor
                                : Color(uiColor: .secondarySystemBackground)
                        )
                )
        }
        .buttonStyle(.plain)
        .frame(width: metrics.sideActionWidth)
    }

    static func deleteButton(
        size: CGFloat,
        iconSize: CGFloat,
        offset: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: iconSize, weight: .bold))
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.black.opacity(0.55)))
        }
        .buttonStyle(.plain)
        .offset(x: offset, y: -offset)
    }

    static func deleteButton(
        metrics: MedicalDocumentBottomActionMetrics,
        action: @escaping () -> Void
    ) -> some View {
        deleteButton(
            size: metrics.deleteButtonSize,
            iconSize: metrics.deleteIconSize,
            offset: metrics.deleteButtonOffset,
            action: action
        )
    }

    static func bottomPanelBackground() -> some View {
        MedicalDocumentTopRoundedRectangle(cornerRadius: MedicalDocumentCameraShapes.bottomPanelCornerRadius)
            .fill(Color(uiColor: .systemBackground))
    }

    static func titleLeading(
        icon: String,
        title: String,
        accentColor: Color,
        metrics: MedicalDocumentBottomActionMetrics
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: metrics.titleIconSize, weight: .semibold))
                .foregroundColor(accentColor)

            Text(title)
                .font(.system(.title3, design: .default).weight(.bold))
                .foregroundColor(Color(uiColor: .label))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: metrics.sideActionWidth)
    }
}
