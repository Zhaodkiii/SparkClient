import Foundation

protocol MedicalRecordRepository: Sendable {
    func loadRecords(memberID: Int, limit: Int) async -> [MedicalRecord]
    func buildMemberContextSummary(memberID: Int, limit: Int) async -> String
}
