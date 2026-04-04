import Foundation

struct RecognizedMedicalDraft: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let patientID: UUID
    let sourcePath: String
    let rawText: String
    let title: String
    let summary: String
    let diagnosis: String?
    let occurredAt: Date
    let createdAt: Date
    var isConfirmed: Bool

    init(
        id: UUID = UUID(),
        patientID: UUID,
        sourcePath: String,
        rawText: String,
        title: String,
        summary: String,
        diagnosis: String? = nil,
        occurredAt: Date,
        createdAt: Date = Date(),
        isConfirmed: Bool = false
    ) {
        self.id = id
        self.patientID = patientID
        self.sourcePath = sourcePath
        self.rawText = rawText
        self.title = title
        self.summary = summary
        self.diagnosis = diagnosis
        self.occurredAt = occurredAt
        self.createdAt = createdAt
        self.isConfirmed = isConfirmed
    }
}

protocol MedicalDraftRepository: Sendable {
    func save(_ draft: RecognizedMedicalDraft) async
    func latest(patientID: UUID) async -> RecognizedMedicalDraft?
    func markConfirmed(draftID: UUID) async
}

