import Foundation

/// 成员引导选项目录：非中文环境展示英文，持久化仍用中文 canonical 值（与 `SparkFormMenuCustomPicker` 一致）。
enum MemberSetupBilingualCatalog {
    static var prefersEnglish: Bool { SparkFormCatalogMenuLocale.prefersEnglish }

    static func display(_ item: SparkBilingualItem) -> String {
        prefersEnglish ? item.en : item.cn
    }

    static func displayOptions(_ items: [SparkBilingualItem]) -> [String] {
        items.map { display($0) }
    }

    static func storedValues(_ items: [SparkBilingualItem]) -> [String] {
        items.map(\.cn)
    }

    static func canonicalCN(_ raw: String, in items: [SparkBilingualItem]) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.first { $0.cn == trimmed || $0.en == trimmed }?.cn ?? trimmed
    }

    static func displayString(stored: String, in items: [SparkBilingualItem]) -> String {
        let cn = canonicalCN(stored, in: items)
        guard let item = items.first(where: { $0.cn == cn }) else { return stored }
        return display(item)
    }

    static func contains(stored: String, in items: [SparkBilingualItem]) -> Bool {
        let cn = canonicalCN(stored, in: items)
        return items.contains { $0.cn == cn }
    }
}

struct MemberSetupOccupationOption: Sendable {
    let icon: String
    let valueCN: String
    let title: SparkBilingualItem
    let subtitle: SparkBilingualItem

    var value: String { valueCN }
    var displayTitle: String { MemberSetupBilingualCatalog.display(title) }
    var displaySubtitle: String { MemberSetupBilingualCatalog.display(subtitle) }
}

enum MemberSetupOccupationCatalog {
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

enum MedicalLifestyleOptionCatalog {
    static let historyDurations: [SparkBilingualItem] = [
        .init(cn: "不足1年", en: "Less than 1 year"),
        .init(cn: "1-3年", en: "1-3 years"),
        .init(cn: "3-5年", en: "3-5 years"),
        .init(cn: "5-10年", en: "5-10 years"),
        .init(cn: "10年以上", en: "More than 10 years")
    ]

    static let quitDurations: [SparkBilingualItem] = [
        .init(cn: "不足6个月", en: "Less than 6 months"),
        .init(cn: "6个月-1年", en: "6 months to 1 year"),
        .init(cn: "1-2年", en: "1-2 years"),
        .init(cn: "2-5年", en: "2-5 years"),
        .init(cn: "5年以上", en: "More than 5 years")
    ]

    static let dailySmokingAmounts: [SparkBilingualItem] = [
        .init(cn: "几支/日", en: "A few per day"),
        .init(cn: "半包/日", en: "Half pack/day"),
        .init(cn: "1包/日", en: "1 pack/day"),
        .init(cn: "1-2包/日", en: "1-2 packs/day"),
        .init(cn: "2包以上/日", en: "More than 2 packs/day")
    ]

    static let exerciseDurations: [SparkBilingualItem] = [
        .init(cn: "15分钟", en: "15 minutes"),
        .init(cn: "30分钟", en: "30 minutes"),
        .init(cn: "45分钟", en: "45 minutes"),
        .init(cn: "1小时", en: "1 hour"),
        .init(cn: "1小时以上", en: "More than 1 hour")
    ]

    static var smokingHistoryDurations: [SparkBilingualItem] { historyDurations }
    static var drinkingHistoryDurations: [SparkBilingualItem] { historyDurations }
}

enum MemberSetupPresetOptionsCatalog {
    static let drinkingTypes: [SparkBilingualItem] = [
        .init(cn: "白酒", en: "Baijiu"),
        .init(cn: "啤酒", en: "Beer"),
        .init(cn: "红酒/葡萄酒", en: "Red wine"),
        .init(cn: "黄酒", en: "Huangjiu"),
        .init(cn: "洋酒", en: "Spirits"),
        .init(cn: "果酒/米酒", en: "Fruit wine / Rice wine")
    ]

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

    static var presetDrinkingTypeValues: [String] {
        MemberSetupBilingualCatalog.storedValues(drinkingTypes)
    }

    static var presetExerciseTypeValues: [String] {
        MemberSetupBilingualCatalog.storedValues(exerciseTypes)
    }
}
