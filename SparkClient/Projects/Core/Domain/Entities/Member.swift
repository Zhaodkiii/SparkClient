import Foundation

/// 家庭档案中的成员（就诊人/家属）：病例、检查、处方等医疗实体通过 `memberID` 与之关联。
///
/// `relationship` 约定包含「本人」（如 `self` / `本人`），用于产品层判断是否可展示本机 Apple 健康等能力；与 `SyncedHealthMetric` 的档案维度无关。
struct Member: Identifiable, Codable, Equatable, Sendable {
    /// 服务端自增主键。
    let id: Int
    var name: String
    /// 原始枚举字符串，如 `male` / `female` / `unknown`。
    var gender: String
    /// 与本人的关系描述；影响 UI 与部分业务分支（如首页运动健康是否读 HealthKit）。
    var relationship: String
    var birthDate: Date?
    var bloodType: String
    var allergies: [String]
    var chronicConditions: [String]
    var notes: String
    var avatarUrl: String
    /// 是否为主档案成员（排序与默认选中时常优先）。
    var isPrimary: Bool
    /// 最近修改时间，用于列表排序与冲突处理参考。
    var updatedAt: Date

    /// - Parameters:
    ///   - id: 服务端成员 ID。
    ///   - name: 显示姓名。
    ///   - gender: 性别编码，默认 `unknown`。
    ///   - relationship: 关系，默认 `self`（本人）。
    ///   - birthDate: 出生日期，可选。
    ///   - bloodType: 血型信息。
    ///   - allergies: 过敏史列表。
    ///   - chronicConditions: 慢病摘要列表。
    ///   - notes: 成员备注。
    ///   - avatarUrl: 头像 URL。
    ///   - isPrimary: 是否主成员，默认 `false`。
    ///   - updatedAt: 业务更新时间，默认当前时间。
    init(
        id: Int,
        name: String,
        gender: String = "unknown",
        relationship: String = "self",
        birthDate: Date? = nil,
        bloodType: String = "",
        allergies: [String] = [],
        chronicConditions: [String] = [],
        notes: String = "",
        avatarUrl: String = "",
        isPrimary: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.gender = gender
        self.relationship = relationship
        self.birthDate = birthDate
        self.bloodType = bloodType
        self.allergies = allergies
        self.chronicConditions = chronicConditions
        self.notes = notes
        self.avatarUrl = avatarUrl
        self.isPrimary = isPrimary
        self.updatedAt = updatedAt
    }
}
