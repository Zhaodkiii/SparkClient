import Foundation

/// 设备绑定相关错误。
nonisolated enum DeviceBindingError: Error, LocalizedError, Equatable {
    /// 数据源当前未接入。
    case sourceNotAvailable(HealthDataSourceType)
    /// 设备不支持 HealthKit。
    case healthKitUnavailable
    /// 数据源已被其他成员绑定。
    case alreadyBoundToOtherMember(DeviceBinding)
    /// 成员已绑定同类型健康账号。
    case memberAlreadyBoundSameSource
    /// 本地存储读写失败。
    case storageFailure
    /// 授权请求失败。
    case authorizationFailed
    /// 绑定操作进行中，拒绝并发触发。
    case bindingInProgress
    /// 未登录，缺少账号上下文。
    case accountRequired

    var errorDescription: String? {
        switch self {
        case .sourceNotAvailable(let type):
            return L10n.format("device.access.not_available", fallback: "%@暂未接入，敬请期待", type.displayName)
        case .healthKitUnavailable:
            return L10n.text("device.error.healthkit_unavailable", fallback: "当前设备不支持苹果健康")
        case .alreadyBoundToOtherMember(let binding):
            return L10n.format(
                "device.switch.already_bound_to_other",
                fallback: "%@当前已绑定给「%@」",
                binding.sourceType.displayName,
                binding.memberName
            )
        case .memberAlreadyBoundSameSource:
            return L10n.text("device.switch.member_has_other_binding", fallback: "该成员已绑定其他健康账号，一个成员只能绑定一个健康账号")
        case .storageFailure:
            return L10n.text("device.error.storage_failed", fallback: "设备数据读取失败，请稍后重试")
        case .authorizationFailed:
            return L10n.text("device.error.bind_failed", fallback: "绑定失败，请稍后重试")
        case .bindingInProgress:
            return L10n.text("device.error.binding_in_progress", fallback: "绑定进行中，请稍候")
        case .accountRequired:
            return L10n.text("device.error.login_required", fallback: "请先登录后再绑定设备")
        }
    }
}