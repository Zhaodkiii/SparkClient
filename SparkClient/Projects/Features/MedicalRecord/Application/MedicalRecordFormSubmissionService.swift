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
    func submitMedicationSingle(memberID: Int, draft: MedicationRecognitionDraft) async throws -> Int {
        let batchID = try await workflowAPI.savePrescription(.init(
            member: memberID,
            medicalCase: nil,
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

    /// 更新已存在的药品行（同一 `batch`），用于时间轴/列表进入编辑。
    func submitMedicationUpdate(
        memberID: Int,
        existing: SparkMedicalSyncAPI.RemoteMedication,
        draft: MedicationRecognitionDraft
    ) async throws -> Int {
        try await workflowAPI.saveMedication(.init(
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
        ))
    }
}
