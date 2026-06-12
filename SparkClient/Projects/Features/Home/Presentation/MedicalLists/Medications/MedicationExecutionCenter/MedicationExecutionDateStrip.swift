import SwiftUI

enum MedicationExecutionDateStripMetrics {
    static let itemWidth: CGFloat = 48
    static let itemSpacing: CGFloat = 8
    static let stripHeight: CGFloat = 108
    static let progressCircleDiameter: CGFloat = 44
    static let selectedWeekdayBadgeSize: CGFloat = 26
}

struct MedicationExecutionDateDot: View {
    let date: Date
    let isSelected: Bool
    let isLoaded: Bool
    let progress: Double
    let calendar: Calendar

    private var weekdayText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }

    private var effectiveProgress: Double {
        guard isLoaded else { return 0 }
        return max(0, min(progress, 1))
    }

    var body: some View {
        VStack(spacing: 8) {
            weekdayLabel
                .frame(height: MedicationExecutionDateStripMetrics.selectedWeekdayBadgeSize)
            progressCircle
        }
        .frame(width: MedicationExecutionDateStripMetrics.itemWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var weekdayLabel: some View {
        if isSelected {
            Text(weekdayText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(uiColor: .systemBackground))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(
                    width: MedicationExecutionDateStripMetrics.selectedWeekdayBadgeSize,
                    height: MedicationExecutionDateStripMetrics.selectedWeekdayBadgeSize
                )
                .background {
                    Circle()
                        .fill(Color.primary)
                }
        } else {
            Text(weekdayText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: MedicationExecutionDateStripMetrics.itemWidth)
        }
    }

    @ViewBuilder
    private var progressCircle: some View {
        let diameter = MedicationExecutionDateStripMetrics.progressCircleDiameter

        ZStack {
            Circle()
                .fill(Color(uiColor: .systemGray5))

            if effectiveProgress >= 1 {
                Circle()
                    .fill(Color(uiColor: .systemTeal))
            } else if effectiveProgress > 0 {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(Color(uiColor: .systemTeal))
                        .frame(height: proxy.size.height * effectiveProgress)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
                .clipShape(Circle())
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private var accessibilityText: String {
        let status: String
        if isSelected {
            status = "已选中"
        } else if isLoaded == false {
            status = "暂无加载"
        } else if effectiveProgress >= 1 {
            status = "已全部完成"
        } else if effectiveProgress > 0 {
            status = "部分完成"
        } else {
            status = "未完成"
        }

        return "\(weekdayText)，\(Self.accessibilityDateFormatter.string(from: date))，\(status)"
    }

    private static let accessibilityDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()
}
