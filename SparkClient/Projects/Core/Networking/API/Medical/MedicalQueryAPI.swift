import Foundation

/// 医疗按需查询 API：替代快照全量拉取，按资源请求并利用 ETag。
struct SparkMedicalQueryAPI: @unchecked Sendable {
    /// 统一后端配置（网络引擎、鉴权、ETag 存储与日志）。
    let configuration: SparkBackendConfiguration

    private let resources: SparkMedicalWorkflowAPI

    /// 医疗资源工作流 API（创建/更新/按 id 查询等）。
    var medicalWorkflowAPI: SparkMedicalWorkflowAPI { resources }

    /// 通过应用层注入网络配置。
    init(configuration: SparkBackendConfiguration) {
        self.configuration = configuration
        self.resources = SparkMedicalWorkflowAPI(configuration: configuration)
    }

    /// 查询成员列表。
    ///
    /// - Returns: 当前账号下所有成员。
    /// - Note: 此接口不带 member 过滤参数。
    func listMembers() async throws -> [SparkMedicalSyncAPI.RemoteMember] {
        try await resources.list([SparkMedicalSyncAPI.RemoteMember].self, kind: .members)
    }

    /// 查询病历主档（按成员可选过滤）。
    func listMedicalCases(memberID: Int? = nil) async throws -> [SparkMedicalSyncAPI.RemoteMedicalCase] {
        try await resources.list([SparkMedicalSyncAPI.RemoteMedicalCase].self, kind: .cases, query: memberQuery(memberID))
    }

    /// 查询病历列表摘要（含列表展示所需附件/症状/用药字段）。
    func listMedicalCaseSummaries(memberID: Int? = nil) async throws -> [SparkMedicalSyncAPI.RemoteMedicalCaseSummary] {
        try await resources.list([SparkMedicalSyncAPI.RemoteMedicalCaseSummary].self, kind: .cases, query: memberQuery(memberID))
    }

    /// 查询症状（按成员、病历可选过滤）。
    func listSymptoms(memberID: Int? = nil, medicalCaseID: Int? = nil) async throws -> [SparkMedicalSyncAPI.RemoteSymptom] {
        try await resources.list(
            [SparkMedicalSyncAPI.RemoteSymptom].self,
            kind: .symptoms,
            query: memberAndCaseQuery(memberID: memberID, medicalCaseID: medicalCaseID)
        )
    }

    /// 查询就诊记录（按成员、病历可选过滤）。
    func listVisits(memberID: Int? = nil, medicalCaseID: Int? = nil) async throws -> [SparkMedicalSyncAPI.RemoteVisit] {
        try await resources.list(
            [SparkMedicalSyncAPI.RemoteVisit].self,
            kind: .visits,
            query: memberAndCaseQuery(memberID: memberID, medicalCaseID: medicalCaseID)
        )
    }

    /// 查询手术记录（按成员、病历可选过滤）。
    func listSurgeries(memberID: Int? = nil, medicalCaseID: Int? = nil) async throws -> [SparkMedicalSyncAPI.RemoteSurgery] {
        try await resources.list(
            [SparkMedicalSyncAPI.RemoteSurgery].self,
            kind: .surgeries,
            query: memberAndCaseQuery(memberID: memberID, medicalCaseID: medicalCaseID)
        )
    }

    /// 查询随访记录（按成员、病历可选过滤）。
    func listFollowUps(memberID: Int? = nil, medicalCaseID: Int? = nil) async throws -> [SparkMedicalSyncAPI.RemoteFollowUp] {
        try await resources.list(
            [SparkMedicalSyncAPI.RemoteFollowUp].self,
            kind: .followUps,
            query: memberAndCaseQuery(memberID: memberID, medicalCaseID: medicalCaseID)
        )
    }

    /// 查询体检报告（按成员可选过滤）。
    func listHealthExamReports(memberID: Int? = nil) async throws -> [SparkMedicalSyncAPI.RemoteHealthExamReport] {
        try await resources.list([SparkMedicalSyncAPI.RemoteHealthExamReport].self, kind: .healthExamReports, query: memberQuery(memberID))
    }

    /// 查询体检报告列表摘要（含附件；明细仍由列表页懒加载）。
    func listHealthExamReportsWithAttachments(memberID: Int? = nil) async throws -> [SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments] {
        try await resources.list([SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments].self, kind: .healthExamReports, query: memberQuery(memberID))
    }

    /// 查询检查报告（按成员可选过滤）。
    func listExaminationReports(memberID: Int? = nil) async throws -> [SparkMedicalSyncAPI.RemoteExaminationReport] {
        try await resources.list([SparkMedicalSyncAPI.RemoteExaminationReport].self, kind: .examinationReports, query: memberQuery(memberID))
    }

    /// 查询检查报告列表摘要（含附件；明细仍由列表页懒加载）。
    func listExaminationReportsWithAttachments(memberID: Int? = nil) async throws -> [SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments] {
        try await resources.list([SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments].self, kind: .examinationReports, query: memberQuery(memberID))
    }

    /// 查询体检/检查明细（按成员及业务维度可选过滤）。
    func listMedExamDetails(
        memberID: Int? = nil,
        businessType: String? = nil,
        businessID: Int? = nil
    ) async throws -> [SparkMedicalSyncAPI.RemoteMedExamDetail] {
        var q: [URLQueryItem] = memberQuery(memberID)
        if let businessType {
            q.append(URLQueryItem(name: "business_type", value: businessType))
        }
        if let businessID {
            q.append(URLQueryItem(name: "business_id", value: "\(businessID)"))
        }
        return try await resources.list([SparkMedicalSyncAPI.RemoteMedExamDetail].self, kind: .medExamDetails, query: q)
    }

    /// 家庭药箱汇总：按入口成员 ID 返回其创建者名下全部成员药品与公共药品。
    func listFamilyMedicineCabinet(memberID: Int) async throws -> [SparkMedicalSyncAPI.RemoteMedicineBox] {
        try await request(
            path: "/api/v1/medical/medicine-cabinet/summary/",
            query: [URLQueryItem(name: "member_id", value: "\(memberID)")],
            responseType: [SparkMedicalSyncAPI.RemoteMedicineBox].self,
            etagTTL: 120
        )
    }

    /// 查询药箱库存（按成员可选过滤）。
    func listMedicineBoxes(
        memberID: Int? = nil,
        medicineType: String? = nil,
        expireBefore: Date? = nil,
        lowStock: Bool? = nil
    ) async throws -> [SparkMedicalSyncAPI.RemoteMedicineBox] {
        var q: [URLQueryItem] = memberQuery(memberID)
        if let medicineType {
            q.append(URLQueryItem(name: "medicine_type", value: medicineType))
        }
        if let expireBefore {
            q.append(URLQueryItem(name: "expire_before", value: MedicalDateCoding.encodeDateOnly(expireBefore)))
        }
        if let lowStock {
            q.append(URLQueryItem(name: "low_stock", value: lowStock ? "true" : "false"))
        }
        return try await resources.list([SparkMedicalSyncAPI.RemoteMedicineBox].self, kind: .medicineBoxes, query: q)
    }

    /// 查询处方（按成员、状态可选过滤）。
    func listPrescriptions(memberID: Int? = nil, medicalCaseID: Int? = nil, status: String? = nil) async throws -> [SparkMedicalSyncAPI.RemotePrescription] {
        var q: [URLQueryItem] = memberQuery(memberID)
        if let medicalCaseID {
            q.append(URLQueryItem(name: "medical_case_id", value: "\(medicalCaseID)"))
        }
        if let status {
            q.append(URLQueryItem(name: "status", value: status))
        }
        return try await resources.list([SparkMedicalSyncAPI.RemotePrescription].self, kind: .prescriptions, query: q)
    }

    /// 查询服药计划（按成员、药箱、处方、状态可选过滤）。
    func listMedicationPlans(
        memberID: Int? = nil,
        medicalCaseID: Int? = nil,
        medicineBoxID: Int? = nil,
        prescriptionID: Int? = nil,
        status: String? = nil
    ) async throws -> [SparkMedicalSyncAPI.RemoteMedicationPlan] {
        var q: [URLQueryItem] = memberQuery(memberID)
        if let medicalCaseID {
            q.append(URLQueryItem(name: "medical_case_id", value: "\(medicalCaseID)"))
        }
        if let medicineBoxID {
            q.append(URLQueryItem(name: "medicine_box_id", value: "\(medicineBoxID)"))
        }
        if let prescriptionID {
            q.append(URLQueryItem(name: "prescription_id", value: "\(prescriptionID)"))
        }
        if let status {
            q.append(URLQueryItem(name: "status", value: status))
        }
        return try await resources.list([SparkMedicalSyncAPI.RemoteMedicationPlan].self, kind: .medicationPlans, query: q)
    }

    /// 查询服药记录（按成员、计划、状态、计划时间窗口可选过滤）。
    func listMedicationRecords(
        memberID: Int? = nil,
        planID: Int? = nil,
        status: String? = nil,
        scheduledFrom: Date? = nil,
        scheduledTo: Date? = nil
    ) async throws -> [SparkMedicalSyncAPI.RemoteMedicationRecord] {
        var q: [URLQueryItem] = memberQuery(memberID)
        if let planID {
            q.append(URLQueryItem(name: "plan_id", value: "\(planID)"))
        }
        if let status {
            q.append(URLQueryItem(name: "status", value: status))
        }
        if let scheduledFrom {
            q.append(URLQueryItem(name: "scheduled_from", value: MedicalDateCoding.encodeISO8601(scheduledFrom)))
        }
        if let scheduledTo {
            q.append(URLQueryItem(name: "scheduled_to", value: MedicalDateCoding.encodeISO8601(scheduledTo)))
        }
        return try await resources.list([SparkMedicalSyncAPI.RemoteMedicationRecord].self, kind: .medicationRecords, query: q)
    }

    func retrieveExaminationReport(id: Int) async throws -> SparkMedicalSyncAPI.RemoteExaminationReport {
        try await resources.retrieve(SparkMedicalSyncAPI.RemoteExaminationReport.self, kind: .examinationReports, id: id)
    }

    func retrieveExaminationReportWithAttachments(
        id: Int
    ) async throws -> SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments {
        try await resources.retrieve(
            SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments.self,
            kind: .examinationReports,
            id: id
        )
    }

    func retrieveHealthExamReport(id: Int) async throws -> SparkMedicalSyncAPI.RemoteHealthExamReport {
        try await resources.retrieve(SparkMedicalSyncAPI.RemoteHealthExamReport.self, kind: .healthExamReports, id: id)
    }

    func retrieveHealthExamReportWithAttachments(
        id: Int
    ) async throws -> SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments {
        try await resources.retrieve(
            SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments.self,
            kind: .healthExamReports,
            id: id
        )
    }

    func retrieveMedicalCase(id: Int) async throws -> SparkMedicalSyncAPI.RemoteMedicalCase {
        try await resources.retrieve(SparkMedicalSyncAPI.RemoteMedicalCase.self, kind: .cases, id: id)
    }

    func retrievePrescription(id: Int) async throws -> SparkMedicalSyncAPI.RemotePrescription {
        try await resources.retrieve(SparkMedicalSyncAPI.RemotePrescription.self, kind: .prescriptions, id: id)
    }

    func retrieveMedicationPlan(id: Int) async throws -> SparkMedicalSyncAPI.RemoteMedicationPlan {
        try await resources.retrieve(SparkMedicalSyncAPI.RemoteMedicationPlan.self, kind: .medicationPlans, id: id)
    }

    func retrieveMedicineBox(id: Int) async throws -> SparkMedicalSyncAPI.RemoteMedicineBox {
        try await resources.retrieve(SparkMedicalSyncAPI.RemoteMedicineBox.self, kind: .medicineBoxes, id: id)
    }

    func retrieveMedicationRecord(id: Int) async throws -> SparkMedicalSyncAPI.RemoteMedicationRecord {
        try await resources.retrieve(SparkMedicalSyncAPI.RemoteMedicationRecord.self, kind: .medicationRecords, id: id)
    }

    func retrieveSymptom(id: Int) async throws -> SparkMedicalSyncAPI.RemoteSymptom {
        try await resources.retrieve(SparkMedicalSyncAPI.RemoteSymptom.self, kind: .symptoms, id: id)
    }

    func retrieveVisit(id: Int) async throws -> SparkMedicalSyncAPI.RemoteVisit {
        try await resources.retrieve(SparkMedicalSyncAPI.RemoteVisit.self, kind: .visits, id: id)
    }

    func retrieveSurgery(id: Int) async throws -> SparkMedicalSyncAPI.RemoteSurgery {
        try await resources.retrieve(SparkMedicalSyncAPI.RemoteSurgery.self, kind: .surgeries, id: id)
    }

    func retrieveFollowUp(id: Int) async throws -> SparkMedicalSyncAPI.RemoteFollowUp {
        try await resources.retrieve(SparkMedicalSyncAPI.RemoteFollowUp.self, kind: .followUps, id: id)
    }

    /// 按成员单接口拉取医疗数据汇总（病例汇总 / 报告头 / 处方与附件）。
    func fetchMemberCompleteData(memberID: Int) async throws -> SparkMedicalSyncAPI.RemoteMemberCompleteData {
        try await request(
            path: "/api/v1/medical/members/\(memberID)/complete-data/",
            responseType: SparkMedicalSyncAPI.RemoteMemberCompleteData.self,
            etagTTL: 86400
        )
    }

    private func memberQuery(_ memberID: Int?) -> [URLQueryItem] {
        memberID.map { [URLQueryItem(name: "member_id", value: "\($0)")] } ?? []
    }

    private func memberAndCaseQuery(memberID: Int?, medicalCaseID: Int?) -> [URLQueryItem] {
        var q = memberQuery(memberID)
        if let medicalCaseID {
            q.append(URLQueryItem(name: "medical_case_id", value: "\(medicalCaseID)"))
        }
        return q
    }

    /// 摘要等非统一资源路径仍走直连 GET。
    private func request<T: Decodable>(
        path: String,
        query: [URLQueryItem] = [],
        responseType: T.Type,
        etagTTL: TimeInterval = 120
    ) async throws -> T {
        let operation = CacheableSparkNetworkOperation(
            name: "Medical.Query.\(path)",
            apiName: "MedicalQueryAPI",
            request: SparkNetworkRequest(
                method: .get,
                path: path,
                queryItems: query,
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: true,
                    serialKey: "medical.query.\(path)",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .normal,
                    etagTTL: etagTTL
                )
            )
        )
        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedData(responseType, from: response, decoder: .medicalAPI)
    }
}
