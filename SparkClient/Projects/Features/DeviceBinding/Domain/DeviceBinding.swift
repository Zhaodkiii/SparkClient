import Foundation

/// 设备绑定记录（本地持久化，不与服务器同步）。
nonisolated struct DeviceBinding: Identifiable, Codable, Equatable, Sendable {
    /// 绑定记录唯一标识（本地 UUID）。
    var id: String
    /// 数据来源类型。
    var sourceType: HealthDataSourceType
    /// 绑定的成员 ID（对应服务端 `Member.id`）。
    var memberId: Int
    /// 成员姓名缓存。
    var memberName: String
    /// 成员关系缓存（`self` / `father` 等）。
    var memberRelationship: String
    /// 成员头像 URL 缓存。
    var memberAvatarUrl: String
    /// 授权状态。
    var authorizationStatus: HealthAuthorizationStatus
    /// 绑定时间。
    var bindTime: Date
    /// 最近一次授权校验时间。
    var lastAuthCheckTime: Date?
    /// 账号标识（如第三方账号手机号，苹果健康无）。
    var accountIdentifier: String?
    /// 账号展示文本。
    var accountDisplayText: String?
    /// 授权异常时的错误信息。
    var errorMessage: String?

    init(
        id: String = UUID().uuidString,
        sourceType: HealthDataSourceType,
        memberId: Int,
        memberName: String,
        memberRelationship: String,
        memberAvatarUrl: String = "",
        authorizationStatus: HealthAuthorizationStatus = .notDetermined,
        bindTime: Date = Date(),
        lastAuthCheckTime: Date? = nil,
        accountIdentifier: String? = nil,
        accountDisplayText: String? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.sourceType = sourceType
        self.memberId = memberId
        self.memberName = memberName
        self.memberRelationship = memberRelationship
        self.memberAvatarUrl = memberAvatarUrl
        self.authorizationStatus = authorizationStatus
        self.bindTime = bindTime
        self.lastAuthCheckTime = lastAuthCheckTime
        self.accountIdentifier = accountIdentifier
        self.accountDisplayText = accountDisplayText
        self.errorMessage = errorMessage
    }
}