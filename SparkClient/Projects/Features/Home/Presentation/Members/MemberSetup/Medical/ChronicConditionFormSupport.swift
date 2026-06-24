import Foundation

struct ChronicDiseaseCategoryGroup: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let systemImage: String
    let diseases: [String]
}

enum ChronicConditionFormSupport {
    static let introText = "记录您的过往疾病与慢性病史，能协助系统更精准地评估当前的健康基线，并在后续的AI体检推荐或就医指导中，自动规避禁忌、强化专项防御。"

    static let diseaseCategories: [ChronicDiseaseCategoryGroup] = [
        .init(
            title: L10n.text("member.setup.medical.chronic.chronic.12d496"),
            systemImage: "heart.fill",
            diseases: ["高血压", "冠心病", "高脂血症", "脑卒中/脑梗死", "心律失常", "心肌缺血"]
        ),
        .init(
            title: L10n.text("member.setup.medical.chronic.chronic.4bfb23"),
            systemImage: "drop.fill",
            diseases: ["2型糖尿病", "1型糖尿病", "高尿酸血症/痛风", "甲状腺结节", "甲亢/甲减", "骨质疏松"]
        ),
        .init(
            title: L10n.text("member.setup.medical.chronic.chronic.4bd70f"),
            systemImage: "lungs.fill",
            diseases: ["慢性胃炎/胃溃疡", "脂肪肝", "胆囊结石/胆囊炎", "支气管哮喘", "慢性支气管炎/COPD", "过敏性鼻炎"]
        ),
        .init(
            title: L10n.text("member.setup.medical.chronic.chronic.d4632a"),
            systemImage: "figure.walk",
            diseases: ["慢性肾脏病", "肾结石/尿路结石", "前列腺增生", "颈椎病/腰椎间盘突出", "退行性关节炎"]
        )
    ]

    static func filteredCategories(matching searchText: String) -> [ChronicDiseaseCategoryGroup] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return diseaseCategories }

        return diseaseCategories.compactMap { category in
            if CatalogItemSearch.matches(category.title, searchText: trimmed) {
                return category
            }

            let matchedDiseases = category.diseases.filter { CatalogItemSearch.matches($0, searchText: trimmed) }
            guard matchedDiseases.isEmpty == false else { return nil }
            return ChronicDiseaseCategoryGroup(
                title: category.title,
                systemImage: category.systemImage,
                diseases: matchedDiseases
            )
        }
    }

    static func summaryLine(name: String, detail: MedicalGuideChronicConditionDetail?) -> String {
        var pieces = [name]
        if let detail {
            if detail.diagnosedYear.isEmpty == false {
                pieces.append("\(detail.diagnosedYear)年确诊")
            }
            if detail.controlStatus.isEmpty == false {
                pieces.append(detail.controlStatus)
            }
            if detail.notes.isEmpty == false {
                pieces.append(detail.notes)
            }
        }
        return pieces.joined(separator: " · ")
    }
}
