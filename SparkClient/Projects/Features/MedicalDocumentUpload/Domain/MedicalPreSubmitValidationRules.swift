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

        if raw.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            return true
        }

        if PreSubmitISO8601.medicalWithFractionalSeconds.date(from: raw) != nil
            || PreSubmitISO8601.medicalBasic.date(from: raw) != nil {
            return true
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current

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
            if formatter.date(from: raw) != nil {
                return true
            }
        }

        return false
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
        let normalized = raw.lowercased()
        let allowed = Set(MedicationReminderFrequencyType.allCases.map(\.rawValue))
        if allowed.contains(normalized) { return true }
        switch normalized {
        case "every_n_days", "interval", "间隔", "weekly", "week", "每周", "daily", "每天":
            return true
        default:
            return false
        }
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
