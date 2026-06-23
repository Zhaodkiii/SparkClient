import Foundation

/// 从已加载的 `MedExamDetail` 提取异常项（逻辑对齐服务端 `extract_abnormal_items_from_report`）。
enum MemberMedicalExamArchiveAbnormalExtractor {
    private static let abnormalFlags = ["h", "l", "high", "low", "abnormal", "阳性", "↑", "↓", "偏高", "偏低", "异常"]
    private static let diagnosisTokens = ["异常", "偏高", "偏低", "结节", "囊肿", "增生"]
    private static let summaryTokens = ["异常", "偏高", "偏低", "结节", "囊肿", "脂肪肝", "增高", "降低"]

    static func extract(
        from report: SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments
    ) -> [SparkMedicalExamArchiveAPI.AbnormalItem] {
        var items: [SparkMedicalExamArchiveAPI.AbnormalItem] = []
        var seenKeys: Set<String> = []

        for detail in report.medExamDetails ?? [] {
            guard isAbnormalDetail(detail) else { continue }
            let name = [detail.itemName, detail.subCategory, detail.category, "异常指标"]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { $0.isEmpty == false }) ?? "异常指标"
            let key = slugKey(name)
            guard seenKeys.insert(key).inserted else { continue }

            var suggestion = (detail.diagnosis ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if suggestion.isEmpty, detail.referenceRange.isEmpty == false {
                suggestion = "参考范围 \(detail.referenceRange)"
            }

            items.append(
                SparkMedicalExamArchiveAPI.AbnormalItem(
                    key: key,
                    code: detail.itemCode.isEmpty ? key : detail.itemCode,
                    name: name,
                    value: detail.resultValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                    unit: detail.unit.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    severity: severity(from: detail.flag),
                    reason: suggestion.isEmpty ? "报告标记为异常" : suggestion,
                    suggestion: suggestion.isEmpty ? nil : suggestion
                )
            )
        }

        if items.isEmpty, let summary = report.summary?.trimmingCharacters(in: .whitespacesAndNewlines), summary.isEmpty == false {
            for chunk in summary.components(separatedBy: CharacterSet(charactersIn: ";；、,\n")) {
                let text = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                guard text.count >= 2 else { continue }
                guard summaryTokens.contains(where: { text.contains($0) }) else { continue }
                let key = slugKey(text)
                guard seenKeys.insert(key).inserted else { continue }
                items.append(
                    SparkMedicalExamArchiveAPI.AbnormalItem(
                        key: key,
                        code: key,
                        name: String(text.prefix(64)),
                        value: nil,
                        unit: nil,
                        severity: "medium",
                        reason: "来自报告摘要",
                        suggestion: "建议结合专科意见定期复查"
                    )
                )
            }
        }

        return items
    }

    private static func isAbnormalDetail(_ detail: SparkMedicalSyncAPI.RemoteMedExamDetail) -> Bool {
        let flag = detail.flag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if flag.isEmpty == false, abnormalFlags.contains(where: { flag.contains($0) }) {
            return true
        }
        let diagnosis = (detail.diagnosis ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if diagnosis.isEmpty == false, diagnosisTokens.contains(where: { diagnosis.contains($0) }) {
            return true
        }
        return false
    }

    private static func severity(from flag: String) -> String {
        let lowered = flag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["h", "high", "↑", "偏高", "阳性"].contains(where: { lowered.contains($0) }) {
            return "medium"
        }
        if ["l", "low", "↓", "偏低"].contains(where: { lowered.contains($0) }) {
            return "low"
        }
        return "medium"
    }

    private static func slugKey(_ text: String) -> String {
        let normalized = text
            .lowercased()
            .replacingOccurrences(of: #"[^\w\u4e00-\u9fff]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if normalized.isEmpty == false {
            return String(normalized.prefix(48))
        }
        return String(abs(text.hashValue))
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
