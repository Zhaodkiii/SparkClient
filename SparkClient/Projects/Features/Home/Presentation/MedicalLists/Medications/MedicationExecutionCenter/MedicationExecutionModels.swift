import Foundation

enum MedicationPlanStatus {
    static let asNeeded = "as_needed"
}

enum MedicationDoseLogStatus: String, Equatable {
    case taken
    case skipped

    var title: String {
        switch self {
        case .taken: return L10n.text("home.medical.medication_execution.status.taken")
        case .skipped: return L10n.text("home.medical.medication_execution.status.skipped")
        }
    }

    var symbolName: String {
        switch self {
        case .taken: return "checkmark.circle.fill"
        case .skipped: return "xmark.circle.fill"
        }
    }
}

struct MedicationExecutionDateItem: Identifiable, Equatable {
    let date: Date
    let id: String

    init(date: Date, calendar: Calendar) {
        self.date = date
        self.id = Self.id(for: date, calendar: calendar)
    }

    static func id(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

enum MedicationExecutionLogSheetSource {
    /// 按需用药：来自服药计划
    case medicationPlans
    /// 按需用药：来自个人药箱
    case medicineBox
}

struct MedicationExecutionLogSubmission {
    let selections: [MedicationExecutionDose.ID: MedicationDoseLogStatus]
    let edits: [MedicationExecutionDose.ID: MedicationExecutionDoseEdit]
    let doses: [MedicationExecutionDose]
}

struct MedicationExecutionDoseEdit: Equatable {
    var quantity: Double
    var doseUnit: String
    var scheduledAt: Date

    var plannedDose: String {
        MedicationExecutionDoseEditSupport.formattedDose(quantity: quantity, unit: doseUnit)
    }

    static func from(dose: MedicationExecutionDose) -> MedicationExecutionDoseEdit {
        let source = dose.record.flatMap { $0.actualDose.trimmedNonEmpty }
            ?? dose.record?.plannedDose.trimmedNonEmpty
            ?? dose.plannedDose
        let parsed = MedicationExecutionDoseEditSupport.parse(
            source: source,
            fallbackUnit: dose.dosageFormUnitToken
        )
        return MedicationExecutionDoseEdit(
            quantity: parsed.quantity,
            doseUnit: parsed.unit,
            scheduledAt: dose.scheduledAt
        )
    }
}

enum MedicationExecutionDoseEditSupport {
    static func parse(source: String, fallbackUnit: String) -> (quantity: Double, unit: String) {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parts = MedicineSpecification.splitLeadingDoseNumericPrefix(trimmed),
           let quantity = Double(parts.0) {
            let unit = parts.1.isEmpty
                ? fallbackUnit
                : MedicineSpecificationCatalog.storedDoseUnit(fromAny: parts.1)
            return (max(quantity, 0.5), unit.isEmpty ? fallbackUnit : unit)
        }
        if let quantity = Double(trimmed) {
            return (max(quantity, 0.5), fallbackUnit)
        }
        return (1, fallbackUnit)
    }

    static func formattedDose(quantity: Double, unit: String) -> String {
        let prefersEnglish = SparkFormCatalogMenuLocale.prefersEnglish
        let unitDisplay = MedicineSpecificationCatalog.displayUnit(stored: unit, prefersEnglish: prefersEnglish)
        let quantityText = quantity.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", quantity)
            : String(format: "%.1f", quantity)
        if unitDisplay.isEmpty { return quantityText }
        if prefersEnglish { return "\(quantityText) \(unitDisplay)" }
        return "\(quantityText)\(unitDisplay)"
    }

    static func mergeTime(_ time: Date, on day: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = 0
        return calendar.date(from: components) ?? time
    }

    static var quantityOptions: [Double] {
        var values: [Double] = []
        var current = 0.5
        while current <= 20 {
            values.append(current)
            current += current < 1 ? 0.5 : 1
        }
        return values
    }
}

struct MedicationExecutionLogSheetContext: Identifiable {
    let id = UUID()
    let title: String
    let date: Date
    let doses: [MedicationExecutionDose]
    var source: MedicationExecutionLogSheetSource = .medicationPlans

    /// 编辑已有记录时，用当前状态预填选择
    var initialSelections: [MedicationExecutionDose.ID: MedicationDoseLogStatus] {
        doses.reduce(into: [:]) { partial, dose in
            guard let status = MedicationDoseLogStatus(rawValue: dose.status) else { return }
            partial[dose.id] = status
        }
    }
}

struct MedicationExecutionDose: Identifiable, Equatable {
    let id: String
    let plan: SparkMedicalSyncAPI.RemoteMedicationPlan
    let scheduledAt: Date
    let plannedDose: String
    let doseSequence: Int
    let record: SparkMedicalSyncAPI.RemoteMedicationRecord?
    let imageAttachment: SparkMedicalSyncAPI.RemoteManagedFile?

    var status: String {
        record?.status ?? "scheduled"
    }

    var isCompleted: Bool {
        status == "taken" || status == "skipped"
    }

    var displayName: String {
        plan.drugName.trimmedNonEmpty ?? L10n.text("home.medical.medication_execution.unnamed_drug")
    }

    var specificationText: String {
        let doseUnit = plan.doseUnit.trimmedNonEmpty
        let tablet = L10n.text("home.medical.medication_execution.spec.tablet")
        let parts = [tablet, doseUnit].compactMap { $0 }
        let separator = Locale.current.language.languageCode?.identifier.hasPrefix("zh") == true ? "，" : ", "
        return parts.joined(separator: separator)
    }

    var instructionText: String {
        let time = MedicationExecutionPlanner.timeText(for: scheduledAt)
        return L10n.format("home.medical.medication_execution.instruction", time, plannedDose)
    }

    func instructionText(edit: MedicationExecutionDoseEdit) -> String {
        let time = MedicationExecutionPlanner.timeText(for: edit.scheduledAt)
        return L10n.format("home.medical.medication_execution.instruction", time, edit.plannedDose)
    }

    var dosageFormLabel: String {
        if let unit = plan.doseUnit.trimmedNonEmpty {
            return MedicineSpecificationCatalog.displayUnit(
                stored: unit,
                prefersEnglish: SparkFormCatalogMenuLocale.prefersEnglish
            )
        }
        return L10n.text("home.medical.medication_execution.spec.tablet")
    }

    var dosageFormUnitToken: String {
        plan.doseUnit.trimmedNonEmpty
            ?? MedicineSpecificationCatalog.storedDoseUnit(
                fromDisplay: L10n.text("home.medical.medication_execution.spec.tablet")
            )
    }

    var detailSubtitle: String {
        let strength = plan.dosePerTime.trimmedNonEmpty ?? ""
        let separator = Locale.current.language.languageCode?.identifier.hasPrefix("zh") == true ? "，" : ", "
        if strength.isEmpty { return dosageFormLabel }
        return [dosageFormLabel, strength].joined(separator: separator)
    }
}

struct MedicationExecutionTimeGroup: Equatable {
    let timeText: String
    let doses: [MedicationExecutionDose]
}

struct MedicationRecordCreatePayload: Encodable {
    let member: Int
    let plan: Int
    let scheduledAt: String
    let takenAt: String?
    let status: String
    let plannedDose: String
    let actualDose: String
    let doseSequence: Int
    let timezone: String
    let notes: String
    let extra: [String: String]
}

struct MedicationRecordUpdatePayload: Encodable {
    let scheduledAt: String?
    let takenAt: String?
    let status: String
    let plannedDose: String?
    let actualDose: String
    let notes: String
    let extra: [String: String]
}

extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
