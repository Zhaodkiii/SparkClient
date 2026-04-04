import Foundation

struct SparkMedicalSyncAPI {
    let configuration: SparkBackendConfiguration

    init(configuration: SparkBackendConfiguration) {
        self.configuration = configuration
    }

    struct RemoteSnapshotPayload: Codable, Sendable, Equatable {
        var members: [RemoteMember]
        var medicalCases: [RemoteMedicalCase]
        var examinationReports: [RemoteExaminationReport]
        var medicalReports: [RemoteMedicalReport]
        var prescriptions: [RemotePrescription]
        var healthMetrics: [RemoteHealthMetric]

        enum CodingKeys: String, CodingKey {
            case members
            case medicalCases = "medical_cases"
            case examinationReports = "examination_reports"
            case medicalReports = "medical_reports"
            case prescriptions
            case healthMetrics = "health_metrics"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.members = (try? container.decode([RemoteMember].self, forKey: .members)) ?? []
            self.medicalCases = (try? container.decode([RemoteMedicalCase].self, forKey: .medicalCases)) ?? []
            self.examinationReports = (try? container.decode([RemoteExaminationReport].self, forKey: .examinationReports)) ?? []
            self.medicalReports = (try? container.decode([RemoteMedicalReport].self, forKey: .medicalReports)) ?? []
            self.prescriptions = (try? container.decode([RemotePrescription].self, forKey: .prescriptions)) ?? []
            self.healthMetrics = (try? container.decode([RemoteHealthMetric].self, forKey: .healthMetrics)) ?? []
        }
    }

    struct RemoteHealthMetric: Codable, Sendable, Equatable {
        var id: Int
        var clientUID: UUID
        var profileClientUID: UUID
        var metricType: String
        var value: Double
        var unit: String
        var recordedAt: Date
        var note: String?
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case clientUID = "client_uid"
            case profileClientUID = "profile_client_uid"
            case metricType = "metric_type"
            case value
            case unit
            case recordedAt = "recorded_at"
            case note
            case updatedAt = "updated_at"
        }
    }

    struct RemoteMember: Codable, Sendable, Equatable {
        var id: Int
        var clientUID: UUID
        var name: String
        var age: Int
        var gender: String
        var relationship: String
        var avatar: String
        var birthDate: Date?
        var isPrimary: Bool
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case clientUID = "client_uid"
            case name
            case age
            case gender
            case relationship
            case avatar
            case birthDate = "birth_date"
            case isPrimary = "is_primary"
            case updatedAt = "updated_at"
        }

    }

    struct RemoteMedicalCase: Codable, Sendable, Equatable {
        var id: Int
        var clientUID: UUID
        var member: Int
        var title: String
        var chiefComplaint: String
        var diagnosis: String
        var severity: String
        var visitDate: Date
        var status: String
        var notes: String
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case clientUID = "client_uid"
            case member
            case title
            case chiefComplaint = "chief_complaint"
            case diagnosis
            case severity
            case visitDate = "visit_date"
            case status
            case notes
            case updatedAt = "updated_at"
        }
    }

    struct RemoteExaminationReport: Codable, Sendable, Equatable {
        var id: Int
        var clientUID: UUID
        var member: Int
        var medicalCase: Int?
        var category: String
        var subcategory: String
        var reportName: String
        var checkType: String
        var conclusion: String
        var doctorAdvice: String
        var date: Date
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case clientUID = "client_uid"
            case member
            case medicalCase = "medical_case"
            case category
            case subcategory
            case reportName = "report_name"
            case checkType = "check_type"
            case conclusion
            case doctorAdvice = "doctor_advice"
            case date
            case updatedAt = "updated_at"
        }
    }

    struct RemoteMedicalReport: Codable, Sendable, Equatable {
        var id: Int
        var clientUID: UUID
        var member: Int
        var medicalCase: Int?
        var reportType: String
        var title: String
        var hospital: String
        var doctor: String
        var content: String
        var date: Date
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case clientUID = "client_uid"
            case member
            case medicalCase = "medical_case"
            case reportType = "report_type"
            case title
            case hospital
            case doctor
            case content
            case date
            case updatedAt = "updated_at"
        }
    }

    struct RemotePrescription: Codable, Sendable, Equatable {
        var id: Int
        var clientUID: UUID
        var member: Int
        var medicalCase: Int?
        var drugName: String
        var dosage: String
        var frequency: String
        var durationDays: Int
        var instructions: String
        var startDate: Date?
        var endDate: Date?
        var status: String
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case clientUID = "client_uid"
            case member
            case medicalCase = "medical_case"
            case drugName = "drug_name"
            case dosage
            case frequency
            case durationDays = "duration_days"
            case instructions
            case startDate = "start_date"
            case endDate = "end_date"
            case status
            case updatedAt = "updated_at"
        }
    }

    struct UploadSnapshotPayload: Encodable, Sendable {
        let members: [UploadMember]
        let medicalCases: [UploadMedicalCase]
        let examinationReports: [UploadExaminationReport]
        let medicalReports: [UploadMedicalReport]
        let prescriptions: [UploadPrescription]
        let healthMetrics: [UploadHealthMetric]

        enum CodingKeys: String, CodingKey {
            case members
            case medicalCases = "medical_cases"
            case examinationReports = "examination_reports"
            case medicalReports = "medical_reports"
            case prescriptions
            case healthMetrics = "health_metrics"
        }
    }

    struct UploadHealthMetric: Encodable, Sendable {
        let clientUID: UUID
        let profileClientUID: UUID
        let metricType: String
        let value: Double
        let unit: String
        let recordedAt: Date
        let note: String?
        let updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case clientUID = "client_uid"
            case profileClientUID = "profile_client_uid"
            case metricType = "metric_type"
            case value
            case unit
            case recordedAt = "recorded_at"
            case note
            case updatedAt = "updated_at"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(clientUID, forKey: .clientUID)
            try container.encode(profileClientUID, forKey: .profileClientUID)
            try container.encode(metricType, forKey: .metricType)
            try container.encode(value, forKey: .value)
            try container.encode(unit, forKey: .unit)
            try container.encode(MedicalDateCoding.encodeISO8601(recordedAt), forKey: .recordedAt)
            try container.encodeIfPresent(note, forKey: .note)
            try container.encode(MedicalDateCoding.encodeISO8601(updatedAt), forKey: .updatedAt)
        }
    }

    struct UploadMember: Encodable, Sendable {
        let clientUID: UUID
        let name: String
        let age: Int
        let gender: String
        let relationship: String
        let avatar: String
        let birthDate: Date?
        let isPrimary: Bool

        enum CodingKeys: String, CodingKey {
            case clientUID = "client_uid"
            case name
            case age
            case gender
            case relationship
            case avatar
            case birthDate = "birth_date"
            case isPrimary = "is_primary"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(clientUID, forKey: .clientUID)
            try container.encode(name, forKey: .name)
            try container.encode(age, forKey: .age)
            try container.encode(gender, forKey: .gender)
            try container.encode(relationship, forKey: .relationship)
            try container.encode(avatar, forKey: .avatar)
            if let birthDate {
                try container.encode(MedicalDateCoding.encodeDateOnly(birthDate), forKey: .birthDate)
            } else {
                try container.encodeNil(forKey: .birthDate)
            }
            try container.encode(isPrimary, forKey: .isPrimary)
        }
    }

    struct UploadMedicalCase: Encodable, Sendable {
        let clientUID: UUID
        let memberClientUID: UUID
        let title: String
        let chiefComplaint: String
        let diagnosis: String
        let severity: String
        let visitDate: Date
        let status: String
        let notes: String

        enum CodingKeys: String, CodingKey {
            case clientUID = "client_uid"
            case memberClientUID = "member_client_uid"
            case title
            case chiefComplaint = "chief_complaint"
            case diagnosis
            case severity
            case visitDate = "visit_date"
            case status
            case notes
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(clientUID, forKey: .clientUID)
            try container.encode(memberClientUID, forKey: .memberClientUID)
            try container.encode(title, forKey: .title)
            try container.encode(chiefComplaint, forKey: .chiefComplaint)
            try container.encode(diagnosis, forKey: .diagnosis)
            try container.encode(severity, forKey: .severity)
            try container.encode(MedicalDateCoding.encodeISO8601(visitDate), forKey: .visitDate)
            try container.encode(status, forKey: .status)
            try container.encode(notes, forKey: .notes)
        }
    }

    struct UploadExaminationReport: Encodable, Sendable {
        let clientUID: UUID
        let memberClientUID: UUID
        let medicalCaseClientUID: UUID?
        let category: String
        let subcategory: String
        let reportName: String
        let checkType: String
        let conclusion: String
        let doctorAdvice: String
        let date: Date

        enum CodingKeys: String, CodingKey {
            case clientUID = "client_uid"
            case memberClientUID = "member_client_uid"
            case medicalCaseClientUID = "medical_case_client_uid"
            case category
            case subcategory
            case reportName = "report_name"
            case checkType = "check_type"
            case conclusion
            case doctorAdvice = "doctor_advice"
            case date
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(clientUID, forKey: .clientUID)
            try container.encode(memberClientUID, forKey: .memberClientUID)
            try container.encodeIfPresent(medicalCaseClientUID, forKey: .medicalCaseClientUID)
            try container.encode(category, forKey: .category)
            try container.encode(subcategory, forKey: .subcategory)
            try container.encode(reportName, forKey: .reportName)
            try container.encode(checkType, forKey: .checkType)
            try container.encode(conclusion, forKey: .conclusion)
            try container.encode(doctorAdvice, forKey: .doctorAdvice)
            try container.encode(MedicalDateCoding.encodeISO8601(date), forKey: .date)
        }
    }

    struct UploadMedicalReport: Encodable, Sendable {
        let clientUID: UUID
        let memberClientUID: UUID
        let medicalCaseClientUID: UUID?
        let reportType: String
        let title: String
        let hospital: String
        let doctor: String
        let content: String
        let date: Date

        enum CodingKeys: String, CodingKey {
            case clientUID = "client_uid"
            case memberClientUID = "member_client_uid"
            case medicalCaseClientUID = "medical_case_client_uid"
            case reportType = "report_type"
            case title
            case hospital
            case doctor
            case content
            case date
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(clientUID, forKey: .clientUID)
            try container.encode(memberClientUID, forKey: .memberClientUID)
            try container.encodeIfPresent(medicalCaseClientUID, forKey: .medicalCaseClientUID)
            try container.encode(reportType, forKey: .reportType)
            try container.encode(title, forKey: .title)
            try container.encode(hospital, forKey: .hospital)
            try container.encode(doctor, forKey: .doctor)
            try container.encode(content, forKey: .content)
            try container.encode(MedicalDateCoding.encodeISO8601(date), forKey: .date)
        }
    }

    struct UploadPrescription: Encodable, Sendable {
        let clientUID: UUID
        let memberClientUID: UUID
        let medicalCaseClientUID: UUID?
        let drugName: String
        let dosage: String
        let frequency: String
        let durationDays: Int
        let instructions: String
        let startDate: Date?
        let endDate: Date?
        let status: String

        enum CodingKeys: String, CodingKey {
            case clientUID = "client_uid"
            case memberClientUID = "member_client_uid"
            case medicalCaseClientUID = "medical_case_client_uid"
            case drugName = "drug_name"
            case dosage
            case frequency
            case durationDays = "duration_days"
            case instructions
            case startDate = "start_date"
            case endDate = "end_date"
            case status
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(clientUID, forKey: .clientUID)
            try container.encode(memberClientUID, forKey: .memberClientUID)
            try container.encodeIfPresent(medicalCaseClientUID, forKey: .medicalCaseClientUID)
            try container.encode(drugName, forKey: .drugName)
            try container.encode(dosage, forKey: .dosage)
            try container.encode(frequency, forKey: .frequency)
            try container.encode(durationDays, forKey: .durationDays)
            try container.encode(instructions, forKey: .instructions)
            if let startDate {
                try container.encode(MedicalDateCoding.encodeDateOnly(startDate), forKey: .startDate)
            } else {
                try container.encodeNil(forKey: .startDate)
            }
            if let endDate {
                try container.encode(MedicalDateCoding.encodeDateOnly(endDate), forKey: .endDate)
            } else {
                try container.encodeNil(forKey: .endDate)
            }
            try container.encode(status, forKey: .status)
        }
    }

    func fetchSnapshot(priority: CloudSyncPriority) async throws -> RemoteSnapshotPayload {
        let queuePriority: RequestQueuePriority
        switch priority {
        case .realtime: queuePriority = .veryHigh
        case .balanced: queuePriority = .normal
        case .background: queuePriority = .low
        }
        let operation = CacheableSparkNetworkOperation(
            name: "Medical.Sync.Bootstrap",
            apiName: "MedicalSyncAPI",
            request: SparkNetworkRequest(
                method: .get,
                path: "/api/v1/medical/sync/bootstrap/",
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: true,
                    serialKey: "medical.sync.bootstrap",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: queuePriority,
                    etagTTL: 120
                )
            )
        )
        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedData(
            RemoteSnapshotPayload.self,
            from: response,
            decoder: .sparkISO8601
        )
    }

    func uploadSnapshot(_ payload: UploadSnapshotPayload, priority: CloudSyncPriority) async throws {
        let queuePriority: RequestQueuePriority
        switch priority {
        case .realtime: queuePriority = .veryHigh
        case .balanced: queuePriority = .high
        case .background: queuePriority = .low
        }
        let operation = CacheableSparkNetworkOperation(
            name: "Medical.Sync.Upload",
            apiName: "MedicalSyncAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/medical/sync/upload/",
                body: .json(AnyEncodable(payload)),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "medical.sync.upload",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: queuePriority
                )
            )
        )
        let response = try await configuration.execute(operation)
        _ = try APIResponseDecoder.decodeWrappedData(JSONValue?.self, from: response, decoder: .sparkISO8601)
    }
}

private extension JSONDecoder {
    static let sparkISO8601: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(MedicalDateCoding.decodeFlexibleDate(from:))
        return decoder
    }()
}
