import Foundation

enum MedicationFormSupport {
    static func summaryLine(for plan: SparkMedicalSyncAPI.RemoteMedicationPlan) -> String {
        var parts: [String] = [plan.drugName]
        if plan.dosePerTime.nilIfBlank != nil {
            parts.append(plan.dosePerTime)
        } else if let value = plan.doseValue, plan.doseUnit.nilIfBlank != nil {
            parts.append("\(value)\(plan.doseUnit)")
        }
        if plan.frequencyText.nilIfBlank != nil {
            parts.append(plan.frequencyText)
        }
        if plan.status == "paused" {
            parts.append("已暂停")
        }
        return parts.joined(separator: " · ")
    }

    static func summaryLine(for item: SparkMedicalSyncAPI.RemoteMedicationFocusItem) -> String {
        let drug = item.drugName.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = item.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard summary.isEmpty == false else { return drug }
        return "\(drug) · \(summary)"
    }

    static func profileSummary(from focus: [SparkMedicalSyncAPI.RemoteMedicationFocusItem]) -> String {
        let lines = focus.map(summaryLine(for:)).filter { $0.isEmpty == false }
        guard lines.isEmpty == false else { return "暂无长期用药" }
        return lines.joined(separator: " / ")
    }

    static func statusLabel(_ status: String) -> String {
        switch status {
        case "active": return "执行中"
        case "paused": return "已暂停"
        case "completed": return "已完成"
        case "cancelled": return "已取消"
        default: return status
        }
    }
}
