import Foundation

enum MedicationDoseLogStatus: String, Equatable {
    case taken
    case skipped

    var title: String {
        switch self {
        case .taken: return "已用药"
        case .skipped: return "已跳过"
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

struct MedicationExecutionLogSheetContext: Identifiable {
    let id = UUID()
    let title: String
    let date: Date
    let doses: [MedicationExecutionDose]
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
        plan.drugName.trimmedNonEmpty ?? "未命名药品"
    }

    var specificationText: String {
        let doseUnit = plan.doseUnit.trimmedNonEmpty
        return ["药片", doseUnit].compactMap { $0 }.joined(separator: "，")
    }

    var instructionText: String {
        let time = MedicationExecutionPlanner.timeText(for: scheduledAt)
        return "\(time) 用药： \(plannedDose)"
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
    let takenAt: String?
    let status: String
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
