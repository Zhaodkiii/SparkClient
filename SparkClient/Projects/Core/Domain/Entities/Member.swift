import Foundation

/// 当前用户对成员的绑定能力与元数据。
struct MemberBindingInfo: Codable, Equatable, Sendable {
    var bindingID: Int
    var role: String
    var sharedUserCount: Int
    var canShare: Bool
    var canEdit: Bool
    var canDelete: Bool
    var canUnbind: Bool
    var canManageBindings: Bool
}

/// 家庭档案中的成员（就诊人/家属）：病例、检查、处方等医疗实体通过 `memberID` 与之关联。
///
/// `relationship` 为当前用户视角下的绑定关系（如 `self` / `father`），供 UI 展示与排序等使用。
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
    /// 当前用户与该成员的绑定信息；旧接口未返回时可为 `nil`。
    var binding: MemberBindingInfo?

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
        updatedAt: Date = Date(),
        binding: MemberBindingInfo? = nil
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
        self.binding = binding
    }

    /// 缺失 binding 时采用最小权限，避免旧接口漏字段导致 UI 误展示分享/删除。
    var effectiveBinding: MemberBindingInfo {
        binding ?? .restrictedFallback
    }

    var isSelfMember: Bool {
        let normalized = relationship.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "self" || normalized == "本人"
    }
}

extension MemberBindingInfo {
    static let restrictedFallback = MemberBindingInfo(
        bindingID: 0,
        role: "unknown",
        sharedUserCount: 0,
        canShare: false,
        canEdit: false,
        canDelete: false,
        canUnbind: false,
        canManageBindings: false
    )

    static func ownerLike(bindingID: Int, sharedUserCount: Int = 1) -> MemberBindingInfo {
        MemberBindingInfo(
            bindingID: bindingID,
            role: "owner",
            sharedUserCount: sharedUserCount,
            canShare: true,
            canEdit: true,
            canDelete: true,
            canUnbind: true,
            canManageBindings: true
        )
    }
}
