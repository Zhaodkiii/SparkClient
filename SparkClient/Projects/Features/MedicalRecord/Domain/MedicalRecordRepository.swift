import Foundation

protocol MedicalRecordRepository: Sendable {
    func loadRecords(patientID: Int, limit: Int) async -> [MedicalRecord]
    func buildPatientContextSummary(patientID: Int, limit: Int) async -> String
}

