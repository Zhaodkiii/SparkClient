import Foundation

/// 睡眠可视化模型（对齐 HealthClient 的结构语义，裁剪为聊天卡片渲染所需字段）。
nonisolated struct ChatHealthSleepModel: Codable, Equatable, Sendable {
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
        var vitals: SegmentVitals?
    }

    struct SegmentVitals: Codable, Equatable, Sendable {
        var avgHeartRate: Double?
        var minHeartRate: Double?
        var maxHeartRate: Double?
        var avgRespiratoryRate: Double?
        var avgWristTemperature: Double?
    }

    enum Stage: String, Codable, Equatable, Sendable {
        case deep
        case core
        case rem
        case awake
        case unspecified

        var displayName: String {
            switch self {
            case .deep: return L10n.text("chat.sleep.stage.deep")
            case .core: return L10n.text("chat.sleep.stage.core")
            case .rem: return L10n.text("chat.sleep.stage.rem")
            case .awake: return L10n.text("chat.sleep.stage.awake")
            case .unspecified: return L10n.text("chat.sleep.stage.unspecified")
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
    /// 生成 AI 可读文本：按日期升序拼接多天睡眠摘要。
    func toReadableText() -> String {
        let sortedDays = days.sorted { $0.date < $1.date }
        return sortedDays.map { $0.toReadableText() }.joined(separator: "\n\n")
    }
}

extension ChatHealthSleepModel.SegmentVitals {
    var hasValues: Bool {
        avgHeartRate != nil
            || minHeartRate != nil
            || maxHeartRate != nil
            || avgRespiratoryRate != nil
            || avgWristTemperature != nil
    }
}

extension ChatHealthSleepModel.Day {
    /// 单日睡眠结构化数据 -> 自然语言文本（会话明细 + 日汇总）。
    func toReadableText() -> String {
        var lines: [String] = []

        lines.append("*\(Self.formatDate(date))*")
        lines.append(L10n.text("chat.sleep.readable.sessions.title", fallback: "【睡眠会话】"))

        guard !timeline.isEmpty else {
            lines.append(
                L10n.text(
                    "chat.sleep.readable.empty",
                    fallback: "  - 无睡眠数据"
                )
            )
            return lines.joined(separator: "\n")
        }

        for segment in timeline {
            let start = segment.startText ?? Self.formatTime(segment.start)
            let end = segment.endText ?? Self.formatTime(segment.end)
            let duration = max(0, segment.end - segment.start)
            let durationText = Self.formatDuration(duration)
            lines.append(
                String(
                    format: L10n.text(
                        "chat.sleep.readable.session_item_format",
                        fallback: "  - %@ - %@：%@，%@"
                    ),
                    locale: .current,
                    start,
                    end,
                    segment.stage.displayName,
                    durationText
                )
            )
            if let vitals = segment.vitals {
                lines.append(contentsOf: Self.formatVitals(vitals))
            }
        }

        lines.append(
            String(
                format: L10n.text(
                    "chat.sleep.readable.daily_summary.title",
                    fallback: "\n【日汇总】"
                ),
                locale: .current
            )
        )

        let total = max(0, summary.end - summary.start)
        let totalSleep = Int64(summary.totalSleepMinutes * 60)
        let awake = Int64(stages.awake * 60)
        let rem = Int64(stages.rem * 60)
        let core = Int64(stages.core * 60)
        let deep = Int64(stages.deep * 60)
        let unspecified = Int64(stages.unspecified * 60)

        lines.append(
            String(
                format: L10n.text(
                    "chat.sleep.readable.daily_summary.total_format",
                    fallback: "  - 总时长：%@"
                ),
                locale: .current,
                Self.formatDuration(total)
            )
        )
        lines.append(
            String(
                format: L10n.text(
                    "chat.sleep.readable.daily_summary.sleep_total_format",
                    fallback: "  - 睡眠时长：%@"
                ),
                locale: .current,
                Self.formatDuration(totalSleep)
            )
        )
        lines.append(
            String(
                format: L10n.text(
                    "chat.sleep.readable.daily_summary.stage_format",
                    fallback: "  - %@：%@（%@）"
                ),
                locale: .current,
                ChatHealthSleepModel.Stage.awake.displayName,
                Self.formatDuration(awake),
                Self.percent(awake, total)
            )
        )
        lines.append(
            String(
                format: L10n.text(
                    "chat.sleep.readable.daily_summary.stage_format",
                    fallback: "  - %@：%@（%@）"
                ),
                locale: .current,
                ChatHealthSleepModel.Stage.rem.displayName,
                Self.formatDuration(rem),
                Self.percent(rem, total)
            )
        )
        lines.append(
            String(
                format: L10n.text(
                    "chat.sleep.readable.daily_summary.stage_format",
                    fallback: "  - %@：%@（%@）"
                ),
                locale: .current,
                ChatHealthSleepModel.Stage.core.displayName,
                Self.formatDuration(core),
                Self.percent(core, total)
            )
        )
        lines.append(
            String(
                format: L10n.text(
                    "chat.sleep.readable.daily_summary.stage_format",
                    fallback: "  - %@：%@（%@）"
                ),
                locale: .current,
                ChatHealthSleepModel.Stage.deep.displayName,
                Self.formatDuration(deep),
                Self.percent(deep, total)
            )
        )
        if unspecified > 0 {
            lines.append(
                String(
                    format: L10n.text(
                        "chat.sleep.readable.daily_summary.stage_format",
                        fallback: "  - %@：%@（%@）"
                    ),
                    locale: .current,
                    ChatHealthSleepModel.Stage.unspecified.displayName,
                    Self.formatDuration(unspecified),
                    Self.percent(unspecified, total)
                )
            )
        }

        return lines.joined(separator: "\n")
    }

    private static func formatDate(_ dateStr: String) -> String {
        let iso = DateFormatter()
        iso.calendar = Calendar.current
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.timeZone = Calendar.current.timeZone
        iso.dateFormat = "yyyy-MM-dd"
        guard let date = iso.date(from: dateStr) else { return dateStr }

        let out = DateFormatter()
        out.locale = .current
        out.calendar = Calendar.current
        out.dateStyle = .medium
        out.timeStyle = .none
        return out.string(from: date)
    }

    private static func formatTime(_ ts: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = Calendar.current
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func formatDuration(_ seconds: Int64) -> String {
        let total = max(0, seconds)
        let hours = Int(total / 3600)
        let minutes = Int((total % 3600) / 60)
        if hours > 0 {
            return String(
                format: L10n.text("chat.sleep.legend.hours_minutes", fallback: "%dh %dm"),
                locale: .current,
                hours,
                minutes
            )
        }
        return String(
            format: L10n.text("chat.sleep.legend.minutes", fallback: "%dm"),
            locale: .current,
            minutes
        )
    }

    private static func percent(_ part: Int64, _ total: Int64) -> String {
        guard total > 0 else { return "0%" }
        let value = Double(part) / Double(total) * 100
        return String(format: "%.1f%%", value)
    }

    private static func formatVitals(_ vitals: ChatHealthSleepModel.SegmentVitals) -> [String] {
        var lines: [String] = []
        if let heartRate = vitals.avgHeartRate {
            if let minHeartRate = vitals.minHeartRate, let maxHeartRate = vitals.maxHeartRate {
                lines.append(
                    String(
                        format: L10n.text(
                            "chat.sleep.readable.vitals.heart_rate_range_format",
                            fallback: "    心率：%.0f bpm（最低%.0f / 最高%.0f）"
                        ),
                        locale: .current,
                        heartRate,
                        minHeartRate,
                        maxHeartRate
                    )
                )
            } else {
                lines.append(
                    String(
                        format: L10n.text(
                            "chat.sleep.readable.vitals.heart_rate_format",
                            fallback: "    心率：%.0f bpm"
                        ),
                        locale: .current,
                        heartRate
                    )
                )
            }
        }
        if let respiratoryRate = vitals.avgRespiratoryRate {
            lines.append(
                String(
                    format: L10n.text(
                        "chat.sleep.readable.vitals.respiratory_rate_format",
                        fallback: "    呼吸：%.0f 次/分钟"
                    ),
                    locale: .current,
                    respiratoryRate
                )
            )
        }
        if let wristTemperature = vitals.avgWristTemperature {
            lines.append(
                String(
                    format: L10n.text(
                        "chat.sleep.readable.vitals.wrist_temperature_format",
                        fallback: "    手腕温度：%+.2f°C"
                    ),
                    locale: .current,
                    wristTemperature
                )
            )
        }
        return lines
    }
}
