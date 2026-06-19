import Foundation

/// 新增家庭成员引导页填写草稿模型
/// Equatable：支持等值对比；Sendable：线程安全，可跨异步任务传递
struct MemberSetupDraft: Equatable, Sendable {
    /// 成员姓名
    var name: String = ""
    /// 出生日期，未填写为nil
    var birthDate: Date? = nil
    /// 亲属关系编码，使用默认关系编码兜底
    var relationshipCode: String = MemberRelationshipCatalog.defaultCode
    /// 性别编码，默认未选择状态
    var gender: String = MemberRelationshipCatalog.unsetGender
}

/// 家庭成员创建流程可选健康功能模块枚举
/// rawValue：对应后端存储模块编码；CaseIterable：可遍历全部模块；Identifiable：SwiftUI列表可用；Sendable：线程安全
enum MemberSetupModule: String, CaseIterable, Identifiable, Sendable {
    /// 医疗健康模块（慢病、用药、体检、症状随访）
    case medical
    /// 饮食营养模块（饮食、体重、营养管理）
    case nutrition
    /// 日常健康模块（运动睡眠，预留未开放）
    case dailyHealth = "daily_health"

    /// Identifiable 协议唯一标识，直接使用后端raw编码
    var id: String { rawValue }

    /// 页面展示排序序号
    var displayOrder: Int {
        switch self {
        case .medical: return 0
        case .nutrition: return 1
        case .dailyHealth: return 2
        }
    }

    /// 模块标题（多语言，带兜底默认文案）
    var title: String {
        switch self {
        case .medical:
            return L10n.text("member.module.medical.title", fallback: "医疗模块")
        case .nutrition:
            return L10n.text("member.module.nutrition.title", fallback: "饮食健康")
        case .dailyHealth:
            return L10n.text("member.module.daily_health.title", fallback: "日常健康")
        }
    }

    /// 模块副标题/功能简介
    var subtitle: String {
        switch self {
        case .medical:
            return L10n.text("member.module.medical.subtitle", fallback: "慢病、用药、体检、症状随访")
        case .nutrition:
            return L10n.text("member.module.nutrition.subtitle", fallback: "饮食目标、营养、体重管理")
        case .dailyHealth:
            return L10n.text("member.module.daily_health.subtitle", fallback: "运动、睡眠、饮水、照护提醒（预留）")
        }
    }

    /// 是否在新建成员引导页展示
    /// dailyHealth 为预留模块，创建流程隐藏
    var isVisibleInSetup: Bool {
        self != .dailyHealth
    }
}
