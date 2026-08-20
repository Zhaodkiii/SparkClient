import Foundation

/// 健康数据访问检查结果。
nonisolated enum HealthDataAccessResult: Equatable, Sendable {
    /// 允许访问。
    case granted
    /// 未绑定设备。
    case noBinding(HealthDataSourceType)
    /// 授权被收回。
    case authorizationRevoked
    /// 授权被拒绝。
    case authorizationDenied
    /// 部分授权（附缺失权限标识）。
    case partialAuthorization(Set<String>)
    /// 成员未绑定该数据源。
    case memberNotBound
    /// 数据源当前不可用。
    case dataSourceNotAvailable(HealthDataSourceType)
    /// 设备不支持 HealthKit。
    case healthKitUnavailable

    var isGranted: Bool {
        if case .granted = self { return true }
        return false
    }

    /// 面向用户的错误提示。
    var errorDescription: String {
        switch self {
        case .granted:
            return ""
        case .noBinding:
            return L10n.text("device.access.no_binding", fallback: "尚未绑定健康数据来源，请先添加设备")
        case .authorizationRevoked:
            return L10n.text("device.permission.revoked_message", fallback: "无法获取数据，你的苹果健康可能暂无数据产生或系统权限未开启")
        case .authorizationDenied:
            return L10n.text("device.access.denied", fallback: "健康数据权限被拒绝，请在系统设置中开启")
        case .partialAuthorization:
            return L10n.text("device.access.partial", fallback: "部分健康数据权限未开启，可能导致数据不完整")
        case .memberNotBound:
            return L10n.text("device.access.member_not_bound", fallback: "当前成员未绑定健康数据来源")
        case .dataSourceNotAvailable(let type):
            return L10n.format("device.access.not_available", fallback: "%@暂未接入，敬请期待", type.displayName)
        case .healthKitUnavailable:
            return L10n.text("device.error.healthkit_unavailable", fallback: "当前设备不支持苹果健康")
        }
    }

    /// 是否需要展示权限引导弹窗。
    var shouldShowPermissionGuide: Bool {
        switch self {
        case .authorizationRevoked, .authorizationDenied, .partialAuthorization:
            return true
        default:
            return false
        }
    }
}