import SwiftUI

struct ChatSleepVisualizationMessageCard: View {
    let model: ChatHealthSleepModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "bed.double.fill")
                    .foregroundColor(Color("HLBluefont"))
                Text(L10n.text("chat.sleep.visualization.title"))
                    .font(.headline.bold())
                Spacer()
            }
            ChatSleepCardView(model: model)
        }
    }
}

/// 对话内睡眠可视化入口：按天数切换单日时间轴、2-3 天对比、4+ 天趋势图。
struct ChatSleepCardView: View {
    let model: ChatHealthSleepModel

    var body: some View {
        let sortedDays = model.days.sorted { $0.date < $1.date }
        if sortedDays.count == 1, let day = sortedDays.first {
            SleepDayTimelineCard(day: day)
        } else if sortedDays.count >= 2, sortedDays.count <= 3 {
            SleepComparisonCard(days: sortedDays)
        } else if sortedDays.count > 3 {
            SleepAverageCard(days: sortedDays)
        } else {
            ChatSleepReadableTextCard(text: model.toReadableText())
        }
    }
}

enum SleepComparisonMode: String, CaseIterable {
    case structure
    case duration

    func title(isChinese: Bool) -> String {
        switch self {
        case .structure: return L10n.text("chat.sleep.comparison.mode.structure")
        case .duration: return L10n.text("chat.sleep.comparison.mode.duration")
        }
    }
}

struct SleepComparisonCard: View {
    let days: [ChatHealthSleepModel.Day]

    @State private var mode: SleepComparisonMode = .structure

    private var isChinese: Bool { Locale.preferredLanguages.first?.hasPrefix("zh") ?? false }
    private var sortedDays: [ChatHealthSleepModel.Day] { days.sorted { $0.date < $1.date } }
    private var maxSleepMinutes: Int { sortedDays.map(\.summary.totalSleepMinutes).max() ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            modePicker
            dataRows
            legendRow
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.text("chat.sleep.comparison.title"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(String(format: L10n.text("chat.sleep.comparison.subtitle"), locale: Locale.current, sortedDays.count))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var modePicker: some View {
        Picker("", selection: $mode) {
            ForEach(SleepComparisonMode.allCases, id: \.self) { item in
                Text(item.title(isChinese: isChinese)).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }

    private var dataRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(sortedDays) { day in
                SleepComparisonRow(
                    day: day,
                    mode: mode,
                    barWidthFraction: CGFloat(max(0.1, Double(day.summary.totalSleepMinutes) / Double(maxSleepMinutes)))
                )
            }
        }
    }

    private var legendRow: some View {
        let stages: [(ChatHealthSleepModel.Stage, String)] = [
            (.deep, "deep"),
            (.core, "core"),
            (.rem, "rem"),
            (.awake, "awake")
        ]
        return HStack(spacing: 16) {
            ForEach(stages, id: \.1) { item in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(sleepStageColor(item.0))
                        .frame(width: 10, height: 10)
                    Text(item.0.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct SleepAverageCard: View {
    let days: [ChatHealthSleepModel.Day]

    private var isChinese: Bool { Locale.preferredLanguages.first?.hasPrefix("zh") ?? false }
    private var sortedDays: [ChatHealthSleepModel.Day] { days.sorted { $0.date < $1.date } }
    private var sharedRelativeBounds: (start: Int64, end: Int64) {
        sleepAverageSharedRelativeBounds(days: sortedDays)
    }

    private var yAxisWindow: (start: Int64, end: Int64) {
        guard let first = sortedDays.first,
              let anchorTS = sleepAverageDayAnchorMidnightTS(dateYMD: first.date) else {
            let start = sortedDays.map(\.summary.start).min() ?? 0
            let end = sortedDays.map(\.summary.end).max() ?? 1
            return (start, max(end, start + 1))
        }
        let relative = sharedRelativeBounds
        return (anchorTS + relative.start, anchorTS + relative.end)
    }

    private var averageSleepMinutes: Int {
        sortedDays.isEmpty ? 0 : sortedDays.map(\.summary.totalSleepMinutes).reduce(0, +) / sortedDays.count
    }

    private var dateRangeText: String {
        guard let first = sortedDays.first?.date, let last = sortedDays.last?.date else { return "" }
        return String(format: L10n.text("chat.sleep.average.date_range"), locale: Locale.current, first, last)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            chartSection
            legendRow
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text("chat.sleep.average.title"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                let parts = splitHoursMinutes(averageSleepMinutes)
                Text("\(parts.hours)")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                Text(L10n.text("chat.sleep.unit.hour"))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("\(parts.minutes)")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                Text(L10n.text("chat.sleep.unit.minute"))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Text(dateRangeText)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var chartSection: some View {
        let columnWidth: CGFloat = 52
        let chartHeight: CGFloat = 200

        return HStack(alignment: .bottom, spacing: 0) {
            timeAxisLabels(chartHeight: chartHeight)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(sortedDays) { day in
                        SleepAverageColumn(
                            day: day,
                            relBounds: sharedRelativeBounds,
                            columnWidth: columnWidth,
                            chartHeight: chartHeight
                        )
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }

    private func timeAxisLabels(chartHeight: CGFloat) -> some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone.current
        let axis = yAxisWindow
        let span = axis.end - axis.start
        let labels = (0..<4).map { index -> String in
            let ts = axis.start + span * Int64(index) / 3
            return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
        }
        return VStack(alignment: .leading, spacing: 0) {
            Text(labels[0])
            Spacer(minLength: 4)
            Text(labels[1])
            Spacer(minLength: 4)
            Text(labels[2])
            Spacer(minLength: 4)
            Text(labels[3])
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .frame(width: 36, height: chartHeight)
    }

    private var legendRow: some View {
        let stages: [(ChatHealthSleepModel.Stage, String)] = [
            (.awake, "awake"), (.rem, "rem"), (.core, "core"), (.deep, "deep")
        ]
        return HStack(spacing: 16) {
            ForEach(stages, id: \.1) { item in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(sleepStageColor(item.0))
                        .frame(width: 10, height: 10)
                    Text(item.0.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct SleepAverageColumn: View {
    let day: ChatHealthSleepModel.Day
    let relBounds: (start: Int64, end: Int64)
    let columnWidth: CGFloat
    let chartHeight: CGFloat

    private var summaryBounds: (start: Int64, end: Int64) {
        (day.summary.start, max(day.summary.end, day.summary.start + 1))
    }

    private var layoutWindow: (start: Int64, end: Int64) {
        guard let anchorTS = sleepAverageDayAnchorMidnightTS(dateYMD: day.date) else { return summaryBounds }
        let window = (anchorTS + relBounds.start, anchorTS + relBounds.end)
        guard window.1 > window.0 else { return summaryBounds }
        return window
    }

    private var windowSpan: Double { max(1, Double(layoutWindow.end - layoutWindow.start)) }

    private var displaySegments: [SleepChartDisplaySegment] {
        let window = layoutWindow
        return sleepChartPreparedSegments(timeline: day.timeline, windowStart: window.start, windowEnd: window.end)
    }

    private var isChinese: Bool { Locale.preferredLanguages.first?.hasPrefix("zh") ?? false }

    private var weekdayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        guard let date = formatter.date(from: day.date) else { return "" }
        formatter.dateFormat = "EEE"
        formatter.locale = Locale(identifier: isChinese ? "zh_CN" : "en_US")
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            ZStack(alignment: .bottom) {
                Color.clear.frame(width: columnWidth, height: chartHeight)

                let window = layoutWindow
                let barStart = max(day.summary.start, window.start)
                let barEnd = min(day.summary.end, window.end)
                if barEnd > barStart {
                    let barHeight = max(4, CGFloat(Double(barEnd - barStart) / windowSpan) * chartHeight)
                    let barOffset = yOffset(for: barEnd)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(.secondarySystemFill).opacity(0.5))
                        .frame(width: columnWidth, height: barHeight)
                        .offset(y: -barOffset)
                }

                ForEach(displaySegments) { segment in
                    let height = max(2, CGFloat(Double(segment.end - segment.start) / windowSpan) * chartHeight)
                    let offset = yOffset(for: segment.end)
                    sleepStageColor(segment.stage)
                        .frame(width: columnWidth, height: height)
                        .offset(y: -offset)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(weekdayLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(minWidth: columnWidth + 8)
    }

    private func yOffset(for ts: Int64) -> CGFloat {
        CGFloat(Double(layoutWindow.end - ts) / windowSpan) * chartHeight
    }
}

struct SleepComparisonRow: View {
    let day: ChatHealthSleepModel.Day
    let mode: SleepComparisonMode
    let barWidthFraction: CGFloat

    private var timelineLayouts: [(stage: ChatHealthSleepModel.Stage, xFrac: CGFloat, widthFrac: CGFloat)] {
        day.timeline.map { segment in
            (segment.stage, CGFloat(segment.startPercent / 100), CGFloat(max(0.002, segment.widthPercent / 100)))
        }
    }

    private var structureStageLayouts: [(stage: ChatHealthSleepModel.Stage, widthFrac: CGFloat)] {
        let total = timelineLayouts.reduce(CGFloat(0)) { $0 + $1.widthFrac }
        guard total > 0 else { return [] }
        return timelineLayouts.map { ($0.stage, max(0.002, $0.widthFrac / total)) }
    }

    private var compactDate: String {
        let parts = day.date.split(separator: "-")
        guard parts.count >= 3 else { return day.date }
        let month = Int(parts[1]) ?? 0
        let day = Int(parts[2]) ?? 0
        return "\(month)-\(day)"
    }

    private var durationText: String {
        let parts = splitHoursMinutes(day.summary.totalSleepMinutes)
        let isChinese = Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        if parts.hours > 0 {
            return isChinese ? "\(parts.hours)h\(parts.minutes)m" : "\(parts.hours)h \(parts.minutes)m"
        }
        return "\(parts.minutes)m"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(compactDate)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)

            barContent

            Text(durationText)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .frame(width: 48, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var barContent: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let barWidth = width * barWidthFraction
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: width, height: height)
                switch mode {
                case .duration:
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(sleepStageColor(.core))
                        .frame(width: max(4, barWidth), height: height)
                case .structure:
                    HStack(spacing: 0) {
                        ForEach(Array(structureStageLayouts.enumerated()), id: \.offset) { _, layout in
                            sleepStageColor(layout.stage)
                                .frame(width: max(1, barWidth * layout.widthFrac), height: height)
                        }
                    }
                    .frame(width: barWidth, height: height)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .frame(height: 40)
    }
}

struct SleepDayTimelineCard: View {
    let day: ChatHealthSleepModel.Day

    private var timelineLayouts: [(stage: ChatHealthSleepModel.Stage, xFrac: CGFloat, widthFrac: CGFloat)] {
        day.timeline.map { segment in
            (segment.stage, CGFloat(segment.startPercent / 100), CGFloat(max(0.002, segment.widthPercent / 100)))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            timelineSection
            legendGrid
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text("chat.sleep.timeline.title"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                let parts = splitHoursMinutes(day.summary.totalSleepMinutes)
                Text("\(parts.hours)")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                Text(L10n.text("chat.sleep.unit.hour"))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("\(parts.minutes)")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                Text(L10n.text("chat.sleep.unit.minute"))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Text(day.date)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(day.summary.startText ?? "")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(day.summary.endText ?? "")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                    ForEach(Array(timelineLayouts.enumerated()), id: \.offset) { _, layout in
                        sleepStageColor(layout.stage)
                            .frame(width: max(1, width * layout.widthFrac), height: height)
                            .offset(x: width * layout.xFrac)
                    }
                }
            }
            .frame(height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var legendGrid: some View {
        let stages: [(ChatHealthSleepModel.Stage, Int)] = [
            (.deep, day.stages.deep),
            (.core, day.stages.core),
            (.rem, day.stages.rem),
            (.awake, day.stages.awake),
            (.unspecified, day.stages.unspecified)
        ].filter { $0.1 > 0 }

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
            ForEach(0..<stages.count, id: \.self) { index in
                let (stage, minutes) = stages[index]
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(sleepStageColor(stage))
                        .frame(width: 12, height: 12)
                    Text(stage.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatLegendMinutes(minutes))
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func formatLegendMinutes(_ minutes: Int) -> String {
        let parts = splitHoursMinutes(minutes)
        if parts.hours > 0 {
            return String(format: L10n.text("chat.sleep.legend.hours_minutes"), locale: Locale.current, parts.hours, parts.minutes)
        }
        return String(format: L10n.text("chat.sleep.legend.minutes"), locale: Locale.current, parts.minutes)
    }
}

private struct ChatSleepReadableTextCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                Text(String(line))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SleepChartDisplaySegment: Identifiable {
    let id: String
    let start: Int64
    let end: Int64
    let stage: ChatHealthSleepModel.Stage
}

private func sleepAverageDayAnchorMidnightTS(dateYMD: String) -> Int64? {
    let calendar = Calendar.current
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    guard let parsed = formatter.date(from: dateYMD) else { return nil }
    return Int64(calendar.startOfDay(for: parsed).timeIntervalSince1970)
}

private func sleepAverageDayDataLayoutWindow(day: ChatHealthSleepModel.Day) -> (start: Int64, end: Int64) {
    let summary = (day.summary.start, max(day.summary.end, day.summary.start + 1))
    guard !day.timeline.isEmpty,
          let timelineStart = day.timeline.map(\.start).min(),
          let timelineEnd = day.timeline.map(\.end).max(),
          timelineEnd > timelineStart else {
        return summary
    }
    let padding: Int64 = 600
    return (timelineStart - padding, timelineEnd + padding)
}

private func sleepAverageSharedRelativeBounds(days: [ChatHealthSleepModel.Day]) -> (start: Int64, end: Int64) {
    let sorted = days.sorted { $0.date < $1.date }
    guard !sorted.isEmpty else { return (0, 3600 * 12) }

    var minRelative = Int64.max
    var maxRelative = Int64.min
    for day in sorted {
        guard let anchorTS = sleepAverageDayAnchorMidnightTS(dateYMD: day.date) else { continue }
        let window = sleepAverageDayDataLayoutWindow(day: day)
        let relativeStart = window.start - anchorTS
        var relativeEnd = window.end - anchorTS

        // 极端异常数据会压扁所有柱子，这里限制单日纵轴跨度以稳定卡片可读性。
        let maxSpanPerDay: Int64 = 20 * 3600
        if relativeEnd - relativeStart > maxSpanPerDay {
            relativeEnd = relativeStart + maxSpanPerDay
        }
        minRelative = min(minRelative, relativeStart)
        maxRelative = max(maxRelative, relativeEnd)
    }

    if minRelative == Int64.max || maxRelative <= minRelative {
        return (0, 3600 * 12)
    }

    minRelative -= 120
    maxRelative += 120
    let maxTotalSpan: Int64 = 22 * 3600
    if maxRelative - minRelative > maxTotalSpan {
        let center = (minRelative + maxRelative) / 2
        let half = maxTotalSpan / 2
        minRelative = center - half
        maxRelative = center + half
    }
    return (minRelative, maxRelative)
}

private func sleepChartPreparedSegments(
    timeline: [ChatHealthSleepModel.Segment],
    windowStart: Int64,
    windowEnd: Int64,
    collapseShorterThanSeconds: Int64 = 45
) -> [SleepChartDisplaySegment] {
    struct Row {
        var start: Int64
        var end: Int64
        let stage: ChatHealthSleepModel.Stage
    }

    // 先按当前图表窗口裁剪片段，避免跨日数据把柱状图撑出视图范围。
    var clipped: [Row] = []
    for segment in timeline {
        let start = max(segment.start, windowStart)
        let end = min(segment.end, windowEnd)
        guard end > start else { continue }
        clipped.append(Row(start: start, end: end, stage: segment.stage))
    }

    clipped.sort { $0.start < $1.start }
    var merged: [Row] = []
    for row in clipped {
        if let lastIndex = merged.indices.last,
           merged[lastIndex].stage == row.stage,
           row.start <= merged[lastIndex].end + 1 {
            merged[lastIndex].end = max(merged[lastIndex].end, row.end)
        } else {
            merged.append(row)
        }
    }

    // 极短阶段在小卡片上容易形成噪点，合并到前段保持整体结构清晰。
    var collapsed: [Row] = []
    for row in merged {
        let duration = row.end - row.start
        if duration < collapseShorterThanSeconds, var previous = collapsed.popLast() {
            previous.end = max(previous.end, row.end)
            collapsed.append(previous)
        } else {
            collapsed.append(row)
        }
    }

    return collapsed.enumerated().map { index, row in
        SleepChartDisplaySegment(
            id: "\(row.start)_\(row.end)_\(row.stage.rawValue)_\(index)",
            start: row.start,
            end: row.end,
            stage: row.stage
        )
    }
}

private func splitHoursMinutes(_ totalMinutes: Int) -> (hours: Int, minutes: Int) {
    let total = max(0, totalMinutes)
    return (total / 60, total % 60)
}

private func sleepStageColor(_ stage: ChatHealthSleepModel.Stage) -> Color {
    switch stage {
    case .deep:
        return Color(.systemIndigo)
    case .core:
        return Color(.systemBlue)
    case .rem:
        return Color(.systemCyan)
    case .awake:
        return Color(.systemRed)
    case .unspecified:
        return Color(.systemPurple)
    }
}
