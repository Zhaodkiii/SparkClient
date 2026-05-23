import Foundation

/// 公共分享页支持的分享通道；二期可扩展手机号、App 内通知等。
enum ShareChannel: String, CaseIterable, Identifiable {
    case qrCode
    case nearby
    case remoteInvite

    var id: String { rawValue }
}
