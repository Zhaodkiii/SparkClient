import Foundation

/// 公共图片预览加载失败原因（展示层需映射为本地化文案）。
nonisolated enum SecondCameraMediaPreviewLoadError: Error, Equatable, Sendable {
    case fileMissing
    case unsupportedType
    case cannotCreateImageSource
    case cannotDecodeImage
    case cancelled

    var localizedUserMessage: String {
        switch self {
        case .fileMissing:
            return SecondCameraEditorL10n.PublicPreview.fileMissing
        case .unsupportedType, .cannotCreateImageSource, .cannotDecodeImage:
            return SecondCameraEditorL10n.PublicPreview.imageLoadFailed
        case .cancelled:
            return SecondCameraEditorL10n.PublicPreview.imageLoadFailed
        }
    }

    var logCode: String {
        switch self {
        case .fileMissing: return "file_missing"
        case .unsupportedType: return "unsupported_type"
        case .cannotCreateImageSource: return "cannot_create_image_source"
        case .cannotDecodeImage: return "cannot_decode_image"
        case .cancelled: return "cancelled"
        }
    }
}
