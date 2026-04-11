import Foundation

/// 医疗按需查询 API：替代快照全量拉取，按资源请求并利用 ETag。
struct SparkMedicalQueryAPI {
    /// 统一后端配置（网络引擎、鉴权、ETag 存储与日志）。
    let configuration: SparkBackendConfiguration

    private let resources: SparkMedicalResourceAPI

    /// 通过应用层注入网络配置。
    init(configuration: SparkBackendConfiguration) {
        self.configuration = configuration
        self.resources = SparkMedicalResourceAPI(configuration: configuration)
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

    /// 查询检查报告（按成员可选过滤）。
    func listExaminationReports(memberID: Int? = nil) async throws -> [SparkMedicalSyncAPI.RemoteExaminationReport] {
        try await resources.list([SparkMedicalSyncAPI.RemoteExaminationReport].self, kind: .examinationReports, query: memberQuery(memberID))
    }

    /// 查询处方批次（按成员、病历可选过滤）。
    func listPrescriptionBatches(memberID: Int? = nil, medicalCaseID: Int? = nil) async throws -> [SparkMedicalSyncAPI.RemotePrescriptionBatch] {
        try await resources.list(
            [SparkMedicalSyncAPI.RemotePrescriptionBatch].self,
            kind: .prescriptionBatches,
            query: memberAndCaseQuery(memberID: memberID, medicalCaseID: medicalCaseID)
        )
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

    /// 查询用药（按成员、批次可选过滤）。
    func listMedications(memberID: Int? = nil, batchID: Int? = nil) async throws -> [SparkMedicalSyncAPI.RemoteMedication] {
        var q: [URLQueryItem] = memberQuery(memberID)
        if let batchID {
            q.append(URLQueryItem(name: "batch_id", value: "\(batchID)"))
        }
        return try await resources.list([SparkMedicalSyncAPI.RemoteMedication].self, kind: .medications, query: q)
    }

    /// 查询服药打卡记录（按成员、药品可选过滤）。
    func listMedicationTakenRecords(memberID: Int? = nil, medicationID: Int? = nil) async throws -> [SparkMedicalSyncAPI.RemoteMedicationTakenRecord] {
        var q: [URLQueryItem] = memberQuery(memberID)
        if let medicationID {
            q.append(URLQueryItem(name: "medication_id", value: "\(medicationID)"))
        }
        return try await resources.list([SparkMedicalSyncAPI.RemoteMedicationTakenRecord].self, kind: .medicationTakenRecords, query: q)
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
        return try APIResponseDecoder.decodeWrappedData(responseType, from: response, decoder: .sparkISO8601)
    }
}

private extension JSONDecoder {
    /// 医疗接口专用解码器：统一日期容错策略，减少模型层分支。
    static let sparkISO8601: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(MedicalDateCoding.decodeFlexibleDate(from:))
        return decoder
    }()
}
