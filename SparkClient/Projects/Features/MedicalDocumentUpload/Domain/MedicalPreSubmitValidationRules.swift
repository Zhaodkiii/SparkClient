import Foundation

enum MedicalPreSubmitValidationRules {
    static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), raw.isEmpty == false else {
            return nil
        }
        return raw
    }

    static func isBlank(_ value: String?) -> Bool {
        trimmedNonEmpty(value) == nil
    }

    /// `yyyy-MM-dd` 或完整 ISO8601 视为完整日期；`yyyy-MM`、`yyyy` 等不完整格式不通过。
    static func isCompleteDate(_ value: String?) -> Bool {
        guard let raw = trimmedNonEmpty(value) else { return true }

        if raw.range(of: #"^\d{4}-\d{2}$"#, options: .regularExpression) != nil { return false }
        if raw.range(of: #"^\d{4}$"#, options: .regularExpression) != nil { return false }

        return parseComparableDateOnly(raw) != nil
    }

    static func requiresCompleteDateIfPresent(_ value: String?) -> Bool {
        guard trimmedNonEmpty(value) != nil else { return true }
        return isCompleteDate(value)
    }

    static func isNonNegativeNumber(_ value: String?) -> Bool {
        guard let raw = trimmedNonEmpty(value) else { return true }
        guard let number = Optional(raw).parsedAsTotalQuantity() ?? Double(raw) else { return false }
        return number >= 0
    }

    /// 服务端 `dose_value` 要求纯数值字符串；空值不阻断。
    static func isValidDecimalString(_ value: String?) -> Bool {
        guard let raw = trimmedNonEmpty(value) else { return true }
        return Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) != nil
    }

    static func isValidExaminationCategory(_ value: String?) -> Bool {
        guard let raw = trimmedNonEmpty(value) else { return true }
        let normalized = raw.lowercased()
        let allowed: Set<String> = [
            ExaminationReportCategory.laboratory.rawValue,
            ExaminationReportCategory.imaging.rawValue,
            ExaminationReportCategory.pathology.rawValue,
            "laboratory", "lab", "实验室检查", "检验", "化验",
            "imaging", "image", "影像", "影像学检查",
            "pathology", "病理", "病理检查"
        ]
        return allowed.contains(normalized)
    }

    static func isValidFrequencyType(_ value: String?) -> Bool {
        guard let raw = trimmedNonEmpty(value) else { return true }
        let normalized = PrescriptionFieldNormalization.normalizeFrequencyType(raw)
        return Set(MedicationReminderFrequencyType.allCases.map(\.rawValue)).contains(normalized)
    }

    static func isValidPrescriptionStatus(_ value: String?) -> Bool {
        guard let raw = trimmedNonEmpty(value) else { return true }
        let normalized = raw.lowercased()
        return PrescriptionLifecycleStatus.allRawValues.contains(normalized)
    }

    static func isValidMedicationPlanStatus(_ value: String?) -> Bool {
        guard let raw = trimmedNonEmpty(value) else { return true }
        let normalized = raw.lowercased()
        return MedicationPlanLifecycleStatus.allRawValues.contains(normalized)
    }

    static func isValidEveryNDays(_ frequencyType: String?, everyNDays: String?) -> Bool {
        let normalized = PrescriptionFieldNormalization.normalizeFrequencyType(frequencyType)
        guard normalized == MedicationReminderFrequencyType.everyNDays.rawValue else { return true }
        guard let raw = trimmedNonEmpty(everyNDays), let days = Int(raw) else { return false }
        return (1...365).contains(days)
    }

    static func isValidWeeklyWeekdays(_ frequencyType: String?, weekdays: [Int]?) -> Bool {
        let normalized = PrescriptionFieldNormalization.normalizeFrequencyType(frequencyType)
        guard normalized == MedicationReminderFrequencyType.weekly.rawValue else { return true }
        guard let weekdays, weekdays.isEmpty == false else { return false }
        return weekdays.allSatisfy { (1...7).contains($0) }
    }

    static func isEndDateOnOrAfterStartDate(startDate: String?, endDate: String?) -> Bool {
        guard let end = trimmedNonEmpty(endDate) else { return true }
        guard let endParsed = parseComparableDateOnly(end) else { return false }
        guard let start = trimmedNonEmpty(startDate) else { return true }
        guard let startParsed = parseComparableDateOnly(start) else { return false }
        return endParsed >= startParsed
    }

    static func isStrictDateOnly(_ value: String?) -> Bool {
        guard let raw = trimmedNonEmpty(value) else { return true }
        return parseComparableDateOnly(raw) != nil
    }

    static func isHighRiskDoseValue(doseValue: String?, doseUnit: String?) -> Bool {
        guard let raw = trimmedNonEmpty(doseValue),
              let value = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")),
              let unit = trimmedNonEmpty(doseUnit)
        else { return false }
        let riskyUnits: Set<String> = ["片", "粒", "袋", "滴"]
        guard riskyUnits.contains(unit) else { return false }
        return value > 20
    }

    static func hasConflictingMedicineBoxBinding(
        medicineBoxID: String?,
        hasMedicineBox: Bool
    ) -> Bool {
        guard trimmedNonEmpty(medicineBoxID) != nil else { return false }
        return hasMedicineBox
    }

    static func isValidReminderTimes(_ times: [ReminderTime]?) -> Bool {
        guard let times else { return true }
        for entry in times {
            let trimmed = entry.time.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return false }
            if trimmed.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) == nil { return false }
        }
        return true
    }

    static func prescriptionStatusMessage() -> String {
        L10n.text("medical.upload.presubmit.error.prescription_status")
    }

    static func medicationPlanStatusMessage() -> String {
        L10n.text("medical.upload.presubmit.error.medication_plan_status")
    }

    static func everyNDaysMessage() -> String {
        L10n.text("medical.upload.presubmit.error.every_n_days")
    }

    static func weeklyWeekdaysMessage() -> String {
        L10n.text("medical.upload.presubmit.error.weekly_weekdays")
    }

    static func endDateBeforeStartDateMessage() -> String {
        L10n.text("medical.upload.presubmit.error.end_date_before_start")
    }

    static func highRiskDoseMessage() -> String {
        L10n.text("medical.upload.presubmit.error.high_risk_dose")
    }

    static func medicineBoxBindingConflictMessage() -> String {
        L10n.text("medical.upload.presubmit.error.medicine_box_binding")
    }

    static func reminderTimesMessage() -> String {
        L10n.text("medical.upload.presubmit.error.reminder_times")
    }

    /// 解析可比较的日历日期（UTC 零点），与 `isCompleteDate` 使用同一套格式。
    private static func parseComparableDateOnly(_ raw: String) -> Date? {
        if raw.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            return parseDateOnlyWithFormat(raw, format: "yyyy-MM-dd")
        }

        if let isoDate = PreSubmitISO8601.medicalWithFractionalSeconds.date(from: raw)
            ?? PreSubmitISO8601.medicalBasic.date(from: raw) {
            return calendarDateStart(from: isoDate)
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let supportedFormats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy.MM.dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy/MM/dd HH:mm",
            "yyyy.MM.dd HH:mm",
            "yyyy-MM-dd",
            "yyyy/MM/dd",
            "yyyy.MM.dd"
        ]

        for format in supportedFormats {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: raw) {
                return calendarDateStart(from: parsed)
            }
        }

        return nil
    }

    private static func parseDateOnlyWithFormat(_ raw: String, format: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter.date(from: raw)
    }

    private static func calendarDateStart(from date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.startOfDay(for: date)
    }

    static func requiredFieldMessage(fieldLabel: String) -> String {
        String(format: L10n.text("medical.upload.presubmit.error.required"), fieldLabel)
    }

    static func completeDateMessage() -> String {
        L10n.text("medical.upload.presubmit.error.complete_date")
    }

    static func validNumberMessage() -> String {
        L10n.text("medical.upload.presubmit.error.valid_number")
    }

    static func doseValueDecimalMessage() -> String {
        L10n.text("medical.upload.presubmit.error.dose_value_decimal")
    }

    static func validEnumMessage(fieldLabel: String) -> String {
        String(format: L10n.text("medical.upload.presubmit.error.valid_enum"), fieldLabel)
    }

    static func indexedRequiredMessage(index: Int, fieldLabel: String) -> String {
        String(
            format: L10n.text("medical.upload.presubmit.error.indexed_required"),
            index + 1,
            fieldLabel
        )
    }
}

private enum PreSubmitISO8601 {
    static let medicalBasic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let medicalWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
