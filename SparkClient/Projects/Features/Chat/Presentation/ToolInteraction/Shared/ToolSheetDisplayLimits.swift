import CoreGraphics
import UIKit

enum ToolSheetDisplayLimits {
    static let maxResultChars = 32_000
    static let maxArgumentChars = 12_000
    static let maxToolPreviewChars = 32_000
    static let maxPreviewHeight: CGFloat = 320

    static func responsiveMaxPreviewHeight(for screenHeight: CGFloat) -> CGFloat {
        min(360, screenHeight * 0.35)
    }
}
