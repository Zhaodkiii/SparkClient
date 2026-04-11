import Foundation

// MARK: - 医疗 API 共享模型（SparkMedicalSyncAPI）
//
// 命名空间内为各医疗 REST 列表/详情接口共用的 **Remote*** 解码类型（与后端 snake_case JSON 对齐）。
// 网络请求由 `SparkMedicalQueryAPI` 等按资源路径发起；已不再提供全量快照 bootstrap/upload。

/// 医疗域远程 DTO 的命名空间（无实例，仅嵌套类型）。
enum SparkMedicalSyncAPI {

    // MARK: - Remote 实体（服务端 → 客户端解码）

    /// 家庭成员或健康档案成员；是多数医疗实体的外键 `member` 所指对象。
    struct RemoteMember: Codable, Sendable, Equatable {
        var id: Int
        var name: String
        /// 性别：通常与后端枚举字符串一致。
        var gender: String
        /// 与当前用户的关系（本人、父母等）。
        var relationship: String
        /// 出生日期；仅日期语义，解码由 `MedicalDateCoding` 处理。
        var birthDate: Date?
        var bloodType: String
        var allergies: [String]
        var chronicConditions: [String]
        var notes: String
        /// 头像 URL 字符串；可能为空串或完整 URL。
        var avatarUrl: String
        /// 是否为当前账号下的主档案。
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

    /// 医疗案件/一次就诊聚合；`symptoms`、`visits` 等子表通过 `medical_case` 关联。
    struct RemoteMedicalCase: Codable, Sendable, Equatable {
        var id: Int
        /// 所属 `RemoteMember.id`。
        var member: Int
        /// 记录类型（门诊/住院等），字符串编码。
        var recordType: String
        /// 业务状态整型，含义由后端与客户端共同约定。
        var status: Int
        var title: String
        var hospitalName: String
        /// 就诊时年龄，可选。
        var ageAtVisit: Int?
        var diagnosisSummary: String
        /// 扩展键值，便于后端向前兼容增加字段而不改表结构。
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

    /// 症状实体；同时冗余 `member` 与 `medicalCase` 便于按人/按案查询。
    struct RemoteSymptom: Codable, Sendable, Equatable {
        var id: Int
        var member: Int
        /// 关联的 `RemoteMedicalCase.id`。
        var medicalCase: Int
        var name: String
        /// 症状编码（如标准术语代码），可与 `name` 并存。
        var code: String
        /// 严重程度描述或分级字符串。
        var severity: String
        var startedAt: Date?
        /// 持续时间数值，与 `durationUnit` 搭配。
        var durationValue: Int?
        /// 时间单位（天、周等）。
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

    /// 就诊记录（到院一次就诊的元数据）。
    struct RemoteVisit: Codable, Sendable, Equatable {
        var id: Int
        var member: Int
        var medicalCase: Int
        var visitType: String
        var visitedAt: Date?
        var department: String
        var doctorName: String
        /// 院内就诊号/流水号。
        var visitNo: String
        /// 外部系统（如医院 HIS）中的主键或业务 ID，用于去重与溯源。
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

    /// 手术记录；`asaClass` 为 ASA 分级，`incisionLevel` 为切口等级等临床字段的字符串存储。
    struct RemoteSurgery: Codable, Sendable, Equatable {
        var id: Int
        var member: Int
        var medicalCase: Int
        var procedureName: String
        var procedureCode: String
        /// 手术部位。
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

    /// 随访：计划时间、完成时间、方式（电话/复诊）、结果与下一步动作。
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

    /// 检查报告头：可关联可选 `medicalRecord`（病历/案件维度）；`source`/`status` 为整型枚举，与 OCR 流水线状态对应。
    struct RemoteExaminationReport: Codable, Sendable, Equatable {
        var id: Int
        var member: Int
        /// 可选关联的医疗记录 ID；无则仅为成员维度下的孤立报告。
        var medicalRecord: Int?
        var category: String
        var subCategory: String
        var itemName: String
        var performedAt: Date?
        var reportedAt: Date?
        var organizationName: String
        var departmentName: String
        var doctorName: String
        /// 影像/检查所见。
        var findings: String?
        /// 诊断印象或结论。
        var impression: String?
        /// 数据来源（手工录入、OCR、导入等），整型与后端一致。
        var source: Int
        /// OCR 原始键值，如页码、区域文本等，结构由业务定义。
        var rawOCR: [String: String]?
        /// 解析/审核状态。
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

    /// 体检报告汇总：机构、报告号、体检日期与类型；细项指标通常在 `RemoteMedExamDetail` 中通过 `business_type`/`business_id` 关联。
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

    /// 检查/检验细项行：通过 `businessType` + `businessID` 多态关联到体检报告、检查报告等不同父业务。
    struct RemoteMedExamDetail: Codable, Sendable, Equatable {
        var id: Int
        /// 业务类型标识（如 health_exam、examination 等），与后端常量一致。
        var businessType: String
        /// 父业务主键。
        var businessID: Int
        var member: Int
        var category: String
        var subCategory: String
        var itemName: String
        var itemCode: String
        var resultValue: String
        var unit: String
        var referenceRange: String
        /// 高低箭头、阴阳性等标志字符串。
        var flag: String
        var resultAt: Date?
        /// 检查模态（CT、超声等），检验场景可为空或占位。
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

    /// 通用医疗报告（出院小结、病理等）；`medicalCase` 可选。
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

    /// 处方批次：一次开药可包含多条 `RemoteMedication`（`batch` 外键指向本表 `id`）。
    struct RemotePrescriptionBatch: Codable, Sendable, Equatable {
        var id: Int
        var member: Int
        var medicalCase: Int?
        var prescriberName: String
        var institutionName: String
        var prescribedAt: Date?
        var diagnosis: String
        var batchNo: String?
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

    /// 处方药品行：同时保留「展示用字符串」（如 `dosePerTime`、`frequencyText`）与「结构化字段」（`doseValue`、`timesPerPeriod`）便于解析与提醒。
    struct RemoteMedication: Codable, Sendable, Equatable {
        var id: Int
        var member: Int
        /// 所属 `RemotePrescriptionBatch.id`。
        var batch: Int
        var genericName: String
        var brandName: String
        var drugName: String
        var dosageForm: String
        var strength: String
        /// 给药途径（口服、静脉等）。
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
        /// 提醒时间列表，通常为 HH:mm 或 ISO 局部时间字符串，与产品约定一致。
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

    /// 用药记录：某一剂次应服时间、实际服用时间、状态与用户在当时的时区（跨区旅行时有意义）。
    struct RemoteMedicationTakenRecord: Codable, Sendable, Equatable {
        var id: Int
        var member: Int
        /// 关联 `RemoteMedication.id`。
        var medication: Int
        var scheduledAt: Date
        var takenAt: Date?
        var status: String
        /// 当天或疗程内的第几剂。
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

    /// 附件元数据（`ManagedFile`），与 ``/complete-data/`` 内嵌附件一致。
    /// 除 `id` 外字段均为可选，以匹配合成 `Decodable` 与后端缺省键。
    struct RemoteManagedFile: Codable, Sendable, Equatable {
        var id: Int
        var fileUuid: String?
        var originalName: String?
        var fileSize: Int?
        var mimeType: String?
        var fileMd5: String?
        var businessType: String?
        var businessId: String?
        var objectKey: String?
        var storageType: String?
        var createdAt: Date?
        /// 服务端构造的 OSS 直链或空串。
        var fileUrl: String?

        enum CodingKeys: String, CodingKey {
            case id
            case fileUuid = "file_uuid"
            case originalName = "original_name"
            case fileSize = "file_size"
            case mimeType = "mime_type"
            case fileMd5 = "file_md5"
            case businessType = "business_type"
            case businessId = "business_id"
            case objectKey = "object_key"
            case storageType = "storage_type"
            case createdAt = "created_at"
            case fileUrl = "file_url"
        }
    }

    /// 病例汇总：基本信息 + 症状/药品展示名 + 附件（无检验明细）。
    struct RemoteMedicalCaseSummary: Codable, Sendable, Equatable {
        var id: Int
        var member: Int
        var recordType: String?
        var status: Int?
        var title: String?
        var hospitalName: String?
        var ageAtVisit: Int?
        var diagnosisSummary: String?
        var extra: [String: String]?
        var createdAt: Date?
        var updatedAt: Date?
        var symptoms: [String]?
        var medications: [String]?
        var attachments: [RemoteManagedFile]?

        enum CodingKeys: String, CodingKey {
            case id, member, status, title, extra, symptoms, medications, attachments
            case recordType = "record_type"
            case hospitalName = "hospital_name"
            case ageAtVisit = "age_at_visit"
            case diagnosisSummary = "diagnosis_summary"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }
    }

    /// 体检报告 + 附件（首页不含明细行）。
    struct RemoteHealthExamReportWithAttachments: Codable, Sendable, Equatable {
        var id: Int
        var member: Int
        var institutionName: String?
        var reportNo: String?
        var examDate: Date?
        var examType: Int?
        var summary: String?
        var source: Int?
        var status: Int?
        var extra: [String: String]?
        var createdAt: Date?
        var updatedAt: Date?
        var attachments: [RemoteManagedFile]?

        enum CodingKeys: String, CodingKey {
            case id, member, summary, source, status, extra, attachments
            case institutionName = "institution_name"
            case reportNo = "report_no"
            case examDate = "exam_date"
            case examType = "exam_type"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }
    }

    /// 检查报告 + 附件（首页不含明细行）。
    struct RemoteExaminationReportWithAttachments: Codable, Sendable, Equatable {
        var id: Int
        var member: Int
        var medicalRecord: Int?
        var category: String?
        var subCategory: String?
        var itemName: String?
        var performedAt: Date?
        var reportedAt: Date?
        var organizationName: String?
        var departmentName: String?
        var doctorName: String?
        var findings: String?
        var impression: String?
        var source: Int?
        var status: Int?
        var extra: [String: String]?
        var createdAt: Date?
        var updatedAt: Date?
        var attachments: [RemoteManagedFile]?

        enum CodingKeys: String, CodingKey {
            case id, member, category, findings, impression, source, status, extra, attachments
            case medicalRecord = "medical_record"
            case subCategory = "sub_category"
            case itemName = "item_name"
            case performedAt = "performed_at"
            case reportedAt = "reported_at"
            case organizationName = "organization_name"
            case departmentName = "department_name"
            case doctorName = "doctor_name"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }
    }

    /// 处方批次 + 嵌套药品行 + 附件。
    struct RemotePrescriptionBatchComplete: Codable, Sendable, Equatable {
        var id: Int
        var member: Int
        var medicalCase: Int?
        var prescriberName: String?
        var institutionName: String?
        var prescribedAt: Date?
        var diagnosis: String?
        var batchNo: String?
        var status: String?
        var auditorName: String?
        var auditedAt: Date?
        var extra: [String: String]?
        var createdAt: Date?
        var updatedAt: Date?
        var medications: [RemoteMedication]?
        var attachments: [RemoteManagedFile]?

        enum CodingKeys: String, CodingKey {
            case id, member, diagnosis, status, extra, medications, attachments
            case medicalCase = "medical_case"
            case prescriberName = "prescriber_name"
            case institutionName = "institution_name"
            case prescribedAt = "prescribed_at"
            case batchNo = "batch_no"
            case auditorName = "auditor_name"
            case auditedAt = "audited_at"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }
    }

    /// 单接口成员医疗数据汇总（``GET …/complete-data/``）。
    struct RemoteMemberCompleteData: Codable, Sendable, Equatable {
        var memberId: Int
        var member: RemoteMember
        var medicalCases: [RemoteMedicalCaseSummary]?
        var healthExamReports: [RemoteHealthExamReportWithAttachments]?
        var examinationReports: [RemoteExaminationReportWithAttachments]?
        var prescriptionBatches: [RemotePrescriptionBatchComplete]?
        var standaloneMedications: [RemoteMedication]?

        enum CodingKeys: String, CodingKey {
            case memberId = "member_id"
            case member
            case medicalCases = "medical_cases"
            case healthExamReports = "health_exam_reports"
            case examinationReports = "examination_reports"
            case prescriptionBatches = "prescription_batches"
            case standaloneMedications = "standalone_medications"
        }
    }
}
