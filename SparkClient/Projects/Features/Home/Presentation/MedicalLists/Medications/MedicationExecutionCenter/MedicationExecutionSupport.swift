#if canImport(UIKit)
import UIKit
#endif

enum MedicationExecutionSupport {
    static func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        #endif
    }

    static func longDateTitle(_ date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.month, .day], from: date)
        let month = comps.month ?? 1
        let day = comps.day ?? 1
        if calendar.isDateInToday(date) {
            return L10n.format("home.medical.medication_execution.date.today_header", month, day)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        let weekday = formatter.string(from: date)
        return L10n.format("home.medical.medication_execution.date.weekday_header", month, day, weekday)
    }

    static func logSheetDateTitle(_ date: Date) -> String {
        longDateTitle(date, calendar: Calendar.current)
    }

    static func logTitle(at timeText: String) -> String {
        L10n.format("home.medical.medication_execution.log_title_at_time", timeText)
    }

    static func allDrugsLogTitle() -> String {
        L10n.text("home.medical.medication_execution.log_title_all_drugs")
    }
}
