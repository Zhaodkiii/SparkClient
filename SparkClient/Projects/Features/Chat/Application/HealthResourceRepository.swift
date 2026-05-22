import Foundation

/// 按 `HealthResourceIdentity` 加载 complete-data 切片、单资源详情与报告明细（仅数据访问）。
struct HealthResourceRepository {
    let medicalQueryAPI: SparkMedicalQueryAPI

    init(medicalQueryAPI: SparkMedicalQueryAPI) {
        self.medicalQueryAPI = medicalQueryAPI
    }

    func fetchMemberCompleteData(memberID: Int) async -> Result<SparkMedicalSyncAPI.RemoteMemberCompleteData, HealthResourceLoadError> {
        do {
            return .success(try await medicalQueryAPI.fetchMemberCompleteData(memberID: memberID))
        } catch {
            return .failure(HealthResourceLoadError.map(error))
        }
    }

    func loadMedExamDetails(
        memberID: Int,
        businessID: Int,
        businessType: String? = nil
    ) async -> Result<[SparkMedicalSyncAPI.RemoteMedExamDetail], HealthResourceLoadError> {
        do {
            return .success(try await medicalQueryAPI.listMedExamDetails(
                memberID: memberID,
                businessType: businessType,
                businessID: businessID
            ))
        } catch {
            return .failure(HealthResourceLoadError.map(error))
        }
    }

    func retrieveExaminationReport(id: Int) async -> Result<SparkMedicalSyncAPI.RemoteExaminationReport, HealthResourceLoadError> {
        await fetch { try await medicalQueryAPI.retrieveExaminationReport(id: id) }
    }

    func retrieveExaminationReportWithAttachments(
        id: Int
    ) async -> Result<SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments, HealthResourceLoadError> {
        await fetch { try await medicalQueryAPI.retrieveExaminationReportWithAttachments(id: id) }
    }

    func retrieveHealthExamReport(id: Int) async -> Result<SparkMedicalSyncAPI.RemoteHealthExamReport, HealthResourceLoadError> {
        await fetch { try await medicalQueryAPI.retrieveHealthExamReport(id: id) }
    }

    func retrieveHealthExamReportWithAttachments(
        id: Int
    ) async -> Result<SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments, HealthResourceLoadError> {
        await fetch { try await medicalQueryAPI.retrieveHealthExamReportWithAttachments(id: id) }
    }

    func retrieveMedicalCase(id: Int) async -> Result<SparkMedicalSyncAPI.RemoteMedicalCase, HealthResourceLoadError> {
        await fetch { try await medicalQueryAPI.retrieveMedicalCase(id: id) }
    }

    func retrievePrescription(id: Int) async -> Result<SparkMedicalSyncAPI.RemotePrescription, HealthResourceLoadError> {
        await fetch { try await medicalQueryAPI.retrievePrescription(id: id) }
    }

    func retrieveMedicationPlan(id: Int) async -> Result<SparkMedicalSyncAPI.RemoteMedicationPlan, HealthResourceLoadError> {
        await fetch { try await medicalQueryAPI.retrieveMedicationPlan(id: id) }
    }

    func retrieveMedicineBox(id: Int) async -> Result<SparkMedicalSyncAPI.RemoteMedicineBox, HealthResourceLoadError> {
        await fetch { try await medicalQueryAPI.retrieveMedicineBox(id: id) }
    }

    func retrieveMedicationRecord(id: Int) async -> Result<SparkMedicalSyncAPI.RemoteMedicationRecord, HealthResourceLoadError> {
        await fetch { try await medicalQueryAPI.retrieveMedicationRecord(id: id) }
    }

    func retrieveSymptom(id: Int) async -> Result<SparkMedicalSyncAPI.RemoteSymptom, HealthResourceLoadError> {
        await fetch { try await medicalQueryAPI.retrieveSymptom(id: id) }
    }

    func retrieveVisit(id: Int) async -> Result<SparkMedicalSyncAPI.RemoteVisit, HealthResourceLoadError> {
        await fetch { try await medicalQueryAPI.retrieveVisit(id: id) }
    }

    func retrieveSurgery(id: Int) async -> Result<SparkMedicalSyncAPI.RemoteSurgery, HealthResourceLoadError> {
        await fetch { try await medicalQueryAPI.retrieveSurgery(id: id) }
    }

    func retrieveFollowUp(id: Int) async -> Result<SparkMedicalSyncAPI.RemoteFollowUp, HealthResourceLoadError> {
        await fetch { try await medicalQueryAPI.retrieveFollowUp(id: id) }
    }

    func listMedicineBoxes(memberID: Int) async -> Result<[SparkMedicalSyncAPI.RemoteMedicineBox], HealthResourceLoadError> {
        await fetch { try await medicalQueryAPI.listMedicineBoxes(memberID: memberID) }
    }

    func listMedicationPlans(
        memberID: Int,
        prescriptionID: Int? = nil
    ) async -> Result<[SparkMedicalSyncAPI.RemoteMedicationPlan], HealthResourceLoadError> {
        await fetch { try await medicalQueryAPI.listMedicationPlans(memberID: memberID, prescriptionID: prescriptionID) }
    }

    func listMedicationRecords(
        memberID: Int,
        planID: Int? = nil
    ) async -> Result<[SparkMedicalSyncAPI.RemoteMedicationRecord], HealthResourceLoadError> {
        await fetch { try await medicalQueryAPI.listMedicationRecords(memberID: memberID, planID: planID) }
    }

    private func fetch<T>(
        _ operation: () async throws -> T
    ) async -> Result<T, HealthResourceLoadError> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(HealthResourceLoadError.map(error))
        }
    }
}
