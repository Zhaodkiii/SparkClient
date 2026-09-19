import Foundation

/// 症状采集仅存在于当前会话与当前 AI 上下文，不写入健康档案或长期记忆。
nonisolated struct SymptomCollectionSnapshot: Codable, Equatable, Sendable {
    let collectionID: UUID
    var primaryComplaint: String?
    var associatedSymptoms: [String]
    var values: [String: String]
    /// 字段标识对应的用户可读名称，由本轮问题生成，避免汇总卡片暴露技术字段名。
    var fieldLabels: [String: String]
    var requiredFields: [String]
    var status: Status
    var revision: Int

    /// 当前轮用于卡片展示的阶段性说明，不代表诊断结论。
    var analysisSummary: String?

    private enum CodingKeys: String, CodingKey {
        // JSONDecoder.convertFromSnakeCase 会把 `collection_id` 转成 `collectionId`，
        // 而不是 Swift 属性名里的 `collectionID`。显式使用 collectionId 才能和
        // JSONEncoder.convertToSnakeCase 形成稳定的 collection_id 往返。
        case collectionID = "collectionId"
        case primaryComplaint, associatedSymptoms, values, fieldLabels, requiredFields, status, revision, analysisSummary
    }

    enum Status: String, Codable, Sendable {
        case collecting
        case reviewing
        case completed
        case cancelled
        case expired
    }

    init(
        collectionID: UUID = UUID(),
        primaryComplaint: String? = nil,
        associatedSymptoms: [String] = [],
        values: [String: String] = [:],
        fieldLabels: [String: String] = [:],
        requiredFields: [String] = [],
        status: Status = .collecting,
        revision: Int = 0,
        analysisSummary: String? = nil
    ) {
        self.collectionID = collectionID
        self.primaryComplaint = primaryComplaint
        self.associatedSymptoms = associatedSymptoms
        self.values = values
        self.fieldLabels = fieldLabels
        self.requiredFields = requiredFields
        self.status = status
        self.revision = revision
        self.analysisSummary = analysisSummary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 早期服务端生成的历史卡片没有 collection_id。缺失时仍允许卡片展示，
        // 后续由包含外层 symptom_collection_id 的问答卡统一归并到同一采集。
        collectionID = try container.decodeIfPresent(UUID.self, forKey: .collectionID) ?? UUID()
        primaryComplaint = try container.decodeIfPresent(String.self, forKey: .primaryComplaint)
        associatedSymptoms = try container.decodeIfPresent([String].self, forKey: .associatedSymptoms) ?? []
        values = try container.decodeIfPresent([String: String].self, forKey: .values) ?? [:]
        fieldLabels = try container.decodeIfPresent([String: String].self, forKey: .fieldLabels) ?? [:]
        requiredFields = try container.decodeIfPresent([String].self, forKey: .requiredFields) ?? []
        status = try container.decodeIfPresent(Status.self, forKey: .status) ?? .collecting
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        analysisSummary = try container.decodeIfPresent(String.self, forKey: .analysisSummary)
    }

    var isComplete: Bool {
        guard requiredFields.isEmpty == false else { return false }
        return requiredFields.allSatisfy { field in
            !(values[field]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }

    var completionPercent: Int {
        guard requiredFields.isEmpty == false else { return 0 }
        let completed = requiredFields.filter { field in
            !(values[field]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }.count
        return Int((Double(completed) / Double(requiredFields.count) * 100).rounded())
    }

    var summaryLines: [String] {
        var lines: [String] = []
        if let primaryComplaint, !primaryComplaint.isEmpty { lines.append("主诉：\(primaryComplaint)") }
        if !associatedSymptoms.isEmpty { lines.append("伴随症状：\(associatedSymptoms.joined(separator: "、"))") }
        lines.append(contentsOf: values
            .filter { key, _ in
                !(associatedSymptoms.isEmpty == false && Self.isAssociatedSymptomsField(key))
                    && Self.isReviewArtifactField(key) == false
            }
            .sorted(by: { $0.key < $1.key })
            .map { key, value in
                let label = fieldLabels[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayLabel = label.flatMap { $0.isEmpty ? nil : $0 } ?? Self.displayName(for: key)
                return "\(displayLabel)：\(value)"
            })
        return lines
    }

    private static func isAssociatedSymptomsField(_ field: String) -> Bool {
        let lower = field.lowercased()
        return lower.contains("accompan") || lower.contains("associated") || field.contains("伴随")
    }

    private static func isReviewArtifactField(_ field: String) -> Bool {
        let lower = field.lowercased().replacingOccurrences(of: "_", with: "")
        return lower.contains("confirm") || lower.contains("review") || field.contains("确认")
    }

    private static func displayName(for field: String) -> String {
        let lower = field.lowercased()
        if lower.contains("onset") || lower.contains("start") { return "开始时间" }
        if lower.contains("duration") { return "持续时间" }
        if lower.contains("severity") { return "严重程度" }
        if lower.contains("dizziness") && lower.contains("type") { return "头晕感觉" }
        if lower.contains("frequency") { return "发生频率" }
        if lower.contains("trigger") { return "诱发因素" }
        if lower.contains("position") || lower.contains("posture") { return "体位关系" }
        if isAssociatedSymptomsField(field) { return "伴随症状" }
        return field
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }
}

/// 当前进程内、按会话隔离的症状采集状态。模型只负责提出问题，不能成为采集状态的唯一持有者。
actor SymptomCollectionSessionStore {
    private var activeSnapshots: [UUID: SymptomCollectionSnapshot] = [:]

    func activeSnapshot(threadID: UUID?) -> SymptomCollectionSnapshot? {
        guard let threadID else { return nil }
        return activeSnapshots[threadID]
    }

    func save(_ snapshot: SymptomCollectionSnapshot, threadID: UUID?) {
        guard let threadID else { return }
        activeSnapshots[threadID] = snapshot
    }

    func remove(threadID: UUID?) {
        guard let threadID else { return }
        activeSnapshots.removeValue(forKey: threadID)
    }
}

nonisolated enum CollectSymptomsAction: String, Codable, Sendable {
    case start
    case ask
    case review
}
