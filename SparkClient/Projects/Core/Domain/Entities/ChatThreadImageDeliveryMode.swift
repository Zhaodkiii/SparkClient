import Foundation

/// 会话级图片送达策略（对齐 ZDK `ZDKThreadImageDeliveryMode` 语义）。
enum ChatThreadImageDeliveryMode: String, Codable, Sendable, CaseIterable {
    /// 直发多模态：在模型支持视觉且网关已编码时，将原图以 `image_url` parts 送入 API。
    case directMultimodal = "directMultimodal"
    /// 本地 OCR + 仅文本：上传后拼 oss_file_id / OCR / 用户文字，不向模型送像素。
    case localOCR = "localOCR"
}

/// 运行时有效模式：非视觉模型强制走 OCR 文本语义。
func effectiveChatImageDeliveryMode(
    threadMode: ChatThreadImageDeliveryMode,
    supportsMultimodal: Bool
) -> ChatThreadImageDeliveryMode {
    guard supportsMultimodal else { return .localOCR }
    return threadMode
}
