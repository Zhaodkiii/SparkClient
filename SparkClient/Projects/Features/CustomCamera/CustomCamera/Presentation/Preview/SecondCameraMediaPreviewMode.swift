import Foundation

/// 媒体预览能力模式。
/// - `readOnly`：公共只读预览，不允许编辑或变更输入集合。
/// - `cameraEditable`：仅相机拍摄后预览使用，保留编辑与结果回传。
enum SecondCameraMediaPreviewMode: Equatable, Sendable {
    case readOnly
    case cameraEditable
}
