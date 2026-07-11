import Foundation

struct MedicationPlanDraft {
    var medicalCaseID: Int?
    var medicineBoxID: Int?
    var prescriptionID: Int?
    var drugName = ""
    var dosePerTime = ""
    var doseValue = ""
    var doseUnit = "片"
    var reminderFrequencyType: MedicationReminderFrequencyType = .daily
    var everyNDays: Int = 1
    var weeklyWeekdays: Set<Int> = []
    var frequencyText = ""
    var reminderTimesText = "08:00"
    var startDate = Date()
    var hasEndDate = false
    var endDate = Date()
    var instructions = ""
    var reminderEnabled = true
    var status = "active"

    init() {}

    init(existing: SparkMedicalSyncAPI.RemoteMedicationPlan) {
        medicalCaseID = existing.medicalCase
        medicineBoxID = existing.medicineBox
        prescriptionID = existing.prescription
        drugName = existing.drugName
        dosePerTime = existing.dosePerTime
        doseValue = existing.doseValue.map { $0.formatted(.number.precision(.fractionLength(0...3))) } ?? ""
        doseUnit = existing.doseUnit
        reminderFrequencyType = MedicationReminderFrequencyType(rawValue: existing.frequencyType) ?? .daily
        everyNDays = min(max(existing.everyNDays ?? 1, 1), 365)
        weeklyWeekdays = Set(existing.weeklyWeekdays.filter { (1...7).contains($0) })
        frequencyText = existing.frequencyText
        if frequencyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            frequencyText = MedicationReminderFrequencySummary.displayLine(
                type: reminderFrequencyType,
                everyNDays: everyNDays,
                weekdays: weeklyWeekdays
            )
        }
        reminderTimesText = existing.reminderTimes.map(\.time).joined(separator: ", ")
        startDate = existing.startDate
        if let endDate = existing.endDate {
            hasEndDate = true
            self.endDate = endDate
        }
        instructions = existing.instructions
        reminderEnabled = existing.reminderEnabled
        status = existing.status
    }

    var doseValueValue: Double? {
        doseValue.nilIfBlank.flatMap(Double.init)
    }

    /// Human-readable `dose_per_time` line from structured fields, e.g. `1 / 5 ml` when both are set.
    static func suggestedDosePerTimeLine(doseValue: String, doseUnit: String, prefersEnglish: Bool) -> String {
        let dv = doseValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let du = doseUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        let duDisp = du.isEmpty ? "" : MedicineSpecificationCatalog.displayUnit(stored: du, prefersEnglish: prefersEnglish)
        switch (dv.isEmpty, duDisp.isEmpty) {
        case (true, true): return ""
        case (false, true): return dv
        case (true, false): return duDisp
        case (false, false): return "\(dv) / \(duDisp)"
        }
    }

    var isReminderFrequencyComplete: Bool {
        MedicationReminderFrequencySummary.isComplete(
            type: reminderFrequencyType,
            everyNDays: everyNDays,
            weekdays: weeklyWeekdays
        )
    }

    var resolvedFrequencyText: String {
        if let manual = frequencyText.nilIfBlank {
            return manual
        }
        return MedicationReminderFrequencySummary.displayLine(
            type: reminderFrequencyType,
            everyNDays: everyNDays,
            weekdays: weeklyWeekdays
        )
    }

    var reminderFrequencyPickerDisplay: String {
        let line = resolvedFrequencyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty == false { return line }
        return MedicationReminderFrequencySummary.displayLine(
            type: reminderFrequencyType,
            everyNDays: everyNDays,
            weekdays: weeklyWeekdays
        )
    }

    var reminderTimesError: String? {
        parseReminderTimes().error
    }

    var validationMessage: String {
        if drugName.nilIfBlank == nil {
            return L10n.text("medication_plan.form.validation.drug_name_required", fallback: "请填写药品名称")
        }
        if dosePerTime.nilIfBlank == nil {
            return L10n.text("medication_plan.form.validation.dose_required", fallback: "请填写单次剂量")
        }
        if isReminderFrequencyComplete == false {
            return L10n.text("medication_plan.form.validation.frequency_incomplete", fallback: "请完整选择服药频次（每几天需选天数，每周需至少选一天）")
        }
        if resolvedFrequencyText.nilIfBlank == nil {
            return L10n.text("medication_plan.form.validation.frequency_text_required", fallback: "请填写或生成服药频次说明")
        }
        if let reminderTimesError {
            return reminderTimesError
        }
        if hasEndDate && endDate < startDate {
            return L10n.text("medication_plan.form.validation.end_date_before_start", fallback: "结束日期不能早于开始日期")
        }
        return L10n.text("medication_plan.form.validation.incomplete", fallback: "请完善服药计划信息")
    }

    func payload(memberID: Int) throws -> MedicationPlanPayload {
        let reminderTimesResult = parseReminderTimes()
        if let error = reminderTimesResult.error {
            throw MedicationPlanFormError.invalidReminderTimes(error)
        }
        let weeklyPayload: [Int] = {
            guard reminderFrequencyType == .weekly else { return [] }
            return weeklyWeekdays.filter { (1...7).contains($0) }.sorted()
        }()
        return MedicationPlanPayload(
            member: memberID,
            medicalCase: medicalCaseID,
            medicineBox: medicineBoxID,
            prescription: prescriptionID,
            drugName: drugName.trimmed,
            dosePerTime: dosePerTime.trimmed,
            doseValue: doseValueValue,
            doseUnit: doseUnit.nilIfBlank ?? "",
            frequencyType: reminderFrequencyType.rawValue,
            everyNDays: reminderFrequencyType == .everyNDays ? everyNDays : nil,
            weeklyWeekdays: weeklyPayload,
            frequencyText: resolvedFrequencyText.trimmed,
            reminderTimes: reminderTimesResult.times,
            startDate: MedicalDateCoding.encodeDateOnly(startDate),
            endDate: hasEndDate ? MedicalDateCoding.encodeDateOnly(endDate) : nil,
            instructions: instructions.nilIfBlank ?? "",
            reminderEnabled: reminderEnabled,
            status: status,
            extra: [:]
        )
    }

    private func parseReminderTimes() -> (times: [ReminderTime], error: String?) {
        let rawItems = reminderTimesText
            .components(separatedBy: CharacterSet(charactersIn: ",，、;； \n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        var result: [ReminderTime] = []
        var seen = Set<String>()
        for item in rawItems {
            guard Self.isValidTimeText(item) else {
                return ([], L10n.text("medication_plan.form.validation.reminder_time_format", fallback: "提醒时间格式应为 HH:mm，例如 08:00"))
            }
            guard seen.insert(item).inserted else { continue }
            result.append(.init(time: item, dose: doseValueValue))
        }
        return (result, nil)
    }

    static func isValidTimeText(_ value: String) -> Bool {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return false
        }
        return (0...23).contains(hour) && (0...59).contains(minute)
    }
}

extension MedicationPlanDraft {
    /// 从当前文案中提取有效、去重后的 `HH:mm` 列表（用于用药时间 chips；无效片段被跳过，仍可由 `reminderTimesError` 提示整体验证）。
    var orderedReminderTimeSlots: [String] {
        let rawItems = reminderTimesText
            .components(separatedBy: CharacterSet(charactersIn: ",，、;； \n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        var result: [String] = []
        var seen = Set<String>()
        for item in rawItems {
            guard Self.isValidTimeText(item) else { continue }
            let norm = Self.normalizedReminderTimeToken(item)
            guard seen.insert(norm).inserted else { continue }
            result.append(norm)
        }
        return result
    }

    mutating func replaceReminderTimeSlots(_ slots: [String]) {
        var seen = Set<String>()
        var unique: [String] = []
        for slot in slots {
            let norm = Self.normalizedReminderTimeToken(slot)
            guard Self.isValidTimeText(norm) else { continue }
            if seen.insert(norm).inserted {
                unique.append(norm)
            }
        }
        unique.sort()
        reminderTimesText = unique.isEmpty ? "" : unique.joined(separator: ", ")
    }

    static func normalizedReminderTimeToken(_ value: String) -> String {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(format: "%02d:%02d", hour, minute)
    }

    static func reminderTimeString(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let h = min(max(c.hour ?? 0, 0), 23)
        let m = min(max(c.minute ?? 0, 0), 59)
        return String(format: "%02d:%02d", h, m)
    }

    static func dateForReminderTimeToken(_ token: String) -> Date {
        let parts = token.split(separator: ":")
        let h = min(max(Int(parts[0]) ?? 8, 0), 23)
        let m = parts.count > 1 ? min(max(Int(parts[1]) ?? 0, 0), 59) : 0
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = h
        c.minute = m
        return Calendar.current.date(from: c) ?? Date()
    }
}

nonisolated struct MedicationPlanPayload: Encodable {
    let member: Int
    let medicalCase: Int?
    let medicineBox: Int?
    let prescription: Int?
    let drugName: String
    let dosePerTime: String
    let doseValue: Double?
    let doseUnit: String
    let frequencyType: String
    let everyNDays: Int?
    let weeklyWeekdays: [Int]
    let frequencyText: String
    let reminderTimes: [ReminderTime]
    let startDate: String
    let endDate: String?
    let instructions: String
    let reminderEnabled: Bool
    let status: String
    let extra: [String: String]


    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodableKey.self)
        try container.encode(member, forKey: .key("member"))
        try container.encodeNullable(medicalCase, forKey: .key("medicalCase"))
        try container.encodeNullable(medicineBox, forKey: .key("medicineBox"))
        try container.encodeNullable(prescription, forKey: .key("prescription"))
        try container.encode(drugName, forKey: .key("drugName"))
        try container.encode(dosePerTime, forKey: .key("dosePerTime"))
        try container.encodeNullable(doseValue, forKey: .key("doseValue"))
        try container.encode(doseUnit, forKey: .key("doseUnit"))
        try container.encode(frequencyType, forKey: .key("frequencyType"))
        try container.encodeNullable(everyNDays, forKey: .key("everyNDays"))
        try container.encode(weeklyWeekdays, forKey: .key("weeklyWeekdays"))
        try container.encode(frequencyText, forKey: .key("frequencyText"))
        try container.encode(reminderTimes, forKey: .key("reminderTimes"))
        try container.encode(startDate, forKey: .key("startDate"))
        try container.encodeNullable(endDate, forKey: .key("endDate"))
        try container.encode(instructions, forKey: .key("instructions"))
        try container.encode(reminderEnabled, forKey: .key("reminderEnabled"))
        try container.encode(status, forKey: .key("status"))
        try container.encode(extra, forKey: .key("extra"))
    }
}

enum MedicationPlanFormError: LocalizedError {
    case invalidReminderTimes(String)

    var errorDescription: String? {
        switch self {
        case .invalidReminderTimes(let message):
            return message
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension KeyedEncodingContainer {
    nonisolated mutating func encodeNullable<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
