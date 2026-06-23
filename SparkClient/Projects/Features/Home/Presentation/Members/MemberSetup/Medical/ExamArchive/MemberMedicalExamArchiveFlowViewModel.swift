import Combine
import Foundation

@MainActor
final class MemberMedicalExamArchiveFlowViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case failed(String)
        case loaded
    }

    @Published var selectedPath: MemberMedicalExamArchivePath?
    @Published var selectedReport: SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments?
    @Published var abnormalItems: [SparkMedicalExamArchiveAPI.AbnormalItem] = []
    @Published var selectedAbnormalItemIDs: Set<String> = []
    @Published var followUpTasks: [SparkMedicalExamArchiveAPI.FollowUpTaskDraft] = []
    @Published var selectedFollowUpTaskIDs: Set<String> = []
    @Published var generatedPlan: SparkMedicalExamArchiveAPI.ExamPlanDraft?
    @Published var evidenceSnapshot: SparkMedicalExamArchiveAPI.EvidenceSnapshot?
    @Published var loadState: LoadState = .idle
    @Published var createdTaskCount = 0
    @Published var latestAIPlanResponse: SparkMedicalExamArchiveAPI.AIPlanResponse?

    var memberID: Int
    let medicalQueryAPI: SparkMedicalQueryAPI
    private let onCompleteDataPatch: ((@escaping (inout SparkMedicalSyncAPI.RemoteMemberCompleteData) -> Void) -> Void)?
    private let logger: Logger = ConsoleLogger()
    private let reportDetailLoader: MedExamDetailLazyLoadViewModel<SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments>

    var healthExamReports: [SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments]
    var onFlowCompleted: ((SparkMedicalExamArchiveAPI.AIPlanResponse?) -> Void)?
    var onReportsWithDetailsUpdated: (([SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments]) -> Void)?

    /// 生成计划时实际采用的已确认异常项，用于结果页展示生成依据。
    var planRationaleAbnormalItems: [SparkMedicalExamArchiveAPI.AbnormalItem] {
        if let items = latestAIPlanResponse?.abnormalItems, items.isEmpty == false {
            return items
        }
        return abnormalItems.filter { selectedAbnormalItemIDs.contains($0.id) }
    }

    init(
        memberID: Int,
        healthExamReports: [SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments],
        medicalQueryAPI: SparkMedicalQueryAPI,
        onCompleteDataPatch: ((@escaping (inout SparkMedicalSyncAPI.RemoteMemberCompleteData) -> Void) -> Void)?
    ) {
        self.memberID = memberID
        self.healthExamReports = healthExamReports
        self.medicalQueryAPI = medicalQueryAPI
        self.onCompleteDataPatch = onCompleteDataPatch
        self.reportDetailLoader = MedExamDetailLazyLoadViewModel(
            reports: healthExamReports,
            medicalQueryAPI: medicalQueryAPI,
            logger: ConsoleLogger(),
            scene: "medical_setup_exam_archive_flow"
        )
    }

    func syncMemberID(_ id: Int) {
        guard id > 0 else { return }
        memberID = id
    }

    private var resolvedMemberID: Int {
        if memberID > 0 { return memberID }
        return selectedReport?.member ?? healthExamReports.first?.member ?? 0
    }

    func logEntry() {
        logger.info("体检档案流程：进入 memberID=\(memberID) mode=entry")
    }

    func selectPath(_ path: MemberMedicalExamArchivePath) {
        selectedPath = path
        logger.info("体检档案流程：选择\(path == .hasHistoryReport ? "有历史报告" : "暂无历史报告") memberID=\(memberID)")
    }

    func refreshReports(_ reports: [SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments]) {
        healthExamReports = reports
        reportDetailLoader.replaceReports(reports)
        if let selectedID = selectedReport?.id,
           let updated = reports.first(where: { $0.id == selectedID }) {
            selectedReport = updated
        }
    }

    func selectReport(_ report: SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments) {
        selectedReport = report
    }

    func handleUploadCompleted(reportID: Int) {
        logger.info("体检档案流程：上传报告完成 reportID=\(reportID)")
        if let report = healthExamReports.first(where: { $0.id == reportID }) {
            selectedReport = report
        }
    }

    func isLoadingReportDetails(reportID: Int) -> Bool {
        reportDetailLoader.isLoading(reportID: reportID)
    }

    func loadReportDetailsIfNeeded(reportID: Int) async {
        await reportDetailLoader.loadDetailsIfNeeded(for: reportID)
        let reportsWithDetails = reportDetailLoader.reports
        healthExamReports = reportsWithDetails
        onReportsWithDetailsUpdated?(reportsWithDetails)
        if let selectedID = selectedReport?.id, selectedID == reportID,
           let updated = reportsWithDetails.first(where: { $0.id == reportID }) {
            selectedReport = updated
        }
    }

    /// 与体检报告列表卡片一致：先懒加载 `MedExamDetail`，再提取异常项并请求随访草稿。
    func previewAbnormalItems(reportID: Int) async -> Bool {
        let memberID = resolvedMemberID
        guard memberID > 0 else {
            loadState = .failed("成员信息未加载")
            return false
        }

        loadState = .loading
        defer {
            if case .loading = loadState {
                loadState = .idle
            }
        }

        await reportDetailLoader.loadDetailsIfNeeded(for: reportID)
        let reportsWithDetails = reportDetailLoader.reports
        healthExamReports = reportsWithDetails
        onReportsWithDetailsUpdated?(reportsWithDetails)

        let report = reportsWithDetails.first(where: { $0.id == reportID }) ?? selectedReport
        guard let report else {
            loadState = .failed("未找到体检报告")
            return false
        }
        selectedReport = report

        let localItems = MemberMedicalExamArchiveAbnormalExtractor.extract(from: report)
        logger.info("体检档案流程：明细加载完成 reportID=\(reportID) detailCount=\(report.medExamDetails?.count ?? 0) localAbnormal=\(localItems.count)")

        do {
            let response = try await medicalQueryAPI.previewExamArchiveAbnormalItems(
                memberID: memberID,
                reportID: reportID
            )
            abnormalItems = response.abnormalItems.isEmpty ? localItems : response.abnormalItems
            followUpTasks = response.followUpTasks
        } catch {
            guard localItems.isEmpty == false else {
                loadState = .failed(error.localizedDescription)
                return false
            }
            abnormalItems = localItems
            followUpTasks = []
            logger.warning("体检档案流程：预览接口失败，已使用本地明细提取 reportID=\(reportID) error=\(error.localizedDescription)")
        }

        selectedAbnormalItemIDs = Set(abnormalItems.map(\.id))
        selectedFollowUpTaskIDs = Set(followUpTasks.map(\.id))
        loadState = abnormalItems.isEmpty ? .failed("未识别到异常项，请检查报告明细或手动补充") : .loaded
        logger.info("体检档案流程：异常项预览完成 reportID=\(reportID) count=\(abnormalItems.count)")
        return abnormalItems.isEmpty == false
    }

    func confirmAbnormalItems() async -> Bool {
        let selected = abnormalItems.filter { selectedAbnormalItemIDs.contains($0.id) }
        guard selected.isEmpty == false else { return false }
        loadState = .loading
        defer {
            if case .loading = loadState {
                loadState = .idle
            }
        }
        do {
            let response = try await medicalQueryAPI.confirmExamArchiveAbnormalItems(
                memberID: resolvedMemberID,
                reportID: selectedReport?.id,
                items: selected
            )
            followUpTasks = response.followUpTasks
            selectedFollowUpTaskIDs = Set(response.followUpTasks.map(\.id))
            loadState = .loaded
            logger.info("体检档案流程：用户确认异常项 count=\(selected.count)")
            return true
        } catch {
            loadState = .failed(error.localizedDescription)
            return false
        }
    }

    func loadEvidence() async -> Bool {
        loadState = .loading
        defer {
            if case .loading = loadState {
                loadState = .idle
            }
        }
        do {
            let response = try await medicalQueryAPI.loadExamArchiveEvidence(memberID: resolvedMemberID)
            evidenceSnapshot = response.evidence
            loadState = .loaded
            return true
        } catch {
            loadState = .failed(error.localizedDescription)
            return false
        }
    }

    func generatePlan(createFollowUpTasks: Bool) async -> Bool {
        loadState = .loading
        let selectedAbnormals = abnormalItems.filter { selectedAbnormalItemIDs.contains($0.id) }
        let selectedFollowUps = createFollowUpTasks ? Array(selectedFollowUpTaskIDs) : []
        let mode = selectedPath == .noHistoryReport ? "baseline" : "report_based"
        let request = SparkMedicalExamArchiveAPI.AIPlanRequest(
            mode: mode,
            healthExamReportID: selectedReport?.id,
            selectedAbnormalItems: selectedAbnormals.map {
                SparkMedicalExamArchiveAPI.ConfirmedAbnormalItemPayload(
                    code: $0.code ?? $0.key,
                    name: $0.name,
                    value: $0.value,
                    unit: $0.unit,
                    severity: $0.severity
                )
            },
            createFollowUpTasks: createFollowUpTasks,
            selectedFollowUpTaskKeys: selectedFollowUps.isEmpty ? nil : selectedFollowUps
        )
        do {
            let response = try await medicalQueryAPI.generateExamArchiveAIPlan(
                memberID: resolvedMemberID,
                planRequest: request
            )
            generatedPlan = response.examPlan
            latestAIPlanResponse = response
            createdTaskCount = response.createdTasks.count
            if evidenceSnapshot == nil {
                _ = await loadEvidence()
            }
            applyCachePatch(response)
            loadState = .loaded
            logger.info("体检档案流程：AI 体检计划生成成功 planID=\(response.planID ?? 0)")
            return true
        } catch {
            loadState = .failed(error.localizedDescription)
            return false
        }
    }

    func finishFlow() {
        onFlowCompleted?(latestAIPlanResponse)
    }

    func skipFlow() {
        onFlowCompleted?(nil)
    }

    private func applyCachePatch(_ response: SparkMedicalExamArchiveAPI.AIPlanResponse) {
        onCompleteDataPatch? { completeData in
            if let profile = response.memberMedicalProfile {
                completeData.memberMedicalProfile = profile
            }
            if let reportID = response.sourceReportID,
               let report = self.healthExamReports.first(where: { $0.id == reportID }) {
                MemberModuleSetupCompleteDataPatcher.upsertHealthExamReport(report, into: &completeData)
            }
        }
        logger.info("体检档案流程：缓存已更新 memberID=\(memberID)")
    }
}
