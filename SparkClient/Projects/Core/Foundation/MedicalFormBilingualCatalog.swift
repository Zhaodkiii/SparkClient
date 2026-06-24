import Foundation

/// 医疗表单预设选项双语目录：展示随系统语言，持久化统一使用中文标准值。
enum MedicalFormBilingualCatalog {
    // MARK: - Symptom

    static let symptomDurationOptions: [SparkBilingualItem] = [
        .init(cn: "1天", en: "1 day"),
        .init(cn: "3天", en: "3 days"),
        .init(cn: "1周", en: "1 week"),
        .init(cn: "2周", en: "2 weeks"),
        .init(cn: "1个月", en: "1 month"),
        .init(cn: "3个月以上", en: "Over 3 months")
    ]

    static let symptomCategories: [MedicalBilingualCategoryGroup] = [
        .init(
            title: .init(cn: "全身与神经系统", en: "General and nervous system"),
            systemImage: "figure.stand",
            items: [
                .init(cn: "发热", en: "Fever"),
                .init(cn: "头痛", en: "Headache"),
                .init(cn: "眩晕/头晕", en: "Dizziness"),
                .init(cn: "疲劳/乏力", en: "Fatigue"),
                .init(cn: "睡眠障碍", en: "Sleep disorder"),
                .init(cn: "盗汗/异常出汗", en: "Night sweats / abnormal sweating"),
                .init(cn: "体重骤降", en: "Rapid weight loss")
            ]
        ),
        .init(
            title: .init(cn: "心肺与呼吸系统", en: "Cardiopulmonary and respiratory"),
            systemImage: "heart.fill",
            items: [
                .init(cn: "咳嗽", en: "Cough"),
                .init(cn: "咳痰", en: "Sputum"),
                .init(cn: "气促/呼吸困难", en: "Shortness of breath"),
                .init(cn: "胸痛", en: "Chest pain"),
                .init(cn: "心悸", en: "Palpitations"),
                .init(cn: "血压波动", en: "Blood pressure fluctuation")
            ]
        ),
        .init(
            title: .init(cn: "胃肠与代谢系统", en: "Gastrointestinal and metabolic"),
            systemImage: "fork.knife",
            items: [
                .init(cn: "胃肠不适", en: "GI discomfort"),
                .init(cn: "胃酸/反流", en: "Acid reflux"),
                .init(cn: "恶心/呕吐", en: "Nausea / vomiting"),
                .init(cn: "腹泻", en: "Diarrhea"),
                .init(cn: "便秘", en: "Constipation"),
                .init(cn: "血糖波动", en: "Blood sugar fluctuation"),
                .init(cn: "食欲改变", en: "Appetite change")
            ]
        ),
        .init(
            title: .init(cn: "肌肉与体表", en: "Musculoskeletal and skin"),
            systemImage: "figure.walk",
            items: [
                .init(cn: "关节疼痛", en: "Joint pain"),
                .init(cn: "肌肉酸痛", en: "Muscle soreness"),
                .init(cn: "异常浮肿", en: "Abnormal swelling"),
                .init(cn: "皮疹/瘙痒", en: "Rash / itching"),
                .init(cn: "脱发", en: "Hair loss"),
                .init(cn: "淋巴结肿大", en: "Lymph node swelling")
            ]
        )
    ]

    static var allSymptomItems: [SparkBilingualItem] {
        symptomCategories.flatMap(\.items)
    }

    // MARK: - Surgery

    static let surgeryRecoveryOptions: [SparkBilingualItem] = [
        .init(cn: "恢复良好", en: "Recovered well"),
        .init(cn: "定期随访", en: "Regular follow-up"),
        .init(cn: "仍有不适", en: "Still uncomfortable"),
        .init(cn: "不清楚", en: "Unknown")
    ]

    static let surgeryCategories: [MedicalBilingualCategoryGroup] = [
        .init(
            title: .init(cn: "普外与胃肠系统", en: "General surgery and GI"),
            systemImage: "cross.case.fill",
            items: [
                .init(cn: "阑尾切除", en: "Appendectomy"),
                .init(cn: "胆囊切除/微创", en: "Cholecystectomy / minimally invasive"),
                .init(cn: "疝气修补", en: "Hernia repair"),
                .init(cn: "肠胃息肉摘除", en: "GI polyp removal")
            ]
        ),
        .init(
            title: .init(cn: "骨科与运动医学", en: "Orthopedics and sports medicine"),
            systemImage: "figure.walk",
            items: [
                .init(cn: "骨折复位固定", en: "Fracture reduction and fixation"),
                .init(cn: "关节置换", en: "Joint replacement"),
                .init(cn: "半月板/韧带修复", en: "Meniscus / ligament repair"),
                .init(cn: "腰椎手术", en: "Lumbar spine surgery")
            ]
        ),
        .init(
            title: .init(cn: "心胸与血管", en: "Cardiothoracic and vascular"),
            systemImage: "heart.fill",
            items: [
                .init(cn: "心脏支架(PCI)", en: "Coronary stent (PCI)"),
                .init(cn: "心脏起搏器植入", en: "Pacemaker implantation"),
                .init(cn: "肺结节/肺叶切除", en: "Lung nodule / lobectomy")
            ]
        ),
        .init(
            title: .init(cn: "妇产与泌尿生殖", en: "OB/GYN and urogenital"),
            systemImage: "person.crop.circle.badge.plus",
            items: [
                .init(cn: "剖宫产", en: "Cesarean section"),
                .init(cn: "子宫肌瘤/囊肿剔除", en: "Uterine fibroid / cyst removal"),
                .init(cn: "肾/输尿管碎石术", en: "Kidney / ureter lithotripsy")
            ]
        ),
        .init(
            title: .init(cn: "五官与头颈", en: "ENT and head/neck"),
            systemImage: "eye.fill",
            items: [
                .init(cn: "甲状腺切除/消融", en: "Thyroidectomy / ablation"),
                .init(cn: "白内障摘除", en: "Cataract removal"),
                .init(cn: "扁桃体/腺样体切除", en: "Tonsil / adenoid removal")
            ]
        )
    ]

    static var allSurgeryProcedureItems: [SparkBilingualItem] {
        surgeryCategories.flatMap(\.items)
    }

    // MARK: - Allergy

    static let allergyCustomCategoryCN = "自定义"

    static let allergyDetailCategories: [SparkBilingualItem] = [
        .init(cn: "药物过敏", en: "Drug allergy"),
        .init(cn: "食物过敏", en: "Food allergy"),
        .init(cn: "环境与吸入性过敏", en: "Environmental and inhalant allergy"),
        .init(cn: "接触性与其它", en: "Contact and other")
    ]

    static let allergySeverityOptions: [SparkBilingualItem] = [
        .init(cn: "轻度", en: "Mild"),
        .init(cn: "中度", en: "Moderate"),
        .init(cn: "严重", en: "Severe")
    ]

    static let allergyReactionOptions: [SparkBilingualItem] = [
        .init(cn: "皮疹/发痒", en: "Rash / itching"),
        .init(cn: "红肿", en: "Swelling / redness"),
        .init(cn: "恶心呕吐", en: "Nausea / vomiting"),
        .init(cn: "腹痛/腹泻", en: "Abdominal pain / diarrhea"),
        .init(cn: "呼吸困难/哮喘", en: "Breathing difficulty / asthma"),
        .init(cn: "头晕/休克", en: "Dizziness / shock")
    ]

    static let allergyCategoryDefinitions: [AllergyBilingualCategoryDefinition] = [
        .init(
            title: .init(cn: "药物过敏 (体检及就医高危项)", en: "Drug allergies (high-risk for exams and care)"),
            systemImage: "pills.fill",
            tintKey: "drug",
            detailCategoryCN: "药物过敏",
            allergens: [
                .init(cn: "青霉素/阿莫西林", en: "Penicillin / amoxicillin"),
                .init(cn: "头孢菌素", en: "Cephalosporins"),
                .init(cn: "阿司匹林/解热镇痛药", en: "Aspirin / analgesics"),
                .init(cn: "磺胺类药物", en: "Sulfonamides"),
                .init(cn: "碘造影剂 (增强CT必备)", en: "Iodine contrast (enhanced CT)"),
                .init(cn: "局部麻醉药", en: "Local anesthetics")
            ]
        ),
        .init(
            title: .init(cn: "食物过敏", en: "Food allergies"),
            systemImage: "fork.knife",
            tintKey: "food",
            detailCategoryCN: "食物过敏",
            allergens: [
                .init(cn: "鱼/虾/蟹海鲜", en: "Seafood (fish / shrimp / crab)"),
                .init(cn: "花生/坚果", en: "Peanuts / tree nuts"),
                .init(cn: "鸡蛋", en: "Eggs"),
                .init(cn: "牛奶/乳制品", en: "Milk / dairy"),
                .init(cn: "大豆/豆制品", en: "Soy / soy products"),
                .init(cn: "小麦/麸质", en: "Wheat / gluten"),
                .init(cn: "芒果/热带水果", en: "Mango / tropical fruits")
            ]
        ),
        .init(
            title: .init(cn: "环境与吸入性过敏 (季节性)", en: "Environmental and inhalant allergies (seasonal)"),
            systemImage: "leaf.fill",
            tintKey: "environment",
            detailCategoryCN: "环境与吸入性过敏",
            allergens: [
                .init(cn: "花粉/柳絮/艾草", en: "Pollen / catkins / mugwort"),
                .init(cn: "尘螨", en: "Dust mites"),
                .init(cn: "动物皮毛/猫狗皮屑", en: "Animal fur / pet dander"),
                .init(cn: "霉菌", en: "Mold"),
                .init(cn: "杨树毛/梧桐絮", en: "Poplar / plane tree fluff")
            ]
        ),
        .init(
            title: .init(cn: "接触性、昆虫与其它", en: "Contact, insect, and other"),
            systemImage: "hand.raised.fill",
            tintKey: "contact",
            detailCategoryCN: "接触性与其它",
            allergens: [
                .init(cn: "乳胶制品", en: "Latex products"),
                .init(cn: "油漆", en: "Paint"),
                .init(cn: "金属镍/饰品", en: "Nickel / jewelry"),
                .init(cn: "紫外线/日光", en: "UV / sunlight"),
                .init(cn: "染发剂/香精", en: "Hair dye / fragrance"),
                .init(cn: "蚊虫/蜂叮咬", en: "Insect / bee stings")
            ]
        )
    ]

    static var allAllergyItems: [SparkBilingualItem] {
        allergyCategoryDefinitions.flatMap(\.allergens)
    }

    // MARK: - Chronic condition

    static let chronicControlStatusOptions: [SparkBilingualItem] = [
        .init(cn: "控制良好", en: "Well controlled"),
        .init(cn: "治疗中", en: "Under treatment"),
        .init(cn: "已治愈", en: "Cured")
    ]

    static let chronicCategories: [MedicalBilingualCategoryGroup] = [
        .init(
            title: .init(cn: "心脑血管系统", en: "Cardiovascular system"),
            systemImage: "heart.fill",
            items: [
                .init(cn: "高血压", en: "Hypertension"),
                .init(cn: "冠心病", en: "Coronary heart disease"),
                .init(cn: "高脂血症", en: "Hyperlipidemia"),
                .init(cn: "脑卒中/脑梗死", en: "Stroke / cerebral infarction"),
                .init(cn: "心律失常", en: "Arrhythmia"),
                .init(cn: "心肌缺血", en: "Myocardial ischemia")
            ]
        ),
        .init(
            title: .init(cn: "内分泌与代谢", en: "Endocrine and metabolic"),
            systemImage: "drop.fill",
            items: [
                .init(cn: "2型糖尿病", en: "Type 2 diabetes"),
                .init(cn: "1型糖尿病", en: "Type 1 diabetes"),
                .init(cn: "高尿酸血症/痛风", en: "Hyperuricemia / gout"),
                .init(cn: "甲状腺结节", en: "Thyroid nodule"),
                .init(cn: "甲亢/甲减", en: "Hyperthyroidism / hypothyroidism"),
                .init(cn: "骨质疏松", en: "Osteoporosis")
            ]
        ),
        .init(
            title: .init(cn: "消化与呼吸系统", en: "Digestive and respiratory system"),
            systemImage: "lungs.fill",
            items: [
                .init(cn: "慢性胃炎/胃溃疡", en: "Chronic gastritis / gastric ulcer"),
                .init(cn: "脂肪肝", en: "Fatty liver"),
                .init(cn: "胆囊结石/胆囊炎", en: "Gallstones / cholecystitis"),
                .init(cn: "支气管哮喘", en: "Bronchial asthma"),
                .init(cn: "慢性支气管炎/COPD", en: "Chronic bronchitis / COPD"),
                .init(cn: "过敏性鼻炎", en: "Allergic rhinitis")
            ]
        ),
        .init(
            title: .init(cn: "泌尿与运动系统", en: "Urinary and musculoskeletal system"),
            systemImage: "figure.walk",
            items: [
                .init(cn: "慢性肾脏病", en: "Chronic kidney disease"),
                .init(cn: "肾结石/尿路结石", en: "Kidney / urinary stones"),
                .init(cn: "前列腺增生", en: "Benign prostatic hyperplasia"),
                .init(cn: "颈椎病/腰椎间盘突出", en: "Cervical spondylosis / lumbar disc herniation"),
                .init(cn: "退行性关节炎", en: "Degenerative arthritis")
            ]
        )
    ]

    static var allChronicDiseaseItems: [SparkBilingualItem] {
        chronicCategories.flatMap(\.items)
    }

    // MARK: - Display helpers

    static func display(_ item: SparkBilingualItem) -> String {
        SparkFormCatalogMenuLocale.prefersEnglish ? item.en : item.cn
    }

    static func displayStored(_ stored: String, in items: [SparkBilingualItem]) -> String {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let item = items.first(where: { $0.cn == trimmed || $0.en == trimmed }) else { return stored }
        return display(item)
    }

    static func displaySymptomSeverity(_ value: String) -> String {
        switch value {
        case "low": return display(.init(cn: "轻度", en: "Mild"))
        case "medium": return display(.init(cn: "中度", en: "Moderate"))
        case "high": return display(.init(cn: "重度", en: "Severe"))
        default: return value
        }
    }

    static func filteredGroups(
        _ groups: [MedicalBilingualCategoryGroup],
        matching searchText: String
    ) -> [MedicalBilingualCategoryGroup] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return groups }

        return groups.compactMap { group in
            if CatalogItemSearch.matches(group.title, searchText: trimmed) {
                return group
            }
            let matchedItems = group.items.filter { CatalogItemSearch.matches($0, searchText: trimmed) }
            guard matchedItems.isEmpty == false else { return nil }
            return MedicalBilingualCategoryGroup(
                title: group.title,
                systemImage: group.systemImage,
                items: matchedItems
            )
        }
    }

    static func filteredAllergyCategories(matching searchText: String) -> [AllergyBilingualCategoryDefinition] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return allergyCategoryDefinitions }

        return allergyCategoryDefinitions.compactMap { category in
            if CatalogItemSearch.matches(category.title, searchText: trimmed) {
                return category
            }
            let matchedAllergens = category.allergens.filter { CatalogItemSearch.matches($0, searchText: trimmed) }
            guard matchedAllergens.isEmpty == false else { return nil }
            return AllergyBilingualCategoryDefinition(
                title: category.title,
                systemImage: category.systemImage,
                tintKey: category.tintKey,
                detailCategoryCN: category.detailCategoryCN,
                allergens: matchedAllergens
            )
        }
    }
}

struct MedicalBilingualCategoryGroup: Equatable, Sendable {
    let title: SparkBilingualItem
    let systemImage: String
    let items: [SparkBilingualItem]
}

struct AllergyBilingualCategoryDefinition: Equatable, Sendable {
    let title: SparkBilingualItem
    let systemImage: String
    let tintKey: String
    let detailCategoryCN: String
    let allergens: [SparkBilingualItem]
}
