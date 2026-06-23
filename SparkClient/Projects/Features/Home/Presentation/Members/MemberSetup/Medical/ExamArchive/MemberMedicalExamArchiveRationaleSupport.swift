import Foundation

enum MemberMedicalExamArchiveRationaleSupport {
    struct Row: Identifiable, Equatable {
        let id: String
        let title: String
        let detail: String

        var hasDetail: Bool {
            detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }

        var previewText: String {
            hasDetail ? detail : L10n.text("medical.exam_archive.evidence.empty")
        }
    }

    static func buildRows(
        rationale: [String],
        evidence: SparkMedicalExamArchiveAPI.EvidenceSnapshot?,
        abnormalItems: [SparkMedicalExamArchiveAPI.AbnormalItem],
        sourceReportTitle: String?
    ) -> [Row] {
        rationale.map { tag in
            Row(
                id: tag,
                title: tag,
                detail: detail(
                    for: tag,
                    evidence: evidence,
                    abnormalItems: abnormalItems,
                    sourceReportTitle: sourceReportTitle
                )
            )
        }
    }

    private static func detail(
        for tag: String,
        evidence: SparkMedicalExamArchiveAPI.EvidenceSnapshot?,
        abnormalItems: [SparkMedicalExamArchiveAPI.AbnormalItem],
        sourceReportTitle: String?
    ) -> String {
        if tag.contains("体检报告") || tag == "历史报告" {
            return reportDetail(
                tag: tag,
                sourceReportTitle: sourceReportTitle,
                abnormalItems: abnormalItems
            )
        }
        if tag.contains("基础档案") {
            return trimmed(evidence?.basicProfile)
        }
        if tag.contains("病史") {
            return trimmed(evidence?.healthHistory)
        }
        if tag.contains("症状") {
            return trimmed(evidence?.symptoms)
        }
        if tag.contains("生活习惯") || tag.contains("生活") {
            return trimmed(evidence?.lifestyle)
        }
        if tag.contains("家族") {
            return familyHistoryDetail(evidence?.familyHistory)
        }
        return ""
    }

    private static func reportDetail(
        tag: String,
        sourceReportTitle: String?,
        abnormalItems: [SparkMedicalExamArchiveAPI.AbnormalItem]
    ) -> String {
        var sections: [String] = []
        if let sourceReportTitle, sourceReportTitle.isEmpty == false {
            sections.append(sourceReportTitle)
        } else if tag.contains("年") {
            sections.append(tag)
        }
        if abnormalItems.isEmpty == false {
            let abnormalLines = abnormalItems.map { item in
                var line = item.name
                if let value = item.value, value.isEmpty == false {
                    line += "：\(value)\(item.unit.map { " \($0)" } ?? "")"
                }
                if item.displaySuggestion.isEmpty == false {
                    line += "（\(item.displaySuggestion)）"
                }
                return line
            }
            sections.append(
                L10n.text("medical.exam_archive.result.rationale.abnormals")
                    + "\n"
                    + abnormalLines.joined(separator: "\n")
            )
        }
        return sections.joined(separator: "\n\n")
    }

    private static func familyHistoryDetail(
        _ records: [SparkMedicalSyncAPI.RemoteFamilyHistoryRecord]?
    ) -> String {
        guard let records, records.isEmpty == false else { return "" }
        return records.map { record in
            var parts = [record.disease, record.relative]
                .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            if record.diagnosedAge.isEmpty == false {
                parts.append(record.diagnosedAge)
            }
            if record.notes.isEmpty == false {
                parts.append(record.notes)
            }
            return parts.joined(separator: " · ")
        }
        .joined(separator: "\n")
    }

    private static func trimmed(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
