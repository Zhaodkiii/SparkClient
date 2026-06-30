import Foundation

/// 医疗记录表单提交服务（独立于结果页绑定，可直接供新建/编辑页调用）。
struct MedicalRecordFormSubmissionService: Sendable {
    let workflowAPI: SparkMedicalWorkflowAPI

    func submitSymptomCreate(memberID: Int, medicalCaseID: Int?, draft: SymptomRecognitionDraft) async throws -> SparkMedicalSyncAPI.SymptomMutationResponse {
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
            notes: draft.notes,
            fileIds: []
        ))
    }

    func submitSymptomDelete(id: Int) async throws -> SparkMedicalSyncAPI.SymptomMutationResponse {
        try await workflowAPI.deleteSymptom(id: id)
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
            notes: draft.notes,
            fileIds: []
        ))
    }

    func submitSurgeryCreate(
        memberID: Int,
        medicalCaseID: Int?,
        draft: SurgeryRecognitionDraft,
        recoveryStatus: String = "",
        hospitalName: String = ""
    ) async throws -> SparkMedicalSyncAPI.SurgeryMutationResponse {
        let extra = SurgeryFormSupport.buildExtra(
            draft: draft,
            recoveryStatus: recoveryStatus,
            hospitalName: hospitalName
        )
        return try await workflowAPI.createSurgery(.init(
            member: memberID,
            medicalCase: medicalCaseID,
            procedureName: draft.procedureName,
            procedureCode: draft.procedureCode,
            site: draft.site,
            performedAt: SurgeryFormSupport.workflowPerformedAt(for: draft),
            surgeon: draft.surgeon,
            anesthesiaType: draft.anesthesiaType,
            incisionLevel: draft.incisionLevel,
            asaClass: draft.asaClass,
            notes: draft.notes,
            extra: extra,
            fileIds: []
        ))
    }

    func submitSurgeryDelete(id: Int) async throws -> SparkMedicalSyncAPI.SurgeryMutationResponse {
        try await workflowAPI.deleteSurgery(id: id)
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
            nextAction: draft.nextAction,
            fileIds: []
        ))
    }

    func submitMedicalReportCreate(memberID: Int, draft: MedicalReportRecognitionDraft, medicalCaseID: Int? = nil) async throws -> Int {
        let details = draft.details.enumerated().map { index, row in
            let apiItem = row.toMedicalReportItem(fallbackCategory: draft.category, sortOrder: index)
            return SparkMedicalWorkflowAPI.MedicalReportDetailPayload(
                category: apiItem.category,
                subCategory: apiItem.subCategory ?? "",
                itemName: apiItem.itemName ?? "",
                itemCode: apiItem.itemCode ?? "",
                resultValue: apiItem.resultValue ?? "",
                unit: apiItem.unit ?? "",
                referenceRange: apiItem.referenceRange ?? "",
                flag: apiItem.flag ?? "",
                resultAt: apiItem.resultAt,
                modality: apiItem.modality ?? "",
                bodyPart: apiItem.bodyPart ?? "",
                diagnosis: apiItem.diagnosis ?? "",
                extra: apiItem.extra ?? [:],
                sortOrder: apiItem.sortOrder.parsedAsSortOrderInt() ?? index
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
            findings: draft.resolvedFindingsText ?? "",
            impression: draft.resolvedImpressionText ?? "",
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
    ) async throws -> SparkMedicalSyncAPI.SymptomMutationResponse {
        let startedAt = (draft.startedAt ?? "").nilIfBlank ?? existing.startedAt.map { MedicalDateCoding.encodeISO8601($0) }
        return try await workflowAPI.updateSymptom(
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
        draft: SurgeryRecognitionDraft,
        recoveryStatus: String = "",
        hospitalName: String = ""
    ) async throws -> SparkMedicalSyncAPI.SurgeryMutationResponse {
        var extra = existing.extra ?? [:]
        let merged = SurgeryFormSupport.buildExtra(
            draft: draft,
            recoveryStatus: recoveryStatus,
            hospitalName: hospitalName,
            source: extra["source"] ?? "manual"
        )
        extra.merge(merged) { _, new in new }

        let performedAt = SurgeryFormSupport.workflowPerformedAt(for: draft)
            ?? existing.performedAt.map { MedicalDateCoding.encodeISO8601($0) }

        return try await workflowAPI.updateSurgery(
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
                extra: extra
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

    func submitPrescriptionCreate(
        memberID: Int,
        medicalCaseID: Int?,
        draft: PrescriptionRecognitionDraft
    ) async throws -> SparkMedicalWorkflowAPI.MedicationPlanBundleSaveResponse {
        let prescription = SparkMedicalWorkflowAPI.PrescriptionPayload(
            medicalCase: medicalCaseID ?? draft.medicalCase,
            prescriberName: draft.prescriberName,
            institutionName: draft.institutionName,
            prescribedAt: draft.prescribedAt,
            diagnosis: draft.diagnosis,
            prescriptionNo: draft.prescriptionNo,
            status: PrescriptionFieldNormalization.resolvedLifecycleStatus(draft.status),
            extra: draft.extra ?? [:]
        )
        let payload = SparkMedicalWorkflowAPI.MedicationPlanBundleSavePayload(
            member: memberID,
            medicalCase: medicalCaseID ?? draft.medicalCase,
            prescriptionID: nil,
            prescription: prescription,
            items: medicationPlanBundleItems(from: draft.medicationPlans ?? []),
            fileIds: []
        )
        return try await workflowAPI.saveMedicationPlanBundleResponse(payload)
    }

    func submitPrescriptionUpdate(
        memberID: Int,
        existing: SparkMedicalSyncAPI.RemotePrescription,
        draft: PrescriptionRecognitionDraft
    ) async throws -> SparkMedicalSyncAPI.RemotePrescription {
        let updated = try await workflowAPI.update(
            SparkMedicalSyncAPI.RemotePrescription.self,
            kind: .prescriptions,
            id: existing.id,
            body: PrescriptionUpdatePayload(
                medicalCase: existing.medicalCase,
                prescriberName: draft.prescriberName ?? existing.prescriberName,
                institutionName: draft.institutionName ?? existing.institutionName,
                prescribedAt: draft.prescribedAt?.nilIfBlank ?? existing.prescribedAt.map { MedicalDateCoding.encodeDateOnly($0) },
                diagnosis: draft.diagnosis ?? existing.diagnosis,
                prescriptionNo: draft.prescriptionNo ?? existing.prescriptionNo,
                status: PrescriptionFieldNormalization.resolvedLifecycleStatus(draft.status ?? existing.status),
                extra: existing.extra ?? [:]
            )
        )

        let items = medicationPlanBundleItems(from: draft.medicationPlans ?? [])
        if items.isEmpty == false {
            _ = try await workflowAPI.saveMedicationPlanBundleResponse(
                SparkMedicalWorkflowAPI.MedicationPlanBundleSavePayload(
                    member: memberID,
                    medicalCase: existing.medicalCase,
                    prescriptionID: existing.id,
                    prescription: nil,
                    items: items,
                    fileIds: []
                )
            )
        }
        return updated
    }

    func submitMedicalReportUpdate(
        report: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments,
        draft: MedicalReportRecognitionDraft
    ) async throws {
        try await ExaminationReportServerMutationService(resources: workflowAPI)
            .updateReport(report: report, draft: draft)
    }

    func submitMedicationPlanCreate(
        memberID: Int,
        medicalCaseID: Int?,
        draft: MedicationPlanRecognitionDraft
    ) async throws -> SparkMedicalWorkflowAPI.MedicationPlanBundleSaveResponse {
        try await workflowAPI.saveMedicationPlanBundleResponse(
            SparkMedicalWorkflowAPI.MedicationPlanBundleSavePayload(
                member: memberID,
                medicalCase: medicalCaseID,
                prescriptionID: nil,
                prescription: nil,
                items: medicationPlanBundleItems(from: [draft]),
                fileIds: []
            )
        )
    }

    func submitMedicationPlanUpdate(
        memberID: Int,
        existing: SparkMedicalSyncAPI.RemoteMedicationPlan,
        draft: MedicationPlanRecognitionDraft
    ) async throws -> SparkMedicalSyncAPI.MedicationMutationResponse {
        try await workflowAPI.updateMedicationPlan(
            id: existing.id,
            body: medicationPlanPayload(memberID: memberID, existing: existing, draft: draft)
        )
    }

    private func medicationPlanPayload(
        memberID: Int,
        existing: SparkMedicalSyncAPI.RemoteMedicationPlan,
        draft: MedicationPlanRecognitionDraft
    ) -> MedicationPlanPayload {
        MedicationPlanPayload(
            member: memberID,
            medicalCase: existing.medicalCase,
            medicineBox: existing.medicineBox,
            prescription: existing.prescription,
            drugName: draft.medicineName?.nilIfBlank ?? draft.brandName?.nilIfBlank ?? existing.drugName,
            dosePerTime: draft.dosePerTime?.nilIfBlank ?? existing.dosePerTime,
            doseValue: draft.doseValue.flatMap { Double($0) } ?? existing.doseValue,
            doseUnit: draft.doseUnit?.nilIfBlank ?? existing.doseUnit,
            frequencyType: draft.frequencyType?.nilIfBlank ?? existing.frequencyType,
            everyNDays: existing.everyNDays,
            weeklyWeekdays: existing.weeklyWeekdays,
            frequencyText: draft.frequencyText?.nilIfBlank ?? existing.frequencyText,
            reminderTimes: .normalized(from: draft.reminderTimes),
            startDate: draft.startDate?.nilIfBlank ?? MedicalDateCoding.encodeDateOnly(existing.startDate),
            endDate: draft.endDate?.nilIfBlank ?? existing.endDate.map { MedicalDateCoding.encodeDateOnly($0) },
            instructions: draft.instructions?.nilIfBlank ?? existing.instructions,
            reminderEnabled: draft.reminderEnabled ?? existing.reminderEnabled,
            status: PrescriptionFieldNormalization.normalizeMedicationPlanStatus(draft.status ?? existing.status),
            extra: existing.extra ?? [:]
        )
    }

    private func medicationPlanBundleItems(
        from drafts: [MedicationPlanRecognitionDraft]
    ) -> [SparkMedicalWorkflowAPI.MedicationPlanBundleItemPayload] {
        let now = Date()
        return drafts.enumerated().map { index, draft in
            let medicineName = draft.medicineName?.nilIfBlank ?? draft.brandName?.nilIfBlank ?? "未命名药品"
            let doseUnit = draft.doseUnit?.nilIfBlank ?? "片"
            let dosePerTime = draft.dosePerTime?.nilIfBlank ?? "按医嘱"
            return SparkMedicalWorkflowAPI.MedicationPlanBundleItemPayload(
                medicineBoxID: nil,
                medicineBox: nil,
                drugName: medicineName,
                dosePerTime: dosePerTime,
                doseValue: draft.doseValue?.nilIfBlank,
                doseUnit: doseUnit,
                frequencyType: "daily",
                everyNDays: nil,
                weeklyWeekdays: [],
                frequencyText: draft.frequencyText?.nilIfBlank ?? "按医嘱",
                reminderTimes: .normalized(from: draft.reminderTimes),
                startDate: draft.startDate?.nilIfBlank ?? MedicalDateCoding.encodeDateOnly(now),
                endDate: draft.endDate?.nilIfBlank,
                instructions: draft.instructions?.nilIfBlank ?? "",
                reminderEnabled: draft.reminderEnabled ?? false,
                status: PrescriptionFieldNormalization.normalizeMedicationPlanStatus(draft.status),
                extra: ["sort_order": "\(index)"],
                fileIds: []
            )
        }
    }
}

private struct SymptomUpdatePayload: Encodable {
    let member: Int
    let medicalCase: Int?
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
    let medicalCase: Int?
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

private struct PrescriptionUpdatePayload: Encodable {
    let medicalCase: Int?
    let prescriberName: String
    let institutionName: String
    let prescribedAt: String?
    let diagnosis: String
    let prescriptionNo: String?
    let status: String
    let extra: [String: String]
}
