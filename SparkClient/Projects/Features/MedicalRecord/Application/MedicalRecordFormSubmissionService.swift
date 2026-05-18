import Foundation

/// 医疗记录表单提交服务（独立于结果页绑定，可直接供新建/编辑页调用）。
struct MedicalRecordFormSubmissionService: Sendable {
    let workflowAPI: SparkMedicalWorkflowAPI

    func submitSymptomCreate(memberID: Int, medicalCaseID: Int?, draft: SymptomRecognitionDraft) async throws -> Int {
        try await workflowAPI.createSymptom(.init(
            member: memberID,
            medicalCase: medicalCaseID,
            name: draft.name,
            code: draft.code,
            severity: draft.severity,
            startedAt: draft.startedAt,
            durationValue: draft.durationValue.parsedAsAgeAtVisitInteger(),
            durationUnit: draft.durationUnit,
            bodyPart: draft.bodyPart,
            notes: draft.notes
        ))
    }

    func submitVisitCreate(memberID: Int, medicalCaseID: Int?, draft: VisitRecognitionDraft) async throws -> Int {
        try await workflowAPI.createVisit(.init(
            member: memberID,
            medicalCase: medicalCaseID,
            visitType: draft.visitType,
            visitedAt: draft.visitedAt,
            department: draft.department,
            doctorName: draft.doctorName,
            visitNo: draft.visitNo,
            notes: draft.notes
        ))
    }

    func submitSurgeryCreate(memberID: Int, medicalCaseID: Int?, draft: SurgeryRecognitionDraft) async throws -> Int {
        try await workflowAPI.createSurgery(.init(
            member: memberID,
            medicalCase: medicalCaseID,
            procedureName: draft.procedureName,
            procedureCode: draft.procedureCode,
            site: draft.site,
            performedAt: draft.performedAt,
            surgeon: draft.surgeon,
            anesthesiaType: draft.anesthesiaType,
            incisionLevel: draft.incisionLevel,
            asaClass: draft.asaClass,
            notes: draft.notes
        ))
    }

    func submitFollowUpCreate(memberID: Int, medicalCaseID: Int?, draft: FollowUpRecognitionDraft) async throws -> Int {
        try await workflowAPI.createFollowUp(.init(
            member: memberID,
            medicalCase: medicalCaseID,
            plannedAt: draft.plannedAt,
            completedAt: draft.completedAt,
            status: draft.status,
            method: draft.method,
            outcome: draft.outcome,
            nextAction: draft.nextAction
        ))
    }

    func submitMedicalReportCreate(memberID: Int, draft: MedicalReportRecognitionDraft, medicalCaseID: Int? = nil) async throws -> Int {
        let details = draft.details.enumerated().map { index, row in
            SparkMedicalWorkflowAPI.MedicalReportDetailPayload(
                category: row.category,
                subCategory: row.subCategory ?? "",
                itemName: row.itemName ?? "",
                itemCode: row.itemCode ?? "",
                resultValue: row.resultValue ?? "",
                unit: row.unit ?? "",
                referenceRange: row.referenceRange ?? "",
                flag: row.flag ?? "",
                resultAt: row.resultAt,
                modality: row.modality ?? "",
                bodyPart: row.bodyPart ?? "",
                diagnosis: row.diagnosis ?? "",
                extra: row.extra ?? [:],
                sortOrder: row.sortOrder.parsedAsSortOrderInt() ?? index
            )
        }

        return try await workflowAPI.createMedicalReport(.init(
            member: memberID,
            medicalCase: medicalCaseID,
            category: draft.category ?? "laboratory",
            subCategory: "",
            itemName: draft.title,
            performedAt: draft.date,
            reportedAt: draft.date,
            organizationName: draft.hospital,
            departmentName: "",
            doctorName: draft.doctor ?? "",
            findings: draft.content,
            impression: draft.content,
            modality: "",
            bodyPart: "",
            diagnosis: "",
            fileIds: [],
            details: details
        ))
    }

    func submitSymptomUpdate(
        memberID: Int,
        existing: SparkMedicalSyncAPI.RemoteSymptom,
        draft: SymptomRecognitionDraft
    ) async throws {
        let startedAt = (draft.startedAt ?? "").nilIfBlank ?? existing.startedAt.map { MedicalDateCoding.encodeISO8601($0) }
        _ = try await workflowAPI.update(
            SparkMedicalSyncAPI.RemoteSymptom.self,
            kind: .symptoms,
            id: existing.id,
            body: SymptomUpdatePayload(
                member: memberID,
                medicalCase: existing.medicalCase,
                name: draft.name,
                code: draft.code ?? "",
                severity: draft.severity ?? "",
                startedAt: startedAt,
                durationValue: draft.durationValue.parsedAsAgeAtVisitInteger() ?? existing.durationValue,
                durationUnit: draft.durationUnit ?? "",
                bodyPart: draft.bodyPart ?? "",
                notes: draft.notes ?? "",
                extra: existing.extra ?? [:]
            )
        )
    }

    func submitVisitUpdate(
        memberID: Int,
        existing: SparkMedicalSyncAPI.RemoteVisit,
        draft: VisitRecognitionDraft
    ) async throws {
        let visitedAt = (draft.visitedAt ?? "").nilIfBlank ?? existing.visitedAt.map { MedicalDateCoding.encodeISO8601($0) }
        _ = try await workflowAPI.update(
            SparkMedicalSyncAPI.RemoteVisit.self,
            kind: .visits,
            id: existing.id,
            body: VisitUpdatePayload(
                member: memberID,
                medicalCase: existing.medicalCase,
                visitType: draft.visitType ?? existing.visitType,
                visitedAt: visitedAt,
                department: draft.department ?? "",
                doctorName: draft.doctorName ?? "",
                visitNo: draft.visitNo ?? "",
                sourceSystemID: existing.sourceSystemId,
                notes: draft.notes ?? "",
                extra: existing.extra ?? [:]
            )
        )
    }

    func submitSurgeryUpdate(
        memberID: Int,
        existing: SparkMedicalSyncAPI.RemoteSurgery,
        draft: SurgeryRecognitionDraft
    ) async throws {
        let performedAt = (draft.performedAt ?? "").nilIfBlank ?? existing.performedAt.map { MedicalDateCoding.encodeISO8601($0) }
        _ = try await workflowAPI.update(
            SparkMedicalSyncAPI.RemoteSurgery.self,
            kind: .surgeries,
            id: existing.id,
            body: SurgeryUpdatePayload(
                member: memberID,
                medicalCase: existing.medicalCase,
                procedureName: draft.procedureName,
                procedureCode: draft.procedureCode ?? "",
                site: draft.site ?? "",
                performedAt: performedAt,
                surgeon: draft.surgeon ?? "",
                anesthesiaType: draft.anesthesiaType ?? "",
                incisionLevel: draft.incisionLevel ?? "",
                asaClass: draft.asaClass ?? "",
                sourceSystemID: existing.sourceSystemId,
                notes: draft.notes ?? "",
                extra: existing.extra ?? [:]
            )
        )
    }

    func submitFollowUpUpdate(
        memberID: Int,
        existing: SparkMedicalSyncAPI.RemoteFollowUp,
        draft: FollowUpRecognitionDraft
    ) async throws {
        let plannedAt = (draft.plannedAt ?? "").nilIfBlank ?? existing.plannedAt.map { MedicalDateCoding.encodeISO8601($0) }
        let completedAt = (draft.completedAt ?? "").nilIfBlank ?? existing.completedAt.map { MedicalDateCoding.encodeISO8601($0) }
        _ = try await workflowAPI.update(
            SparkMedicalSyncAPI.RemoteFollowUp.self,
            kind: .followUps,
            id: existing.id,
            body: FollowUpUpdatePayload(
                member: memberID,
                medicalCase: existing.medicalCase,
                plannedAt: plannedAt,
                completedAt: completedAt,
                status: draft.status ?? existing.status,
                method: draft.method ?? "",
                outcome: draft.outcome ?? "",
                nextAction: draft.nextAction ?? "",
                extra: existing.extra ?? [:]
            )
        )
    }
}

private struct SymptomUpdatePayload: Encodable {
    let member: Int
    let medicalCase: Int
    let name: String
    let code: String
    let severity: String
    let startedAt: String?
    let durationValue: Int?
    let durationUnit: String
    let bodyPart: String
    let notes: String
    let extra: [String: String]

}

private struct VisitUpdatePayload: Encodable {
    let member: Int
    let medicalCase: Int
    let visitType: String
    let visitedAt: String?
    let department: String
    let doctorName: String
    let visitNo: String
    let sourceSystemID: String
    let notes: String
    let extra: [String: String]

}

private struct SurgeryUpdatePayload: Encodable {
    let member: Int
    let medicalCase: Int
    let procedureName: String
    let procedureCode: String
    let site: String
    let performedAt: String?
    let surgeon: String
    let anesthesiaType: String
    let incisionLevel: String
    let asaClass: String
    let sourceSystemID: String
    let notes: String
    let extra: [String: String]

}

private struct FollowUpUpdatePayload: Encodable {
    let member: Int
    let medicalCase: Int
    let plannedAt: String?
    let completedAt: String?
    let status: String
    let method: String
    let outcome: String
    let nextAction: String
    let extra: [String: String]

}
