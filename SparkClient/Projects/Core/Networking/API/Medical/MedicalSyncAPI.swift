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
        var bindingId: Int?
        var name: String
        /// 性别：通常与后端枚举字符串一致。
        var gender: String
        /// 与当前用户的关系（本人、父母等）；`complete-data` 等旧路径可能缺失，解码时回退为 `self`。
        var relationship: String?
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
        var bindingRole: String?
        var sharedUserCount: Int?
        var canShare: Bool?
        var canEdit: Bool?
        var canDelete: Bool?
        var canUnbind: Bool?
        var canManageBindings: Bool?
        var updatedAt: Date

        var bindingInfo: MemberBindingInfo? {
            guard let bindingId else { return nil }
            return MemberBindingInfo(
                bindingID: bindingId,
                role: bindingRole ?? "owner",
                sharedUserCount: sharedUserCount ?? 1,
                canShare: canShare ?? false,
                canEdit: canEdit ?? false,
                canDelete: canDelete ?? false,
                canUnbind: canUnbind ?? true,
                canManageBindings: canManageBindings ?? false
            )
        }
    }

    /// 成员医疗维护档案。
    struct RemoteMedicationFocusItem: Codable, Sendable, Equatable, Identifiable {
        var drugName: String
        var summary: String
        var status: String
        var reminderEnabled: Bool
        var sourcePlanId: Int

        var id: Int { sourcePlanId }
    }

    /// 成员医疗维护档案。
    struct RemoteMemberMedicalProfile: Codable, Sendable, Equatable, Identifiable {
        var id: Int
        var user: Int?
        var member: Int
        var chronicConditions: [String]
        var medicationFocus: [RemoteMedicationFocusItem]
        var examFocus: [String]
        var symptomFollowUpFocus: [String]
        var notes: String
        var extra: [String: String]?
        var createdAt: Date?
        var updatedAt: Date?
    }

    /// 成员模块维护状态。
    struct RemoteMemberModuleSetting: Codable, Sendable, Equatable, Identifiable {
        var id: Int
        var user: Int?
        var member: Int
        var moduleCode: String
        var isEnabled: Bool
        var isCompleted: Bool
        var displayOrder: Int
        var summaryText: String
        var detailData: [String: String]
        var completedAt: Date?
        var extra: [String: String]?
        var createdAt: Date?
        var updatedAt: Date?
    }

    /// 成员关键健康指标记录。
    struct RemoteMemberMedicalKeyIndicatorRecord: Codable, Sendable, Equatable, Identifiable {
        var id: Int
        var user: Int?
        var member: Int
        var source: String
        var scenario: String
        var recordedAt: Date?
        var qaSessionId: String
        var title: String
        var summary: String
        var extra: [String: String]?
        var detailRows: [RemoteMedExamDetail]?
        var createdAt: Date?
        var updatedAt: Date?
    }

    /// 医疗引导状态聚合。
    struct RemoteMedicalGuidanceState: Codable, Sendable, Equatable {
        var member: RemoteMember
        var medicalProfile: RemoteMemberMedicalProfile?
        var latestKeyIndicatorRecord: RemoteMemberMedicalKeyIndicatorRecord?
        var latestRiskAssessment: [String: String]?
        var latestExamPlan: [String: String]?
        var moduleSetting: RemoteMemberModuleSetting?
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
        /// 病情严重程度，可为空。
        var severity: String? = nil
        /// 业务展示状态，可为空；区别于后端整型流转状态 `status`。
        var caseStatus: String? = nil
        var diagnosisSummary: String
        /// 扩展键值，便于后端向前兼容增加字段而不改表结构。
        var extra: [String: String]?
        var updatedAt: Date

    }

    /// 症状实体；同时冗余 `member` 与 `medicalCase` 便于按人/按案查询。
    struct RemoteSymptom: Codable, Sendable, Equatable, Identifiable {
        var id: Int
        var member: Int
        /// 关联的 `RemoteMedicalCase.id`；成员独立症状可为空。
        var medicalCase: Int?
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

    }

    /// 症状增删改后返回：明细 + 重算后的成员医疗画像摘要。
    struct SymptomMutationResponse: Codable, Sendable, Equatable {
        var deleted: Bool?
        var symptom: RemoteSymptom?
        var memberProfile: RemoteMemberMedicalProfile?
        var summary: String?
    }

    /// 用药计划增删改后返回：明细 + 重算后的成员医疗画像摘要。
    struct MedicationMutationResponse: Codable, Sendable, Equatable {
        var deleted: Bool?
        var medicationPlan: RemoteMedicationPlan?
        var memberProfile: RemoteMemberMedicalProfile?
        var summary: String?
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
        var sourceSystemId: String
        var notes: String
        var extra: [String: String]?
        var updatedAt: Date

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
        var sourceSystemId: String
        var notes: String
        var extra: [String: String]?
        var updatedAt: Date

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
        var rawOcr: [String: String]?
        /// 解析/审核状态。
        var status: Int
        var extra: [String: String]?
        var updatedAt: Date

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
        var rawOcr: [String: String]?
        var status: Int
        var extra: [String: String]?
        var updatedAt: Date

    }

    /// 检查/检验细项行：通过 `businessType` + `businessId` 多态关联到体检报告、检查报告等不同父业务。
    struct RemoteMedExamDetail: Codable, Sendable, Equatable {
        var id: Int
        /// 业务类型标识（如 health_exam、examination 等），与后端常量一致。
        var businessType: String
        /// 父业务主键。
        var businessId: Int
        var member: Int
        var category: String
        var subCategory: String
        var itemName: String
        var itemCode: String
        var resultValue: String?
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

    }

    /// 通用医疗报告（出院小结、病理等）；`medicalCase` 可选。
    struct RemoteMedicalReport: Codable, Sendable, Equatable {
        var id: Int
        var member: Int
        var medicalCase: Int?
        var category: String
        var title: String
        var hospital: String
        var doctor: String
        var content: String
        var date: Date
        var updatedAt: Date

    }

    /// 药箱：用户/成员拥有的物理药品库存。
    struct RemoteMedicineBox: Codable, Sendable, Equatable {
        var id: Int
        var member: Int?
        var medicineName: String
        var medicineType: String?
        var brandName: String
        var dosageForm: String
        var strength: String
        var doseUnit: String = ""
        var totalQuantity: Double?
        var expireDate: Date?
        var notes: String
        var extra: [String: String]?
        var attachments: [RemoteManagedFile]?
        var updatedAt: Date

    }

    /// 处方：作为服药计划的可选来源，不再承载药品行。
    struct RemotePrescription: Codable, Sendable, Equatable {
        var id: Int
        var member: Int
        var medicalCase: Int?
        var prescriberName: String
        var institutionName: String
        var prescribedAt: Date?
        var diagnosis: String
        var prescriptionNo: String?
        var status: String
        var extra: [String: String]?
        var attachments: [RemoteManagedFile]?
        var updatedAt: Date

    }

    /// 服药计划：独立的用药规则，可选关联药箱与处方。
    struct RemoteMedicationPlan: Codable, Sendable, Equatable, Identifiable {
        var id: Int
        var member: Int
        var medicalCase: Int?
        var medicineBox: Int?
        var prescription: Int?
        var drugName: String
        var dosePerTime: String
        var doseValue: Double?
        var doseUnit: String
        var frequencyType: String
        var everyNDays: Int?
        var weeklyWeekdays: [Int]
        var frequencyText: String
        @CodableReminderTimesList var reminderTimes: [ReminderTime]
        var startDate: Date
        var endDate: Date?
        var instructions: String
        var reminderEnabled: Bool
        var status: String
        var extra: [String: String]?
        var attachments: [RemoteManagedFile]?
        var updatedAt: Date
    }

    /// 服药记录：计划剂次与实际打卡事实表。
    struct RemoteMedicationRecord: Codable, Sendable, Equatable {
        var id: Int
        var member: Int
        var plan: Int
        var scheduledAt: Date
        var takenAt: Date?
        var status: String
        var plannedDose: String
        var actualDose: String
        var doseSequence: Int
        var timezone: String
        var notes: String
        var extra: [String: String]?
        var updatedAt: Date

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
        var severity: String? = nil
        var caseStatus: String? = nil
        var diagnosisSummary: String?
        var extra: [String: String]?
        var createdAt: Date?
        var updatedAt: Date?
        var symptoms: [String]?
        var medications: [String]?
        var attachments: [RemoteManagedFile]?

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
        /// 首页 `/complete-data/` 默认不返回；列表页进入后按需懒加载。
        var medExamDetails: [RemoteMedExamDetail]?

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
        /// 首页 `/complete-data/` 默认不返回；列表页进入后按需懒加载。
        var medExamDetails: [RemoteMedExamDetail]?

    }

    struct RemoteMedicationSummary: Codable, Sendable, Equatable {
        var todayTotal: Int
        var todayTaken: Int
        var todaySkipped: Int
        var adherenceRate: Double
        var activePlanCount: Int
        var lowStockCount: Int
        var expiringSoonCount: Int

    }

    /// 单接口成员医疗数据汇总模型
    ///
    /// 对应接口：GET …/complete-data/
    /// 用途：一次性获取当前成员的全量医疗相关数据，包含病例、体检、检查、用药、随访、手术等所有模块
    struct RemoteMemberCompleteData: Codable, Sendable, Equatable {
        /// 成员唯一ID
        var memberId: Int
        
        /// 成员基础信息
        var member: RemoteMember
        
        /// 病例摘要列表
        var medicalCases: [RemoteMedicalCaseSummary]?
        
        /// 体检报告列表（含附件）
        var healthExamReports: [RemoteHealthExamReportWithAttachments]?
        
        /// 检查检验报告列表（含附件）
        var examinationReports: [RemoteExaminationReportWithAttachments]?
        
        /// 药盒列表
        var medicineBoxes: [RemoteMedicineBox]?
        
        /// 家庭药箱汇总列表；首页首次加载/切换成员不主动返回。
        /// 只有进入家庭药箱模块后按 entryMemberID 加载成功，再写入首页完整成员数据缓存。
        var familyMedicineBoxes: [RemoteMedicineBox]?
        
        /// 处方列表
        var prescriptions: [RemotePrescription]?
        
        /// 用药计划列表
        var medicationPlans: [RemoteMedicationPlan]?
        
        /// 今日用药记录
        var todayMedicationRecords: [RemoteMedicationRecord]?
        
        /// 用药统计汇总
        var medicationSummary: RemoteMedicationSummary?
        
        /// 症状记录列表
        var symptoms: [RemoteSymptom]?
        
        /// 就诊记录列表
        var visits: [RemoteVisit]?
        
        /// 手术记录列表
        var surgeries: [RemoteSurgery]?
        
        /// 随访记录列表
        var followUps: [RemoteFollowUp]?
    }

    /// 开启提醒用药计划聚合响应（本地通知补全专用）。
    struct RemoteMedicationReminderEnabledPlansResponse: Codable, Sendable, Equatable {
        var windowStartDate: String
        var windowEndDate: String
        var members: [RemoteMedicationReminderMemberGroup]
    }

    struct RemoteMedicationReminderMemberGroup: Codable, Sendable, Equatable {
        var member: RemoteMedicationReminderMemberSummary
        var source: String
        var selfOwners: [RemoteMedicationReminderSelfOwner]
        var plans: [RemoteMedicationPlan]
        var records: [RemoteMedicationRecord]
    }

    struct RemoteMedicationReminderMemberSummary: Codable, Sendable, Equatable {
        var id: Int
        var name: String
        var relationship: String
        var isSelfMember: Bool
        var bindingRole: String?
        var canShare: Bool
        var canWrite: Bool
    }

    struct RemoteMedicationReminderSelfOwner: Codable, Sendable, Equatable {
        var userId: Int64
        var displayName: String
        var hasApns: Bool
        var notificationsEnabled: Bool
    }

    struct RemoteMemberNotificationOwnership: Codable, Sendable, Equatable {
        var memberId: Int
        var memberName: String
        var currentUserRelationship: String
        var isCurrentUserSelfMember: Bool
        var canShare: Bool
        var canWrite: Bool
        var hasOtherSelfOwner: Bool
        var selfOwners: [RemoteMedicationReminderSelfOwner]
    }

    struct RemoteMedicationReminderLocalAuthorization: Codable, Sendable, Equatable {
        var id: Int?
        var userId: Int64
        var memberId: Int
        var medicationPlanId: Int
        var enabled: Bool
        var exists: Bool
        var isSelfMember: Bool
        var source: String
        var updatedAt: Date?
    }
}
