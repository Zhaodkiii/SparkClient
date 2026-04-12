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

    /// 单药表单提交：先创建一个最小处方批次，再保存其中药品。
    func submitMedicationSingle(memberID: Int, medicalCaseID: Int? = nil, draft: MedicationRecognitionDraft) async throws -> Int {
        let batchID = try await workflowAPI.savePrescription(.init(
            member: memberID,
            medicalCase: medicalCaseID,
            prescriberName: "",
            institutionName: "",
            prescribedAt: nil,
            diagnosis: "",
            batchNo: "",
            status: "active",
            auditorName: "",
            auditedAt: nil,
            extra: ["source": "medication_form"],
            medications: []
        ))

        return try await workflowAPI.saveMedication(.init(
            member: memberID,
            batch: batchID,
            genericName: draft.genericName ?? "",
            brandName: draft.brandName ?? "",
            drugName: draft.drugName ?? draft.genericName ?? "",
            dosageForm: draft.dosageForm ?? "",
            strength: draft.strength ?? "",
            route: draft.route ?? "",
            dosePerTime: draft.dosePerTime ?? "",
            doseValue: draft.doseValue.parsedAsDoseValue(),
            doseUnit: draft.doseUnit ?? "",
            frequencyCode: draft.frequencyCode ?? "",
            period: draft.period ?? "",
            timesPerPeriod: draft.timesPerPeriod.parsedAsTimesPerPeriod(),
            frequencyText: draft.frequencyText ?? "",
            durationDays: draft.durationDays.parsedAsDurationDays(),
            instructions: draft.instructions ?? "",
            reminderEnabled: draft.reminderEnabled ?? false,
            reminderTimes: draft.reminderTimes ?? [],
            sortOrder: draft.sortOrder.parsedAsSortOrderInt() ?? 0,
            extra: draft.extra ?? [:]
        ))
    }

    func submitPrescriptionBatch(memberID: Int, draft: PrescriptionRecognitionDraft) async throws -> Int {
        let medications: [SparkMedicalWorkflowAPI.MedicationSavePayload] = (draft.medications ?? []).enumerated().map { index, line in
            SparkMedicalWorkflowAPI.MedicationSavePayload(
                member: memberID,
                batch: 0,
                genericName: line.genericName ?? "",
                brandName: line.brandName ?? "",
                drugName: line.drugName ?? line.genericName ?? "",
                dosageForm: line.dosageForm ?? "",
                strength: line.strength ?? "",
                route: line.route ?? "",
                dosePerTime: line.dosePerTime ?? "",
                doseValue: line.doseValue.parsedAsDoseValue(),
                doseUnit: line.doseUnit ?? "",
                frequencyCode: line.frequencyCode ?? "",
                period: line.period ?? "",
                timesPerPeriod: line.timesPerPeriod.parsedAsTimesPerPeriod(),
                frequencyText: line.frequencyText ?? "",
                durationDays: line.durationDays.parsedAsDurationDays(),
                instructions: line.instructions ?? "",
                reminderEnabled: line.reminderEnabled ?? false,
                reminderTimes: line.reminderTimes ?? [],
                sortOrder: line.sortOrder.parsedAsSortOrderInt() ?? index,
                extra: line.extra ?? [:]
            )
        }

        return try await workflowAPI.savePrescription(.init(
            member: memberID,
            medicalCase: draft.medicalCase,
            prescriberName: draft.prescriberName ?? "",
            institutionName: draft.institutionName ?? "",
            prescribedAt: draft.prescribedAt,
            diagnosis: draft.diagnosis ?? "",
            batchNo: draft.batchNo ?? "",
            status: draft.status,
            auditorName: draft.auditorName ?? "",
            auditedAt: draft.auditedAt,
            extra: draft.extra ?? [:],
            medications: medications
        ))
    }

    /// 更新已存在的处方批次头信息 + 重建药品行：先 PATCH 批次字段，再删除旧药品、创建新药品。
    func submitPrescriptionBatchUpdate(
        existingBatch: SparkMedicalSyncAPI.RemotePrescriptionBatchComplete,
        memberID: Int,
        draft: PrescriptionRecognitionDraft
    ) async throws {
        _ = try await workflowAPI.update(
            SparkMedicalSyncAPI.RemotePrescriptionBatch.self,
            kind: .prescriptionBatches,
            id: existingBatch.id,
            body: PrescriptionBatchUpdatePayload(
                prescriberName: draft.prescriberName ?? "",
                institutionName: draft.institutionName ?? "",
                prescribedAt: draft.prescribedAt,
                diagnosis: draft.diagnosis ?? "",
                batchNo: draft.batchNo ?? "",
                status: draft.status,
                auditorName: draft.auditorName ?? "",
                auditedAt: draft.auditedAt,
                extra: draft.extra ?? existingBatch.extra ?? [:]
            )
        )

        for med in existingBatch.medications ?? [] {
            try await workflowAPI.delete(kind: .medications, id: med.id)
        }

        for (index, line) in (draft.medications ?? []).enumerated() {
            _ = try await workflowAPI.saveMedication(.init(
                member: memberID,
                batch: existingBatch.id,
                genericName: line.genericName ?? "",
                brandName: line.brandName ?? "",
                drugName: line.drugName ?? line.genericName ?? "",
                dosageForm: line.dosageForm ?? "",
                strength: line.strength ?? "",
                route: line.route ?? "",
                dosePerTime: line.dosePerTime ?? "",
                doseValue: line.doseValue.parsedAsDoseValue(),
                doseUnit: line.doseUnit ?? "",
                frequencyCode: line.frequencyCode ?? "",
                period: line.period ?? "",
                timesPerPeriod: line.timesPerPeriod.parsedAsTimesPerPeriod(),
                frequencyText: line.frequencyText ?? "",
                durationDays: line.durationDays.parsedAsDurationDays(),
                instructions: line.instructions ?? "",
                reminderEnabled: line.reminderEnabled ?? false,
                reminderTimes: line.reminderTimes ?? [],
                sortOrder: line.sortOrder.parsedAsSortOrderInt() ?? index,
                extra: line.extra ?? [:]
            ))
        }
    }

    /// 更新已存在的药品行（同一 `batch`），对原记录做 PATCH，不新建。
    func submitMedicationUpdate(
        memberID: Int,
        existing: SparkMedicalSyncAPI.RemoteMedication,
        draft: MedicationRecognitionDraft
    ) async throws {
        _ = try await workflowAPI.update(
            SparkMedicalSyncAPI.RemoteMedication.self,
            kind: .medications,
            id: existing.id,
            body: SparkMedicalWorkflowAPI.MedicationSavePayload(
                member: memberID,
                batch: existing.batch,
                genericName: draft.genericName ?? "",
                brandName: draft.brandName ?? "",
                drugName: draft.drugName ?? draft.genericName ?? "",
                dosageForm: draft.dosageForm ?? "",
                strength: draft.strength ?? "",
                route: draft.route ?? "",
                dosePerTime: draft.dosePerTime ?? "",
                doseValue: draft.doseValue.parsedAsDoseValue(),
                doseUnit: draft.doseUnit ?? "",
                frequencyCode: draft.frequencyCode ?? "",
                period: draft.period ?? "",
                timesPerPeriod: draft.timesPerPeriod.parsedAsTimesPerPeriod(),
                frequencyText: draft.frequencyText ?? "",
                durationDays: draft.durationDays.parsedAsDurationDays(),
                instructions: draft.instructions ?? "",
                reminderEnabled: draft.reminderEnabled ?? existing.reminderEnabled,
                reminderTimes: draft.reminderTimes ?? existing.reminderTimes,
                sortOrder: draft.sortOrder.parsedAsSortOrderInt() ?? existing.sortOrder,
                extra: draft.extra ?? existing.extra ?? [:]
            )
        )
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
                sourceSystemID: existing.sourceSystemID,
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
                sourceSystemID: existing.sourceSystemID,
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

private struct PrescriptionBatchUpdatePayload: Encodable {
    let prescriberName: String
    let institutionName: String
    let prescribedAt: String?
    let diagnosis: String
    let batchNo: String
    let status: String?
    let auditorName: String
    let auditedAt: String?
    let extra: [String: String]

    enum CodingKeys: String, CodingKey {
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

    enum CodingKeys: String, CodingKey {
        case member
        case medicalCase = "medical_case"
        case name, code, severity, notes, extra
        case startedAt = "started_at"
        case durationValue = "duration_value"
        case durationUnit = "duration_unit"
        case bodyPart = "body_part"
    }
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

    enum CodingKeys: String, CodingKey {
        case member
        case medicalCase = "medical_case"
        case visitType = "visit_type"
        case visitedAt = "visited_at"
        case department
        case doctorName = "doctor_name"
        case visitNo = "visit_no"
        case sourceSystemID = "source_system_id"
        case notes, extra
    }
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

    enum CodingKeys: String, CodingKey {
        case member
        case medicalCase = "medical_case"
        case procedureName = "procedure_name"
        case procedureCode = "procedure_code"
        case site
        case performedAt = "performed_at"
        case surgeon
        case anesthesiaType = "anesthesia_type"
        case incisionLevel = "incision_level"
        case asaClass = "asa_class"
        case sourceSystemID = "source_system_id"
        case notes, extra
    }
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

    enum CodingKeys: String, CodingKey {
        case member
        case medicalCase = "medical_case"
        case plannedAt = "planned_at"
        case completedAt = "completed_at"
        case status, method, outcome, extra
        case nextAction = "next_action"
    }
}
