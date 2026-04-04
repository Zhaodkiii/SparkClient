import Foundation

final class DefaultMedicalDataRepository: MedicalDataRepository, @unchecked Sendable {
    private let snapshotStore: CoreDataMedicalSnapshotStore
    private let healthMetricsStore: HealthMetricsSyncStore
    private let remoteAPI: SparkMedicalSyncAPI
    private let logger: Logger

    init(
        snapshotStore: CoreDataMedicalSnapshotStore,
        healthMetricsStore: HealthMetricsSyncStore,
        remoteAPI: SparkMedicalSyncAPI,
        logger: Logger = ConsoleLogger()
    ) {
        self.snapshotStore = snapshotStore
        self.healthMetricsStore = healthMetricsStore
        self.remoteAPI = remoteAPI
        self.logger = logger
    }

    func loadSnapshot() async -> MedicalDataSnapshot {
        let medicalSnapshot = (try? await snapshotStore.loadSnapshot()) ?? .empty
        var snapshot = medicalSnapshot
        snapshot.healthMetrics = (try? await healthMetricsStore.loadAll()) ?? []
        return snapshot
    }

    func saveSnapshot(_ snapshot: MedicalDataSnapshot) async throws {
        try await snapshotStore.saveSnapshot(snapshot)
        try await healthMetricsStore.overwriteAll(with: snapshot.healthMetrics)
    }

    func uploadSnapshotToServer(priority: CloudSyncPriority) async throws {
        var local = (try? await snapshotStore.loadSnapshot()) ?? .empty
        local.healthMetrics = (try? await healthMetricsStore.loadAll()) ?? []
        let payload = makeUploadPayload(from: local)
        try await remoteAPI.uploadSnapshot(payload, priority: priority)
        logger.info("本地健康快照已上传至服务端", category: "medical_sync")
    }

    func pullSnapshotFromServer(priority: CloudSyncPriority) async throws {
        let remote = try await remoteAPI.fetchSnapshot(priority: priority)
        let snapshot = makeLocalSnapshot(from: remote)
        try await snapshotStore.saveSnapshot(snapshot)
        try? await healthMetricsStore.overwriteAll(with: snapshot.healthMetrics)
        logger.info("远程健康快照已拉取并写入本地", category: "medical_sync")
    }

    private func makeUploadPayload(from snapshot: MedicalDataSnapshot) -> SparkMedicalSyncAPI.UploadSnapshotPayload {
        let members = snapshot.members.map { member in
            SparkMedicalSyncAPI.UploadMember(
                clientUID: member.id,
                name: member.name,
                age: member.age,
                gender: member.gender,
                relationship: member.relationship,
                avatar: member.avatar,
                birthDate: member.birthDate,
                isPrimary: member.isPrimary
            )
        }

        let cases = snapshot.medicalCases.map { medicalCase in
            SparkMedicalSyncAPI.UploadMedicalCase(
                clientUID: medicalCase.id,
                memberClientUID: medicalCase.memberID,
                title: medicalCase.title,
                chiefComplaint: medicalCase.chiefComplaint,
                diagnosis: medicalCase.diagnosis,
                severity: medicalCase.severity,
                visitDate: medicalCase.visitDate,
                status: medicalCase.status,
                notes: medicalCase.notes
            )
        }

        let examReports = snapshot.examinationReports.map { report in
            SparkMedicalSyncAPI.UploadExaminationReport(
                clientUID: report.id,
                memberClientUID: report.memberID,
                medicalCaseClientUID: report.medicalCaseID,
                category: report.category,
                subcategory: report.subcategory,
                reportName: report.reportName,
                checkType: report.checkType,
                conclusion: report.conclusion,
                doctorAdvice: report.doctorAdvice,
                date: report.date
            )
        }

        let medicalReports = snapshot.medicalReports.map { report in
            SparkMedicalSyncAPI.UploadMedicalReport(
                clientUID: report.id,
                memberClientUID: report.memberID,
                medicalCaseClientUID: report.medicalCaseID,
                reportType: report.reportType,
                title: report.title,
                hospital: report.hospital,
                doctor: report.doctor,
                content: report.content,
                date: report.date
            )
        }

        let prescriptions = snapshot.prescriptions.map { prescription in
            SparkMedicalSyncAPI.UploadPrescription(
                clientUID: prescription.id,
                memberClientUID: prescription.memberID,
                medicalCaseClientUID: prescription.medicalCaseID,
                drugName: prescription.drugName,
                dosage: prescription.dosage,
                frequency: prescription.frequency,
                durationDays: prescription.durationDays,
                instructions: prescription.instructions,
                startDate: prescription.startDate,
                endDate: prescription.endDate,
                status: prescription.status
            )
        }
        let healthMetrics = snapshot.healthMetrics.map { metric in
            SparkMedicalSyncAPI.UploadHealthMetric(
                clientUID: metric.id,
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
            examinationReports: examReports,
            medicalReports: medicalReports,
            prescriptions: prescriptions,
            healthMetrics: healthMetrics
        )
    }

    private func makeLocalSnapshot(from payload: SparkMedicalSyncAPI.RemoteSnapshotPayload) -> MedicalDataSnapshot {
        let members = payload.members.map { member in
            Member(
                id: member.clientUID,
                remoteID: member.id,
                name: member.name,
                age: member.age,
                gender: member.gender,
                relationship: member.relationship,
                avatar: member.avatar,
                birthDate: member.birthDate,
                isPrimary: member.isPrimary,
                updatedAt: member.updatedAt
            )
        }
        let memberMapping = Dictionary(uniqueKeysWithValues: members.compactMap { member -> (Int, UUID)? in
            guard let remoteID = member.remoteID else { return nil }
            return (remoteID, member.id)
        })

        let medicalCases = payload.medicalCases.compactMap { medicalCase -> MedicalCase? in
            guard let localMemberID = memberMapping[medicalCase.member] else { return nil }
            return MedicalCase(
                id: medicalCase.clientUID,
                remoteID: medicalCase.id,
                memberID: localMemberID,
                title: medicalCase.title,
                chiefComplaint: medicalCase.chiefComplaint,
                diagnosis: medicalCase.diagnosis,
                severity: medicalCase.severity,
                visitDate: medicalCase.visitDate,
                status: medicalCase.status,
                notes: medicalCase.notes,
                updatedAt: medicalCase.updatedAt
            )
        }
        let caseMapping = Dictionary(uniqueKeysWithValues: medicalCases.compactMap { item -> (Int, UUID)? in
            guard let remoteID = item.remoteID else { return nil }
            return (remoteID, item.id)
        })

        let examinationReports = payload.examinationReports.compactMap { report -> ExaminationReport? in
            guard let localMemberID = memberMapping[report.member] else { return nil }
            let localCaseID = report.medicalCase.flatMap { caseMapping[$0] }
            return ExaminationReport(
                id: report.clientUID,
                remoteID: report.id,
                memberID: localMemberID,
                medicalCaseID: localCaseID,
                category: report.category,
                subcategory: report.subcategory,
                reportName: report.reportName,
                checkType: report.checkType,
                conclusion: report.conclusion,
                doctorAdvice: report.doctorAdvice,
                date: report.date,
                updatedAt: report.updatedAt
            )
        }

        let medicalReports = payload.medicalReports.compactMap { report -> MedicalReport? in
            guard let localMemberID = memberMapping[report.member] else { return nil }
            let localCaseID = report.medicalCase.flatMap { caseMapping[$0] }
            return MedicalReport(
                id: report.clientUID,
                remoteID: report.id,
                memberID: localMemberID,
                medicalCaseID: localCaseID,
                reportType: report.reportType,
                title: report.title,
                hospital: report.hospital,
                doctor: report.doctor,
                content: report.content,
                date: report.date,
                updatedAt: report.updatedAt
            )
        }

        let prescriptions = payload.prescriptions.compactMap { prescription -> Prescription? in
            guard let localMemberID = memberMapping[prescription.member] else { return nil }
            let localCaseID = prescription.medicalCase.flatMap { caseMapping[$0] }
            return Prescription(
                id: prescription.clientUID,
                remoteID: prescription.id,
                memberID: localMemberID,
                medicalCaseID: localCaseID,
                drugName: prescription.drugName,
                dosage: prescription.dosage,
                frequency: prescription.frequency,
                durationDays: prescription.durationDays,
                instructions: prescription.instructions,
                startDate: prescription.startDate,
                endDate: prescription.endDate,
                status: prescription.status,
                updatedAt: prescription.updatedAt
            )
        }
        let healthMetrics = payload.healthMetrics.map { metric in
            SyncedHealthMetric(
                id: metric.clientUID,
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
            examinationReports: examinationReports,
            medicalReports: medicalReports,
            prescriptions: prescriptions,
            healthMetrics: healthMetrics,
            updatedAt: Date()
        )
    }
}
