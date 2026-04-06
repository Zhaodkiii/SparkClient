import Foundation

struct SparkMedicalSyncAPI {
    let configuration: SparkBackendConfiguration

    init(configuration: SparkBackendConfiguration) {
        self.configuration = configuration
    }

    struct RemoteSnapshotPayload: Codable, Sendable, Equatable {
        var members: [RemoteMember]
        var medicalCases: [RemoteMedicalCase]
        var symptoms: [RemoteSymptom]
        var visits: [RemoteVisit]
        var surgeries: [RemoteSurgery]
        var followUps: [RemoteFollowUp]
        var healthExamReports: [RemoteHealthExamReport]
        var examinationReports: [RemoteExaminationReport]
        var medExamDetails: [RemoteMedExamDetail]
        var medicalReports: [RemoteMedicalReport]
        var prescriptionBatches: [RemotePrescriptionBatch]
        var medications: [RemoteMedication]
        var medicationTakenRecords: [RemoteMedicationTakenRecord]
        var healthMetrics: [RemoteHealthMetric]

        enum CodingKeys: String, CodingKey {
            case members
            case medicalCases = "medical_cases"
            case symptoms
            case visits
            case surgeries
            case followUps = "follow_ups"
            case healthExamReports = "health_exam_reports"
            case examinationReports = "examination_reports"
            case medExamDetails = "med_exam_details"
            case medicalReports = "medical_reports"
            case prescriptionBatches = "prescription_batches"
            case medications
            case medicationTakenRecords = "medication_taken_records"
            case healthMetrics = "health_metrics"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.members = (try? container.decode([RemoteMember].self, forKey: .members)) ?? []
            self.medicalCases = (try? container.decode([RemoteMedicalCase].self, forKey: .medicalCases)) ?? []
            self.symptoms = (try? container.decode([RemoteSymptom].self, forKey: .symptoms)) ?? []
            self.visits = (try? container.decode([RemoteVisit].self, forKey: .visits)) ?? []
            self.surgeries = (try? container.decode([RemoteSurgery].self, forKey: .surgeries)) ?? []
            self.followUps = (try? container.decode([RemoteFollowUp].self, forKey: .followUps)) ?? []
            self.healthExamReports = (try? container.decode([RemoteHealthExamReport].self, forKey: .healthExamReports)) ?? []
            self.examinationReports = (try? container.decode([RemoteExaminationReport].self, forKey: .examinationReports)) ?? []
            self.medExamDetails = (try? container.decode([RemoteMedExamDetail].self, forKey: .medExamDetails)) ?? []
            self.medicalReports = (try? container.decode([RemoteMedicalReport].self, forKey: .medicalReports)) ?? []
            self.prescriptionBatches = (try? container.decode([RemotePrescriptionBatch].self, forKey: .prescriptionBatches)) ?? []
            self.medications = (try? container.decode([RemoteMedication].self, forKey: .medications)) ?? []
            self.medicationTakenRecords = (try? container.decode([RemoteMedicationTakenRecord].self, forKey: .medicationTakenRecords)) ?? []
            self.healthMetrics = (try? container.decode([RemoteHealthMetric].self, forKey: .healthMetrics)) ?? []
        }
    }

    struct RemoteHealthMetric: Codable, Sendable, Equatable {
        var id: Int
        var profileClientUID: UUID
        var metricType: String
        var value: Double
        var unit: String
        var recordedAt: Date
        var note: String?
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id
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
        var name: String
        var gender: String
        var relationship: String
        var birthDate: Date?
        var bloodType: String
        var allergies: [String]
        var chronicConditions: [String]
        var notes: String
        var avatarUrl: String
        var isPrimary: Bool
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case gender
            case relationship
            case birthDate = "birth_date"
            case bloodType = "blood_type"
            case allergies
            case chronicConditions = "chronic_conditions"
            case notes
            case avatarUrl = "avatar_url"
            case isPrimary = "is_primary"
            case updatedAt = "updated_at"
        }

    }

    struct RemoteMedicalCase: Codable, Sendable, Equatable {
        var id: Int
        var member: Int
        var recordType: String
        var status: Int
        var title: String
        var hospitalName: String
        var ageAtVisit: Int?
        var diagnosisSummary: String
        var extra: [String: String]?
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case member
            case recordType = "record_type"
            case status
            case title
            case hospitalName = "hospital_name"
            case ageAtVisit = "age_at_visit"
            case diagnosisSummary = "diagnosis_summary"
            case extra
            case updatedAt = "updated_at"
        }
    }

    struct RemoteSymptom: Codable, Sendable, Equatable {
        var id: Int
        var member: Int
        var medicalCase: Int
        var name: String
        var code: String
        var severity: String
        var startedAt: Date?
        var durationValue: Int?
        var durationUnit: String
        var bodyPart: String
        var notes: String
        var extra: [String: String]?
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id, member, name, code, severity, notes, extra
            case medicalCase = "medical_case"
            case startedAt = "started_at"
            case durationValue = "duration_value"
            case durationUnit = "duration_unit"
            case bodyPart = "body_part"
            case updatedAt = "updated_at"
        }
    }

    struct RemoteVisit: Codable, Sendable, Equatable {
        var id: Int
        var member: Int
        var medicalCase: Int
        var visitType: String
        var visitedAt: Date?
        var department: String
        var doctorName: String
        var visitNo: String
        var sourceSystemID: String
        var notes: String
        var extra: [String: String]?
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id, member, department, notes, extra
            case medicalCase = "medical_case"
            case visitType = "visit_type"
            case visitedAt = "visited_at"
            case doctorName = "doctor_name"
            case visitNo = "visit_no"
            case sourceSystemID = "source_system_id"
            case updatedAt = "updated_at"
        }
    }

    struct RemoteSurgery: Codable, Sendable, Equatable {
        var id: Int
        var member: Int
        var medicalCase: Int
        var procedureName: String
        var procedureCode: String
        var site: String
        var performedAt: Date?
        var surgeon: String
        var anesthesiaType: String
        var incisionLevel: String
        var asaClass: String
        var sourceSystemID: String
        var notes: String
        var extra: [String: String]?
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id, member, site, surgeon, notes, extra
            case medicalCase = "medical_case"
            case procedureName = "procedure_name"
            case procedureCode = "procedure_code"
            case performedAt = "performed_at"
            case anesthesiaType = "anesthesia_type"
            case incisionLevel = "incision_level"
            case asaClass = "asa_class"
            case sourceSystemID = "source_system_id"
            case updatedAt = "updated_at"
        }
    }

    struct RemoteFollowUp: Codable, Sendable, Equatable {
        var id: Int
        var member: Int
        var medicalCase: Int
        var plannedAt: Date?
        var completedAt: Date?
        var status: String
        var method: String
        var outcome: String
        var nextAction: String
        var extra: [String: String]?
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id, member, status, method, outcome, extra
            case medicalCase = "medical_case"
            case plannedAt = "planned_at"
            case completedAt = "completed_at"
            case nextAction = "next_action"
            case updatedAt = "updated_at"
        }
    }

    struct RemoteExaminationReport: Codable, Sendable, Equatable {
        var id: Int
        var member: Int
        var medicalRecord: Int?
        var category: String
        var subCategory: String
        var itemName: String
        var performedAt: Date?
        var reportedAt: Date?
        var organizationName: String
        var departmentName: String
        var doctorName: String
        var findings: String?
        var impression: String?
        var source: Int
        var rawOCR: [String: String]?
        var status: Int
        var extra: [String: String]?
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case member
            case medicalRecord = "medical_record"
            case category
            case subCategory = "sub_category"
            case itemName = "item_name"
            case performedAt = "performed_at"
            case reportedAt = "reported_at"
            case organizationName = "organization_name"
            case departmentName = "department_name"
            case doctorName = "doctor_name"
            case findings
            case impression
            case source
            case rawOCR = "raw_ocr"
            case status
            case extra
            case updatedAt = "updated_at"
        }
    }

    struct RemoteHealthExamReport: Codable, Sendable, Equatable {
        var id: Int
        var member: Int
        var institutionName: String
        var reportNo: String
        var examDate: Date?
        var examType: Int
        var summary: String?
        var source: Int
        var rawOCR: [String: String]?
        var status: Int
        var extra: [String: String]?
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case member
            case institutionName = "institution_name"
            case reportNo = "report_no"
            case examDate = "exam_date"
            case examType = "exam_type"
            case summary
            case source
            case rawOCR = "raw_ocr"
            case status
            case extra
            case updatedAt = "updated_at"
        }
    }

    struct RemoteMedExamDetail: Codable, Sendable, Equatable {
        var id: Int
        var businessType: String
        var businessID: Int
        var member: Int
        var category: String
        var subCategory: String
        var itemName: String
        var itemCode: String
        var resultValue: String
        var unit: String
        var referenceRange: String
        var flag: String
        var resultAt: Date?
        var modality: String
        var bodyPart: String
        var diagnosis: String?
        var extra: [String: String]?
        var sortOrder: Int
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case businessType = "business_type"
            case businessID = "business_id"
            case member
            case category
            case subCategory = "sub_category"
            case itemName = "item_name"
            case itemCode = "item_code"
            case resultValue = "result_value"
            case unit
            case referenceRange = "reference_range"
            case flag
            case resultAt = "result_at"
            case modality
            case bodyPart = "body_part"
            case diagnosis
            case extra
            case sortOrder = "sort_order"
            case updatedAt = "updated_at"
        }
    }

    struct RemoteMedicalReport: Codable, Sendable, Equatable {
        var id: Int
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

    struct RemotePrescriptionBatch: Codable, Sendable, Equatable {
        var id: Int
        var member: Int
        var medicalCase: Int?
        var prescriberName: String
        var institutionName: String
        var prescribedAt: Date?
        var diagnosis: String
        var batchNo: String
        var status: String
        var auditorName: String
        var auditedAt: Date?
        var extra: [String: String]?
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case member
            case medicalCase = "medical_case"
            case prescriberName = "prescriber_name"
            case institutionName = "institution_name"
            case prescribedAt = "prescribed_at"
            case diagnosis
            case batchNo = "batch_no"
            case status
            case auditorName = "auditor_name"
            case auditedAt = "audited_at"
            case extra
            case updatedAt = "updated_at"
        }
    }

    struct RemoteMedication: Codable, Sendable, Equatable {
        var id: Int
        var member: Int
        var batch: Int
        var genericName: String
        var brandName: String
        var drugName: String
        var dosageForm: String
        var strength: String
        var route: String
        var dosePerTime: String
        var doseValue: Double?
        var doseUnit: String
        var frequencyCode: String
        var period: String
        var timesPerPeriod: Int?
        var frequencyText: String
        var durationDays: Int?
        var instructions: String
        var reminderEnabled: Bool
        var reminderTimes: [String]
        var sortOrder: Int
        var extra: [String: String]?
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id, member, batch, strength, route, period, instructions, extra
            case genericName = "generic_name"
            case brandName = "brand_name"
            case drugName = "drug_name"
            case dosageForm = "dosage_form"
            case dosePerTime = "dose_per_time"
            case doseValue = "dose_value"
            case doseUnit = "dose_unit"
            case frequencyCode = "frequency_code"
            case timesPerPeriod = "times_per_period"
            case frequencyText = "frequency_text"
            case durationDays = "duration_days"
            case reminderEnabled = "reminder_enabled"
            case reminderTimes = "reminder_times"
            case sortOrder = "sort_order"
            case updatedAt = "updated_at"
        }
    }

    struct RemoteMedicationTakenRecord: Codable, Sendable, Equatable {
        var id: Int
        var member: Int
        var medication: Int
        var scheduledAt: Date
        var takenAt: Date?
        var status: String
        var doseSequence: Int
        var actualDose: String
        var timezone: String
        var notes: String
        var extra: [String: String]?
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id, member, medication, status, timezone, notes, extra
            case scheduledAt = "scheduled_at"
            case takenAt = "taken_at"
            case doseSequence = "dose_sequence"
            case actualDose = "actual_dose"
            case updatedAt = "updated_at"
        }
    }

    struct UploadSnapshotPayload: Encodable, Sendable {
        let members: [UploadMember]
        let medicalCases: [UploadMedicalCase]
        let symptoms: [UploadSymptom]
        let visits: [UploadVisit]
        let surgeries: [UploadSurgery]
        let followUps: [UploadFollowUp]
        let healthExamReports: [UploadHealthExamReport]
        let examinationReports: [UploadExaminationReport]
        let medExamDetails: [UploadMedExamDetail]
        let medicalReports: [UploadMedicalReport]
        let prescriptionBatches: [UploadPrescriptionBatch]
        let medications: [UploadMedication]
        let medicationTakenRecords: [UploadMedicationTakenRecord]
        let healthMetrics: [UploadHealthMetric]

        enum CodingKeys: String, CodingKey {
            case members
            case medicalCases = "medical_cases"
            case symptoms
            case visits
            case surgeries
            case followUps = "follow_ups"
            case healthExamReports = "health_exam_reports"
            case examinationReports = "examination_reports"
            case medExamDetails = "med_exam_details"
            case medicalReports = "medical_reports"
            case prescriptionBatches = "prescription_batches"
            case medications
            case medicationTakenRecords = "medication_taken_records"
            case healthMetrics = "health_metrics"
        }
    }

    struct UploadHealthMetric: Encodable, Sendable {
        let id: Int?
        let profileClientUID: UUID
        let metricType: String
        let value: Double
        let unit: String
        let recordedAt: Date
        let note: String?
        let updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id
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
            try container.encodeIfPresent(id, forKey: .id)
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
        let id: Int?
        let name: String
        let gender: String
        let relationship: String
        let birthDate: Date?
        let bloodType: String
        let allergies: [String]
        let chronicConditions: [String]
        let notes: String
        let avatarUrl: String
        let isPrimary: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case gender
            case relationship
            case birthDate = "birth_date"
            case bloodType = "blood_type"
            case allergies
            case chronicConditions = "chronic_conditions"
            case notes
            case avatarUrl = "avatar_url"
            case isPrimary = "is_primary"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(gender, forKey: .gender)
            try container.encode(relationship, forKey: .relationship)
            if let birthDate {
                try container.encode(MedicalDateCoding.encodeDateOnly(birthDate), forKey: .birthDate)
            } else {
                try container.encodeNil(forKey: .birthDate)
            }
            try container.encode(bloodType, forKey: .bloodType)
            try container.encode(allergies, forKey: .allergies)
            try container.encode(chronicConditions, forKey: .chronicConditions)
            try container.encode(notes, forKey: .notes)
            try container.encode(avatarUrl, forKey: .avatarUrl)
            try container.encode(isPrimary, forKey: .isPrimary)
        }
    }

    struct UploadMedicalCase: Encodable, Sendable {
        let id: Int
        let member: Int
        let recordType: String
        let status: Int
        let title: String
        let hospitalName: String
        let ageAtVisit: Int?
        let diagnosisSummary: String
        let extra: [String: String]

        enum CodingKeys: String, CodingKey {
            case id
            case member
            case recordType = "record_type"
            case status
            case title
            case hospitalName = "hospital_name"
            case ageAtVisit = "age_at_visit"
            case diagnosisSummary = "diagnosis_summary"
            case extra
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(member, forKey: .member)
            try container.encode(recordType, forKey: .recordType)
            try container.encode(status, forKey: .status)
            try container.encode(title, forKey: .title)
            try container.encode(hospitalName, forKey: .hospitalName)
            try container.encodeIfPresent(ageAtVisit, forKey: .ageAtVisit)
            try container.encode(diagnosisSummary, forKey: .diagnosisSummary)
            try container.encode(extra, forKey: .extra)
        }
    }

    struct UploadSymptom: Encodable, Sendable {
        let id: Int
        let member: Int
        let medicalCase: Int
        let name: String
        let code: String
        let severity: String
        let startedAt: Date?
        let durationValue: Int?
        let durationUnit: String
        let bodyPart: String
        let notes: String
        let extra: [String: String]

        enum CodingKeys: String, CodingKey {
            case id, member, name, code, severity, notes, extra
            case medicalCase = "medical_case"
            case startedAt = "started_at"
            case durationValue = "duration_value"
            case durationUnit = "duration_unit"
            case bodyPart = "body_part"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(member, forKey: .member)
            try container.encode(medicalCase, forKey: .medicalCase)
            try container.encode(name, forKey: .name)
            try container.encode(code, forKey: .code)
            try container.encode(severity, forKey: .severity)
            try container.encodeIfPresent(startedAt.map(MedicalDateCoding.encodeISO8601), forKey: .startedAt)
            try container.encodeIfPresent(durationValue, forKey: .durationValue)
            try container.encode(durationUnit, forKey: .durationUnit)
            try container.encode(bodyPart, forKey: .bodyPart)
            try container.encode(notes, forKey: .notes)
            try container.encode(extra, forKey: .extra)
        }
    }

    struct UploadVisit: Encodable, Sendable {
        let id: Int
        let member: Int
        let medicalCase: Int
        let visitType: String
        let visitedAt: Date?
        let department: String
        let doctorName: String
        let visitNo: String
        let sourceSystemID: String
        let notes: String
        let extra: [String: String]

        enum CodingKeys: String, CodingKey {
            case id, member, department, notes, extra
            case medicalCase = "medical_case"
            case visitType = "visit_type"
            case visitedAt = "visited_at"
            case doctorName = "doctor_name"
            case visitNo = "visit_no"
            case sourceSystemID = "source_system_id"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(member, forKey: .member)
            try container.encode(medicalCase, forKey: .medicalCase)
            try container.encode(visitType, forKey: .visitType)
            try container.encodeIfPresent(visitedAt.map(MedicalDateCoding.encodeISO8601), forKey: .visitedAt)
            try container.encode(department, forKey: .department)
            try container.encode(doctorName, forKey: .doctorName)
            try container.encode(visitNo, forKey: .visitNo)
            try container.encode(sourceSystemID, forKey: .sourceSystemID)
            try container.encode(notes, forKey: .notes)
            try container.encode(extra, forKey: .extra)
        }
    }

    struct UploadSurgery: Encodable, Sendable {
        let id: Int
        let member: Int
        let medicalCase: Int
        let procedureName: String
        let procedureCode: String
        let site: String
        let performedAt: Date?
        let surgeon: String
        let anesthesiaType: String
        let incisionLevel: String
        let asaClass: String
        let sourceSystemID: String
        let notes: String
        let extra: [String: String]

        enum CodingKeys: String, CodingKey {
            case id, member, site, surgeon, notes, extra
            case medicalCase = "medical_case"
            case procedureName = "procedure_name"
            case procedureCode = "procedure_code"
            case performedAt = "performed_at"
            case anesthesiaType = "anesthesia_type"
            case incisionLevel = "incision_level"
            case asaClass = "asa_class"
            case sourceSystemID = "source_system_id"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(member, forKey: .member)
            try container.encode(medicalCase, forKey: .medicalCase)
            try container.encode(procedureName, forKey: .procedureName)
            try container.encode(procedureCode, forKey: .procedureCode)
            try container.encode(site, forKey: .site)
            try container.encodeIfPresent(performedAt.map(MedicalDateCoding.encodeISO8601), forKey: .performedAt)
            try container.encode(surgeon, forKey: .surgeon)
            try container.encode(anesthesiaType, forKey: .anesthesiaType)
            try container.encode(incisionLevel, forKey: .incisionLevel)
            try container.encode(asaClass, forKey: .asaClass)
            try container.encode(sourceSystemID, forKey: .sourceSystemID)
            try container.encode(notes, forKey: .notes)
            try container.encode(extra, forKey: .extra)
        }
    }

    struct UploadFollowUp: Encodable, Sendable {
        let id: Int
        let member: Int
        let medicalCase: Int
        let plannedAt: Date?
        let completedAt: Date?
        let status: String
        let method: String
        let outcome: String
        let nextAction: String
        let extra: [String: String]

        enum CodingKeys: String, CodingKey {
            case id, member, status, method, outcome, extra
            case medicalCase = "medical_case"
            case plannedAt = "planned_at"
            case completedAt = "completed_at"
            case nextAction = "next_action"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(member, forKey: .member)
            try container.encode(medicalCase, forKey: .medicalCase)
            try container.encodeIfPresent(plannedAt.map(MedicalDateCoding.encodeISO8601), forKey: .plannedAt)
            try container.encodeIfPresent(completedAt.map(MedicalDateCoding.encodeISO8601), forKey: .completedAt)
            try container.encode(status, forKey: .status)
            try container.encode(method, forKey: .method)
            try container.encode(outcome, forKey: .outcome)
            try container.encode(nextAction, forKey: .nextAction)
            try container.encode(extra, forKey: .extra)
        }
    }

    struct UploadExaminationReport: Encodable, Sendable {
        let id: Int
        let member: Int
        let medicalRecord: Int?
        let category: String
        let subCategory: String
        let itemName: String
        let performedAt: Date?
        let reportedAt: Date?
        let organizationName: String
        let departmentName: String
        let doctorName: String
        let findings: String?
        let impression: String?
        let source: Int
        let rawOCR: [String: String]?
        let status: Int
        let extra: [String: String]?

        enum CodingKeys: String, CodingKey {
            case id
            case member
            case medicalRecord = "medical_record"
            case category
            case subCategory = "sub_category"
            case itemName = "item_name"
            case performedAt = "performed_at"
            case reportedAt = "reported_at"
            case organizationName = "organization_name"
            case departmentName = "department_name"
            case doctorName = "doctor_name"
            case findings
            case impression
            case source
            case rawOCR = "raw_ocr"
            case status
            case extra
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(member, forKey: .member)
            try container.encodeIfPresent(medicalRecord, forKey: .medicalRecord)
            try container.encode(category, forKey: .category)
            try container.encode(subCategory, forKey: .subCategory)
            try container.encode(itemName, forKey: .itemName)
            try container.encodeIfPresent(performedAt.map(MedicalDateCoding.encodeISO8601), forKey: .performedAt)
            try container.encodeIfPresent(reportedAt.map(MedicalDateCoding.encodeISO8601), forKey: .reportedAt)
            try container.encode(organizationName, forKey: .organizationName)
            try container.encode(departmentName, forKey: .departmentName)
            try container.encode(doctorName, forKey: .doctorName)
            try container.encodeIfPresent(findings, forKey: .findings)
            try container.encodeIfPresent(impression, forKey: .impression)
            try container.encode(source, forKey: .source)
            try container.encodeIfPresent(rawOCR, forKey: .rawOCR)
            try container.encode(status, forKey: .status)
            try container.encodeIfPresent(extra, forKey: .extra)
        }
    }

    struct UploadHealthExamReport: Encodable, Sendable {
        let id: Int
        let member: Int
        let institutionName: String
        let reportNo: String
        let examDate: Date?
        let examType: Int
        let summary: String?
        let source: Int
        let rawOCR: [String: String]?
        let status: Int
        let extra: [String: String]?

        enum CodingKeys: String, CodingKey {
            case id
            case member
            case institutionName = "institution_name"
            case reportNo = "report_no"
            case examDate = "exam_date"
            case examType = "exam_type"
            case summary
            case source
            case rawOCR = "raw_ocr"
            case status
            case extra
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(member, forKey: .member)
            try container.encode(institutionName, forKey: .institutionName)
            try container.encode(reportNo, forKey: .reportNo)
            if let examDate {
                try container.encode(MedicalDateCoding.encodeDateOnly(examDate), forKey: .examDate)
            } else {
                try container.encodeNil(forKey: .examDate)
            }
            try container.encode(examType, forKey: .examType)
            try container.encodeIfPresent(summary, forKey: .summary)
            try container.encode(source, forKey: .source)
            try container.encodeIfPresent(rawOCR, forKey: .rawOCR)
            try container.encode(status, forKey: .status)
            try container.encodeIfPresent(extra, forKey: .extra)
        }
    }

    struct UploadMedExamDetail: Encodable, Sendable {
        let id: Int
        let businessType: String
        let businessID: Int
        let member: Int
        let category: String
        let subCategory: String
        let itemName: String
        let itemCode: String
        let resultValue: String
        let unit: String
        let referenceRange: String
        let flag: String
        let resultAt: Date?
        let modality: String
        let bodyPart: String
        let diagnosis: String?
        let extra: [String: String]?
        let sortOrder: Int

        enum CodingKeys: String, CodingKey {
            case id
            case businessType = "business_type"
            case businessID = "business_id"
            case member
            case category
            case subCategory = "sub_category"
            case itemName = "item_name"
            case itemCode = "item_code"
            case resultValue = "result_value"
            case unit
            case referenceRange = "reference_range"
            case flag
            case resultAt = "result_at"
            case modality
            case bodyPart = "body_part"
            case diagnosis
            case extra
            case sortOrder = "sort_order"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(businessType, forKey: .businessType)
            try container.encode(businessID, forKey: .businessID)
            try container.encode(member, forKey: .member)
            try container.encode(category, forKey: .category)
            try container.encode(subCategory, forKey: .subCategory)
            try container.encode(itemName, forKey: .itemName)
            try container.encode(itemCode, forKey: .itemCode)
            try container.encode(resultValue, forKey: .resultValue)
            try container.encode(unit, forKey: .unit)
            try container.encode(referenceRange, forKey: .referenceRange)
            try container.encode(flag, forKey: .flag)
            try container.encodeIfPresent(resultAt.map(MedicalDateCoding.encodeISO8601), forKey: .resultAt)
            try container.encode(modality, forKey: .modality)
            try container.encode(bodyPart, forKey: .bodyPart)
            try container.encodeIfPresent(diagnosis, forKey: .diagnosis)
            try container.encodeIfPresent(extra, forKey: .extra)
            try container.encode(sortOrder, forKey: .sortOrder)
        }
    }

    struct UploadMedicalReport: Encodable, Sendable {
        let id: Int
        let member: Int
        let medicalCase: Int?
        let reportType: String
        let title: String
        let hospital: String
        let doctor: String
        let content: String
        let date: Date

        enum CodingKeys: String, CodingKey {
            case id
            case member
            case medicalCase = "medical_case"
            case reportType = "report_type"
            case title
            case hospital
            case doctor
            case content
            case date
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(member, forKey: .member)
            try container.encodeIfPresent(medicalCase, forKey: .medicalCase)
            try container.encode(reportType, forKey: .reportType)
            try container.encode(title, forKey: .title)
            try container.encode(hospital, forKey: .hospital)
            try container.encode(doctor, forKey: .doctor)
            try container.encode(content, forKey: .content)
            try container.encode(MedicalDateCoding.encodeISO8601(date), forKey: .date)
        }
    }

    struct UploadPrescriptionBatch: Encodable, Sendable {
        let id: Int
        let member: Int
        let medicalCase: Int?
        let prescriberName: String
        let institutionName: String
        let prescribedAt: Date?
        let diagnosis: String
        let batchNo: String
        let status: String
        let auditorName: String
        let auditedAt: Date?
        let extra: [String: String]

        enum CodingKeys: String, CodingKey {
            case id
            case member
            case medicalCase = "medical_case"
            case prescriberName = "prescriber_name"
            case institutionName = "institution_name"
            case prescribedAt = "prescribed_at"
            case diagnosis
            case batchNo = "batch_no"
            case status
            case auditorName = "auditor_name"
            case auditedAt = "audited_at"
            case extra
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(member, forKey: .member)
            try container.encodeIfPresent(medicalCase, forKey: .medicalCase)
            try container.encode(prescriberName, forKey: .prescriberName)
            try container.encode(institutionName, forKey: .institutionName)
            try container.encodeIfPresent(prescribedAt.map(MedicalDateCoding.encodeISO8601), forKey: .prescribedAt)
            try container.encode(diagnosis, forKey: .diagnosis)
            try container.encode(batchNo, forKey: .batchNo)
            try container.encode(status, forKey: .status)
            try container.encode(auditorName, forKey: .auditorName)
            try container.encodeIfPresent(auditedAt.map(MedicalDateCoding.encodeISO8601), forKey: .auditedAt)
            try container.encode(extra, forKey: .extra)
        }
    }

    struct UploadMedication: Encodable, Sendable {
        let id: Int
        let member: Int
        let batch: Int
        let genericName: String
        let brandName: String
        let drugName: String
        let dosageForm: String
        let strength: String
        let route: String
        let dosePerTime: String
        let doseValue: Double?
        let doseUnit: String
        let frequencyCode: String
        let period: String
        let timesPerPeriod: Int?
        let frequencyText: String
        let durationDays: Int?
        let instructions: String
        let reminderEnabled: Bool
        let reminderTimes: [String]
        let sortOrder: Int
        let extra: [String: String]

        enum CodingKeys: String, CodingKey {
            case id, member, batch, strength, route, period, instructions, extra
            case genericName = "generic_name"
            case brandName = "brand_name"
            case drugName = "drug_name"
            case dosageForm = "dosage_form"
            case dosePerTime = "dose_per_time"
            case doseValue = "dose_value"
            case doseUnit = "dose_unit"
            case frequencyCode = "frequency_code"
            case timesPerPeriod = "times_per_period"
            case frequencyText = "frequency_text"
            case durationDays = "duration_days"
            case reminderEnabled = "reminder_enabled"
            case reminderTimes = "reminder_times"
            case sortOrder = "sort_order"
        }
    }

    struct UploadMedicationTakenRecord: Encodable, Sendable {
        let id: Int
        let member: Int
        let medication: Int
        let scheduledAt: Date
        let takenAt: Date?
        let status: String
        let doseSequence: Int
        let actualDose: String
        let timezone: String
        let notes: String
        let extra: [String: String]

        enum CodingKeys: String, CodingKey {
            case id, member, medication, status, timezone, notes, extra
            case scheduledAt = "scheduled_at"
            case takenAt = "taken_at"
            case doseSequence = "dose_sequence"
            case actualDose = "actual_dose"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(member, forKey: .member)
            try container.encode(medication, forKey: .medication)
            try container.encode(MedicalDateCoding.encodeISO8601(scheduledAt), forKey: .scheduledAt)
            try container.encodeIfPresent(takenAt.map(MedicalDateCoding.encodeISO8601), forKey: .takenAt)
            try container.encode(status, forKey: .status)
            try container.encode(doseSequence, forKey: .doseSequence)
            try container.encode(actualDose, forKey: .actualDose)
            try container.encode(timezone, forKey: .timezone)
            try container.encode(notes, forKey: .notes)
            try container.encode(extra, forKey: .extra)
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
