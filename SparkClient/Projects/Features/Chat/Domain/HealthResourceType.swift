import Foundation

/// 健康资料引用类型，与 `RemoteMemberCompleteData` 字段及消息 block `resourceType` 对齐。
nonisolated enum HealthResourceType: String, Codable, Sendable, CaseIterable {
    case healthExamReport = "health_exam_report"
    case examinationReport = "examination_report"
    case medicalCase = "medical_case"
    case medicineBox = "medicine_box"
    case prescription = "prescription"
    case medicationPlan = "medication_plan"
    case medicationRecord = "medication_record"
    case medicationSummary = "medication_summary"
    case symptom = "symptom"
    case visit = "visit"
    case surgery = "surgery"
    case followUp = "follow_up"

    var localizationKey: String {
        "chat.ask_report.resource_type.\(rawValue)"
    }
}
