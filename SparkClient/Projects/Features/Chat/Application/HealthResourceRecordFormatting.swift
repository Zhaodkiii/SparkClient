import Foundation

/// 健康资料 AI 上下文与卡片摘要共用的文本格式化（无网络、无业务编排）。
enum HealthResourceRecordFormatting {
    static func trimmed(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    static func formatDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func joinLines(date: Date?, institution: String?, summary: String?) -> String {
        var lines: [String] = []
        if let institution = trimmed(institution) { lines.append("机构：\(institution)") }
        if let date, let text = formatDate(date) { lines.append("日期：\(text)") }
        if let summary = trimmed(summary) { lines.append(summary) }
        return lines.joined(separator: "\n")
    }

    static func appendMedExamLines(_ lines: inout [String], details: [SparkMedicalSyncAPI.RemoteMedExamDetail]?) {
        guard let details, details.isEmpty == false else { return }
        lines.append("指标：")
        for row in details.prefix(40) {
            let reference = row.referenceRange.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = reference.isEmpty ? "" : " 参考 \(reference)"
            lines.append("· \(row.itemName): \(row.resultValue ?? "—") \(row.unit) \(row.flag)\(suffix)")
        }
    }

    static func examinationBody(
        itemName: String?,
        reportedAt: Date?,
        performedAt: Date?,
        organizationName: String?,
        category: String?,
        departmentName: String?,
        doctorName: String?,
        findings: String?,
        impression: String?,
        cachedDetails: [SparkMedicalSyncAPI.RemoteMedExamDetail]?
    ) -> String {
        var lines: [String] = []
        if let name = trimmed(itemName) { lines.append(name) }
        lines.append(contentsOf: joinLines(date: reportedAt ?? performedAt, institution: organizationName, summary: nil)
            .split(separator: "\n")
            .map(String.init))
        if let category = trimmed(category) { lines.append("类别：\(category)") }
        if let department = trimmed(departmentName) { lines.append("科室：\(department)") }
        if let doctor = trimmed(doctorName) { lines.append("医生：\(doctor)") }
        if let findings = trimmed(findings) { lines.append("所见：\(findings)") }
        if let impression = trimmed(impression) { lines.append("结论：\(impression)") }
        appendMedExamLines(&lines, details: cachedDetails)
        return lines.joined(separator: "\n")
    }

    static func healthExamBody(
        institutionName: String?,
        examDate: Date?,
        reportNo: String?,
        summary: String?,
        cachedDetails: [SparkMedicalSyncAPI.RemoteMedExamDetail]?
    ) -> String {
        var lines = joinLines(date: examDate, institution: institutionName, summary: summary)
            .split(separator: "\n")
            .map(String.init)
        if let reportNo = trimmed(reportNo) { lines.append("报告号：\(reportNo)") }
        appendMedExamLines(&lines, details: cachedDetails)
        return lines.joined(separator: "\n")
    }

    static func isAIContextBodySufficient(_ body: String, type: HealthResourceType) -> Bool {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedBody.isEmpty == false else { return false }
        switch type {
        case .examinationReport, .healthExamReport:
            return trimmedBody.contains("所见：")
                || trimmedBody.contains("结论：")
                || trimmedBody.contains("指标：")
                || trimmedBody.count >= 120
        default:
            return true
        }
    }

    static func examinationClinicalContentIsPresent(
        findings: String?,
        impression: String?,
        details: [SparkMedicalSyncAPI.RemoteMedExamDetail]?
    ) -> Bool {
        trimmed(findings) != nil
            || trimmed(impression) != nil
            || (details?.isEmpty == false)
    }

    static func healthExamClinicalContentIsPresent(
        summary: String?,
        details: [SparkMedicalSyncAPI.RemoteMedExamDetail]?
    ) -> Bool {
        trimmed(summary) != nil || (details?.isEmpty == false)
    }
}
