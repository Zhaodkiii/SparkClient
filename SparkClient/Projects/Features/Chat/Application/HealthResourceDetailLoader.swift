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

/// 详情页深加载：先 complete-data 切片，未命中再经 `HealthResourceRepository` 单条/列表拉取。
struct HealthResourceDetailLoader {
    let repository: HealthResourceRepository
    let logger: Logger

    init(repository: HealthResourceRepository, logger: Logger = ConsoleLogger()) {
        self.repository = repository
        self.logger = logger
    }

    init(medicalQueryAPI: SparkMedicalQueryAPI, logger: Logger = ConsoleLogger()) {
        self.init(repository: HealthResourceRepository(medicalQueryAPI: medicalQueryAPI), logger: logger)
    }

    func load(
        reference: HealthResourceReference,
        cachedCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData?,
        onCompleteDataPatched: ((SparkMedicalSyncAPI.RemoteMemberCompleteData) -> Void)? = nil
    ) async -> HealthResourceReferenceDetailLoadState {
        let ref = reference.healthRef
        let key = reference.cacheKey
        logger.info("健康资料详情加载开始，key=\(key)", module: .general)

        if let data = cachedCompleteData, data.memberId == reference.memberID,
           let payload = payloadFromCompleteData(ref: ref, data: data) {
            logger.info("健康资料详情命中本地 complete-data，key=\(key)", module: .general)
            let enriched = await enrichReportPayloadIfNeeded(payload, ref: ref)
            patchCompleteDataCacheIfNeeded(
                enriched: enriched,
                cachedCompleteData: data,
                onCompleteDataPatched: onCompleteDataPatched
            )
            return .loaded(enriched)
        }

        guard let type = ref.typedResource else {
            logger.warning("健康资料详情未知类型，key=\(key)", module: .general)
            return .notFound
        }

        if var payload = await payloadFromNetwork(ref: ref, type: type) {
            payload = await enrichReportPayloadIfNeeded(payload, ref: ref)
            logger.info("健康资料详情网络加载成功，key=\(key)", module: .general)
            return .loaded(payload)
        }

        logger.warning("健康资料详情未找到，key=\(key)", module: .general)
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
            guard case .success(let report) = await repository.retrieveExaminationReportWithAttachments(id: ref.resourceID) else {
                return nil
            }
            return .examinationReport(report)
        case .healthExamReport:
            guard case .success(let report) = await repository.retrieveHealthExamReportWithAttachments(id: ref.resourceID) else {
                return nil
            }
            return .healthExamReport(report)
        case .medicalCase:
            guard case .success(let item) = await repository.retrieveMedicalCase(id: ref.resourceID) else { return nil }
            return .medicalCase(Self.medicalCaseSummary(from: item))
        case .prescription:
            guard case .success(let rx) = await repository.retrievePrescription(id: ref.resourceID) else { return nil }
            let plans = await listValueOrEmpty { await repository.listMedicationPlans(memberID: ref.memberID, prescriptionID: ref.resourceID) }
            let boxes = await listValueOrEmpty { await repository.listMedicineBoxes(memberID: ref.memberID) }
            let records = recordsByPlan(
                plans: plans,
                records: await listValueOrEmpty { await repository.listMedicationRecords(memberID: ref.memberID) }
            )
            return .prescription(rx, plans: plans, medicineBoxes: boxes, recordsByPlanID: records)
        case .medicationPlan:
            guard case .success(let plan) = await repository.retrieveMedicationPlan(id: ref.resourceID) else { return nil }
            let boxes = await listValueOrEmpty { await repository.listMedicineBoxes(memberID: ref.memberID) }
            let records = await listValueOrEmpty { await repository.listMedicationRecords(memberID: ref.memberID, planID: ref.resourceID) }
            return .medicationPlan(plan, medicineBoxes: boxes, records: records)
        case .medicineBox:
            guard case .success(let box) = await repository.retrieveMedicineBox(id: ref.resourceID) else { return nil }
            let all = await listValueOrEmpty { await repository.listMedicineBoxes(memberID: ref.memberID) }
            return .medicineBox(box, allBoxes: all.isEmpty ? [box] : all)
        case .medicationSummary:
            return .medicationExecution(
                memberID: ref.memberID,
                plans: await listValueOrEmpty { await repository.listMedicationPlans(memberID: ref.memberID) },
                medicineBoxes: await listValueOrEmpty { await repository.listMedicineBoxes(memberID: ref.memberID) },
                initialRecords: await listValueOrEmpty { await repository.listMedicationRecords(memberID: ref.memberID) }
            )
        case .symptom:
            guard case .success(let item) = await repository.retrieveSymptom(id: ref.resourceID) else { return nil }
            return .readOnly(Self.readOnlySnapshot(ref: ref, type: type, title: item.name, fields: [
                HealthResourceReadOnlyField(title: "严重度", value: item.severity),
                HealthResourceReadOnlyField(title: "部位", value: item.bodyPart)
            ], body: item.notes))
        case .visit:
            guard case .success(let item) = await repository.retrieveVisit(id: ref.resourceID) else { return nil }
            return .readOnly(Self.readOnlySnapshot(ref: ref, type: type, title: item.department, fields: [
                HealthResourceReadOnlyField(title: "医生", value: item.doctorName),
                HealthResourceReadOnlyField(title: "类型", value: item.visitType)
            ], body: item.notes))
        case .surgery:
            guard case .success(let item) = await repository.retrieveSurgery(id: ref.resourceID) else { return nil }
            return .readOnly(Self.readOnlySnapshot(ref: ref, type: type, title: item.procedureName, fields: [
                HealthResourceReadOnlyField(title: "术者", value: item.surgeon)
            ], body: item.notes))
        case .followUp:
            guard case .success(let item) = await repository.retrieveFollowUp(id: ref.resourceID) else { return nil }
            return .readOnly(Self.readOnlySnapshot(ref: ref, type: type, title: item.method, fields: [
                HealthResourceReadOnlyField(title: "结果", value: item.outcome),
                HealthResourceReadOnlyField(title: "下一步", value: item.nextAction)
            ], body: nil))
        case .medicationRecord:
            guard case .success(let item) = await repository.retrieveMedicationRecord(id: ref.resourceID) else { return nil }
            return .readOnly(Self.readOnlySnapshot(ref: ref, type: type, title: L10n.text(type.localizationKey), fields: [
                HealthResourceReadOnlyField(title: "计划剂量", value: item.plannedDose),
                HealthResourceReadOnlyField(title: "实际", value: item.actualDose),
                HealthResourceReadOnlyField(title: "状态", value: item.status)
            ], body: item.notes))
        }
    }

    private func enrichReportPayloadIfNeeded(
        _ payload: HealthResourceReferenceDetailPayload,
        ref: HealthResourceRef
    ) async -> HealthResourceReferenceDetailPayload {
        switch payload {
        case .examinationReport(let report):
            let enriched = await enrichExaminationReport(report, ref: ref)
            return .examinationReport(enriched)
        case .healthExamReport(let report):
            let enriched = await enrichHealthExamReport(report, ref: ref)
            return .healthExamReport(enriched)
        default:
            return payload
        }
    }

    private func enrichExaminationReport(
        _ report: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments,
        ref: HealthResourceRef
    ) async -> SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments {
        var merged = report
        if merged.medExamDetails.isNilOrEmpty {
            if let details = await medExamDetailsOrNil(
                memberID: ref.memberID,
                businessType: HealthResourceType.examinationReport.rawValue,
                businessID: ref.resourceID
            ) {
                merged.medExamDetails = details
                logger.info(
                    "检查报告明细懒加载完成 reportID=\(ref.resourceID) count=\(details.count)",
                    module: .general
                )
            }
        }
        if merged.attachments.isNilOrEmpty,
           case .success(let fresh) = await repository.retrieveExaminationReportWithAttachments(id: ref.resourceID),
           let attachments = fresh.attachments,
           attachments.isEmpty == false {
            merged.attachments = attachments
            logger.info(
                "检查报告附件已从医疗资源接口补齐 reportID=\(ref.resourceID) count=\(attachments.count)",
                module: .general
            )
        }
        return merged
    }

    private func enrichHealthExamReport(
        _ report: SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments,
        ref: HealthResourceRef
    ) async -> SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments {
        var merged = report
        if merged.medExamDetails.isNilOrEmpty {
            if let details = await medExamDetailsOrNil(
                memberID: ref.memberID,
                businessType: HealthResourceType.healthExamReport.rawValue,
                businessID: ref.resourceID
            ) {
                merged.medExamDetails = details
                logger.info(
                    "体检报告明细懒加载完成 reportID=\(ref.resourceID) count=\(details.count)",
                    module: .general
                )
            }
        }
        if merged.attachments.isNilOrEmpty,
           case .success(let fresh) = await repository.retrieveHealthExamReportWithAttachments(id: ref.resourceID),
           let attachments = fresh.attachments,
           attachments.isEmpty == false {
            merged.attachments = attachments
            logger.info(
                "体检报告附件已从医疗资源接口补齐 reportID=\(ref.resourceID) count=\(attachments.count)",
                module: .general
            )
        }
        return merged
    }

    private func patchCompleteDataCacheIfNeeded(
        enriched: HealthResourceReferenceDetailPayload,
        cachedCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData,
        onCompleteDataPatched: ((SparkMedicalSyncAPI.RemoteMemberCompleteData) -> Void)?
    ) {
        guard let onCompleteDataPatched else { return }
        let patched: SparkMedicalSyncAPI.RemoteMemberCompleteData
        switch enriched {
        case .examinationReport(let report):
            patched = HealthResourceCompleteDataCachePatcher.patch(
                cachedCompleteData,
                examinationReport: report
            )
        case .healthExamReport(let report):
            patched = HealthResourceCompleteDataCachePatcher.patch(
                cachedCompleteData,
                healthExamReport: report
            )
        default:
            return
        }
        onCompleteDataPatched(patched)
    }

    private func medExamDetailsOrNil(
        memberID: Int,
        businessType: String,
        businessID: Int
    ) async -> [SparkMedicalSyncAPI.RemoteMedExamDetail]? {
        guard case .success(let details) = await repository.loadMedExamDetails(
            memberID: memberID,
            businessID: businessID
        ) else { return nil }
        return Self.filterMedExamRows(details, acceptedBusinessTypes: acceptedTypes(for: businessType))
    }

    private func acceptedTypes(for businessType: String) -> [String] {
        switch businessType {
        case HealthResourceType.examinationReport.rawValue:
            return ["examination_report", "examination"]
        case HealthResourceType.healthExamReport.rawValue:
            return ["health_exam_report", "health_exam"]
        default:
            return [businessType]
        }
    }

    private static func filterMedExamRows(
        _ rows: [SparkMedicalSyncAPI.RemoteMedExamDetail],
        acceptedBusinessTypes: [String]
    ) -> [SparkMedicalSyncAPI.RemoteMedExamDetail] {
        let accepted = acceptedBusinessTypes.map { $0.lowercased() }
        let filtered = rows.filter { row in
            let normalized = row.businessType.lowercased()
            return accepted.contains(normalized) || rows.count == 1
        }
        return filtered.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.id < rhs.id
            }
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    private func listValueOrEmpty<T>(
        _ load: () async -> Result<[T], HealthResourceLoadError>
    ) async -> [T] {
        guard case .success(let value) = await load() else { return [] }
        return value
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

private extension Optional where Wrapped: Collection {
    var isNilOrEmpty: Bool {
        switch self {
        case .none:
            return true
        case .some(let value):
            return value.isEmpty
        }
    }
}
