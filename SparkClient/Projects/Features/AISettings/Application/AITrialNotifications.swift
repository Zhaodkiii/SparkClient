import Foundation

extension Notification.Name {
    /// 收到试用申请审核结果推送（通过/拒绝）后触发统一刷新。
    static let aiTrialApplicationResultReceived = Notification.Name("aiTrialApplicationResultReceived")

    /// 试用申请提交后，若系统通知权限尚未决定，需要先展示应用内说明“我们将统一通知你”。
    static let aiTrialNotificationPermissionNeedsPrePrompt = Notification.Name("aiTrialNotificationPermissionNeedsPrePrompt")
}

