import Foundation

/// 当前登录用户在应用内的档案摘要（账号维度），与家庭成员 `Member` 不同：后者用于病历归属。
struct UserProfile: Equatable, Sendable {
    /// 服务端账号主键，与会话中的 `accountID` 一致。
    let id: Int64
    /// 登录账号邮箱（Apple 隐私转发邮箱等）。
    let email: String
    /// 展示名（如 Apple 登录回传的姓名或用户昵称）。
    let displayName: String
    /// 档案首次创建时间。
    let createdAt: Date
    /// 最近一次成功登录时间，用于问候与调试展示。
    let lastSignedInAt: Date
}
