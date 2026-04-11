import Foundation

final class DefaultMedicalDataRepository: MedicalDataRepository, @unchecked Sendable {
    private let queryAPI: SparkMedicalQueryAPI
    private let logger: Logger

    init(
        queryAPI: SparkMedicalQueryAPI,
        logger: Logger = ConsoleLogger()
    ) {
        self.queryAPI = queryAPI
        self.logger = logger
    }

    func loadSnapshot() async -> MedicalDataSnapshot {
        do {
            async let members = queryAPI.listMembers()
            async let medicalCases = queryAPI.listMedicalCases()
            async let visits = queryAPI.listVisits()
            async let surgeries = queryAPI.listSurgeries()
            async let followUps = queryAPI.listFollowUps()
            async let healthExamReports = queryAPI.listHealthExamReports()
            async let examinationReports = queryAPI.listExaminationReports()
            async let medExamDetails = queryAPI.listMedExamDetails()
            async let medications = queryAPI.listMedications()
            async let medicationTakenRecords = queryAPI.listMedicationTakenRecords()

            return MedicalDataSnapshot(
                members: try await members.map {
                    Member(
                        id: $0.id,
                        name: $0.name,
                        gender: $0.gender,
                        relationship: $0.relationship,
                        birthDate: $0.birthDate,
                        bloodType: $0.bloodType,
                        allergies: $0.allergies,
                        chronicConditions: $0.chronicConditions,
                        notes: $0.notes,
                        avatarUrl: $0.avatarUrl,
                        isPrimary: $0.isPrimary,
                        updatedAt: $0.updatedAt
                    )
                },
                medicalCases: try await medicalCases.map {
                    MedicalCase(
                        id: $0.id,
                        memberID: $0.member,
                        recordType: $0.recordType,
                        status: $0.status,
                        title: $0.title,
                        hospitalName: $0.hospitalName,
                        ageAtVisit: $0.ageAtVisit,
                        diagnosisSummary: $0.diagnosisSummary,
                        extra: $0.extra ?? [:],
                        updatedAt: $0.updatedAt
                    )
                },
                symptoms: [],
                visits: try await visits.map {
                    Visit(
                        id: $0.id,
                        memberID: $0.member,
                        medicalCaseID: $0.medicalCase,
                        visitType: $0.visitType,
                        visitedAt: $0.visitedAt,
                        department: $0.department,
                        doctorName: $0.doctorName,
                        visitNo: $0.visitNo,
                        sourceSystemID: $0.sourceSystemID,
                        notes: $0.notes,
                        extra: $0.extra ?? [:],
                        updatedAt: $0.updatedAt
                    )
                },
                surgeries: try await surgeries.map {
                    Surgery(
                        id: $0.id,
                        memberID: $0.member,
                        medicalCaseID: $0.medicalCase,
                        procedureName: $0.procedureName,
                        procedureCode: $0.procedureCode,
                        site: $0.site,
                        performedAt: $0.performedAt,
                        surgeon: $0.surgeon,
                        anesthesiaType: $0.anesthesiaType,
                        incisionLevel: $0.incisionLevel,
                        asaClass: $0.asaClass,
                        sourceSystemID: $0.sourceSystemID,
                        notes: $0.notes,
                        extra: $0.extra ?? [:],
                        updatedAt: $0.updatedAt
                    )
                },
                followUps: try await followUps.map {
                    FollowUp(
                        id: $0.id,
                        memberID: $0.member,
                        medicalCaseID: $0.medicalCase,
                        plannedAt: $0.plannedAt,
                        completedAt: $0.completedAt,
                        status: $0.status,
                        method: $0.method,
                        outcome: $0.outcome,
                        nextAction: $0.nextAction,
                        extra: $0.extra ?? [:],
                        updatedAt: $0.updatedAt
                    )
                },
                healthExamReports: try await healthExamReports.map {
                    HealthExamReport(
                        id: $0.id,
                        memberID: $0.member,
                        institutionName: $0.institutionName,
                        reportNo: $0.reportNo,
                        examDate: $0.examDate,
                        examType: $0.examType,
                        summary: $0.summary,
                        source: $0.source,
                        rawOCR: $0.rawOCR,
                        status: $0.status,
                        extra: $0.extra,
                        updatedAt: $0.updatedAt
                    )
                },
                examinationReports: try await examinationReports.map {
                    ExaminationReport(
                        id: $0.id,
                        memberID: $0.member,
                        medicalRecordID: $0.medicalRecord,
                        category: $0.category,
                        subCategory: $0.subCategory,
                        itemName: $0.itemName,
                        performedAt: $0.performedAt,
                        reportedAt: $0.reportedAt,
                        organizationName: $0.organizationName,
                        departmentName: $0.departmentName,
                        doctorName: $0.doctorName,
                        findings: $0.findings,
                        impression: $0.impression,
                        source: $0.source,
                        rawOCR: $0.rawOCR,
                        status: $0.status,
                        extra: $0.extra,
                        updatedAt: $0.updatedAt
                    )
                },
                medExamDetails: try await medExamDetails.map {
                    MedExamDetail(
                        id: $0.id,
                        businessType: $0.businessType,
                        businessID: $0.businessID,
                        memberID: $0.member,
                        category: $0.category,
                        subCategory: $0.subCategory,
                        itemName: $0.itemName,
                        itemCode: $0.itemCode,
                        resultValue: $0.resultValue,
                        unit: $0.unit,
                        referenceRange: $0.referenceRange,
                        flag: $0.flag,
                        resultAt: $0.resultAt,
                        modality: $0.modality,
                        bodyPart: $0.bodyPart,
                        diagnosis: $0.diagnosis,
                        extra: $0.extra,
                        sortOrder: $0.sortOrder,
                        updatedAt: $0.updatedAt
                    )
                },
                medicalReports: [],
                prescriptionBatches: [],
                medications: try await medications.map {
                    Medication(
                        id: $0.id,
                        memberID: $0.member,
                        batchID: $0.batch,
                        genericName: $0.genericName,
                        brandName: $0.brandName,
                        drugName: $0.drugName,
                        dosageForm: $0.dosageForm,
                        strength: $0.strength,
                        route: $0.route,
                        dosePerTime: $0.dosePerTime,
                        doseValue: $0.doseValue,
                        doseUnit: $0.doseUnit,
                        frequencyCode: $0.frequencyCode,
                        period: $0.period,
                        timesPerPeriod: $0.timesPerPeriod,
                        frequencyText: $0.frequencyText,
                        durationDays: $0.durationDays,
                        instructions: $0.instructions,
                        reminderEnabled: $0.reminderEnabled,
                        reminderTimes: $0.reminderTimes,
                        sortOrder: $0.sortOrder,
                        extra: $0.extra ?? [:],
                        updatedAt: $0.updatedAt
                    )
                },
                medicationTakenRecords: try await medicationTakenRecords.map {
                    MedicationTakenRecord(
                        id: $0.id,
                        memberID: $0.member,
                        medicationID: $0.medication,
                        scheduledAt: $0.scheduledAt,
                        takenAt: $0.takenAt,
                        status: $0.status,
                        doseSequence: $0.doseSequence,
                        actualDose: $0.actualDose,
                        timezone: $0.timezone,
                        notes: $0.notes,
                        extra: $0.extra ?? [:],
                        updatedAt: $0.updatedAt
                    )
                },
                healthMetrics: [],
                updatedAt: Date()
            )
        } catch {
            logger.warning("按需医疗数据拉取失败，回退空快照：\(error.localizedDescription)", module: .medical)
            return .empty
        }
    }

    func saveSnapshot(_ snapshot: MedicalDataSnapshot) async throws {
        logger.warning("saveSnapshot 已弃用：不再走全量快照上传。", module: .medical)
        _ = snapshot
    }

    func pullSnapshotFromServer(priority: CloudSyncPriority) async throws {
        _ = try await loadSnapshot()
        _ = priority
        logger.info("按需资源已刷新", module: .medical)
    }

}
