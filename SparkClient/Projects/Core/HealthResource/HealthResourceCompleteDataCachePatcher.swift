import Foundation

/// 将懒加载得到的报告摘要（含明细/附件）回写 `RemoteMemberCompleteData` 内存缓存。
enum HealthResourceCompleteDataCachePatcher {
    static func patch(
        _ data: SparkMedicalSyncAPI.RemoteMemberCompleteData,
        examinationReport: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments? = nil,
        healthExamReport: SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments? = nil
    ) -> SparkMedicalSyncAPI.RemoteMemberCompleteData {
        var patched = data
        if let examinationReport {
            var list = patched.examinationReports ?? []
            if let index = list.firstIndex(where: { $0.id == examinationReport.id }) {
                list[index] = examinationReport
                patched.examinationReports = list
            }
        }
        if let healthExamReport {
            var list = patched.healthExamReports ?? []
            if let index = list.firstIndex(where: { $0.id == healthExamReport.id }) {
                list[index] = healthExamReport
                patched.healthExamReports = list
            }
        }
        return patched
    }
}
