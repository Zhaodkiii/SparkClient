import Foundation

/// 健康数据授权状态。
nonisolated enum HealthAuthorizationStatus: String, Codable, Sendable {
    case notDetermined = "not_determined"
    case authorized = "authorized"
    case denied = "denied"
    case partial = "partial"
    case revoked = "revoked"

    /// 是否可以读取数据（部分授权也允许读取已授权的部分）。
    var canAccessData: Bool {
        switch self {
        case .authorized, .partial:
            return true
        default:
            return false
        }
    }

    /// 是否为异常状态（需要在卡片上展示"数据异常"标记）。
    var isAbnormal: Bool {
        switch self {
        case .denied, .revoked, .notDetermined:
            return true
        default:
            return false
        }
    }

    /// 展示状态文案。
    var statusText: String {
        switch self {
        case .notDetermined:
            return L10n.text("device.status.not_determined", fallback: "未授权")
        case .authorized:
            return L10n.text("device.status.authorized", fallback: "已同步")
        case .denied:
            return L10n.text("device.status.denied", fallback: "已拒绝")
        case .partial:
            return L10n.text("device.status.partial", fallback: "部分授权")
        case .revoked:
            return L10n.text("device.status.data_abnormal", fallback: "数据异常")
        }
    }
}