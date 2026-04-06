import Foundation

final class DefaultMedicalDataRepository: MedicalDataRepository, @unchecked Sendable {
    private let remoteAPI: SparkMedicalSyncAPI
    private let logger: Logger

    init(
        remoteAPI: SparkMedicalSyncAPI,
        logger: Logger = ConsoleLogger()
    ) {
        self.remoteAPI = remoteAPI
        self.logger = logger
    }

    func loadSnapshot() async -> MedicalDataSnapshot {
        do {
            let remote = try await remoteAPI.fetchSnapshot(priority: .balanced)
            return makeLocalSnapshot(from: remote)
        } catch {
            logger.warning("远程健康快照拉取失败，回退空快照：\(error.localizedDescription)", category: "medical_sync")
            return .empty
        }
    }

    func saveSnapshot(_ snapshot: MedicalDataSnapshot) async throws {
        let payload = makeUploadPayload(from: snapshot)
        try await remoteAPI.uploadSnapshot(payload, priority: .balanced)
    }

    func uploadSnapshotToServer(priority: CloudSyncPriority) async throws {
        let snapshot = await loadSnapshot()
        let payload = makeUploadPayload(from: snapshot)
        try await remoteAPI.uploadSnapshot(payload, priority: priority)
        logger.info("远端健康快照已重新上传", category: "medical_sync")
    }

    func pullSnapshotFromServer(priority: CloudSyncPriority) async throws {
        _ = try await remoteAPI.fetchSnapshot(priority: priority)
        logger.info("远程健康快照已拉取", category: "medical_sync")
    }

    private func makeUploadPayload(from snapshot: MedicalDataSnapshot) -> SparkMedicalSyncAPI.UploadSnapshotPayload {
        let members = snapshot.members.map { member in
            SparkMedicalSyncAPI.UploadMember(
                id: member.id,
                name: member.name,
                gender: member.gender,
                relationship: member.relationship,
                birthDate: member.birthDate,
                bloodType: member.bloodType,
                allergies: member.allergies,
                chronicConditions: member.chronicConditions,
                notes: member.notes,
                avatarUrl: member.avatarUrl,
                isPrimary: member.isPrimary
            )
        }

        let cases = snapshot.medicalCases.map { medicalCase in
            SparkMedicalSyncAPI.UploadMedicalCase(
                id: medicalCase.id,
                member: medicalCase.memberID,
                recordType: medicalCase.recordType,
                status: medicalCase.status,
                title: medicalCase.title,
                hospitalName: medicalCase.hospitalName,
                ageAtVisit: medicalCase.ageAtVisit,
                diagnosisSummary: medicalCase.diagnosisSummary,
                extra: medicalCase.extra
            )
        }
        let symptoms = snapshot.symptoms.map { row in
            SparkMedicalSyncAPI.UploadSymptom(
                id: row.id,
                member: row.memberID,
                medicalCase: row.medicalCaseID,
                name: row.name,
                code: row.code,
                severity: row.severity,
                startedAt: row.startedAt,
                durationValue: row.durationValue,
                durationUnit: row.durationUnit,
                bodyPart: row.bodyPart,
                notes: row.notes,
                extra: row.extra
            )
        }
        let visits = snapshot.visits.map { row in
            SparkMedicalSyncAPI.UploadVisit(
                id: row.id,
                member: row.memberID,
                medicalCase: row.medicalCaseID,
                visitType: row.visitType,
                visitedAt: row.visitedAt,
                department: row.department,
                doctorName: row.doctorName,
                visitNo: row.visitNo,
                sourceSystemID: row.sourceSystemID,
                notes: row.notes,
                extra: row.extra
            )
        }
        let surgeries = snapshot.surgeries.map { row in
            SparkMedicalSyncAPI.UploadSurgery(
                id: row.id,
                member: row.memberID,
                medicalCase: row.medicalCaseID,
                procedureName: row.procedureName,
                procedureCode: row.procedureCode,
                site: row.site,
                performedAt: row.performedAt,
                surgeon: row.surgeon,
                anesthesiaType: row.anesthesiaType,
                incisionLevel: row.incisionLevel,
                asaClass: row.asaClass,
                sourceSystemID: row.sourceSystemID,
                notes: row.notes,
                extra: row.extra
            )
        }
        let followUps = snapshot.followUps.map { row in
            SparkMedicalSyncAPI.UploadFollowUp(
                id: row.id,
                member: row.memberID,
                medicalCase: row.medicalCaseID,
                plannedAt: row.plannedAt,
                completedAt: row.completedAt,
                status: row.status,
                method: row.method,
                outcome: row.outcome,
                nextAction: row.nextAction,
                extra: row.extra
            )
        }

        let examReports = snapshot.examinationReports.map { report in
            SparkMedicalSyncAPI.UploadExaminationReport(
                id: report.id,
                member: report.memberID,
                medicalRecord: report.medicalRecordID,
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
                rawOCR: report.rawOCR,
                status: report.status,
                extra: report.extra
            )
        }
        let healthExamReports = snapshot.healthExamReports.map { report in
            SparkMedicalSyncAPI.UploadHealthExamReport(
                id: report.id,
                member: report.memberID,
                institutionName: report.institutionName,
                reportNo: report.reportNo,
                examDate: report.examDate,
                examType: report.examType,
                summary: report.summary,
                source: report.source,
                rawOCR: report.rawOCR,
                status: report.status,
                extra: report.extra
            )
        }
        let medExamDetails = snapshot.medExamDetails.map { row in
            SparkMedicalSyncAPI.UploadMedExamDetail(
                id: row.id,
                businessType: row.businessType,
                businessID: row.businessID,
                member: row.memberID,
                category: row.category,
                subCategory: row.subCategory,
                itemName: row.itemName,
                itemCode: row.itemCode,
                resultValue: row.resultValue,
                unit: row.unit,
                referenceRange: row.referenceRange,
                flag: row.flag,
                resultAt: row.resultAt,
                modality: row.modality,
                bodyPart: row.bodyPart,
                diagnosis: row.diagnosis,
                extra: row.extra,
                sortOrder: row.sortOrder
            )
        }

        let medicalReports = snapshot.medicalReports.map { report in
            SparkMedicalSyncAPI.UploadMedicalReport(
                id: report.id,
                member: report.memberID,
                medicalCase: report.medicalCaseID,
                reportType: report.reportType,
                title: report.title,
                hospital: report.hospital,
                doctor: report.doctor,
                content: report.content,
                date: report.date
            )
        }

        let prescriptionBatches = snapshot.prescriptionBatches.map { row in
            SparkMedicalSyncAPI.UploadPrescriptionBatch(
                id: row.id,
                member: row.memberID,
                medicalCase: row.medicalCaseID,
                prescriberName: row.prescriberName,
                institutionName: row.institutionName,
                prescribedAt: row.prescribedAt,
                diagnosis: row.diagnosis,
                batchNo: row.batchNo,
                status: row.status,
                auditorName: row.auditorName,
                auditedAt: row.auditedAt,
                extra: row.extra
            )
        }
        let medications = snapshot.medications.map { row in
            SparkMedicalSyncAPI.UploadMedication(
                id: row.id,
                member: row.memberID,
                batch: row.batchID,
                genericName: row.genericName,
                brandName: row.brandName,
                drugName: row.drugName,
                dosageForm: row.dosageForm,
                strength: row.strength,
                route: row.route,
                dosePerTime: row.dosePerTime,
                doseValue: row.doseValue,
                doseUnit: row.doseUnit,
                frequencyCode: row.frequencyCode,
                period: row.period,
                timesPerPeriod: row.timesPerPeriod,
                frequencyText: row.frequencyText,
                durationDays: row.durationDays,
                instructions: row.instructions,
                reminderEnabled: row.reminderEnabled,
                reminderTimes: row.reminderTimes,
                sortOrder: row.sortOrder,
                extra: row.extra
            )
        }
        let medicationTakenRecords = snapshot.medicationTakenRecords.map { row in
            SparkMedicalSyncAPI.UploadMedicationTakenRecord(
                id: row.id,
                member: row.memberID,
                medication: row.medicationID,
                scheduledAt: row.scheduledAt,
                takenAt: row.takenAt,
                status: row.status,
                doseSequence: row.doseSequence,
                actualDose: row.actualDose,
                timezone: row.timezone,
                notes: row.notes,
                extra: row.extra
            )
        }
        let healthMetrics = snapshot.healthMetrics.map { metric in
            SparkMedicalSyncAPI.UploadHealthMetric(
                id: nil,
                profileClientUID: metric.profileID,
                metricType: metric.type.rawValue,
                value: metric.value,
                unit: metric.unit,
                recordedAt: metric.recordedAt,
                note: metric.note,
                updatedAt: metric.updatedAt
            )
        }

        return SparkMedicalSyncAPI.UploadSnapshotPayload(
            members: members,
            medicalCases: cases,
            symptoms: symptoms,
            visits: visits,
            surgeries: surgeries,
            followUps: followUps,
            healthExamReports: healthExamReports,
            examinationReports: examReports,
            medExamDetails: medExamDetails,
            medicalReports: medicalReports,
            prescriptionBatches: prescriptionBatches,
            medications: medications,
            medicationTakenRecords: medicationTakenRecords,
            healthMetrics: healthMetrics
        )
    }

    private func makeLocalSnapshot(from payload: SparkMedicalSyncAPI.RemoteSnapshotPayload) -> MedicalDataSnapshot {
        let members = payload.members.map { member in
            Member(
                id: member.id,
                name: member.name,
                gender: member.gender,
                relationship: member.relationship,
                birthDate: member.birthDate,
                bloodType: member.bloodType,
                allergies: member.allergies,
                chronicConditions: member.chronicConditions,
                notes: member.notes,
                avatarUrl: member.avatarUrl,
                isPrimary: member.isPrimary,
                updatedAt: member.updatedAt
            )
        }

        let medicalCases = payload.medicalCases.compactMap { medicalCase -> MedicalCase? in
            guard members.contains(where: { $0.id == medicalCase.member }) else { return nil }
            return MedicalCase(
                id: medicalCase.id,
                memberID: medicalCase.member,
                recordType: medicalCase.recordType,
                status: medicalCase.status,
                title: medicalCase.title,
                hospitalName: medicalCase.hospitalName,
                ageAtVisit: medicalCase.ageAtVisit,
                diagnosisSummary: medicalCase.diagnosisSummary,
                extra: medicalCase.extra ?? [:],
                updatedAt: medicalCase.updatedAt
            )
        }
        let validCaseIDs = Set(medicalCases.map(\.id))
        let symptoms = payload.symptoms.compactMap { row -> Symptom? in
            guard members.contains(where: { $0.id == row.member }), validCaseIDs.contains(row.medicalCase) else { return nil }
            return Symptom(
                id: row.id,
                memberID: row.member,
                medicalCaseID: row.medicalCase,
                name: row.name,
                code: row.code,
                severity: row.severity,
                startedAt: row.startedAt,
                durationValue: row.durationValue,
                durationUnit: row.durationUnit,
                bodyPart: row.bodyPart,
                notes: row.notes,
                extra: row.extra ?? [:],
                updatedAt: row.updatedAt
            )
        }
        let visits = payload.visits.compactMap { row -> Visit? in
            guard members.contains(where: { $0.id == row.member }), validCaseIDs.contains(row.medicalCase) else { return nil }
            return Visit(
                id: row.id,
                memberID: row.member,
                medicalCaseID: row.medicalCase,
                visitType: row.visitType,
                visitedAt: row.visitedAt,
                department: row.department,
                doctorName: row.doctorName,
                visitNo: row.visitNo,
                sourceSystemID: row.sourceSystemID,
                notes: row.notes,
                extra: row.extra ?? [:],
                updatedAt: row.updatedAt
            )
        }
        let surgeries = payload.surgeries.compactMap { row -> Surgery? in
            guard members.contains(where: { $0.id == row.member }), validCaseIDs.contains(row.medicalCase) else { return nil }
            return Surgery(
                id: row.id,
                memberID: row.member,
                medicalCaseID: row.medicalCase,
                procedureName: row.procedureName,
                procedureCode: row.procedureCode,
                site: row.site,
                performedAt: row.performedAt,
                surgeon: row.surgeon,
                anesthesiaType: row.anesthesiaType,
                incisionLevel: row.incisionLevel,
                asaClass: row.asaClass,
                sourceSystemID: row.sourceSystemID,
                notes: row.notes,
                extra: row.extra ?? [:],
                updatedAt: row.updatedAt
            )
        }
        let followUps = payload.followUps.compactMap { row -> FollowUp? in
            guard members.contains(where: { $0.id == row.member }), validCaseIDs.contains(row.medicalCase) else { return nil }
            return FollowUp(
                id: row.id,
                memberID: row.member,
                medicalCaseID: row.medicalCase,
                plannedAt: row.plannedAt,
                completedAt: row.completedAt,
                status: row.status,
                method: row.method,
                outcome: row.outcome,
                nextAction: row.nextAction,
                extra: row.extra ?? [:],
                updatedAt: row.updatedAt
            )
        }
        if symptoms.count != payload.symptoms.count
            || visits.count != payload.visits.count
            || surgeries.count != payload.surgeries.count
            || followUps.count != payload.followUps.count {
            logger.warning(
                "病历叙事快照存在关联不完整数据，已过滤。symptoms=\(symptoms.count)/\(payload.symptoms.count), visits=\(visits.count)/\(payload.visits.count), surgeries=\(surgeries.count)/\(payload.surgeries.count), followUps=\(followUps.count)/\(payload.followUps.count)",
                category: "medical_sync"
            )
        }
        let examinationReports = payload.examinationReports.compactMap { report -> ExaminationReport? in
            guard members.contains(where: { $0.id == report.member }) else { return nil }
            return ExaminationReport(
                id: report.id,
                memberID: report.member,
                medicalRecordID: report.medicalRecord,
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
                rawOCR: report.rawOCR,
                status: report.status,
                extra: report.extra,
                updatedAt: report.updatedAt
            )
        }
        let healthExamReports = payload.healthExamReports.compactMap { report -> HealthExamReport? in
            guard members.contains(where: { $0.id == report.member }) else { return nil }
            return HealthExamReport(
                id: report.id,
                memberID: report.member,
                institutionName: report.institutionName,
                reportNo: report.reportNo,
                examDate: report.examDate,
                examType: report.examType,
                summary: report.summary,
                source: report.source,
                rawOCR: report.rawOCR,
                status: report.status,
                extra: report.extra,
                updatedAt: report.updatedAt
            )
        }
        let medExamDetails = payload.medExamDetails.compactMap { row -> MedExamDetail? in
            guard members.contains(where: { $0.id == row.member }) else { return nil }
            return MedExamDetail(
                id: row.id,
                businessType: row.businessType,
                businessID: row.businessID,
                memberID: row.member,
                category: row.category,
                subCategory: row.subCategory,
                itemName: row.itemName,
                itemCode: row.itemCode,
                resultValue: row.resultValue,
                unit: row.unit,
                referenceRange: row.referenceRange,
                flag: row.flag,
                resultAt: row.resultAt,
                modality: row.modality,
                bodyPart: row.bodyPart,
                diagnosis: row.diagnosis,
                extra: row.extra,
                sortOrder: row.sortOrder,
                updatedAt: row.updatedAt
            )
        }

        let medicalReports = payload.medicalReports.compactMap { report -> MedicalReport? in
            guard members.contains(where: { $0.id == report.member }) else { return nil }
            return MedicalReport(
                id: report.id,
                memberID: report.member,
                medicalCaseID: report.medicalCase,
                reportType: report.reportType,
                title: report.title,
                hospital: report.hospital,
                doctor: report.doctor,
                content: report.content,
                date: report.date,
                updatedAt: report.updatedAt
            )
        }

        let prescriptionBatches = payload.prescriptionBatches.compactMap { row -> PrescriptionBatch? in
            guard members.contains(where: { $0.id == row.member }) else { return nil }
            return PrescriptionBatch(
                id: row.id,
                memberID: row.member,
                medicalCaseID: row.medicalCase,
                prescriberName: row.prescriberName,
                institutionName: row.institutionName,
                prescribedAt: row.prescribedAt,
                diagnosis: row.diagnosis,
                batchNo: row.batchNo,
                status: row.status,
                auditorName: row.auditorName,
                auditedAt: row.auditedAt,
                extra: row.extra ?? [:],
                updatedAt: row.updatedAt
            )
        }
        let validBatchIDs = Set(prescriptionBatches.map(\.id))
        let medications = payload.medications.compactMap { row -> Medication? in
            guard members.contains(where: { $0.id == row.member }), validBatchIDs.contains(row.batch) else { return nil }
            return Medication(
                id: row.id,
                memberID: row.member,
                batchID: row.batch,
                genericName: row.genericName,
                brandName: row.brandName,
                drugName: row.drugName,
                dosageForm: row.dosageForm,
                strength: row.strength,
                route: row.route,
                dosePerTime: row.dosePerTime,
                doseValue: row.doseValue,
                doseUnit: row.doseUnit,
                frequencyCode: row.frequencyCode,
                period: row.period,
                timesPerPeriod: row.timesPerPeriod,
                frequencyText: row.frequencyText,
                durationDays: row.durationDays,
                instructions: row.instructions,
                reminderEnabled: row.reminderEnabled,
                reminderTimes: row.reminderTimes,
                sortOrder: row.sortOrder,
                extra: row.extra ?? [:],
                updatedAt: row.updatedAt
            )
        }
        let validMedicationIDs = Set(medications.map(\.id))
        let medicationTakenRecords = payload.medicationTakenRecords.compactMap { row -> MedicationTakenRecord? in
            guard members.contains(where: { $0.id == row.member }), validMedicationIDs.contains(row.medication) else { return nil }
            return MedicationTakenRecord(
                id: row.id,
                memberID: row.member,
                medicationID: row.medication,
                scheduledAt: row.scheduledAt,
                takenAt: row.takenAt,
                status: row.status,
                doseSequence: row.doseSequence,
                actualDose: row.actualDose,
                timezone: row.timezone,
                notes: row.notes,
                extra: row.extra ?? [:],
                updatedAt: row.updatedAt
            )
        }
        let healthMetrics = payload.healthMetrics.map { metric in
            SyncedHealthMetric(
                id: UUID(),
                profileID: metric.profileClientUID,
                type: HealthMetricType(rawValue: metric.metricType) ?? .steps,
                value: metric.value,
                unit: metric.unit,
                recordedAt: metric.recordedAt,
                note: metric.note,
                updatedAt: metric.updatedAt
            )
        }

        return MedicalDataSnapshot(
            members: members,
            medicalCases: medicalCases,
            symptoms: symptoms,
            visits: visits,
            surgeries: surgeries,
            followUps: followUps,
            healthExamReports: healthExamReports,
            examinationReports: examinationReports,
            medExamDetails: medExamDetails,
            medicalReports: medicalReports,
            prescriptionBatches: prescriptionBatches,
            medications: medications,
            medicationTakenRecords: medicationTakenRecords,
            healthMetrics: healthMetrics,
            updatedAt: Date()
        )
    }
}
