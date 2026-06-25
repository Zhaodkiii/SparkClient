import Foundation

/// 家庭成员相关医疗接口API扩展
extension SparkMedicalMemberAPI {
    /// 生成分享票据接口返回模型
    struct ShareTicketResponse: Decodable, Sendable {
        /// 分享票据唯一凭证
        let shareTicket: String
        /// 二维码承载原始字符串
        let qrPayload: String
    }

    /// 解析分享票据返回结果模型
    struct ShareResolveResponse: Decodable, Sendable {
        /// 被分享的成员基础摘要信息
        struct MemberSummary: Decodable, Sendable, Equatable {
            /// 成员ID
            let id: Int
            /// 成员姓名
            let name: String
            /// 性别标识
            let gender: String
            /// 出生日期，可为空
            let birthDate: Date?
            /// 头像地址
            let avatarUrl: String
        }

        /// 分享发起人的摘要信息
        struct InviterSummary: Decodable, Sendable, Equatable {
            /// 发起分享用户ID
            let userId: Int
            /// 发起人展示昵称
            let displayName: String
            /// 发起人与该成员的亲属关系
            let relationship: String
        }

        /// 被分享成员基础信息
        let member: MemberSummary
        /// 分享发起方信息
        let inviter: InviterSummary
        /// 本次分享默认授予的权限角色
        let defaultRole: String
        /// 当前用户是否已经绑定过该成员
        let alreadyBound: Bool
        /// 已存在的绑定关系ID，未绑定则为nil
        let existingBindingId: Int?
        /// 当前该成员已共享给多少位用户
        let sharedUserCount: Int
    }

    /// 获取单个成员详情接口返回完整模型
    struct MemberDetailResponse: Decodable, Sendable {
        /// 成员主键ID
        let id: Int
        /// 当前用户与该成员的绑定关系ID
        let bindingId: Int
        /// 成员姓名
        let name: String
        /// 性别
        let gender: String
        /// 当前用户与该成员的亲属关系
        let relationship: String
        /// 出生日期
        let birthDate: Date?
        /// 血型
        let bloodType: String
        /// 过敏史列表
        let allergies: [String]
        /// 慢性病列表
        let chronicConditions: [String]
        /// 备注文本
        let notes: String
        /// 头像链接
        let avatarUrl: String
        /// 是否为主账号本人
        let isPrimary: Bool
        /// 当前绑定角色标识
        let bindingRole: String
        /// 已共享用户总数
        let sharedUserCount: Int
        /// 是否拥有分享权限
        let canShare: Bool
        /// 是否拥有编辑资料权限
        let canEdit: Bool
        /// 是否拥有删除成员权限
        let canDelete: Bool
        /// 是否可以解除绑定
        let canUnbind: Bool
        /// 是否能管理该成员的所有共享绑定，可选字段
        let canManageBindings: Bool?
        /// 最后更新时间
        let updatedAt: Date
        /// 医疗数据统计概览
        let medicalOverview: MedicalOverview?
        /// 共享给其他用户的列表，可选
        let sharedUsers: [SharedUserRow]?
        /// 当前用户自身的绑定关系信息，可选
        let myBinding: MyBindingRow?

        /// 成员医疗数据统计概览子模型
        struct MedicalOverview: Decodable, Sendable {
            /// 病例档案数量
            let medicalCaseCount: Int
            /// 体检报告总数
            let healthExamReportCount: Int
            /// 检验报告单数量
            let examinationReportCount: Int
            /// 用药计划数量
            let medicationPlanCount: Int
            /// 医疗资料最后更新时间
            let lastUpdatedAt: Date?
        }

        /// 共享用户列表行模型，支持列表遍历Identifiable
        struct SharedUserRow: Decodable, Sendable, Identifiable {
            /// 绑定关系ID，作为列表唯一标识
            let bindingId: Int
            /// 共享用户ID
            let userId: Int
            /// 对方昵称
            let displayName: String
            /// 对方与成员的亲属关系
            let relationship: String
            /// 授予的角色
            let role: String
            /// 权限标识，可选
            let permission: String?
            /// 是否是当前登录用户自己
            let isSelf: Bool
            /// 绑定共享的时间
            let boundAt: Date

            var id: Int { bindingId }
        }

        /// 当前用户自身绑定关系信息
        struct MyBindingRow: Decodable, Sendable {
            /// 绑定ID
            let bindingId: Int
            /// 自己与成员的亲属关系
            let relationship: String
            /// 自身角色
            let role: String
            /// 是否是本人主账号
            let isPrimary: Bool
        }
    }

    /// 生成分享票据请求入参
    struct GenerateShareTicketPayload: Encodable, Sendable {
        /// 分享渠道标识（二维码/链接等）
        let channel: String
        /// 分享授予权限：edit / view
        let permission: String
    }

    /// 解析票据接口请求体
    struct ShareTicketPayload: Encodable, Sendable {
        /// 需要解析的分享票据
        let shareTicket: String
    }

    /// 接受分享、绑定成员接口入参
    struct AcceptSharePayload: Encodable, Sendable {
        /// 分享票据凭证
        let shareTicket: String
        /// 标准亲属关系编码
        let relationship: String
        /// 自定义亲属关系文本，无则传空字符串
        let customRelationship: String
    }

    /// 修改绑定亲属关系请求体
    struct UpdateBindingPayload: Encodable, Sendable {
        /// 新的亲属关系编码
        let relationship: String
    }

    // MARK: - API 接口方法
    /// 获取指定ID成员完整详情
    /// - Parameter memberID: 成员ID
    /// - Returns: 成员全量详情模型
    func fetchMemberDetail(memberID: Int) async throws -> MemberDetailResponse {
        try await postRequest(
            method: .get,
            path: "/api/v1/medical/members/\(memberID)/",
            body: Optional<String>.none,
            responseType: MemberDetailResponse.self
        )
    }

    /// 生成成员分享票据（用于二维码/分享链接）
    /// - Parameters:
    ///   - memberID: 待分享成员ID
    ///   - channel: 分享渠道标识
    ///   - permission: 授予权限，默认edit可编辑
    /// - Returns: 票据+二维码内容
    func generateShareTicket(
        memberID: Int,
        channel: String,
        permission: String = "edit"
    ) async throws -> ShareTicketResponse {
        try await postRequest(
            method: .post,
            path: "/api/v1/medical/members/\(memberID)/share-ticket/",
            body: GenerateShareTicketPayload(channel: channel, permission: permission),
            responseType: ShareTicketResponse.self
        )
    }

    /// 解析分享票据，预览分享信息（未真正绑定）
    /// - Parameter ticket: 分享票据字符串
    /// - Returns: 分享预览信息、发起人、成员基础信息
    func resolveShareTicket(_ ticket: String) async throws -> ShareResolveResponse {
        try await postRequest(
            method: .post,
            path: "/api/v1/medical/member-share-ticket/resolve/",
            body: ShareTicketPayload(shareTicket: ticket),
            responseType: ShareResolveResponse.self
        )
    }

    /// 确认接受分享，完成成员绑定
    /// - Parameters:
    ///   - ticket: 分享票据
    ///   - relationship: 标准亲属关系编码
    ///   - customRelationship: 自定义亲属关系文本，默认为空
    /// - Returns: 绑定成功后的成员模型
    func acceptShareTicket(
        _ ticket: String,
        relationship: String,
        customRelationship: String = ""
    ) async throws -> RemoteMember {
        try await postRequest(
            method: .post,
            path: "/api/v1/medical/member-share-ticket/accept/",
            body: AcceptSharePayload(
                shareTicket: ticket,
                relationship: relationship,
                customRelationship: customRelationship
            ),
            responseType: RemoteMember.self
        )
    }

    /// 修改已有绑定关系的亲属关系
    /// - Parameters:
    ///   - bindingID: 绑定关系ID
    ///   - relationship: 新亲属关系编码
    /// - Returns: 更新后的成员模型
    func updateBinding(bindingID: Int, relationship: String) async throws -> RemoteMember {
        try await postRequest(
            method: .patch,
            path: "/api/v1/medical/member-bindings/\(bindingID)/",
            body: UpdateBindingPayload(relationship: relationship),
            responseType: RemoteMember.self
        )
    }

    /// 解除成员绑定关系
    /// - Parameter bindingID: 绑定关系ID
    func unbind(bindingID: Int) async throws {
        _ = try await postRequest(
            method: .delete,
            path: "/api/v1/medical/member-bindings/\(bindingID)/",
            body: Optional<String>.none,
            responseType: EmptyResponse.self
        )
    }

    /// 空返回体包装，用于无返回数据的接口（解绑）
    private struct EmptyResponse: Decodable {}

    /// 通用网络请求封装方法
    /// - Parameters:
    ///   - method: HTTP 请求方法 GET/POST/PATCH/DELETE
    ///   - path: 接口路径
    ///   - body: 请求JSON体，nil代表无请求体
    ///   - responseType: 需要解码的返回模型类型
    /// - Returns: 解码后的业务模型
    private func postRequest<T: Decodable, B: Encodable>(
        method: SparkHTTPMethod,
        path: String,
        body: B?,
        responseType: T.Type
    ) async throws -> T {
        // 包装请求Body，无参数传空
        let sparkBody: SparkBody = {
            guard let body else { return .none }
            return .json(AnyEncodable(body))
        }()
        // 构建可缓存网络操作
        let op = CacheableSparkNetworkOperation(
            name: "Medical.Member.\(path)",
            apiName: "SparkMedicalMemberAPI",
            request: SparkNetworkRequest(
                method: method,
                path: path,
                body: sparkBody,
                strategy: NetworkStrategy(
                    requiresAuth: true,          // 全部接口需要登录鉴权
                    allowETag: false,            // 关闭ETag缓存
                    serialKey: "medical.member.\(path)", // 串行防并发标识
                    retryConfig: .default,       // 默认重试策略
                    isIdempotent: method == .get,// GET为幂等，可安全重试
                    queuePriority: .high         // 高优先级网络队列
                )
            )
        )
        // 执行网络请求
        let response = try await configuration.execute(op)
        // 使用医疗专用解码器解析外层code/data包装返回体
        return try APIResponseDecoder.decodeWrappedData(T.self, from: response, decoder: .medicalAPI)
    }
}
