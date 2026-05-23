import Foundation

/// 医疗「家庭成员」REST API 封装：列表、创建、更新、删除。
///
/// 与 `SparkMedicalWorkflowAPI` 等业务接口一致，依赖 `SparkBackendConfiguration` 执行网络请求；
/// 日期字段在解码时使用 `MedicalDateCoding` 灵活解析，编码出生日期时仅输出日期部分（见 `UpsertMemberPayload`）。
struct SparkMedicalMemberAPI {
    /// 注入的后端配置（URL、会话、错误映射等）。
    let configuration: SparkBackendConfiguration

    private let resources: SparkMedicalWorkflowAPI

    init(configuration: SparkBackendConfiguration) {
        self.configuration = configuration
        self.resources = SparkMedicalWorkflowAPI(configuration: configuration)
    }

    /// 服务端返回的成员模型，用于列表与创建/更新响应。
    struct RemoteMember: Decodable, Sendable, Equatable {
        /// 服务端主键。
        let id: Int
        let bindingId: Int?
        /// 显示姓名。
        let name: String
        /// 性别编码或展示文案（与后端约定）。
        let gender: String
        /// 与当前用户的关系（如本人、父母、子女）；部分嵌套响应可能缺失。
        let relationship: String?
        /// 出生日期；缺失时为 `nil`。
        let birthDate: Date?
        /// 血型。
        let bloodType: String
        /// 过敏史列表。
        let allergies: [String]
        /// 慢性病史列表。
        let chronicConditions: [String]
        /// 备注。
        let notes: String
        /// 头像完整 URL 字符串。
        let avatarUrl: String
        /// 是否为当前账号下的主成员（主档案）。
        let isPrimary: Bool
        let bindingRole: String?
        let sharedUserCount: Int?
        let canShare: Bool?
        let canEdit: Bool?
        let canDelete: Bool?
        let canUnbind: Bool?
        let canManageBindings: Bool?
        /// 服务端最后更新时间，用于增量同步或冲突判断。
        let updatedAt: Date

        var bindingInfo: MemberBindingInfo? {
            guard let bindingId else { return nil }
            return MemberBindingInfo(
                bindingID: bindingId,
                role: bindingRole ?? "owner",
                sharedUserCount: sharedUserCount ?? 1,
                canShare: canShare ?? false,
                canEdit: canEdit ?? false,
                canDelete: canDelete ?? false,
                canUnbind: canUnbind ?? true,
                canManageBindings: canManageBindings ?? false
            )
        }
    }

    /// 创建或更新成员时的请求体（PUT/POST 共用形状）。
    ///
    /// 对 `birthDate` 使用自定义 `encode`：有值则按「仅日期」规则编码（与医疗模块其它日期字段一致），无值则显式编码为 JSON `null`。
    struct UpsertMemberPayload: Encodable, Sendable {
        let name: String
        let relationship: String
        let gender: String
        let birthDate: Date?
        let bloodType: String
        let allergies: [String]
        let chronicConditions: [String]
        let notes: String
        let avatarUrl: String
        let isPrimary: Bool


        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodableKey.self)
            try container.encode(name, forKey: .key("name"))
            try container.encode(relationship, forKey: .key("relationship"))
            try container.encode(gender, forKey: .key("gender"))
            // 出生日期：避免默认编码成带时区的完整 DateTime，统一为日期串以匹配后端 `birth_date` 语义。
            if let birthDate {
                try container.encode(MedicalDateCoding.encodeDateOnly(birthDate), forKey: .key("birthDate"))
            } else {
                try container.encodeNil(forKey: .key("birthDate"))
            }
            try container.encode(bloodType, forKey: .key("bloodType"))
            try container.encode(allergies, forKey: .key("allergies"))
            try container.encode(chronicConditions, forKey: .key("chronicConditions"))
            try container.encode(notes, forKey: .key("notes"))
            try container.encode(avatarUrl, forKey: .key("avatarUrl"))
            try container.encode(isPrimary, forKey: .key("isPrimary"))
        }
    }

    /// 拉取当前用户下全部医疗成员；支持 ETag 缓存（TTL 120 秒），适合频繁进入列表页的场景。
    func listMembers() async throws -> [RemoteMember] {
        try await resources.list([RemoteMember].self, kind: .members)
    }

    /// 新建成员；成功返回带服务端 `id` 的 `RemoteMember`。
    func createMember(_ payload: UpsertMemberPayload) async throws -> RemoteMember {
        try await resources.create(RemoteMember.self, kind: .members, body: payload)
    }

    /// 按服务端 ID 全量更新成员信息；成功返回最新 `RemoteMember`。
    ///
    /// - Parameter remoteID: 路径中的成员主键，与 `RemoteMember.id` 一致。
    func updateMember(remoteID: Int, payload: UpsertMemberPayload) async throws -> RemoteMember {
        try await resources.replace(RemoteMember.self, kind: .members, id: remoteID, body: payload)
    }

    /// 删除指定成员；仅校验响应包装结构可解码，不依赖具体业务负载。
    func deleteMember(remoteID: Int) async throws {
        try await resources.delete(kind: .members, id: remoteID)
    }
}
