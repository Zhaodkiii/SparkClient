import CoreGraphics

/// 医疗文档相机取景框与底部面板的纯计算布局（可脱离 SwiftUI 验证）。
struct MedicalDocumentCameraLayout: Equatable {
    let viewfinderRect: CGRect
    let bottomPanelHeight: CGFloat
    let promptY: CGFloat
    let contentSize: CGSize
    let profile: MedicalDocumentCameraLayoutProfile

    var bottomPanelTop: CGFloat {
        contentSize.height - bottomPanelHeight
    }

    var maskCornerRadius: CGFloat {
        min(viewfinderRect.width, viewfinderRect.height) * profile.maskCornerRadiusFactor
    }

    init(contentSize: CGSize, profile: MedicalDocumentCameraLayoutProfile) {
        self.contentSize = contentSize
        self.profile = profile

        let availableWidth = max(0, contentSize.width)
        let contentHeight = max(0, contentSize.height)

        let bottomPanelHeight = Self.clamp(
            contentHeight * profile.bottomPanelHeightRatio,
            min: profile.bottomPanelHeightMin,
            max: profile.bottomPanelHeightMax
        )

        let cameraAreaTop = profile.topVerticalGap
        let bottomPanelTop = contentHeight - bottomPanelHeight
        let promptBottomLimit = bottomPanelTop - profile.bottomVerticalGap
        let cameraAreaBottom = promptBottomLimit - profile.promptHeight
        let cameraAreaHeight = max(0, cameraAreaBottom - cameraAreaTop)

        let preferredWidth = min(max(0, availableWidth - 32), 440)
        let availableAspect = preferredWidth > 0 ? cameraAreaHeight / preferredWidth : profile.maximumAspect
        let viewfinderAspect = Self.clamp(
            availableAspect,
            min: profile.minimumAspect,
            max: profile.maximumAspect
        )
        let viewfinderHeight = min(cameraAreaHeight, preferredWidth * viewfinderAspect)
        let viewfinderWidth = min(preferredWidth, viewfinderHeight / max(viewfinderAspect, .leastNonzeroMagnitude))
        let remainingVerticalSpace = max(0, cameraAreaHeight - viewfinderHeight)
        let viewfinderTop = cameraAreaTop + remainingVerticalSpace * 0.35

        let viewfinderRect = CGRect(
            x: (availableWidth - viewfinderWidth) / 2,
            y: viewfinderTop,
            width: max(0, viewfinderWidth),
            height: max(0, viewfinderHeight)
        )

        let idealPromptY = viewfinderRect.maxY + profile.viewfinderPromptGap + profile.promptHeight / 2
        let maxPromptY = promptBottomLimit - profile.promptHeight / 2

        self.bottomPanelHeight = bottomPanelHeight
        self.viewfinderRect = viewfinderRect
        self.promptY = min(idealPromptY, maxPromptY)
    }

    private static func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.min(maxValue, Swift.max(minValue, value))
    }
}
