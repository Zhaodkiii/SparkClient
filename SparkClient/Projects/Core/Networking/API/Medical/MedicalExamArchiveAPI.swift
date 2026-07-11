import Foundation

enum SparkMedicalExamArchiveAPI {
    struct ExamPlanItem: Codable, Sendable, Equatable, Identifiable, Hashable {
        var key: String?
        var name: String

        var id: String { key ?? name }
    }

    struct AbnormalItem: Codable, Sendable, Equatable, Identifiable, Hashable {
        var key: String?
        var code: String?
        var name: String
        var value: String?
        var unit: String?
        var severity: String?
        var reason: String?
        var suggestion: String?

        var id: String { key ?? code ?? name }

        var displaySuggestion: String {
            (suggestion?.isEmpty == false ? suggestion : reason) ?? ""
        }
    }

    struct FollowUpTaskDraft: Codable, Sendable, Equatable, Identifiable, Hashable {
        var key: String
        var title: String
        var medicalTaskType: String?
        var dueInDays: Int?
        var priority: String?
        var sourceAbnormalKey: String?
        var sourceAbnormalName: String?

        var id: String { key }
    }

    struct ExamPlanDraft: Codable, Sendable, Equatable {
        var id: Int?
        var title: String
        var mustItems: [ExamPlanItem]
        var recommendedItems: [ExamPlanItem]
        var followUpItems: [ExamPlanItem]
        var rationale: [String]
        var riskNotice: String
    }

    struct CreatedTask: Codable, Sendable, Equatable, Identifiable {
        var taskID: Int
        var key: String?
        var title: String
        var reminderTime: String?

        var id: Int { taskID }

        enum CodingKeys: String, CodingKey {
            case key, title
            case taskID = "taskId"
            case reminderTime
        }
    }

    struct EvidenceSnapshot: Codable, Sendable, Equatable {
        var basicProfile: String?
        var healthHistory: String?
        var symptoms: String?
        var lifestyle: String?
        var familyHistory: [SparkMedicalSyncAPI.RemoteFamilyHistoryRecord]?
    }

    struct PreviewAbnormalItemsResponse: Codable, Sendable {
        var memberID: Int
        var healthExamReportID: Int
        var abnormalItems: [AbnormalItem]
        var followUpTasks: [FollowUpTaskDraft]

        enum CodingKeys: String, CodingKey {
            case abnormalItems
            case followUpTasks
            case memberID = "memberId"
            case healthExamReportID = "healthExamReportId"
        }
    }

    struct ConfirmedAbnormalItemsResponse: Codable, Sendable {
        var memberID: Int
        var recordID: Int?
        var abnormalItems: [AbnormalItem]
        var followUpTasks: [FollowUpTaskDraft]

        enum CodingKeys: String, CodingKey {
            case abnormalItems
            case followUpTasks
            case memberID = "memberId"
            case recordID = "recordId"
        }
    }

    struct EvidenceResponse: Codable, Sendable {
        var memberID: Int
        var evidence: EvidenceSnapshot

        enum CodingKeys: String, CodingKey {
            case evidence
            case memberID = "memberId"
        }
    }

    struct AIPlanResponse: Codable, Sendable {
        var mode: String
        var memberID: Int
        var sourceReportID: Int?
        var planID: Int?
        var abnormalItems: [AbnormalItem]
        var followUpTasks: [FollowUpTaskDraft]
        var createdTasks: [CreatedTask]
        var examPlan: ExamPlanDraft
        var memberMedicalProfile: SparkMedicalSyncAPI.RemoteMemberMedicalProfile?
        var guidanceSections: [SparkMedicalSyncAPI.RemoteMemberMedicalProfileSectionSummary]?

        enum CodingKeys: String, CodingKey {
            case mode
            case examPlan
            case abnormalItems
            case followUpTasks
            case createdTasks
            case guidanceSections
            case memberID = "memberId"
            case sourceReportID = "sourceReportId"
            case planID = "planId"
            case memberMedicalProfile
        }
    }

    nonisolated struct PreviewAbnormalItemsRequest: Encodable, Sendable {
        let healthExamReportID: Int

        enum CodingKeys: String, CodingKey {
            case healthExamReportID = "health_exam_report_id"
        }
    }

    nonisolated struct ConfirmedAbnormalItemPayload: Encodable, Sendable {
        let code: String?
        let name: String
        let value: String?
        let unit: String?
        let severity: String?
    }

    nonisolated struct ConfirmedAbnormalItemsRequest: Encodable, Sendable {
        let healthExamReportID: Int?
        let selectedAbnormalItems: [ConfirmedAbnormalItemPayload]

        enum CodingKeys: String, CodingKey {
            case healthExamReportID = "health_exam_report_id"
            case selectedAbnormalItems = "selected_abnormal_items"
        }
    }

    nonisolated struct AIPlanRequest: Encodable, Sendable {
        let mode: String
        let healthExamReportID: Int?
        let selectedAbnormalItems: [ConfirmedAbnormalItemPayload]?
        let createFollowUpTasks: Bool
        let selectedFollowUpTaskKeys: [String]?

        enum CodingKeys: String, CodingKey {
            case mode
            case healthExamReportID = "health_exam_report_id"
            case selectedAbnormalItems = "selected_abnormal_items"
            case createFollowUpTasks = "create_follow_up_tasks"
            case selectedFollowUpTaskKeys = "selected_follow_up_task_keys"
        }
    }
}

extension SparkMedicalQueryAPI {
    func previewExamArchiveAbnormalItems(
        memberID: Int,
        reportID: Int
    ) async throws -> SparkMedicalExamArchiveAPI.PreviewAbnormalItemsResponse {
        try await write(
            method: .post,
            path: "/api/v1/medical/members/\(memberID)/exam-archive/preview-abnormal-items/",
            body: SparkMedicalExamArchiveAPI.PreviewAbnormalItemsRequest(healthExamReportID: reportID),
            responseType: SparkMedicalExamArchiveAPI.PreviewAbnormalItemsResponse.self,
            serialKey: "medical.exam_archive.preview.\(memberID).\(reportID)"
        )
    }

    func confirmExamArchiveAbnormalItems(
        memberID: Int,
        reportID: Int?,
        items: [SparkMedicalExamArchiveAPI.AbnormalItem]
    ) async throws -> SparkMedicalExamArchiveAPI.ConfirmedAbnormalItemsResponse {
        let payload = items.map {
            SparkMedicalExamArchiveAPI.ConfirmedAbnormalItemPayload(
                code: $0.code ?? $0.key,
                name: $0.name,
                value: $0.value,
                unit: $0.unit,
                severity: $0.severity
            )
        }
        return try await write(
            method: .post,
            path: "/api/v1/medical/members/\(memberID)/exam-archive/confirmed-abnormal-items/",
            body: SparkMedicalExamArchiveAPI.ConfirmedAbnormalItemsRequest(
                healthExamReportID: reportID,
                selectedAbnormalItems: payload
            ),
            responseType: SparkMedicalExamArchiveAPI.ConfirmedAbnormalItemsResponse.self,
            serialKey: "medical.exam_archive.confirm.\(memberID)"
        )
    }

    func loadExamArchiveEvidence(memberID: Int) async throws -> SparkMedicalExamArchiveAPI.EvidenceResponse {
        try await request(
            path: "/api/v1/medical/members/\(memberID)/exam-archive/evidence/",
            responseType: SparkMedicalExamArchiveAPI.EvidenceResponse.self,
            etagTTL: 30
        )
    }

    func generateExamArchiveAIPlan(
        memberID: Int,
        planRequest: SparkMedicalExamArchiveAPI.AIPlanRequest
    ) async throws -> SparkMedicalExamArchiveAPI.AIPlanResponse {
        try await write(
            method: .post,
            path: "/api/v1/medical/members/\(memberID)/exam-archive/ai-plan/",
            body: planRequest,
            responseType: SparkMedicalExamArchiveAPI.AIPlanResponse.self,
            serialKey: "medical.exam_archive.ai_plan.\(memberID)"
        )
    }
}
