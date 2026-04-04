import Foundation

/// 集中管理文案 Key，避免 UI 层散落硬编码字符串。
enum L10n {
    static func text(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: .main)
    }

    static func metricTitle(_ type: HealthMetricType) -> String {
        switch type {
        case .steps:
            return text("metric.steps")
        case .sleep:
            return text("metric.sleep")
        case .heartRate:
            return text("metric.heart_rate")
        case .weight:
            return text("metric.weight")
        }
    }

    static func homeGreeting(_ name: String) -> String {
        String(
            format: text("home.greeting"),
            locale: Locale.current,
            name
        )
    }
}
