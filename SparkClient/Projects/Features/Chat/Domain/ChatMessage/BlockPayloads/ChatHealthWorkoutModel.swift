import Foundation

///
/// 健身运动数据模型
/// 用途：
/// 1. 从 Apple Health 读取运动数据后，转换成统一结构
/// 2. 传给 AI 做总结、分析、生成周报
/// 3. 前端渲染运动卡片、心率图表、路线地图
/// 4. 可序列化、可传输、可持久化
///
nonisolated struct ChatHealthWorkoutModel: Codable, Equatable, Sendable {
    /// 数据结构版本（用于向后兼容）
    static let schema = "health_workout_v1"

    /// 当前结构版本号
    var schemaVersion: String = schema
    /// 数据生成时间戳（秒）
    var generatedAt: Int64
    /// 所有运动会话列表（跑步、骑行、游泳等）
    var workouts: [WorkoutSession]
    /// 提示/备注信息（如无法识别的运动类型、无数据提示）
    var notes: [String]

    ///
    /// 单条运动会话（核心数据结构）
    /// 代表一次完整的运动：跑步 / 骑行 / 游泳 / 力量训练
    ///
    struct WorkoutSession: Codable, Equatable, Identifiable, Sendable {
        var id: String                      // 唯一标识
        var activityTypeKey: String         // 运动类型标识符（running/cycling/swimming）
        var activityTypeName: String        // 运动类型名称（跑步/骑行/游泳）
        var start: Int64                    // 开始时间戳（秒）
        var end: Int64                      // 结束时间戳（秒）
        var startText: String?              // 格式化开始时间（如 2025-01-01 10:00）
        var endText: String?                // 格式化结束时间
        var elapsedSeconds: Int64           // 总耗时（秒）
        var trainingSeconds: Int64?         // 有效训练时长
        var pausedSeconds: Int64?           // 暂停时长
        var distanceMeters: Double?         // 总距离（米）
        var activeEnergyKcal: Double?       // 活跃消耗卡路里
        var totalEnergyKcal: Double?        // 总消耗卡路里
        var elevationAscendedMeters: Double? // 爬升高度（米）
        var averageSpeedMps: Double?        // 平均速度（米/秒）
        var averageHeartRateBpm: Double?    // 平均心率
        var averagePowerW: Double?          // 平均功率（瓦）
        var averageCadence: Double?         // 平均步频/踏频
        var averagePaceMinPerKm: Double?    // 平均配速（分钟/公里）
        var poolLengthMeters: Double?       // 泳池长度（仅游泳）
        var swimmingLengthCount: Int?       // 游泳趟数（仅游泳）
        
        var heartRateSamples: [HeartRatePoint] // 心率原始采样点
        var events: [WorkoutEvent]              // 运动事件：暂停/恢复/记圈
        var route: [RoutePoint]                 // GPS 路线轨迹
    }

    /// 心率采样点（时间 + 心率值）
    struct HeartRatePoint: Codable, Equatable, Identifiable, Sendable {
        var id: Int64 { timestamp }         // ID = 时间戳
        var timestamp: Int64                 // 时间戳
        var bpm: Double                      // 心率值
    }

    /// 心率分段（用于图表渲染：一段区间的最低/最高心率）
    struct HeartRateBin: Equatable, Sendable {
        let min: Double        // 最低心率
        let max: Double        // 最高心率
        let timestamp: Int64   // 分段开始时间
        let isEmpty: Bool      // 该分段是否无数据
    }

    /// 运动洞察画像：不同运动给 AI 的重点指标不同
    enum WorkoutInsightProfile: Equatable, Sendable {
        case running
        case cycling
        case swimming
        case strength
        case generic
    }

    /// 心率峰值区间：连续高于峰值 90% 的高强度片段
    struct HeartRatePeakSegment: Equatable, Sendable {
        let start: Int64
        let end: Int64
        let avgBpm: Double
    }

    /// 五区心率时间分布，单位：秒
    struct HeartRateZoneSummary: Equatable, Sendable {
        var z1: Double = 0
        var z2: Double = 0
        var z3: Double = 0
        var z4: Double = 0
        var z5: Double = 0

        var totalSeconds: Double {
            z1 + z2 + z3 + z4 + z5
        }
    }

    /// 给 AI 使用的心率洞察摘要
    struct HeartRateAnalysis: Equatable, Sendable {
        let avg: Double
        let max: Double
        let peakSegment: HeartRatePeakSegment?
        let zones: HeartRateZoneSummary
        let recoveryDropBpm: Double?
        let recoveryScore: Double
    }

    /// 运动事件：暂停、恢复、记圈、标记等
    struct WorkoutEvent: Codable, Equatable, Identifiable, Sendable {
        var id: String { "\(type.rawValue)_\(dateIntervalSince1970)" }
        var type: EventType                          // 事件类型
        var dateIntervalSince1970: Int64             // 事件发生时间

        enum EventType: String, Codable, Equatable, Sendable {
            case pause      // 暂停
            case resume     // 恢复
            case lap        // 记圈
            case marker     // 标记点
            case segment    // 分段
            case other      // 其他
        }
    }

    /// GPS 路线点
    struct RoutePoint: Codable, Equatable, Sendable {
        var lat: Double              // 纬度
        var lon: Double              // 经度
        var altitudeM: Double?       // 海拔
        var timestamp: Int64         // 时间戳
    }
}

// MARK: - 工具方法：数据处理 + 格式化展示
extension ChatHealthWorkoutModel {
    ///
    /// 心率数据分桶（降采样）
    /// 作用：把几百个心率点 → 压缩成 N 个区间，用于图表展示，避免性能问题
    ///
    static func binHeartRates(samples: [HeartRatePoint], maxBins: Int) -> [HeartRateBin] {
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty, maxBins > 0 else { return [] }

        // 运动总时长
        let start = sorted[0].timestamp
        let end = sorted[sorted.count - 1].timestamp
        let duration = max(1, end - start)
        let step = Double(duration) / Double(maxBins)

        var bins: [HeartRateBin] = []
        bins.reserveCapacity(maxBins)

        var index = 0
        for binIndex in 0..<maxBins {
            // 当前分段的时间区间
            let binStart = start + Int64(Double(binIndex) * step)
            let binEnd = start + Int64(Double(binIndex + 1) * step)

            // 跳过不属于当前分段的点
            while index < sorted.count, sorted[index].timestamp < binStart {
                index += 1
            }

            // 遍历当前分段内的所有点，计算最小/最大心率
            var cursor = index
            var minBpm = Double.greatestFiniteMagnitude
            var maxBpm = -Double.greatestFiniteMagnitude
            
            while cursor < sorted.count, sorted[cursor].timestamp < binEnd {
                let bpm = sorted[cursor].bpm
                minBpm = min(minBpm, bpm)
                maxBpm = max(maxBpm, bpm)
                cursor += 1
            }

            // 生成分段数据
            if maxBpm >= minBpm {
                bins.append(HeartRateBin(min: minBpm, max: maxBpm, timestamp: binStart, isEmpty: false))
            } else {
                bins.append(HeartRateBin(min: 0, max: 0, timestamp: binStart, isEmpty: true))
            }
            
            index = cursor
        }

        return bins
    }

    static func profile(for type: String) -> WorkoutInsightProfile {
        switch type {
        case "running":
            return .running
        case "cycling":
            return .cycling
        case "swimming":
            return .swimming
        case "traditional_strength", "strengthTraining", "functional_strength", "crossTraining":
            return .strength
        default:
            return .generic
        }
    }

    /// 从原始心率采样中提取峰值区间、五区分布和 1 分钟恢复能力
    static func analyzeHeartRate(_ samples: [HeartRatePoint]) -> HeartRateAnalysis? {
        let sorted = samples
            .filter { $0.bpm > 0 }
            .sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty else { return nil }

        let avg = sorted.reduce(0) { $0 + $1.bpm } / Double(sorted.count)
        let maxBpm = sorted.map(\.bpm).max() ?? avg
        let peakSegment = findPeakSegment(in: sorted, maxBpm: maxBpm)
        let zones = summarizeHeartRateZones(in: sorted, maxBpm: maxBpm)
        let recoveryDrop = heartRateRecoveryDrop(in: sorted)
        let recoveryScore = recoveryDrop.map { min(max($0 / 35, 0), 1) } ?? 0

        return HeartRateAnalysis(
            avg: avg,
            max: maxBpm,
            peakSegment: peakSegment,
            zones: zones,
            recoveryDropBpm: recoveryDrop,
            recoveryScore: recoveryScore
        )
    }

    ///
    /// 生成 AI 可读的自然语言文本
    /// 把结构化运动数据 → 一段文字，用于 AI 总结/展示
    ///
    func toReadableText() -> String {
        let sorted = workouts.sorted { $0.start < $1.start }
        guard !sorted.isEmpty else {
            return L10n.text("health.tool.error.no_workouts", fallback: "No matching workout records found.")
        }

        // 汇总统计
        let totalDurationMinutes = sorted.reduce(0.0) { $0 + Double($1.elapsedSeconds) / 60 }
        let totalDistanceMeters = sorted.compactMap(\.distanceMeters).reduce(0, +)
        let totalEnergy = sorted.compactMap(\.activeEnergyKcal).reduce(0, +)

        var lines: [String] = []
        lines.append(L10n.text("health.tool.report.workouts.title", fallback: "Workout records"))
        
        // 总览信息
        lines.append(
            String(
                format: L10n.text(
                    "chat.workout.readable.summary_format",
                    fallback: "%d sessions, total duration %@, total distance %@, active energy %.0f kcal"
                ),
                locale: .current,
                sorted.count,
                Self.formatDurationMinutes(totalDurationMinutes),
                Self.formatDistanceMeters(totalDistanceMeters),
                totalEnergy
            )
        )

        // 添加备注信息
        if !notes.isEmpty {
            lines.append(contentsOf: notes)
        }

        // 逐条展示运动记录（最多20条）
        for workout in sorted.prefix(20) {
            lines.append("")
            lines.append(Self.localizedSection("chat.workout.readable.section.summary", fallback: "[Workout Summary]"))
            lines.append(Self.localizedField("chat.workout.readable.field.type", value: workout.activityTypeName, fallback: "Type: %@"))
            if let startText = workout.startText, !startText.isEmpty {
                lines.append(Self.localizedField("chat.workout.readable.field.start", value: startText, fallback: "Start: %@"))
            }
            lines.append(Self.localizedField("chat.workout.readable.field.duration", value: Self.formatDurationMinutes(Double(workout.elapsedSeconds) / 60), fallback: "Duration: %@"))

            for metric in Self.primaryMetrics(for: workout) {
                lines.append(metric)
            }

            if let analysis = Self.analyzeHeartRate(workout.heartRateSamples) {
                lines.append("")
                lines.append(Self.localizedSection("chat.workout.readable.section.heart_rate", fallback: "[Heart Rate Insights]"))
                lines.append(L10n.format("chat.workout.readable.field.avg_hr", fallback: "Avg HR: %.0f bpm", analysis.avg))
                lines.append(L10n.format("chat.workout.readable.field.peak_hr", fallback: "Peak HR: %.0f bpm", analysis.max))
                if let peak = analysis.peakSegment {
                    let start = Self.formatElapsedTime(peak.start - workout.start)
                    let end = Self.formatElapsedTime(peak.end - workout.start)
                    lines.append(L10n.format("chat.workout.readable.field.peak_segment", fallback: "Peak Segment: %@-%@ (avg %.0f bpm)", start, end, peak.avgBpm))
                }
                lines.append(Self.localizedField("chat.workout.readable.field.zones", value: Self.formatHeartRateZones(analysis.zones), fallback: "Zones: %@"))

                if let recoveryDrop = analysis.recoveryDropBpm {
                    lines.append(L10n.format("chat.workout.readable.field.recovery", fallback: "Recovery: %@ (HR drop %.0f bpm in 1 min)", Self.recoveryLabel(for: recoveryDrop), recoveryDrop))
                }

                let tags = Self.aiTags(for: workout, heartRateAnalysis: analysis)
                if !tags.isEmpty {
                    lines.append("")
                    lines.append(Self.localizedSection("chat.workout.readable.section.ai_hints", fallback: "[AI Hints]"))
                    lines.append(contentsOf: tags.map { "- \($0)" })
                }
            } else if let heartRate = workout.averageHeartRateBpm, heartRate > 0 {
                lines.append("")
                lines.append(Self.localizedSection("chat.workout.readable.section.heart_rate", fallback: "[Heart Rate Insights]"))
                lines.append(L10n.format("chat.workout.readable.field.avg_hr", fallback: "Avg HR: %.0f bpm", heartRate))
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func primaryMetrics(for workout: WorkoutSession) -> [String] {
        var metrics: [String] = []

        switch profile(for: workout.activityTypeKey) {
        case .running:
            appendDistance(workout.distanceMeters, to: &metrics)
            appendPace(workout.averagePaceMinPerKm, label: "Avg Pace", to: &metrics)
            appendCadence(workout.averageCadence, to: &metrics)
            appendEnergy(workout.activeEnergyKcal, to: &metrics)
        case .cycling:
            appendDistance(workout.distanceMeters, to: &metrics)
            appendPower(workout.averagePowerW, to: &metrics)
            appendSpeed(workout.averageSpeedMps, to: &metrics)
            appendElevation(workout.elevationAscendedMeters, to: &metrics)
            appendEnergy(workout.activeEnergyKcal, to: &metrics)
        case .swimming:
            appendDistance(workout.distanceMeters, to: &metrics)
            if let lengths = workout.swimmingLengthCount, lengths > 0 {
                metrics.append(L10n.format("chat.workout.readable.field.lengths", fallback: "Lengths: %d", lengths))
            }
            if let poolLength = workout.poolLengthMeters, poolLength > 0 {
                metrics.append(L10n.format("chat.workout.readable.field.pool_length", fallback: "Pool Length: %.0f m", poolLength))
            }
            appendSwimmingPace(workout.averagePaceMinPerKm, to: &metrics)
            appendEnergy(workout.activeEnergyKcal, to: &metrics)
        case .strength:
            appendEnergy(workout.activeEnergyKcal, to: &metrics)
            if let trainingSeconds = workout.trainingSeconds, trainingSeconds > 0 {
                metrics.append(localizedField("chat.workout.readable.field.training_time", value: formatDurationMinutes(Double(trainingSeconds) / 60), fallback: "Training Time: %@"))
            }
            if let pausedSeconds = workout.pausedSeconds, pausedSeconds > 0 {
                metrics.append(localizedField("chat.workout.readable.field.paused_time", value: formatDurationMinutes(Double(pausedSeconds) / 60), fallback: "Paused Time: %@"))
            }
        case .generic:
            appendDistance(workout.distanceMeters, to: &metrics)
            appendEnergy(workout.activeEnergyKcal, to: &metrics)
        }

        return metrics
    }

    private static func appendDistance(_ distance: Double?, to metrics: inout [String]) {
        guard let distance, distance > 0 else { return }
        metrics.append(localizedField("chat.workout.readable.field.distance", value: formatDistanceMeters(distance), fallback: "Distance: %@"))
    }

    private static func appendEnergy(_ energy: Double?, to metrics: inout [String]) {
        guard let energy, energy > 0 else { return }
        metrics.append(L10n.format("chat.workout.readable.field.active_energy", fallback: "Active Energy: %.0f kcal", energy))
    }

    private static func appendPace(_ pace: Double?, label: String, to metrics: inout [String]) {
        guard let pace, pace > 0 else { return }
        metrics.append(localizedField("chat.workout.readable.field.avg_pace", value: formatPaceMinPerKm(pace), fallback: "\(label): %@"))
    }

    private static func appendSwimmingPace(_ paceMinPerKm: Double?, to metrics: inout [String]) {
        guard let paceMinPerKm, paceMinPerKm > 0 else { return }
        metrics.append(localizedField("chat.workout.readable.field.avg_pace", value: formatPaceMinPer100m(paceMinPerKm / 10), fallback: "Avg Pace: %@"))
    }

    private static func appendSpeed(_ speed: Double?, to metrics: inout [String]) {
        guard let speed, speed > 0 else { return }
        metrics.append(L10n.format("chat.workout.readable.field.avg_speed", fallback: "Avg Speed: %.1f km/h", speed * 3.6))
    }

    private static func appendPower(_ power: Double?, to metrics: inout [String]) {
        guard let power, power > 0 else { return }
        metrics.append(L10n.format("chat.workout.readable.field.avg_power", fallback: "Avg Power: %.0f W", power))
    }

    private static func appendCadence(_ cadence: Double?, to metrics: inout [String]) {
        guard let cadence, cadence > 0 else { return }
        metrics.append(L10n.format("chat.workout.readable.field.cadence", fallback: "Cadence: %.0f", cadence))
    }

    private static func appendElevation(_ elevation: Double?, to metrics: inout [String]) {
        guard let elevation, elevation > 0 else { return }
        metrics.append(L10n.format("chat.workout.readable.field.elevation_gain", fallback: "Elevation Gain: %.0f m", elevation))
    }

    private static func findPeakSegment(in samples: [HeartRatePoint], maxBpm: Double) -> HeartRatePeakSegment? {
        let threshold = maxBpm * 0.9
        var best: HeartRatePeakSegment?
        var startIndex: Int?

        func segment(from startIndex: Int, to endIndex: Int) -> HeartRatePeakSegment? {
            guard endIndex >= startIndex else { return nil }
            let start = samples[startIndex].timestamp
            let end = samples[endIndex].timestamp
            guard end - start >= 30 else { return nil }
            let slice = samples[startIndex...endIndex]
            let avg = slice.reduce(0) { $0 + $1.bpm } / Double(slice.count)
            return HeartRatePeakSegment(start: start, end: end, avgBpm: avg)
        }

        for index in samples.indices {
            if samples[index].bpm >= threshold {
                if startIndex == nil {
                    startIndex = index
                }
            } else if let segmentStartIndex = startIndex {
                if let candidate = segment(from: segmentStartIndex, to: max(segmentStartIndex, index - 1)),
                   candidate.avgBpm > (best?.avgBpm ?? 0) {
                    best = candidate
                }
                startIndex = nil
            }
        }

        if let startIndex,
           let candidate = segment(from: startIndex, to: samples.count - 1),
           candidate.avgBpm > (best?.avgBpm ?? 0) {
            best = candidate
        }

        return best
    }

    private static func summarizeHeartRateZones(in samples: [HeartRatePoint], maxBpm: Double) -> HeartRateZoneSummary {
        guard samples.count > 1, maxBpm > 0 else { return HeartRateZoneSummary() }
        var zones = HeartRateZoneSummary()

        for index in 0..<(samples.count - 1) {
            let seconds = Double(max(0, samples[index + 1].timestamp - samples[index].timestamp))
            guard seconds > 0 else { continue }
            let ratio = samples[index].bpm / maxBpm

            switch ratio {
            case 0.9...:
                zones.z5 += seconds
            case 0.8..<0.9:
                zones.z4 += seconds
            case 0.7..<0.8:
                zones.z3 += seconds
            case 0.6..<0.7:
                zones.z2 += seconds
            default:
                zones.z1 += seconds
            }
        }

        return zones
    }

    private static func heartRateRecoveryDrop(in samples: [HeartRatePoint]) -> Double? {
        guard let peakIndex = samples.indices.max(by: { samples[$0].bpm < samples[$1].bpm }) else { return nil }

        let target = samples[peakIndex].timestamp + 60
        guard let recoveryPoint = samples[peakIndex...].first(where: { $0.timestamp >= target }) else { return nil }
        return max(0, samples[peakIndex].bpm - recoveryPoint.bpm)
    }

    private static func aiTags(for workout: WorkoutSession, heartRateAnalysis: HeartRateAnalysis) -> [String] {
        var tags: [String] = []
        let zones = heartRateAnalysis.zones
        let total = max(1, zones.totalSeconds)
        let highIntensityRatio = (zones.z4 + zones.z5) / total

        switch profile(for: workout.activityTypeKey) {
        case .running:
            tags.append(L10n.text("chat.workout.readable.hint.running", fallback: "Running workout"))
        case .cycling:
            tags.append(L10n.text("chat.workout.readable.hint.cycling", fallback: "Cycling workout"))
        case .swimming:
            tags.append(L10n.text("chat.workout.readable.hint.swimming", fallback: "Swimming workout"))
        case .strength:
            tags.append(L10n.text("chat.workout.readable.hint.strength_training", fallback: "Strength training"))
        case .generic:
            break
        }

        if highIntensityRatio >= 0.25 {
            tags.append(L10n.text("chat.workout.readable.hint.high_intensity", fallback: "High intensity load"))
        } else if zones.z2 / total >= 0.4 || zones.z3 / total >= 0.35 {
            tags.append(L10n.text("chat.workout.readable.hint.aerobic", fallback: "Aerobic-focused session"))
        }

        if heartRateAnalysis.peakSegment != nil {
            tags.append(L10n.text("chat.workout.readable.hint.peak_effort_segment", fallback: "Peak effort segment detected"))
        }

        if (heartRateAnalysis.recoveryDropBpm ?? 0) >= 25 {
            tags.append(L10n.text("chat.workout.readable.hint.good_recovery", fallback: "Good 1-minute heart rate recovery"))
        }

        return tags
    }

    private static func formatHeartRateZones(_ zones: HeartRateZoneSummary) -> String {
        let total = zones.totalSeconds
        guard total > 0 else {
            return L10n.text("chat.workout.readable.zones.insufficient", fallback: "not enough interval data")
        }

        return [
            String(format: "Z1 %.0f%%", locale: .current, zones.z1 / total * 100),
            String(format: "Z2 %.0f%%", locale: .current, zones.z2 / total * 100),
            String(format: "Z3 %.0f%%", locale: .current, zones.z3 / total * 100),
            String(format: "Z4 %.0f%%", locale: .current, zones.z4 / total * 100),
            String(format: "Z5 %.0f%%", locale: .current, zones.z5 / total * 100)
        ].joined(separator: ", ")
    }

    private static func recoveryLabel(for dropBpm: Double) -> String {
        if dropBpm >= 30 {
            return L10n.text("chat.workout.readable.recovery.excellent", fallback: "excellent")
        }
        if dropBpm >= 20 {
            return L10n.text("chat.workout.readable.recovery.good", fallback: "good")
        }
        if dropBpm >= 12 {
            return L10n.text("chat.workout.readable.recovery.moderate", fallback: "moderate")
        }
        return L10n.text("chat.workout.readable.recovery.slow", fallback: "slow")
    }

    private static func localizedSection(_ key: String, fallback: String) -> String {
        L10n.text(key, fallback: fallback)
    }

    private static func localizedField(_ key: String, value: String, fallback: String) -> String {
        L10n.format(key, fallback: fallback, value)
    }

    private static func formatElapsedTime(_ seconds: Int64) -> String {
        let clamped = max(0, seconds)
        let minutes = clamped / 60
        let secs = clamped % 60
        return String(format: "%02lld:%02lld", minutes, secs)
    }

    private static func formatPaceMinPerKm(_ pace: Double) -> String {
        let minutes = Int(pace)
        let seconds = Int(((pace - Double(minutes)) * 60).rounded())
        return String(format: "%d:%02d/km", minutes, seconds)
    }

    private static func formatPaceMinPer100m(_ pace: Double) -> String {
        let minutes = Int(pace)
        let seconds = Int(((pace - Double(minutes)) * 60).rounded())
        return String(format: "%d:%02d/100m", minutes, seconds)
    }

    /// 格式化时长：分钟 → 1h 20m / 30m
    static func formatDurationMinutes(_ minutes: Double) -> String {
        let hours = Int(minutes / 60)
        let mins = Int(minutes.truncatingRemainder(dividingBy: 60))
        if hours > 0 {
            return L10n.format("health.tool.unit.duration.hours_minutes", fallback: "%dh %dm", hours, mins)
        }
        return L10n.format("health.tool.unit.duration.minutes", fallback: "%dm", mins)
    }

    /// 格式化距离：米 → 1.25 km / 300 m
    static func formatDistanceMeters(_ meters: Double) -> String {
        if meters >= 1000 {
            return L10n.format("health.tool.unit.kilometers.precision", fallback: "%.2f km", meters / 1000)
        }
        return L10n.format("health.tool.unit.meters", fallback: "%d m", Int(meters.rounded()))
    }
}
