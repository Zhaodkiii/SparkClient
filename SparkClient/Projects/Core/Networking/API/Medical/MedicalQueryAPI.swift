import Foundation

/// 服药记录 `scheduled_at` 区间查询，与服务端 `scheduled_from` / `scheduled_to` 对齐。
///
/// 约定：
/// - `scheduledFrom`：含下界，`scheduled_at >= scheduled_from`
/// - `scheduledToExclusive`：不含上界，`scheduled_at < scheduled_to`
struct MedicationRecordScheduledRange: Equatable, Sendable {
    let scheduledFrom: Date
    let scheduledToExclusive: Date

    init(scheduledFrom: Date, scheduledToExclusive: Date) {
        self.scheduledFrom = scheduledFrom
        self.scheduledToExclusive = scheduledToExclusive
    }
}

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

    /// 查询成员医疗维护档案。
    func listMemberMedicalProfiles(memberID: Int) async throws -> [SparkMedicalSyncAPI.RemoteMemberMedicalProfile] {
        try await resources.list(
            [SparkMedicalSyncAPI.RemoteMemberMedicalProfile].self,
            kind: .memberMedicalProfiles,
            query: memberQuery(memberID)
        )
    }

    /// 创建成员医疗维护档案。
    func createMemberMedicalProfile(_ payload: SparkMedicalWorkflowAPI.MemberMedicalProfileSavePayload) async throws -> SparkMedicalSyncAPI.RemoteMemberMedicalProfile {
        try await resources.create(
            SparkMedicalSyncAPI.RemoteMemberMedicalProfile.self,
            kind: .memberMedicalProfiles,
            body: payload
        )
    }

    /// 更新成员医疗维护档案。
    func updateMemberMedicalProfile(
        id: Int,
        payload: SparkMedicalWorkflowAPI.MemberMedicalProfileSavePayload
    ) async throws -> SparkMedicalSyncAPI.RemoteMemberMedicalProfile {
        try await resources.update(
            SparkMedicalSyncAPI.RemoteMemberMedicalProfile.self,
            kind: .memberMedicalProfiles,
            id: id,
            body: payload
        )
    }

    /// 查询成员模块配置。
    func listMemberModuleSettings(memberID: Int, moduleCode: String? = nil) async throws -> [SparkMedicalSyncAPI.RemoteMemberModuleSetting] {
        var query = memberQuery(memberID)
        if let moduleCode {
            query.append(URLQueryItem(name: "module_code", value: moduleCode))
        }
        return try await resources.list(
            [SparkMedicalSyncAPI.RemoteMemberModuleSetting].self,
            kind: .memberModuleSettings,
            query: query
        )
    }

    /// 创建成员模块配置。
    func createMemberModuleSetting(_ payload: SparkMedicalWorkflowAPI.MemberModuleSettingSavePayload) async throws -> SparkMedicalSyncAPI.RemoteMemberModuleSetting {
        try await resources.create(
            SparkMedicalSyncAPI.RemoteMemberModuleSetting.self,
            kind: .memberModuleSettings,
            body: payload
        )
    }

    /// 更新成员模块配置。
    func updateMemberModuleSetting(
        id: Int,
        payload: SparkMedicalWorkflowAPI.MemberModuleSettingSavePayload
    ) async throws -> SparkMedicalSyncAPI.RemoteMemberModuleSetting {
        try await resources.update(
            SparkMedicalSyncAPI.RemoteMemberModuleSetting.self,
            kind: .memberModuleSettings,
            id: id,
            body: payload
        )
    }

    /// 查询成员关键健康指标记录。
    func listMemberKeyIndicatorRecords(
        memberID: Int? = nil,
        dateFrom: Date? = nil,
        dateTo: Date? = nil
    ) async throws -> [SparkMedicalSyncAPI.RemoteMemberMedicalKeyIndicatorRecord] {
        var query = memberQuery(memberID)
        if let dateFrom {
            query.append(URLQueryItem(name: "date_from", value: MedicalDateCoding.encodeDateOnly(dateFrom)))
        }
        if let dateTo {
            query.append(URLQueryItem(name: "date_to", value: MedicalDateCoding.encodeDateOnly(dateTo)))
        }
        return try await resources.list(
            [SparkMedicalSyncAPI.RemoteMemberMedicalKeyIndicatorRecord].self,
            kind: .memberKeyIndicators,
            query: query
        )
    }

    /// 创建成员关键健康指标记录。
    func createMemberKeyIndicatorRecord(
        _ payload: SparkMedicalWorkflowAPI.MemberMedicalKeyIndicatorRecordSavePayload
    ) async throws -> SparkMedicalSyncAPI.RemoteMemberMedicalKeyIndicatorRecord {
        try await write(
            method: .post,
            path: "/api/v1/medical/member-key-indicators/",
            body: payload,
            responseType: SparkMedicalSyncAPI.RemoteMemberMedicalKeyIndicatorRecord.self,
            serialKey: "medical.query.member_key_indicators.create.\(payload.member)"
        )
    }

    /// 更新成员关键健康指标记录。
    func updateMemberKeyIndicatorRecord(
        id: Int,
        payload: SparkMedicalWorkflowAPI.MemberMedicalKeyIndicatorRecordSavePayload
    ) async throws -> SparkMedicalSyncAPI.RemoteMemberMedicalKeyIndicatorRecord {
        try await write(
            method: .put,
            path: "/api/v1/medical/member-key-indicators/\(id)/",
            body: payload,
            responseType: SparkMedicalSyncAPI.RemoteMemberMedicalKeyIndicatorRecord.self,
            serialKey: "medical.query.member_key_indicators.update.\(id)"
        )
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
    ///
    /// `scheduledRange` 会映射为单次区间查询：
    /// `scheduled_from = scheduledRange.scheduledFrom`，
    /// `scheduled_to = scheduledRange.scheduledToExclusive`（开区间上界）。
    func listMedicationRecords(
        memberID: Int? = nil,
        planID: Int? = nil,
        status: String? = nil,
        scheduledRange: MedicationRecordScheduledRange? = nil
    ) async throws -> [SparkMedicalSyncAPI.RemoteMedicationRecord] {
        var q: [URLQueryItem] = memberQuery(memberID)
        if let planID {
            q.append(URLQueryItem(name: "plan_id", value: "\(planID)"))
        }
        if let status {
            q.append(URLQueryItem(name: "status", value: status))
        }
        if let scheduledRange {
            q.append(
                URLQueryItem(
                    name: "scheduled_from",
                    value: MedicalDateCoding.encodeISO8601(scheduledRange.scheduledFrom)
                )
            )
            q.append(
                URLQueryItem(
                    name: "scheduled_to",
                    value: MedicalDateCoding.encodeISO8601(scheduledRange.scheduledToExclusive)
                )
            )
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

    /// 医疗引导聚合状态：基础档案、最近关键指标、模块设置、AI 计划占位。
    func loadMedicalGuidanceState(memberID: Int) async throws -> SparkMedicalSyncAPI.RemoteMedicalGuidanceState {
        try await request(
            path: "/api/v1/medical/member-guidance/",
            query: [URLQueryItem(name: "member_id", value: "\(memberID)")],
            responseType: SparkMedicalSyncAPI.RemoteMedicalGuidanceState.self,
            etagTTL: 120
        )
    }

    /// 聚合拉取当前账号可访问成员的开启提醒用药计划与窗口内记录（本地通知补全专用）。
    func listMedicationReminderEnabledPlans(
        windowStartDate: Date? = nil,
        windowEndDate: Date? = nil,
        includeRecords: Bool = true
    ) async throws -> SparkMedicalSyncAPI.RemoteMedicationReminderEnabledPlansResponse {
        var query: [URLQueryItem] = []
        if let windowStartDate {
            query.append(URLQueryItem(name: "window_start_date", value: MedicalDateCoding.encodeDateOnly(windowStartDate)))
        }
        if let windowEndDate {
            query.append(URLQueryItem(name: "window_end_date", value: MedicalDateCoding.encodeDateOnly(windowEndDate)))
        }
        query.append(URLQueryItem(name: "include_records", value: includeRecords ? "true" : "false"))
        return try await request(
            path: "/api/v1/medical/medication-reminders/enabled-plans/",
            query: query,
            responseType: SparkMedicalSyncAPI.RemoteMedicationReminderEnabledPlansResponse.self,
            etagTTL: 60
        )
    }

    /// 查询成员通知归属：是否存在其他本人绑定用户及其 APNs 能力。
    func fetchMemberNotificationOwnership(
        memberID: Int
    ) async throws -> SparkMedicalSyncAPI.RemoteMemberNotificationOwnership {
        try await request(
            path: "/api/v1/medical/members/\(memberID)/notification-ownership/",
            responseType: SparkMedicalSyncAPI.RemoteMemberNotificationOwnership.self,
            etagTTL: 60
        )
    }

    func fetchMedicationReminderLocalAuthorization(
        planID: Int
    ) async throws -> SparkMedicalSyncAPI.RemoteMedicationReminderLocalAuthorization {
        try await request(
            path: "/api/v1/medical/medication-reminders/local-authorizations/\(planID)/",
            responseType: SparkMedicalSyncAPI.RemoteMedicationReminderLocalAuthorization.self,
            etagTTL: 60
        )
    }

    func upsertMedicationReminderLocalAuthorization(
        planID: Int,
        enabled: Bool,
        source: String
    ) async throws -> SparkMedicalSyncAPI.RemoteMedicationReminderLocalAuthorization {
        nonisolated struct Payload: Encodable {
            let enabled: Bool
            let source: String
        }
        return try await write(
            method: .put,
            path: "/api/v1/medical/medication-reminders/local-authorizations/\(planID)/",
            body: Payload(enabled: enabled, source: source),
            responseType: SparkMedicalSyncAPI.RemoteMedicationReminderLocalAuthorization.self,
            serialKey: "medical.query.medication_reminder_local_authorization.\(planID)"
        )
    }

    func disableMedicationReminderLocalAuthorization(planID: Int) async throws {
        _ = try await writeOptional(
            method: .delete,
            path: "/api/v1/medical/medication-reminders/local-authorizations/\(planID)/",
            body: nil as EmptyPayload?,
            responseType: SparkMedicalSyncAPI.RemoteMedicationReminderLocalAuthorization.self,
            serialKey: "medical.query.medication_reminder_local_authorization.\(planID)"
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
    func request<T: Decodable>(
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

    func write<T: Decodable, B: Encodable & Sendable>(
        method: SparkHTTPMethod,
        path: String,
        body: B,
        responseType: T.Type,
        serialKey: String
    ) async throws -> T {
        try await writeOptional(
            method: method,
            path: path,
            body: body,
            responseType: responseType,
            serialKey: serialKey
        )
    }

    func writeOptional<T: Decodable, B: Encodable & Sendable>(
        method: SparkHTTPMethod,
        path: String,
        body: B?,
        responseType: T.Type,
        serialKey: String
    ) async throws -> T {
        let operation = CacheableSparkNetworkOperation(
            name: "Medical.Query.\(method.rawValue).\(path)",
            apiName: "MedicalQueryAPI",
            request: SparkNetworkRequest(
                method: method,
                path: path,
                body: body.map { .json(AnyEncodable($0)) } ?? .none,
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: serialKey,
                    retryConfig: .default,
                    isIdempotent: method != .post,
                    queuePriority: .high
                )
            )
        )
        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedData(responseType, from: response, decoder: .medicalAPI)
    }

    nonisolated private struct EmptyPayload: Encodable {}
}
