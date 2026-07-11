import Combine
import Foundation

/// 支持明细懒加载的报告头协议：首页先拿摘要，列表页再按需补齐 `MedExamDetail`。
nonisolated protocol MedExamDetailLoadableReport: Identifiable, Equatable {
    var id: Int { get }
    var member: Int { get }
    var medExamDetails: [SparkMedicalSyncAPI.RemoteMedExamDetail]? { get set }
    static var acceptedBusinessTypes: [String] { get }
    /// 请求 `med-exam-details` 时使用的 `business_type` 查询参数。
    var medExamDetailBusinessType: String { get }
}

extension SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments: MedExamDetailLoadableReport {
    static var acceptedBusinessTypes: [String] { ["health_exam_report", "health_exam"] }
    var medExamDetailBusinessType: String { "health_exam_report" }
}

extension SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments: MedExamDetailLoadableReport {
    static var acceptedBusinessTypes: [String] { ["examination_report", "examination"] }
    var medExamDetailBusinessType: String { "examination_report" }
}

/// 通用明细懒加载 ViewModel：
/// - 初始化直接吃首页 `complete-data` 的摘要数组；
/// - 某条记录 `medExamDetails == nil` 时才触发请求；
/// - 一旦明细已回填，后续滚动/重入页面都不重复加载。
@MainActor
final class MedExamDetailLazyLoadViewModel<Report: MedExamDetailLoadableReport>: ObservableObject {
    @Published private(set) var reports: [Report]
    @Published private(set) var loadingIDs: Set<Int> = []
    @Published var searchText: String = ""

    private let medicalQueryAPI: SparkMedicalQueryAPI
    private let logger: Logger
    private let scene: String
    private let onReportsUpdated: (([Report]) -> Void)?
    private let logModule = LogModule.home

    init(
        reports: [Report],
        medicalQueryAPI: SparkMedicalQueryAPI,
        logger: Logger,
        scene: String,
        onReportsUpdated: (([Report]) -> Void)? = nil
    ) {
        self.reports = reports
        self.medicalQueryAPI = medicalQueryAPI
        self.logger = logger
        self.scene = scene
        self.onReportsUpdated = onReportsUpdated
    }

    deinit {}

    
    func loadDetailsIfNeeded(for reportID: Int) async {
        guard let index = reports.firstIndex(where: { $0.id == reportID }) else { return }
        guard reports[index].medExamDetails == nil else { return }
        guard loadingIDs.contains(reportID) == false else { return }

        loadingIDs.insert(reportID)
        defer { loadingIDs.remove(reportID) }

        let memberID = reports[index].member
        logger.info("明细加载开始 scene=\(scene) reportID=\(reportID) memberID=\(memberID)", module: logModule)

        do {
            let rows = try await medicalQueryAPI.listMedExamDetails(
                memberID: memberID,
                businessType: reports[index].medExamDetailBusinessType,
                businessID: reportID
            )
            let filtered = rows
                .filter { row in
                    let normalized = row.businessType.lowercased()
                    return Report.acceptedBusinessTypes.contains { $0.lowercased() == normalized }
                        || rows.count == 1
                }
                .sorted { lhs, rhs in
                    if lhs.sortOrder == rhs.sortOrder {
                        return lhs.id < rhs.id
                    }
                    return lhs.sortOrder < rhs.sortOrder
                }

            reports[index].medExamDetails = filtered
            onReportsUpdated?(reports)
            logger.info(
                "明细加载完成 scene=\(scene) reportID=\(reportID) count=\(filtered.count)",
                module: logModule
            )
        } catch {
            logger.warning(
                "明细加载失败 scene=\(scene) reportID=\(reportID) error=\(error.localizedDescription)",
                module: logModule
            )
        }
    }

    func isLoading(reportID: Int) -> Bool {
        loadingIDs.contains(reportID)
    }

    func removeReport(reportID: Int) {
        reports.removeAll { $0.id == reportID }
        onReportsUpdated?(reports)
    }

    func replaceReports(_ newReports: [Report]) {
        reports = newReports
        onReportsUpdated?(reports)
    }

    func prependReport(_ report: Report) {
        reports.insert(report, at: 0)
        onReportsUpdated?(reports)
    }

    func upsertReport(_ report: Report) {
        if let index = reports.firstIndex(where: { $0.id == report.id }) {
            reports[index] = report
        } else {
            reports.insert(report, at: 0)
        }
        onReportsUpdated?(reports)
    }
}
