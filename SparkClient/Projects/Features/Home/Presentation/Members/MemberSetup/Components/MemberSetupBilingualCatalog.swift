import Foundation

/// 成员创建双语选项工具类
/// 展示逻辑：跟随系统语言，英文环境展示英文文本；
/// 持久化/存储逻辑：统一存储中文标准值，与表单通用选择器 SparkFormMenuCustomPicker 规则保持一致
enum MemberSetupBilingualCatalog {
    /// 是否偏好英文展示
    static var prefersEnglish: Bool { SparkFormCatalogMenuLocale.prefersEnglish }

    /// 根据语言偏好返回单条选项展示文本
    /// - Parameter item: 双语条目模型
    /// - Returns: 英文/中文展示文案
    static func display(_ item: SparkBilingualItem) -> String {
        prefersEnglish ? item.en : item.cn
    }

    /// 批量转换双语条目为前端展示文案数组
    static func displayOptions(_ items: [SparkBilingualItem]) -> [String] {
        items.map { display($0) }
    }

    /// 获取用于持久化存储的中文标准值数组
    static func storedValues(_ items: [SparkBilingualItem]) -> [String] {
        items.map(\.cn)
    }

    /// 将前端传入的原始字符串统一转为标准中文存储值
    /// 兼容两种场景：传入中文存储值 / 传入英文展示文本
    /// - Parameters:
    ///   - raw: 前端传入原始字符串
    ///   - items: 可选条目数据源
    /// - Returns: 匹配到则返回标准中文，无匹配直接返回原字符串兜底
    static func canonicalCN(_ raw: String, in items: [SparkBilingualItem]) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.first { $0.cn == trimmed || $0.en == trimmed }?.cn ?? trimmed
    }

    /// 根据存储的中文值，获取前端展示用的本地化文案
    /// - Parameters:
    ///   - stored: 数据库持久化中文标准值
    ///   - items: 可选条目数据源
    /// - Returns: 适配当前语言的展示文本
    static func displayString(stored: String, in items: [SparkBilingualItem]) -> String {
        let cn = canonicalCN(stored, in: items)
        guard let item = items.first(where: { $0.cn == cn }) else { return stored }
        return display(item)
    }

    /// 判断存储值是否存在于可选条目列表内
    static func contains(stored: String, in items: [SparkBilingualItem]) -> Bool {
        let cn = canonicalCN(stored, in: items)
        return items.contains { $0.cn == cn }
    }
}

/// 职业选项模型
/// Sendable：线程安全，可跨异步任务传递
struct MemberSetupOccupationOption: Sendable {
    /// SF图标名称
    let icon: String
    /// 持久化存储用中文标准值
    let valueCN: String
    /// 职业标题双语文本
    let title: SparkBilingualItem
    /// 职业特征描述双语文本
    let subtitle: SparkBilingualItem

    /// 持久化存储值，统一使用中文
    var value: String { valueCN }
    /// 适配系统语言的展示标题
    var displayTitle: String { MemberSetupBilingualCatalog.display(title) }
    /// 适配系统语言的展示副标题
    var displaySubtitle: String { MemberSetupBilingualCatalog.display(subtitle) }
}

/// 职业分类枚举，内置全部预设职业选项数据
enum MemberSetupOccupationCatalog {
    /// 全部职业选项分组数组
    static let groups: [MemberSetupOccupationOption] = [
        .init(
            icon: "desktopcomputer",
            valueCN: "程序员 / 开发 / 产品 / 设计",
            title: .init(cn: "程序员 / 开发 / 产品 / 设计", en: "Developer / Product / Design"),
            subtitle: .init(
                cn: "偏久坐、用脑强度高、常伴随加班与屏幕暴露",
                en: "Mostly sedentary, high cognitive load, often long screen time"
            )
        ),
        .init(
            icon: "building.2.fill",
            valueCN: "办公室文职 / 财务 / 法务 / 企业管理",
            title: .init(cn: "办公室文职 / 财务 / 法务 / 企业管理", en: "Office / Finance / Legal / Management"),
            subtitle: .init(
                cn: "常规办公室工作、久坐明显、节奏相对固定",
                en: "Regular office work, mostly sedentary, steady routine"
            )
        ),
        .init(
            icon: "graduationcap.fill",
            valueCN: "教师 / 教培人员",
            title: .init(cn: "教师 / 教培人员", en: "Teacher / Educator"),
            subtitle: .init(
                cn: "教学授课、站立与沟通较多，作息受课程安排影响",
                en: "Teaching-focused, more standing and communication, schedule-driven"
            )
        ),
        .init(
            icon: "cross.case.fill",
            valueCN: "医护与健康服务人员",
            title: .init(cn: "医护与健康服务人员", en: "Healthcare worker"),
            subtitle: .init(
                cn: "倒班、站立、夜班与职业暴露风险相对更高",
                en: "Shift work, standing, night shifts, higher occupational exposure"
            )
        ),
        .init(
            icon: "briefcase.fill",
            valueCN: "销售 / 商务 / 自由职业",
            title: .init(cn: "销售 / 商务 / 自由职业", en: "Sales / Business / Freelance"),
            subtitle: .init(
                cn: "出行沟通频繁，作息弹性大，饮食与休息不稳定",
                en: "Frequent travel and meetings, flexible but irregular meals and rest"
            )
        ),
        .init(
            icon: "truck.box.fill",
            valueCN: "司机 / 物流 / 快递 / 制造业工人",
            title: .init(cn: "司机 / 物流 / 快递 / 制造业工人", en: "Driver / Logistics / Manufacturing worker"),
            subtitle: .init(
                cn: "久坐、体力劳动或重复作业并存，作息与负荷差异大",
                en: "Mix of sitting, physical labor, and repetitive work with variable load"
            )
        )
    ]
}

/// 生活习惯相关双语选项数据源：吸烟、饮酒、运动时长等
enum MedicalLifestyleOptionCatalog {
    /// 吸烟/饮酒年限选项
    static let historyDurations: [SparkBilingualItem] = [
        .init(cn: "不足1年", en: "Less than 1 year"),
        .init(cn: "1-3年", en: "1-3 years"),
        .init(cn: "3-5年", en: "3-5 years"),
        .init(cn: "5-10年", en: "5-10 years"),
        .init(cn: "10年以上", en: "More than 10 years")
    ]

    /// 戒烟时长选项
    static let quitDurations: [SparkBilingualItem] = [
        .init(cn: "不足6个月", en: "Less than 6 months"),
        .init(cn: "6个月-1年", en: "6 months to 1 year"),
        .init(cn: "1-2年", en: "1-2 years"),
        .init(cn: "2-5年", en: "2-5 years"),
        .init(cn: "5年以上", en: "More than 5 years")
    ]

    /// 每日吸烟量选项
    static let dailySmokingAmounts: [SparkBilingualItem] = [
        .init(cn: "几支/日", en: "A few per day"),
        .init(cn: "半包/日", en: "Half pack/day"),
        .init(cn: "1包/日", en: "1 pack/day"),
        .init(cn: "1-2包/日", en: "1-2 packs/day"),
        .init(cn: "2包以上/日", en: "More than 2 packs/day")
    ]

    /// 单次运动时长选项
    static let exerciseDurations: [SparkBilingualItem] = [
        .init(cn: "15分钟", en: "15 minutes"),
        .init(cn: "30分钟", en: "30 minutes"),
        .init(cn: "45分钟", en: "45 minutes"),
        .init(cn: "1小时", en: "1 hour"),
        .init(cn: "1小时以上", en: "More than 1 hour")
    ]

    /// 吸烟年限选项（复用通用年限数组）
    static var smokingHistoryDurations: [SparkBilingualItem] { historyDurations }
    /// 饮酒年限选项（复用通用年限数组）
    static var drinkingHistoryDurations: [SparkBilingualItem] { historyDurations }
}

/// 成员创建页面预设下拉选项数据源：饮酒类型、运动类型
enum MemberSetupPresetOptionsCatalog {
    /// 酒类类型双语选项
    static let drinkingTypes: [SparkBilingualItem] = [
        .init(cn: "白酒", en: "Baijiu"),
        .init(cn: "啤酒", en: "Beer"),
        .init(cn: "红酒/葡萄酒", en: "Red wine"),
        .init(cn: "黄酒", en: "Huangjiu"),
        .init(cn: "洋酒", en: "Spirits"),
        .init(cn: "果酒/米酒", en: "Fruit wine / Rice wine")
    ]

    /// 运动类型双语选项
    static let exerciseTypes: [SparkBilingualItem] = [
        .init(cn: "散步/快走", en: "Walking / Brisk walking"),
        .init(cn: "跑步", en: "Running"),
        .init(cn: "骑行", en: "Cycling"),
        .init(cn: "游泳", en: "Swimming"),
        .init(cn: "器械健身", en: "Gym training"),
        .init(cn: "力量训练", en: "Strength training"),
        .init(cn: "瑜伽/普拉提", en: "Yoga / Pilates"),
        .init(cn: "球类运动", en: "Ball sports"),
        .init(cn: "爬山/徒步", en: "Hiking"),
        .init(cn: "广场舞/操课", en: "Group dance / Aerobics")
    ]

    /// 饮酒类型用于持久化的中文标准值数组
    static var presetDrinkingTypeValues: [String] {
        MemberSetupBilingualCatalog.storedValues(drinkingTypes)
    }

    /// 运动类型用于持久化的中文标准值数组
    static var presetExerciseTypeValues: [String] {
        MemberSetupBilingualCatalog.storedValues(exerciseTypes)
    }
}
