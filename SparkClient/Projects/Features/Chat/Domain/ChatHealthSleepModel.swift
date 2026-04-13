import Foundation

/// 睡眠可视化模型（对齐 HealthClient 的结构语义，裁剪为聊天卡片渲染所需字段）。
struct ChatHealthSleepModel: Codable, Equatable, Sendable {
    static let schema = "health_sleep_v1"

    var schemaVersion: String = schema
    var generatedAt: Int64
    var days: [Day]

    struct Day: Codable, Equatable, Identifiable, Sendable {
        var id: String { date }
        var date: String
        var summary: Summary
        var timeline: [Segment]
        var stages: StageBreakdown
    }

    struct Summary: Codable, Equatable, Sendable {
        var totalSleepMinutes: Int
        var start: Int64
        var end: Int64
        var startText: String?
        var endText: String?
    }

    struct Segment: Codable, Equatable, Identifiable, Sendable {
        var id: String { "\(stage.rawValue)_\(start)" }
        var stage: Stage
        var start: Int64
        var end: Int64
        var startPercent: Double
        var widthPercent: Double
        var startText: String?
        var endText: String?
    }

    enum Stage: String, Codable, Equatable, Sendable {
        case deep
        case core
        case rem
        case awake
        case unspecified

        var displayName: String {
            switch self {
            case .deep: return "深度"
            case .core: return "核心"
            case .rem: return "REM"
            case .awake: return "清醒"
            case .unspecified: return "其他"
            }
        }
    }

    struct StageBreakdown: Codable, Equatable, Sendable {
        var deep: Int
        var core: Int
        var rem: Int
        var awake: Int
        var unspecified: Int
    }
}

extension ChatHealthSleepModel {
    func toReadableText() -> String {
        days.sorted { $0.date < $1.date }
            .map { day in
                "\(day.date) 睡眠时长 \(day.summary.totalSleepMinutes) 分钟（深睡 \(day.stages.deep) 分钟，核心 \(day.stages.core) 分钟，REM \(day.stages.rem) 分钟，清醒 \(day.stages.awake) 分钟）"
            }
            .joined(separator: "\n")
    }
}
