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
            return "\(month)月\(day)日 今天"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEEE"
        return "\(month)月\(day)日 \(formatter.string(from: date))"
    }

    static func logSheetDateTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.month, .day], from: date)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEEE"
        return "\(comps.month ?? 1)月\(comps.day ?? 1)日 \(formatter.string(from: date))"
    }
}
