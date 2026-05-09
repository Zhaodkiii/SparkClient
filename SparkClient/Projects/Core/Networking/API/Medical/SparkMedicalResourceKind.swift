import Foundation

/// 统一医疗资源入口 `GET|POST /api/v1/medical/resources/?kind=...` 的 `kind` 取值，
/// 与 `SparkService` 中 `MEDICAL_UNIFIED_RESOURCE_VIEWSETS` 的 key 一致。
enum SparkMedicalResourceKind: String, Sendable, CaseIterable {
    case members = "members"
    case cases = "cases"
    case symptoms = "symptoms"
    case visits = "visits"
    case surgeries = "surgeries"
    case followUps = "follow-ups"
    case healthExamReports = "health-exam-reports"
    case examinationReports = "examination-reports"
    case medExamDetails = "med-exam-details"
    case medicineBoxes = "medicine-boxes"
    case prescriptions = "prescriptions"
    case medicationPlans = "medication-plans"
    case medicationRecords = "medication-records"
}
