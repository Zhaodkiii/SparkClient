import Foundation

enum HealthResourceReferenceDetailLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded(HealthResourceReferenceDetailPayload)
    case notFound
    case failed(message: String)
}

enum HealthResourceReferenceDetailPayload: Equatable, Sendable {
    case examinationReport(SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments)
    case healthExamReport(SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments)
    case medicalCase(SparkMedicalSyncAPI.RemoteMedicalCaseSummary)
    case prescription(
        SparkMedicalSyncAPI.RemotePrescription,
        plans: [SparkMedicalSyncAPI.RemoteMedicationPlan],
        medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox],
        recordsByPlanID: [Int: [SparkMedicalSyncAPI.RemoteMedicationRecord]]
    )
    case medicationPlan(
        SparkMedicalSyncAPI.RemoteMedicationPlan,
        medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox],
        records: [SparkMedicalSyncAPI.RemoteMedicationRecord]
    )
    case medicineBox(SparkMedicalSyncAPI.RemoteMedicineBox, allBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox])
    case medicationExecution(
        memberID: Int,
        plans: [SparkMedicalSyncAPI.RemoteMedicationPlan],
        medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox],
        initialRecords: [SparkMedicalSyncAPI.RemoteMedicationRecord]
    )
    case readOnly(HealthResourceReadOnlySnapshot)
}

/// 详情页实体加载：先本地 complete-data，未命中再按类型+ID 单条 retrieve。
struct HealthResourceReferenceDetailLoader {
    let medicalQueryAPI: SparkMedicalQueryAPI
    let logger: Logger

    init(medicalQueryAPI: SparkMedicalQueryAPI, logger: Logger = ConsoleLogger()) {
        self.medicalQueryAPI = medicalQueryAPI
        self.logger = logger
    }

    func load(
        reference: HealthResourceReference,
        cachedCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    ) async -> HealthResourceReferenceDetailLoadState {
        let ref = reference.healthRef
        logger.info(
            "健康资料详情加载开始，type=\(reference.resourceType), id=\(reference.resourceID), member=\(reference.memberID)",
            module: .general
        )

        if let data = cachedCompleteData, data.memberId == reference.memberID,
           let payload = payloadFromCompleteData(ref: ref, data: data) {
            logger.info(
                "健康资料详情命中本地 complete-data，type=\(reference.resourceType), id=\(reference.resourceID)",
                module: .general
            )
            return .loaded(payload)
        }

        guard let type = ref.typedResource else {
            logger.warning("健康资料详情未知类型：\(reference.resourceType)", module: .general)
            return .notFound
        }

        if let payload = await payloadFromNetwork(ref: ref, type: type) {
            logger.info(
                "健康资料详情网络加载成功，type=\(reference.resourceType), id=\(reference.resourceID)",
                module: .general
            )
            return .loaded(payload)
        }

        logger.warning(
            "健康资料详情未找到，type=\(reference.resourceType), id=\(reference.resourceID)",
            module: .general
        )
        return .notFound
    }

    // MARK: - Complete-data

    private func payloadFromCompleteData(
        ref: HealthResourceRef,
        data: SparkMedicalSyncAPI.RemoteMemberCompleteData
    ) -> HealthResourceReferenceDetailPayload? {
        guard let type = ref.typedResource else { return nil }
        switch type {
        case .examinationReport:
            guard let report = data.examinationReports?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return .examinationReport(report)
        case .healthExamReport:
            guard let report = data.healthExamReports?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return .healthExamReport(report)
        case .medicalCase:
            guard let item = data.medicalCases?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return .medicalCase(item)
        case .prescription:
            guard let rx = data.prescriptions?.first(where: { $0.id == ref.resourceID }) else { return nil }
            let plans = data.medicationPlans?.filter { $0.prescription == ref.resourceID } ?? []
            let boxes = data.medicineBoxes ?? []
            let records = recordsByPlan(plans: plans, records: data.todayMedicationRecords ?? [])
            return .prescription(rx, plans: plans, medicineBoxes: boxes, recordsByPlanID: records)
        case .medicationPlan:
            guard let plan = data.medicationPlans?.first(where: { $0.id == ref.resourceID }) else { return nil }
            let boxes = data.medicineBoxes ?? []
            let records = data.todayMedicationRecords?.filter { $0.plan == ref.resourceID } ?? []
            return .medicationPlan(plan, medicineBoxes: boxes, records: records)
        case .medicineBox:
            guard let box = data.medicineBoxes?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return .medicineBox(box, allBoxes: data.medicineBoxes ?? [])
        case .medicationSummary:
            return .medicationExecution(
                memberID: ref.memberID,
                plans: data.medicationPlans ?? [],
                medicineBoxes: data.medicineBoxes ?? [],
                initialRecords: data.todayMedicationRecords ?? []
            )
        case .symptom:
            guard let item = data.symptoms?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return .readOnly(Self.readOnlySnapshot(ref: ref, type: type, title: item.name, fields: [
                HealthResourceReadOnlyField(title: "严重度", value: item.severity),
                HealthResourceReadOnlyField(title: "部位", value: item.bodyPart),
                HealthResourceReadOnlyField(title: "备注", value: item.notes)
            ], body: nil))
        case .visit:
            guard let item = data.visits?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return .readOnly(Self.readOnlySnapshot(ref: ref, type: type, title: item.department, fields: [
                HealthResourceReadOnlyField(title: "医生", value: item.doctorName),
                HealthResourceReadOnlyField(title: "类型", value: item.visitType),
                HealthResourceReadOnlyField(title: "备注", value: item.notes)
            ], body: nil))
        case .surgery:
            guard let item = data.surgeries?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return .readOnly(Self.readOnlySnapshot(ref: ref, type: type, title: item.procedureName, fields: [
                HealthResourceReadOnlyField(title: "术者", value: item.surgeon),
                HealthResourceReadOnlyField(title: "备注", value: item.notes)
            ], body: nil))
        case .followUp:
            guard let item = data.followUps?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return .readOnly(Self.readOnlySnapshot(ref: ref, type: type, title: item.method, fields: [
                HealthResourceReadOnlyField(title: "结果", value: item.outcome),
                HealthResourceReadOnlyField(title: "下一步", value: item.nextAction)
            ], body: nil))
        case .medicationRecord:
            guard let item = data.todayMedicationRecords?.first(where: { $0.id == ref.resourceID }) else { return nil }
            return .readOnly(Self.readOnlySnapshot(ref: ref, type: type, title: L10n.text(type.localizationKey), fields: [
                HealthResourceReadOnlyField(title: "计划剂量", value: item.plannedDose),
                HealthResourceReadOnlyField(title: "实际剂量", value: item.actualDose),
                HealthResourceReadOnlyField(title: "状态", value: item.status)
            ], body: item.notes))
        }
    }

    // MARK: - Network

    private func payloadFromNetwork(
        ref: HealthResourceRef,
        type: HealthResourceType
    ) async -> HealthResourceReferenceDetailPayload? {
        switch type {
        case .examinationReport:
            guard let report = try? await medicalQueryAPI.retrieveExaminationReport(id: ref.resourceID) else { return nil }
            let details = try? await medicalQueryAPI.listMedExamDetails(
                memberID: ref.memberID,
                businessType: type.rawValue,
                businessID: ref.resourceID
            )
            return .examinationReport(Self.examinationWithAttachments(report, details: details))
        case .healthExamReport:
            guard let report = try? await medicalQueryAPI.retrieveHealthExamReport(id: ref.resourceID) else { return nil }
            let details = try? await medicalQueryAPI.listMedExamDetails(
                memberID: ref.memberID,
                businessType: type.rawValue,
                businessID: ref.resourceID
            )
            return .healthExamReport(Self.healthExamWithAttachments(report, details: details))
        case .medicalCase:
            guard let item = try? await medicalQueryAPI.retrieveMedicalCase(id: ref.resourceID) else { return nil }
            return .medicalCase(Self.medicalCaseSummary(from: item))
        case .prescription:
            guard let rx = try? await medicalQueryAPI.retrievePrescription(id: ref.resourceID) else { return nil }
            let plans = (try? await medicalQueryAPI.listMedicationPlans(memberID: ref.memberID, prescriptionID: ref.resourceID)) ?? []
            let boxes = (try? await medicalQueryAPI.listMedicineBoxes(memberID: ref.memberID)) ?? []
            let records = recordsByPlan(plans: plans, records: (try? await medicalQueryAPI.listMedicationRecords(memberID: ref.memberID)) ?? [])
            return .prescription(rx, plans: plans, medicineBoxes: boxes, recordsByPlanID: records)
        case .medicationPlan:
            guard let plan = try? await medicalQueryAPI.retrieveMedicationPlan(id: ref.resourceID) else { return nil }
            let boxes = (try? await medicalQueryAPI.listMedicineBoxes(memberID: ref.memberID)) ?? []
            let records = (try? await medicalQueryAPI.listMedicationRecords(memberID: ref.memberID, planID: ref.resourceID)) ?? []
            return .medicationPlan(plan, medicineBoxes: boxes, records: records)
        case .medicineBox:
            guard let box = try? await medicalQueryAPI.retrieveMedicineBox(id: ref.resourceID) else { return nil }
            let all = (try? await medicalQueryAPI.listMedicineBoxes(memberID: ref.memberID)) ?? [box]
            return .medicineBox(box, allBoxes: all)
        case .medicationSummary:
            return .medicationExecution(
                memberID: ref.memberID,
                plans: (try? await medicalQueryAPI.listMedicationPlans(memberID: ref.memberID)) ?? [],
                medicineBoxes: (try? await medicalQueryAPI.listMedicineBoxes(memberID: ref.memberID)) ?? [],
                initialRecords: (try? await medicalQueryAPI.listMedicationRecords(memberID: ref.memberID)) ?? []
            )
        case .symptom:
            guard let item = try? await medicalQueryAPI.retrieveSymptom(id: ref.resourceID) else { return nil }
            return .readOnly(Self.readOnlySnapshot(ref: ref, type: type, title: item.name, fields: [
                HealthResourceReadOnlyField(title: "严重度", value: item.severity),
                HealthResourceReadOnlyField(title: "部位", value: item.bodyPart)
            ], body: item.notes))
        case .visit:
            guard let item = try? await medicalQueryAPI.retrieveVisit(id: ref.resourceID) else { return nil }
            return .readOnly(Self.readOnlySnapshot(ref: ref, type: type, title: item.department, fields: [
                HealthResourceReadOnlyField(title: "医生", value: item.doctorName),
                HealthResourceReadOnlyField(title: "类型", value: item.visitType)
            ], body: item.notes))
        case .surgery:
            guard let item = try? await medicalQueryAPI.retrieveSurgery(id: ref.resourceID) else { return nil }
            return .readOnly(Self.readOnlySnapshot(ref: ref, type: type, title: item.procedureName, fields: [
                HealthResourceReadOnlyField(title: "术者", value: item.surgeon)
            ], body: item.notes))
        case .followUp:
            guard let item = try? await medicalQueryAPI.retrieveFollowUp(id: ref.resourceID) else { return nil }
            return .readOnly(Self.readOnlySnapshot(ref: ref, type: type, title: item.method, fields: [
                HealthResourceReadOnlyField(title: "结果", value: item.outcome),
                HealthResourceReadOnlyField(title: "下一步", value: item.nextAction)
            ], body: nil))
        case .medicationRecord:
            guard let item = try? await medicalQueryAPI.retrieveMedicationRecord(id: ref.resourceID) else { return nil }
            return .readOnly(Self.readOnlySnapshot(ref: ref, type: type, title: L10n.text(type.localizationKey), fields: [
                HealthResourceReadOnlyField(title: "计划剂量", value: item.plannedDose),
                HealthResourceReadOnlyField(title: "实际", value: item.actualDose),
                HealthResourceReadOnlyField(title: "状态", value: item.status)
            ], body: item.notes))
        }
    }

    private func recordsByPlan(
        plans: [SparkMedicalSyncAPI.RemoteMedicationPlan],
        records: [SparkMedicalSyncAPI.RemoteMedicationRecord]
    ) -> [Int: [SparkMedicalSyncAPI.RemoteMedicationRecord]] {
        Dictionary(grouping: records.filter { record in plans.contains(where: { $0.id == record.plan }) }, by: \.plan)
    }

    private static func examinationWithAttachments(
        _ report: SparkMedicalSyncAPI.RemoteExaminationReport,
        attachments: [SparkMedicalSyncAPI.RemoteManagedFile]? = nil,
        details: [SparkMedicalSyncAPI.RemoteMedExamDetail]? = nil
    ) -> SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments {
        SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments(
            id: report.id,
            member: report.member,
            medicalRecord: report.medicalRecord,
            category: report.category,
            subCategory: report.subCategory,
            itemName: report.itemName,
            performedAt: report.performedAt,
            reportedAt: report.reportedAt,
            organizationName: report.organizationName,
            departmentName: report.departmentName,
            doctorName: report.doctorName,
            findings: report.findings,
            impression: report.impression,
            source: report.source,
            status: report.status,
            extra: report.extra,
            createdAt: nil,
            updatedAt: report.updatedAt,
            attachments: attachments,
            medExamDetails: details
        )
    }

    private static func healthExamWithAttachments(
        _ report: SparkMedicalSyncAPI.RemoteHealthExamReport,
        attachments: [SparkMedicalSyncAPI.RemoteManagedFile]? = nil,
        details: [SparkMedicalSyncAPI.RemoteMedExamDetail]? = nil
    ) -> SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments {
        SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments(
            id: report.id,
            member: report.member,
            institutionName: report.institutionName,
            reportNo: report.reportNo,
            examDate: report.examDate,
            examType: report.examType,
            summary: report.summary,
            source: report.source,
            status: report.status,
            extra: report.extra,
            createdAt: nil,
            updatedAt: report.updatedAt,
            attachments: attachments,
            medExamDetails: details
        )
    }

    private static func medicalCaseSummary(from item: SparkMedicalSyncAPI.RemoteMedicalCase) -> SparkMedicalSyncAPI.RemoteMedicalCaseSummary {
        SparkMedicalSyncAPI.RemoteMedicalCaseSummary(
            id: item.id,
            member: item.member,
            recordType: item.recordType,
            status: item.status,
            title: item.title,
            hospitalName: item.hospitalName,
            ageAtVisit: item.ageAtVisit,
            severity: item.severity,
            caseStatus: item.caseStatus,
            diagnosisSummary: item.diagnosisSummary,
            extra: item.extra,
            createdAt: nil,
            updatedAt: item.updatedAt,
            symptoms: nil,
            medications: nil,
            attachments: nil
        )
    }

    private static func readOnlySnapshot(
        ref: HealthResourceRef,
        type: HealthResourceType,
        title: String,
        fields: [HealthResourceReadOnlyField],
        body: String?
    ) -> HealthResourceReadOnlySnapshot {
        let typeLabel = L10n.text(type.localizationKey)
        let nonEmptyFields = fields.filter { $0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        return HealthResourceReadOnlySnapshot(
            typeLabel: typeLabel,
            navigationTitle: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? typeLabel
                : title,
            subtitle: nil,
            fields: nonEmptyFields,
            bodyText: body?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? body : nil
        )
    }
}
