import CoreGraphics

/// 医疗文档相机布局参数集。报告类与药盒共用同一布局算法，仅 profile 不同。
struct MedicalDocumentCameraLayoutProfile: Equatable {
    let bottomPanelHeightRatio: CGFloat
    let bottomPanelHeightMin: CGFloat
    let bottomPanelHeightMax: CGFloat
    let promptHeight: CGFloat
    let topVerticalGap: CGFloat
    let bottomVerticalGap: CGFloat
    let viewfinderPromptGap: CGFloat
    let minimumAspect: CGFloat
    let maximumAspect: CGFloat
    let maskCornerRadiusFactor: CGFloat
    let viewfinderLineWidth: CGFloat
    let viewfinderSegmentFactor: CGFloat

    static let reportDocument = MedicalDocumentCameraLayoutProfile(
        bottomPanelHeightRatio: 0.24,
        bottomPanelHeightMin: 196,
        bottomPanelHeightMax: 252,
        promptHeight: 48,
        topVerticalGap: 12,
        bottomVerticalGap: 10,
        viewfinderPromptGap: 10,
        minimumAspect: 1.28,
        maximumAspect: 1.414,
        maskCornerRadiusFactor: 0.06,
        viewfinderLineWidth: 4,
        viewfinderSegmentFactor: 0.14
    )

    static let medicineBox = MedicalDocumentCameraLayoutProfile(
        bottomPanelHeightRatio: 0.26,
        bottomPanelHeightMin: 220,
        bottomPanelHeightMax: 268,
        promptHeight: 52,
        topVerticalGap: 12,
        bottomVerticalGap: 8,
        viewfinderPromptGap: 12,
        minimumAspect: 1.12,
        maximumAspect: 1.24,
        maskCornerRadiusFactor: 0.09,
        viewfinderLineWidth: 5,
        viewfinderSegmentFactor: 0.18
    )
}
