import SwiftUI

struct AllergyCategoryGroup: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let systemImage: String
    let tint: Color
    let allergens: [String]
    let detailCategory: String
}

enum AllergyRecordFormSupport {
    static let introText = "记录明确的过敏史是保护您就医与用药安全的核心防线。系统将深度解析您的过敏原，在未来的体检排查、影像检查（如造影剂）及日常用药中自动为您拦截高危禁忌。"

    static let customCategory = "自定义"

    static let allergyCategories: [AllergyCategoryGroup] = [
        .init(
            title: "药物过敏 (体检及就医高危项)",
            systemImage: "pills.fill",
            tint: .red,
            allergens: ["青霉素/阿莫西林", "头孢菌素", "阿司匹林/解热镇痛药", "磺胺类药物", "碘造影剂 (增强CT必备)", "局部麻醉药"],
            detailCategory: "药物过敏"
        ),
        .init(
            title: "食物过敏",
            systemImage: "fork.knife",
            tint: .orange,
            allergens: ["鱼/虾/蟹海鲜", "花生/坚果", "鸡蛋", "牛奶/乳制品", "大豆/豆制品", "小麦/麸质", "芒果/热带水果"],
            detailCategory: "食物过敏"
        ),
        .init(
            title: "环境与吸入性过敏 (季节性)",
            systemImage: "leaf.fill",
            tint: .green,
            allergens: ["花粉/柳絮/艾草", "尘螨", "动物皮毛/猫狗皮屑", "霉菌", "杨树毛/梧桐絮"],
            detailCategory: "环境与吸入性过敏"
        ),
        .init(
            title: "接触性、昆虫与其它",
            systemImage: "hand.raised.fill",
            tint: .purple,
            allergens: ["乳胶制品", "油漆", "金属镍/饰品", "紫外线/日光", "染发剂/香精", "蚊虫/蜂叮咬"],
            detailCategory: "接触性与其它"
        )
    ]

    static func filteredCategories(matching searchText: String) -> [AllergyCategoryGroup] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return allergyCategories }

        return allergyCategories.compactMap { category in
            if CatalogItemSearch.matches(category.title, searchText: trimmed) {
                return category
            }

            let matchedAllergens = category.allergens.filter { CatalogItemSearch.matches($0, searchText: trimmed) }
            guard matchedAllergens.isEmpty == false else { return nil }
            return AllergyCategoryGroup(
                title: category.title,
                systemImage: category.systemImage,
                tint: category.tint,
                allergens: matchedAllergens,
                detailCategory: category.detailCategory
            )
        }
    }

    static func detailCategory(for allergen: String) -> String {
        for category in allergyCategories where category.allergens.contains(allergen) {
            return category.detailCategory
        }
        return customCategory
    }

    static func summaryLine(name: String, detail: MedicalGuideAllergyDetail?) -> String {
        var pieces = [name]
        if let detail {
            if detail.severity.isEmpty == false {
                pieces.append(detail.severity)
            }
            if detail.reactions.isEmpty == false {
                pieces.append(detail.reactions.joined(separator: "、"))
            }
            if detail.category.isEmpty == false {
                pieces.append(detail.category)
            }
            if detail.notes.isEmpty == false {
                pieces.append(detail.notes)
            }
        }
        return pieces.joined(separator: " · ")
    }

    static func systemImage(for category: String) -> String {
        if category.contains("药物") { return "pills.fill" }
        if category.contains("食物") { return "fork.knife" }
        if category.contains("环境") { return "leaf.fill" }
        if category.contains("接触") { return "hand.raised.fill" }
        return "allergens"
    }

    static func tint(for category: String) -> Color {
        if category.contains("药物") { return .red }
        if category.contains("食物") { return .orange }
        if category.contains("环境") { return .green }
        if category.contains("接触") { return .purple }
        return .accentColor
    }

    static func severityTint(_ severity: String) -> Color {
        switch severity {
        case "严重":
            return .red
        case "中度":
            return .yellow
        default:
            return .green
        }
    }
}
