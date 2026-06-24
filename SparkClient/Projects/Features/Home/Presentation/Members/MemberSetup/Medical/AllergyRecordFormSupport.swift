import SwiftUI

struct AllergyCategoryGroup: Identifiable, Equatable {
    let titleItem: SparkBilingualItem
    let systemImage: String
    let tint: Color
    let allergenItems: [SparkBilingualItem]
    let detailCategoryCN: String

    var id: String { titleItem.cn }
    var title: String { MedicalFormBilingualCatalog.display(titleItem) }
    var allergens: [String] { allergenItems.map(\.cn) }
    var detailCategory: String { detailCategoryCN }
}

enum AllergyRecordFormSupport {
    static var introText: String { L10n.text("member.setup.medical.allergy.intro_form") }

    static var customCategory: String { MedicalFormBilingualCatalog.allergyCustomCategoryCN }

    static var allergyCategories: [AllergyCategoryGroup] {
        MedicalFormBilingualCatalog.allergyCategoryDefinitions.map { definition in
            AllergyCategoryGroup(
                titleItem: definition.title,
                systemImage: definition.systemImage,
                tint: tint(forDetailCategory: definition.detailCategoryCN),
                allergenItems: definition.allergens,
                detailCategoryCN: definition.detailCategoryCN
            )
        }
    }

    static var severityOptions: [String] {
        MedicalFormBilingualCatalog.allergySeverityOptions.map(\.cn)
    }

    static var reactionOptions: [String] {
        MedicalFormBilingualCatalog.allergyReactionOptions.map(\.cn)
    }

    static func displayAllergen(_ stored: String) -> String {
        MedicalFormBilingualCatalog.displayStored(stored, in: MedicalFormBilingualCatalog.allAllergyItems)
    }

    static func displaySeverity(_ stored: String) -> String {
        MedicalFormBilingualCatalog.displayStored(stored, in: MedicalFormBilingualCatalog.allergySeverityOptions)
    }

    static func displayReaction(_ stored: String) -> String {
        MedicalFormBilingualCatalog.displayStored(stored, in: MedicalFormBilingualCatalog.allergyReactionOptions)
    }

    static func displayDetailCategory(_ stored: String) -> String {
        MedicalFormBilingualCatalog.displayStored(stored, in: MedicalFormBilingualCatalog.allergyDetailCategories + [
            .init(cn: customCategory, en: L10n.text("member.setup.medical.allergy.custom_category"))
        ])
    }

    static func filteredCategories(matching searchText: String) -> [AllergyCategoryGroup] {
        MedicalFormBilingualCatalog.filteredAllergyCategories(matching: searchText).map { definition in
            AllergyCategoryGroup(
                titleItem: definition.title,
                systemImage: definition.systemImage,
                tint: tint(forDetailCategory: definition.detailCategoryCN),
                allergenItems: definition.allergens,
                detailCategoryCN: definition.detailCategoryCN
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
        var pieces = [displayAllergen(name)]
        if let detail {
            if detail.severity.isEmpty == false {
                pieces.append(displaySeverity(detail.severity))
            }
            if detail.reactions.isEmpty == false {
                let reactions = detail.reactions.map { displayReaction($0) }.joined(separator: "、")
                pieces.append(reactions)
            }
            if detail.category.isEmpty == false {
                pieces.append(displayDetailCategory(detail.category))
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
        tint(forDetailCategory: category)
    }

    static func severityTint(_ severity: String) -> Color {
        let canonical = MedicalFormBilingualCatalog.allergySeverityOptions.first(where: {
            $0.cn == severity || $0.en == severity
        })?.cn ?? severity
        switch canonical {
        case "严重":
            return .red
        case "中度":
            return .yellow
        default:
            return .green
        }
    }

    private static func tint(forDetailCategory category: String) -> Color {
        if category.contains("药物") { return .red }
        if category.contains("食物") { return .orange }
        if category.contains("环境") { return .green }
        if category.contains("接触") { return .purple }
        return .accentColor
    }
}
