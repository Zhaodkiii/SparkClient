import Foundation

// MARK: - 运动健康模块领域模型
//
// 运动健康（Fitness）是一个独立 Feature：在 iOS26 主导航中作为一个 Tab，
// 聚合「用户健康档案（体重/BMI）」「苹果健康（睡眠/步数/运动/热量/血氧/心率等）」
// 与「饮食营养（当日摄入热量）」，为后续接入血糖、血压等设备预留占位。

/// 指标状态：正常 / 偏低 / 偏高 / 无数据。
enum FitnessMetricStatus: Equatable, Sendable {
    case normal
    case low
    case high
    case noData
}

/// 运动健康仪表盘中的指标类型。
enum FitnessMetricType: String, CaseIterable, Sendable, Identifiable {
    case sleep
    case nutrition
    case steps
    case workout
    case calories
    case standHour
    case exerciseTime
    case bloodOxygen
    case heartRate
    case bloodGlucose
    case bloodPressure

    var id: String { rawValue }
}

/// 单个健康指标卡片数据。
///
/// `displayText` 用于需要自定义主文本的指标（如「4h47m」「768 / 10000」），
/// 为空时由卡片根据 `value` + `unit` 自行拼接。
struct FitnessMetricValue: Identifiable, Equatable, Sendable {
    let type: FitnessMetricType
    var value: Double?
    var unit: String
    var displayText: String?
    var timestamp: Date?
    var status: FitnessMetricStatus = .normal
    /// 附加标签（如运动类型「羽毛球」、BMI 分类「标准」）。
    var label: String?

    var id: FitnessMetricType { type }

    static func noData(_ type: FitnessMetricType, unit: String = "") -> FitnessMetricValue {
        FitnessMetricValue(
            type: type,
            value: nil,
            unit: unit,
            displayText: nil,
            timestamp: nil,
            status: .noData,
            label: nil
        )
    }

    /// 未授权 HealthKit 时的 HealthKit 指标占位。
    static var healthPlaceholders: [FitnessMetricValue] {
        [
            .noData(.sleep),
            .noData(.steps),
            .noData(.workout),
            .noData(.calories),
            .noData(.standHour),
            .noData(.exerciseTime),
            .noData(.bloodOxygen),
            .noData(.heartRate),
        ]
    }

    /// 血糖 / 血压为后期接入预留，当前始终占位。
    static var reservedPlaceholders: [FitnessMetricValue] {
        [
            .noData(.bloodGlucose, unit: "mmol/L"),
            .noData(.bloodPressure, unit: "mmHg"),
        ]
    }
}

/// 身材管理数据（来自用户健康档案 / 营养目标）。
struct FitnessBodyMetrics: Equatable, Sendable {
    var weightKg: Double?
    var heightCm: Double?
    var bmi: Double?
    var bodyFatPercent: Double?

    var hasData: Bool {
        weightKg != nil || bmi != nil || bodyFatPercent != nil
    }
}

/// 运动健康仪表盘聚合结果。
struct FitnessDashboard: Equatable, Sendable {
    var isAppleHealthBound: Bool
    var bodyMetrics: FitnessBodyMetrics
    var metrics: [FitnessMetricValue]

    var healthMetrics: [FitnessMetricValue] {
        metrics.filter { $0.type != .nutrition && $0.type != .bloodGlucose && $0.type != .bloodPressure }
    }

    var reservedMetrics: [FitnessMetricValue] {
        metrics.filter { $0.type == .bloodGlucose || $0.type == .bloodPressure }
    }

    func metric(_ type: FitnessMetricType) -> FitnessMetricValue? {
        metrics.first { $0.type == type }
    }
}