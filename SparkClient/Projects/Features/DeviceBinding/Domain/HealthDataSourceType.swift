import Foundation

/// 健康数据来源分类。
nonisolated enum DataSourceCategory: String, Codable, Sendable {
    case accountData = "account_data"
    case medicalDevice = "medical_device"
}

/// 健康数据来源类型。
nonisolated enum HealthDataSourceType: String, Codable, CaseIterable, Sendable, Identifiable {
    case appleHealth = "apple_health"
    case huaweiHealth = "huawei_health"
    case vivoHealth = "vivo_health"
    case coros = "coros"

    case bloodPressureMonitor = "bp_monitor"
    case glucometer = "glucometer"

    var id: String { rawValue }

    /// 当前阶段是否已接入（仅苹果健康可用）。
    var isAvailable: Bool {
        switch self {
        case .appleHealth:
            return true
        default:
            return false
        }
    }

    /// 数据源分类。
    var category: DataSourceCategory {
        switch self {
        case .appleHealth, .huaweiHealth, .vivoHealth, .coros:
            return .accountData
        case .bloodPressureMonitor, .glucometer:
            return .medicalDevice
        }
    }

    /// 显示名称。
    var displayName: String {
        switch self {
        case .appleHealth:
            return L10n.text("device.source.apple_health", fallback: "苹果健康")
        case .huaweiHealth:
            return L10n.text("device.source.huawei_health", fallback: "华为运动健康")
        case .vivoHealth:
            return L10n.text("device.source.vivo_health", fallback: "vivo健康")
        case .coros:
            return L10n.text("device.source.coros", fallback: "COROS高驰")
        case .bloodPressureMonitor:
            return L10n.text("device.source.bp_x7", fallback: "讯飞臂筒式血压计 X7")
        case .glucometer:
            return L10n.text("device.source.glucometer", fallback: "血糖仪")
        }
    }

    /// 描述文案。
    var summary: String {
        switch self {
        case .appleHealth:
            return L10n.text("device.source.apple_health.desc", fallback: "支持用户将苹果账号下的健康数据同步至讯飞晓医")
        case .huaweiHealth:
            return L10n.text("device.source.huawei_health.desc", fallback: "支持用户将HUAWEI Health账号的健康数据同步至讯飞晓医")
        case .vivoHealth:
            return L10n.text("device.source.vivo_health.desc", fallback: "支持用户将vivo账号下的健康数据同步至讯飞晓医")
        case .coros:
            return L10n.text("device.source.coros.desc", fallback: "支持用户将COROS账号下的健康数据同步至讯飞晓医")
        case .bloodPressureMonitor:
            return L10n.text("device.source.bp_x7.desc", fallback: "讯飞臂筒式血压计 X7")
        case .glucometer:
            return L10n.text("device.source.glucometer.desc", fallback: "血糖仪")
        }
    }

    /// 图标背景色十六进制值。
    var iconBackgroundHex: String {
        switch self {
        case .appleHealth:
            return "#000000"
        case .huaweiHealth:
            return "#FF6B00"
        case .vivoHealth:
            return "#34D399"
        case .coros:
            return "#1A1A1A"
        case .bloodPressureMonitor, .glucometer:
            return "#F3F4F6"
        }
    }

    /// 是否使用苹果 Logo（区别于 SF Symbol）。
    var usesAppleLogo: Bool {
        self == .appleHealth
    }
}