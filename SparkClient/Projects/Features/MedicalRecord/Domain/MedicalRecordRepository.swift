import Foundation

protocol MedicalRecordRepository: Sendable {
    func loadRecords(patientID: UUID, limit: Int) async -> [MedicalRecord]
    func buildPatientContextSummary(patientID: UUID, limit: Int) async -> String
}

