import CryptoKit
import Foundation

enum ChatGuideMemberProfilePromptFormatter {
    /// 将 complete-data 格式化为 AI prompt 内可用的成员资料摘要。
    @MainActor
    static func makeProfileSummary(
        data: SparkMedicalSyncAPI.RemoteMemberCompleteData,
        requestedFocus: String? = "对话引导卡片健康科普问题生成"
    ) -> String {
        MemberProfileFormatter.makeAIResult(
            data: data,
            requestedFocus: requestedFocus
        ).content
    }

    /// 非敏感 digest，用于 payload 记录与日志。
    nonisolated static func makeProfileDigest(
        memberID: Int,
        data: SparkMedicalSyncAPI.RemoteMemberCompleteData
    ) -> String {
        let parts: [String] = [
            String(memberID),
            String(data.medicalCases?.count ?? 0),
            String(data.symptoms?.count ?? 0),
            String(data.healthExamReports?.count ?? 0),
            String(data.examinationReports?.count ?? 0),
            String(data.medicationPlans?.count ?? 0),
            data.memberMedicalProfile?.guidanceUpdatedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "",
        ]
        let joined = parts.joined(separator: "|")
        let digest = SHA256.hash(data: Data(joined.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    /// 将 metric sections 压缩为 prompt 内健康数据摘要。
    nonisolated static func makeMetricSummary(sections: [ChatGuideMetricSection]) -> String {
        sections.map { section in
            let items = section.items.map { item in
                if let unit = item.unitText, unit.isEmpty == false {
                    return "\(item.title): \(item.valueText) \(unit)"
                }
                return "\(item.title): \(item.valueText)"
            }.joined(separator: "、")
            return "- \(section.title): \(items.isEmpty ? section.state.rawValue : items)"
        }.joined(separator: "\n")
    }
}
