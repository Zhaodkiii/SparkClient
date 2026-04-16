import Foundation

struct ChatMedicationCardPayload: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let dosage: String?
    let frequency: String?
    let instructions: String?
    let isSaved: Bool
    let savedRecordID: Int?
    let ossFileID: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case dosage
        case frequency
        case instructions
        case isSaved
        case savedRecordID
        case ossFileID
        case savedRecordIDSnake = "saved_record_id"
        case ossFileIDSnake = "oss_file_id"
    }

    init(
        id: UUID,
        name: String,
        dosage: String?,
        frequency: String?,
        instructions: String?,
        isSaved: Bool = false,
        savedRecordID: Int? = nil,
        ossFileID: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.frequency = frequency
        self.instructions = instructions
        self.isSaved = isSaved
        self.savedRecordID = savedRecordID
        self.ossFileID = ossFileID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        dosage = try c.decodeIfPresent(String.self, forKey: .dosage)
        frequency = try c.decodeIfPresent(String.self, forKey: .frequency)
        instructions = try c.decodeIfPresent(String.self, forKey: .instructions)
        isSaved = try c.decodeIfPresent(Bool.self, forKey: .isSaved) ?? false
        savedRecordID = try c.decodeIfPresent(Int.self, forKey: .savedRecordID)
            ?? c.decodeIfPresent(Int.self, forKey: .savedRecordIDSnake)
        ossFileID = try c.decodeIfPresent(Int.self, forKey: .ossFileID)
            ?? c.decodeIfPresent(Int.self, forKey: .ossFileIDSnake)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(dosage, forKey: .dosage)
        try c.encodeIfPresent(frequency, forKey: .frequency)
        try c.encodeIfPresent(instructions, forKey: .instructions)
        try c.encode(isSaved, forKey: .isSaved)
        try c.encodeIfPresent(savedRecordID, forKey: .savedRecordID)
        try c.encodeIfPresent(ossFileID, forKey: .ossFileID)
    }
}

struct ChatPrescriptionCardPayload: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let batchNo: String?
    let institutionName: String?
    let prescribedAt: String?
    let diagnosis: String?
    let medications: [ChatMedicationCardPayload]
    let isSaved: Bool
    let savedRecordID: Int?
    let ossFileID: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case batchNo
        case institutionName
        case prescribedAt
        case diagnosis
        case medications
        case isSaved
        case savedRecordID
        case ossFileID
        case savedRecordIDSnake = "saved_record_id"
        case ossFileIDSnake = "oss_file_id"
    }

    init(
        id: UUID,
        batchNo: String?,
        institutionName: String?,
        prescribedAt: String?,
        diagnosis: String?,
        medications: [ChatMedicationCardPayload],
        isSaved: Bool = false,
        savedRecordID: Int? = nil,
        ossFileID: Int? = nil
    ) {
        self.id = id
        self.batchNo = batchNo
        self.institutionName = institutionName
        self.prescribedAt = prescribedAt
        self.diagnosis = diagnosis
        self.medications = medications
        self.isSaved = isSaved
        self.savedRecordID = savedRecordID
        self.ossFileID = ossFileID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        batchNo = try c.decodeIfPresent(String.self, forKey: .batchNo)
        institutionName = try c.decodeIfPresent(String.self, forKey: .institutionName)
        prescribedAt = try c.decodeIfPresent(String.self, forKey: .prescribedAt)
        diagnosis = try c.decodeIfPresent(String.self, forKey: .diagnosis)
        medications = try c.decodeIfPresent([ChatMedicationCardPayload].self, forKey: .medications) ?? []
        isSaved = try c.decodeIfPresent(Bool.self, forKey: .isSaved) ?? false
        savedRecordID = try c.decodeIfPresent(Int.self, forKey: .savedRecordID)
            ?? c.decodeIfPresent(Int.self, forKey: .savedRecordIDSnake)
        ossFileID = try c.decodeIfPresent(Int.self, forKey: .ossFileID)
            ?? c.decodeIfPresent(Int.self, forKey: .ossFileIDSnake)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(batchNo, forKey: .batchNo)
        try c.encodeIfPresent(institutionName, forKey: .institutionName)
        try c.encodeIfPresent(prescribedAt, forKey: .prescribedAt)
        try c.encodeIfPresent(diagnosis, forKey: .diagnosis)
        try c.encode(medications, forKey: .medications)
        try c.encode(isSaved, forKey: .isSaved)
        try c.encodeIfPresent(savedRecordID, forKey: .savedRecordID)
        try c.encodeIfPresent(ossFileID, forKey: .ossFileID)
    }
}

struct ChatExamReportCardPayload: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let title: String
    let hospital: String?
    let date: String?
    let conclusion: String?
    let isSaved: Bool
    let savedRecordID: Int?
    let ossFileID: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case hospital
        case date
        case conclusion
        case isSaved
        case savedRecordID
        case ossFileID
        case savedRecordIDSnake = "saved_record_id"
        case ossFileIDSnake = "oss_file_id"
    }

    init(
        id: UUID,
        title: String,
        hospital: String?,
        date: String?,
        conclusion: String?,
        isSaved: Bool = false,
        savedRecordID: Int? = nil,
        ossFileID: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.hospital = hospital
        self.date = date
        self.conclusion = conclusion
        self.isSaved = isSaved
        self.savedRecordID = savedRecordID
        self.ossFileID = ossFileID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        hospital = try c.decodeIfPresent(String.self, forKey: .hospital)
        date = try c.decodeIfPresent(String.self, forKey: .date)
        conclusion = try c.decodeIfPresent(String.self, forKey: .conclusion)
        isSaved = try c.decodeIfPresent(Bool.self, forKey: .isSaved) ?? false
        savedRecordID = try c.decodeIfPresent(Int.self, forKey: .savedRecordID)
            ?? c.decodeIfPresent(Int.self, forKey: .savedRecordIDSnake)
        ossFileID = try c.decodeIfPresent(Int.self, forKey: .ossFileID)
            ?? c.decodeIfPresent(Int.self, forKey: .ossFileIDSnake)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(hospital, forKey: .hospital)
        try c.encodeIfPresent(date, forKey: .date)
        try c.encodeIfPresent(conclusion, forKey: .conclusion)
        try c.encode(isSaved, forKey: .isSaved)
        try c.encodeIfPresent(savedRecordID, forKey: .savedRecordID)
        try c.encodeIfPresent(ossFileID, forKey: .ossFileID)
    }
}

struct ChatMedicalCaseCardPayload: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let title: String
    let summary: String?
    let diagnosis: String?
    let hospitalName: String?
    let occurredAt: String?
    let isSaved: Bool
    let savedRecordID: Int?
    let ossFileID: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case diagnosis
        case hospitalName
        case occurredAt
        case isSaved
        case savedRecordID
        case ossFileID
        case savedRecordIDSnake = "saved_record_id"
        case ossFileIDSnake = "oss_file_id"
    }

    init(
        id: UUID,
        title: String,
        summary: String?,
        diagnosis: String?,
        hospitalName: String?,
        occurredAt: String?,
        isSaved: Bool = false,
        savedRecordID: Int? = nil,
        ossFileID: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.diagnosis = diagnosis
        self.hospitalName = hospitalName
        self.occurredAt = occurredAt
        self.isSaved = isSaved
        self.savedRecordID = savedRecordID
        self.ossFileID = ossFileID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        diagnosis = try c.decodeIfPresent(String.self, forKey: .diagnosis)
        hospitalName = try c.decodeIfPresent(String.self, forKey: .hospitalName)
        occurredAt = try c.decodeIfPresent(String.self, forKey: .occurredAt)
        isSaved = try c.decodeIfPresent(Bool.self, forKey: .isSaved) ?? false
        savedRecordID = try c.decodeIfPresent(Int.self, forKey: .savedRecordID)
            ?? c.decodeIfPresent(Int.self, forKey: .savedRecordIDSnake)
        ossFileID = try c.decodeIfPresent(Int.self, forKey: .ossFileID)
            ?? c.decodeIfPresent(Int.self, forKey: .ossFileIDSnake)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(summary, forKey: .summary)
        try c.encodeIfPresent(diagnosis, forKey: .diagnosis)
        try c.encodeIfPresent(hospitalName, forKey: .hospitalName)
        try c.encodeIfPresent(occurredAt, forKey: .occurredAt)
        try c.encode(isSaved, forKey: .isSaved)
        try c.encodeIfPresent(savedRecordID, forKey: .savedRecordID)
        try c.encodeIfPresent(ossFileID, forKey: .ossFileID)
    }
}
