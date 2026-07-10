import CoreGraphics
import Foundation

extension MedicalDocumentCameraLayout {
    /// 布局可复现校验：覆盖小屏 / 常规 / 大屏 / 宽屏与横屏极端输入。
    static func validateProfiles() -> [String] {
        var failures: [String] = []
        let sizes: [CGSize] = [
            CGSize(width: 320, height: 480),
            CGSize(width: 375, height: 667),
            CGSize(width: 390, height: 844),
            CGSize(width: 430, height: 932),
            CGSize(width: 768, height: 1024),
            CGSize(width: 1024, height: 768),
            CGSize(width: 200, height: 200)
        ]

        for profile in [MedicalDocumentCameraLayoutProfile.reportDocument, .medicineBox] {
            for size in sizes {
                let layout = MedicalDocumentCameraLayout(contentSize: size, profile: profile)
                let label = "profile=\(profile.minimumAspect)-\(profile.maximumAspect) size=\(Int(size.width))x\(Int(size.height))"

                if layout.viewfinderRect.minX < -0.5 {
                    failures.append("\(label): viewfinderRect.minX < 0")
                }
                if layout.viewfinderRect.minY < -0.5 {
                    failures.append("\(label): viewfinderRect.minY < 0")
                }
                if layout.viewfinderRect.maxX > size.width + 0.5 {
                    failures.append("\(label): viewfinderRect.maxX > contentWidth")
                }
                if layout.viewfinderRect.width.isNaN || layout.viewfinderRect.height.isNaN {
                    failures.append("\(label): NaN in viewfinderRect")
                }
                if layout.viewfinderRect.width < 0 || layout.viewfinderRect.height < 0 {
                    failures.append("\(label): negative viewfinder size")
                }
                if layout.viewfinderRect.height > 0.5,
                   layout.viewfinderRect.maxY > layout.promptY + 0.5 {
                    failures.append("\(label): viewfinder overlaps prompt")
                }
                if layout.promptY > layout.bottomPanelTop + 0.5 {
                    failures.append("\(label): prompt overlaps bottom panel")
                }

                if layout.viewfinderRect.width > 1 {
                    let aspect = layout.viewfinderRect.height / layout.viewfinderRect.width
                    if aspect + 0.02 < profile.minimumAspect || aspect - 0.02 > profile.maximumAspect {
                        // 极端高度不足时允许被可用高度压缩，但仍不得为负。
                        if size.height >= 480,
                           (aspect + 0.02 < profile.minimumAspect || aspect - 0.02 > profile.maximumAspect) {
                            failures.append("\(label): aspect \(aspect) outside \(profile.minimumAspect)...\(profile.maximumAspect)")
                        }
                    }
                }
            }
        }

        return failures
    }
}
