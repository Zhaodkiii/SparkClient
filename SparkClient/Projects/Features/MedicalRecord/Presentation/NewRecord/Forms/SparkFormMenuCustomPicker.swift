import Foundation
import SwiftUI

/// 目录类表单菜单：非中文语言环境用英文选项展示；选中预设项时持久化仍用 **中文**（与各 `*Taxonomy` 一致）。
enum SparkFormCatalogMenuLocale {
    static let prefersEnglish: Bool = {
        if #available(iOS 16, *) {
            let code = Locale.current.language.languageCode?.identifier ?? ""
            if code.hasPrefix("zh") { return false }
            return true
        }
        if let lang = Locale.preferredLanguages.first?.lowercased() {
            return lang.hasPrefix("zh") == false
        }
        return true
    }()
}

public struct SparkBilingualItem: Equatable, Hashable, Sendable {
    public let cn: String
    public let en: String

    public init(cn: String, en: String) {
        self.cn = cn
        self.en = en
    }
}

public struct SparkBilingualCategory: Equatable, Hashable, Sendable {
    public let primary: SparkBilingualItem
    public let subcategories: [SparkBilingualItem]

    public init(primary: SparkBilingualItem, subcategories: [SparkBilingualItem]) {
        self.primary = primary
        self.subcategories = subcategories
    }

    public var primaryCN: String { primary.cn }
    public var primaryEN: String { primary.en }
}

public protocol SparkTaxonomy {
    static var bilingualGroups: [SparkBilingualCategory] { get }
    static var subcategoryAliasesCN: [String: [String: String]] { get }
}

public extension SparkTaxonomy {
    static var prefersEnglish: Bool { SparkFormCatalogMenuLocale.prefersEnglish }

    static var subcategoryAliasesCN: [String: [String: String]] { [:] }

    static var groups: [(primary: String, subcategories: [String])] {
        bilingualGroups.map { ($0.primary.cn, $0.subcategories.map(\.cn)) }
    }

    static var primaryTitles: [String] { groups.map(\.primary) }

    static func subcategories(for primary: String) -> [String] {
        let p = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        return group(primaryCN: p)?.subcategories.map(\.cn) ?? []
    }

    static var defaultPrimary: String { primaryTitles.first ?? "" }

    static func defaultSubcategory(for primary: String) -> String {
        subcategories(for: primary).first ?? ""
    }

    static var primaryTitlesEN: [String] {
        bilingualGroups.map(\.primary.en)
    }

    static func subcategoriesEN(for primaryEN: String) -> [String] {
        let p = primaryEN.trimmingCharacters(in: .whitespacesAndNewlines)
        return bilingualGroups.first { $0.primary.en == p }?.subcategories.map(\.en) ?? []
    }

    static func getEnglish(primaryCN: String) -> String? {
        bilingualGroups.first { $0.primary.cn == primaryCN }?.primary.en
    }

    static func getChinese(primaryEN: String) -> String? {
        bilingualGroups.first { $0.primary.en == primaryEN }?.primary.cn
    }

    static func resolvedCatalogPrimaryCN(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if bilingualGroups.contains(where: { $0.primary.cn == t }) { return t }
        return bilingualGroups.first { $0.primary.en == t }?.primary.cn
    }

    static func displayPrimaryPickerOptions() -> [String] {
        bilingualGroups.map { prefersEnglish ? $0.primary.en : $0.primary.cn }
    }

    static func displaySubcategoryPickerOptions(primaryCN: String) -> [String] {
        guard let g = group(primaryCN: primaryCN) else { return [] }
        return g.subcategories.map { prefersEnglish ? $0.en : $0.cn }
    }

    static func primaryDisplayString(stored: String) -> String {
        let t = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cn = resolvedCatalogPrimaryCN(t),
              let g = group(primaryCN: cn) else {
            return stored
        }
        return prefersEnglish ? g.primary.en : g.primary.cn
    }

    static func primaryCanonicalFromPickerDisplay(_ display: String) -> String {
        let d = display.trimmingCharacters(in: .whitespacesAndNewlines)
        return bilingualGroups.first { $0.primary.cn == d || $0.primary.en == d }?.primary.cn ?? d
    }

    static func subcategoryDisplayString(primaryStored: String, subStored: String) -> String {
        let sub = subStored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pCN = resolvedCatalogPrimaryCN(primaryStored),
              let item = subcategory(primaryCN: pCN, raw: sub) else {
            return subStored
        }
        return prefersEnglish ? item.en : item.cn
    }

    static func subcategoryCanonicalFromPickerDisplay(primaryStored: String, display: String) -> String {
        let d = display.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pCN = resolvedCatalogPrimaryCN(primaryStored),
              let item = subcategory(primaryCN: pCN, raw: d) else {
            return d
        }
        return item.cn
    }

    static func resolvedCatalogSubcategoryCN(primaryCN: String, raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let alias = subcategoryAliasesCN[primaryCN]?[t] { return alias }
        return subcategory(primaryCN: primaryCN, raw: t)?.cn
    }

    private static func group(primaryCN: String) -> SparkBilingualCategory? {
        let p = primaryCN.trimmingCharacters(in: .whitespacesAndNewlines)
        return bilingualGroups.first { $0.primary.cn == p }
    }

    private static func subcategory(primaryCN: String, raw: String) -> SparkBilingualItem? {
        guard let g = group(primaryCN: primaryCN) else { return nil }
        return g.subcategories.first { $0.cn == raw || $0.en == raw }
    }
}

// MARK: - 检验一级 / 二级分类（双语展示 + 中文落库）

/// 检验报告「一级分类 → 二级分类」：双语菜单按系统语言展示，**持久化字段使用中文**（`groups` / `subcategories(for:)` 与既有草稿、接口兼容）。
public enum LabExamCategoryTaxonomy: SparkTaxonomy {

    public static let bilingualGroups: [SparkBilingualCategory] = [
        .init(
            primary: .init(cn: "血常规", en: "Complete Blood Count"),
            subcategories: [
                .init(cn: "全血细胞计数", en: "CBC"),
                .init(cn: "五分类血常规", en: "5-Class CBC"),
                .init(cn: "网织红细胞", en: "Reticulocyte"),
                .init(cn: "贫血三项", en: "Anemia Panel")
            ]
        ),
        .init(
            primary: .init(cn: "尿常规", en: "Urine Test"),
            subcategories: [
                .init(cn: "尿常规", en: "Routine Urine"),
                .init(cn: "尿沉渣", en: "Urine Sediment"),
                .init(cn: "尿微量白蛋白", en: "Microalbuminuria"),
                .init(cn: "24 小时尿蛋白", en: "24h Urine Protein")
            ]
        ),
        .init(
            primary: .init(cn: "生化全套", en: "Comprehensive Metabolic Panel"),
            subcategories: [
                .init(cn: "常规生化", en: "Basic CMP"),
                .init(cn: "大生化", en: "Full CMP"),
                .init(cn: "小生化", en: "Mini CMP")
            ]
        ),
        .init(
            primary: .init(cn: "肝功能", en: "Liver Function"),
            subcategories: [
                .init(cn: "肝功能常规", en: "Basic LFT"),
                .init(cn: "肝功能全套", en: "Full LFT"),
                .init(cn: "胆红素", en: "Bilirubin"),
                .init(cn: "转氨酶", en: "Transaminase")
            ]
        ),
        .init(
            primary: .init(cn: "肾功能", en: "Renal Function"),
            subcategories: [
                .init(cn: "肾功能常规", en: "Basic RFT"),
                .init(cn: "肾小球滤过率", en: "eGFR"),
                .init(cn: "尿酸", en: "Uric Acid"),
                .init(cn: "肌酐清除率", en: "Creatinine Clearance")
            ]
        ),
        .init(
            primary: .init(cn: "血脂", en: "Lipid Panel"),
            subcategories: [
                .init(cn: "血脂常规", en: "Basic Lipid"),
                .init(cn: "血脂全套", en: "Full Lipid"),
                .init(cn: "脂蛋白", en: "Lipoprotein")
            ]
        ),
        .init(
            primary: .init(cn: "血糖", en: "Glucose & Diabetes"),
            subcategories: [
                .init(cn: "空腹血糖", en: "Fasting Glucose"),
                .init(cn: "餐后 2 小时血糖", en: "2h Postprandial Glucose"),
                .init(cn: "糖化血红蛋白", en: "HbA1c"),
                .init(cn: "糖耐量试验", en: "OGTT")
            ]
        ),
        .init(
            primary: .init(cn: "电解质", en: "Electrolytes"),
            subcategories: [
                .init(cn: "钾钠氯", en: "K Na Cl"),
                .init(cn: "钙磷镁", en: "Ca P Mg"),
                .init(cn: "血气分析", en: "Blood Gas Analysis")
            ]
        ),
        .init(
            primary: .init(cn: "心肌酶", en: "Cardiac Markers"),
            subcategories: [
                .init(cn: "心肌酶谱", en: "Cardiac Enzymes"),
                .init(cn: "肌钙蛋白", en: "Troponin"),
                .init(cn: "肌红蛋白", en: "Myoglobin"),
                .init(cn: "BNP/NT-proBNP", en: "BNP/NT-proBNP")
            ]
        ),
        .init(
            primary: .init(cn: "淀粉酶", en: "Amylase & Lipase"),
            subcategories: [
                .init(cn: "血淀粉酶", en: "Serum Amylase"),
                .init(cn: "尿淀粉酶", en: "Urine Amylase"),
                .init(cn: "脂肪酶", en: "Lipase")
            ]
        ),
        .init(
            primary: .init(cn: "凝血功能", en: "Coagulation Profile"),
            subcategories: [
                .init(cn: "凝血四项", en: "Coagulation 4 Items"),
                .init(cn: "D - 二聚体", en: "D-Dimer"),
                .init(cn: "凝血全套", en: "Full Coagulation")
            ]
        ),
        .init(
            primary: .init(cn: "免疫功能", en: "Immune Function"),
            subcategories: [
                .init(cn: "免疫球蛋白", en: "Immunoglobulin"),
                .init(cn: "补体", en: "Complement"),
                .init(cn: "淋巴细胞亚群", en: "Lymphocyte Subsets")
            ]
        ),
        .init(
            primary: .init(cn: "甲状腺功能", en: "Thyroid Function"),
            subcategories: [
                .init(cn: "甲功三项", en: "Thyroid 3 Items"),
                .init(cn: "甲功五项", en: "Thyroid 5 Items"),
                .init(cn: "甲功七项", en: "Thyroid 7 Items"),
                .init(cn: "甲状腺抗体", en: "Thyroid Antibodies")
            ]
        ),
        .init(
            primary: .init(cn: "肿瘤标志物", en: "Tumor Markers"),
            subcategories: [
                .init(cn: "广谱肿瘤标志物", en: "General Tumor Markers"),
                .init(cn: "消化道肿瘤", en: "GI Tumor Markers"),
                .init(cn: "肺部肿瘤", en: "Lung Tumor Markers"),
                .init(cn: "乳腺肿瘤", en: "Breast Tumor Markers"),
                .init(cn: "前列腺肿瘤", en: "Prostate Tumor Markers"),
                .init(cn: "妇科肿瘤", en: "Gynecologic Tumor Markers")
            ]
        ),
        .init(
            primary: .init(cn: "炎症指标", en: "Inflammatory Markers"),
            subcategories: [
                .init(cn: "CRP", en: "CRP"),
                .init(cn: "血沉", en: "ESR"),
                .init(cn: "降钙素原 PCT", en: "PCT"),
                .init(cn: "IL-6", en: "IL-6")
            ]
        ),
        .init(
            primary: .init(cn: "维生素", en: "Vitamins"),
            subcategories: [
                .init(cn: "维生素 D", en: "Vitamin D"),
                .init(cn: "维生素 B12", en: "Vitamin B12"),
                .init(cn: "叶酸", en: "Folic Acid"),
                .init(cn: "维生素 ADEK", en: "Vitamin ADEK")
            ]
        ),
        .init(
            primary: .init(cn: "激素", en: "Hormones"),
            subcategories: [
                .init(cn: "性激素", en: "Sex Hormones"),
                .init(cn: "生长激素", en: "Growth Hormone"),
                .init(cn: "皮质醇", en: "Cortisol"),
                .init(cn: "促肾上腺激素", en: "ACTH")
            ]
        ),
        .init(
            primary: .init(cn: "粪便常规", en: "Stool Test"),
            subcategories: [
                .init(cn: "便常规", en: "Routine Stool"),
                .init(cn: "便潜血", en: "Occult Blood"),
                .init(cn: "寄生虫", en: "Parasites"),
                .init(cn: "粪便培养", en: "Stool Culture")
            ]
        ),
        .init(
            primary: .init(cn: "分泌物检查", en: "Secretion Test"),
            subcategories: [
                .init(cn: "白带常规", en: "Vaginal Secretion"),
                .init(cn: "前列腺液", en: "Prostatic Fluid"),
                .init(cn: "精液常规", en: "Semen Analysis"),
                .init(cn: "分泌物培养", en: "Secretion Culture")
            ]
        ),
        .init(
            primary: .init(cn: "其他检验", en: "Other Tests"),
            subcategories: [
                .init(cn: "血型", en: "Blood Type"),
                .init(cn: "输血前检查", en: "Pre-transfusion Test"),
                .init(cn: "过敏原", en: "Allergen Test"),
                .init(cn: "幽门螺杆菌", en: "H. pylori"),
                .init(cn: "病毒检测", en: "Virus Test")
            ]
        )
    ]

    /// 非中文界面用英文菜单；中文及繁体界面用中文菜单。
    public static var displaysEnglishLabCategories: Bool { prefersEnglish }

    public static let subcategoryAliasesCN: [String: [String: String]] = [
        "凝血功能": ["D-二聚体": "D - 二聚体"]
    ]
}

// MARK: - 影像一级 / 二级分类（双语展示 + 中文落库）

/// 影像检查「一级分类 → 二级分类」：菜单随 `SparkFormCatalogMenuLocale` 显示中/英，**持久化中文预设名**。
public enum ImagingCategoryTaxonomy: SparkTaxonomy {

    public static let bilingualGroups: [SparkBilingualCategory] = [
        .init(
            primary: .init(cn: "X光检查", en: "X-Ray"),
            subcategories: [
                .init(cn: "胸部X光", en: "Chest X-Ray"),
                .init(cn: "颈椎X光", en: "Cervical Spine X-Ray"),
                .init(cn: "腰椎X光", en: "Lumbar X-Ray"),
                .init(cn: "关节X光", en: "Joint X-Ray"),
                .init(cn: "腹部X光", en: "Abdominal X-Ray"),
                .init(cn: "其他X光", en: "Other X-Ray")
            ]
        ),
        .init(
            primary: .init(cn: "CT检查", en: "CT Scan"),
            subcategories: [
                .init(cn: "头部CT", en: "Head CT"),
                .init(cn: "胸部CT", en: "Chest CT"),
                .init(cn: "腹部CT", en: "Abdominal CT"),
                .init(cn: "盆腔CT", en: "Pelvic CT"),
                .init(cn: "脊柱CT", en: "Spine CT"),
                .init(cn: "血管CTA", en: "CTA"),
                .init(cn: "其他CT", en: "Other CT")
            ]
        ),
        .init(
            primary: .init(cn: "核磁共振", en: "MRI"),
            subcategories: [
                .init(cn: "头颅MRI", en: "Brain MRI"),
                .init(cn: "脊柱MRI", en: "Spine MRI"),
                .init(cn: "关节MRI", en: "Joint MRI"),
                .init(cn: "腹部MRI", en: "Abdominal MRI"),
                .init(cn: "盆腔MRI", en: "Pelvic MRI"),
                .init(cn: "血管MR", en: "MRA"),
                .init(cn: "其他MRI", en: "Other MRI")
            ]
        ),
        .init(
            primary: .init(cn: "超声检查", en: "Ultrasound"),
            subcategories: [
                .init(cn: "腹部超声", en: "Abdominal US"),
                .init(cn: "心脏超声", en: "Echocardiography"),
                .init(cn: "甲状腺超声", en: "Thyroid US"),
                .init(cn: "乳腺超声", en: "Breast US"),
                .init(cn: "妇科超声", en: "Pelvic US"),
                .init(cn: "血管超声", en: "Vascular US"),
                .init(cn: "肌肉骨骼超声", en: "MSK US")
            ]
        ),
        .init(
            primary: .init(cn: "内镜检查", en: "Endoscopy"),
            subcategories: [
                .init(cn: "胃镜", en: "Gastroscopy"),
                .init(cn: "肠镜", en: "Colonoscopy"),
                .init(cn: "支气管镜", en: "Bronchoscopy"),
                .init(cn: "鼻咽镜", en: "Nasopharyngoscopy"),
                .init(cn: "宫腔镜", en: "Hysteroscopy"),
                .init(cn: "腹腔镜", en: "Laparoscopy")
            ]
        ),
        .init(
            primary: .init(cn: "病理检查", en: "Pathology"),
            subcategories: [
                .init(cn: "组织病理", en: "Histopathology"),
                .init(cn: "细胞病理", en: "Cytopathology"),
                .init(cn: "穿刺病理", en: "Biopsy"),
                .init(cn: "术后病理", en: "Postoperative Pathology"),
                .init(cn: "免疫组化", en: "IHC")
            ]
        ),
        .init(
            primary: .init(cn: "核医学", en: "Nuclear Medicine"),
            subcategories: [
                .init(cn: "PET-CT", en: "PET-CT"),
                .init(cn: "骨扫描", en: "Bone Scan"),
                .init(cn: "甲状腺扫描", en: "Thyroid Scan"),
                .init(cn: "肾动态显像", en: "Renal Scan")
            ]
        ),
        .init(
            primary: .init(cn: "其他影像", en: "Other Imaging"),
            subcategories: [
                .init(cn: "骨密度", en: "Bone Densitometry"),
                .init(cn: "乳腺钼靶", en: "Mammography"),
                .init(cn: "心电图", en: "ECG"),
                .init(cn: "脑电图", en: "EEG"),
                .init(cn: "其他检查", en: "Other")
            ]
        )
    ]

    public static var displaysEnglishImagingCategories: Bool { prefersEnglish }
}

// MARK: - 病理一级 / 二级分类（双语展示 + 中文落库）

/// 病理检查「一级分类 → 二级分类」：菜单随 `SparkFormCatalogMenuLocale` 显示中/英，**持久化中文预设名**。
public enum PathologyCategoryTaxonomy: SparkTaxonomy {

    public static let bilingualGroups: [SparkBilingualCategory] = [
        .init(
            primary: .init(cn: "组织病理", en: "Histopathology"),
            subcategories: [
                .init(cn: "穿刺活检", en: "Needle Biopsy"),
                .init(cn: "内镜活检", en: "Endoscopic Biopsy"),
                .init(cn: "手术切除标本", en: "Surgical Specimen"),
                .init(cn: "宫颈活检", en: "Cervical Biopsy"),
                .init(cn: "皮肤活检", en: "Skin Biopsy")
            ]
        ),
        .init(
            primary: .init(cn: "细胞病理", en: "Cytopathology"),
            subcategories: [
                .init(cn: "液基细胞学（TCT）", en: "TCT/LCT"),
                .init(cn: "胸水细胞学", en: "Pleural Fluid"),
                .init(cn: "腹水细胞学", en: "Ascitic Fluid"),
                .init(cn: "痰液细胞学", en: "Sputum Cytology"),
                .init(cn: "细针穿刺细胞学", en: "FNAC")
            ]
        ),
        .init(
            primary: .init(cn: "术中冰冻", en: "Frozen Section"),
            subcategories: [
                .init(cn: "手术中快速病理", en: "Intraoperative Frozen"),
                .init(cn: "冰冻切片诊断", en: "Frozen Diagnosis")
            ]
        ),
        .init(
            primary: .init(cn: "免疫组化", en: "IHC"),
            subcategories: [
                .init(cn: "肿瘤免疫组化", en: "Tumor IHC"),
                .init(cn: "抗体标记检测", en: "Antibody Markers"),
                .init(cn: "分型诊断", en: "Subtype Diagnosis")
            ]
        ),
        .init(
            primary: .init(cn: "分子病理", en: "Molecular Pathology"),
            subcategories: [
                .init(cn: "基因检测", en: "Gene Test"),
                .init(cn: "PCR检测", en: "PCR"),
                .init(cn: "FISH检测", en: "FISH"),
                .init(cn: "靶向用药基因", en: "Targeted Gene Panel")
            ]
        ),
        .init(
            primary: .init(cn: "特殊染色", en: "Special Stain"),
            subcategories: [
                .init(cn: "真菌染色", en: "Fungal Stain"),
                .init(cn: "抗酸染色", en: "AFB Stain"),
                .init(cn: "网状纤维染色", en: "Reticulin Stain"),
                .init(cn: "胶原染色", en: "Collagen Stain")
            ]
        ),
        .init(
            primary: .init(cn: "细胞遗传学", en: "Cytogenetics"),
            subcategories: [
                .init(cn: "染色体核型分析", en: "Karyotyping"),
                .init(cn: "微缺失检测", en: "Microdeletion Test")
            ]
        ),
        .init(
            primary: .init(cn: "其他病理", en: "Other Pathology"),
            subcategories: [
                .init(cn: "尸检病理", en: "Autopsy"),
                .init(cn: "会诊病理", en: "Consultation"),
                .init(cn: "病理复查", en: "Second Opinion")
            ]
        )
    ]

    public static var displaysEnglishPathologyCategories: Bool { prefersEnglish }
}

// MARK: - 菜单选项 + 自定义（视觉对齐 `AddLabItemSheet` 单位 / 状态行）

private enum SparkFormMenuCustomPick: Hashable {
    case option(String)
    case custom
}

/// 分段菜单 +「自定义…」与行内输入；`sections` 全空时退化为仅自定义输入（用于「一级为自定义时二级只能手输」）。
public struct SparkFormMenuCustomRow: View {
    public let title: String
    public let required: Bool
    /// 分段选项；`header == nil` 时不显示 Section 标题。
    public let sections: [(header: String?, options: [String])]
    @Binding public var text: String
    public let customMenuTitle: String
    public let customPlaceholder: String
    public var keyboardVisible: Binding<Bool>?
    public let optionSystemImage: ((String) -> String?)?
    public let customAutofocus: Bool

    @FocusState private var customFocused: Bool

    public init(
        title: String,
        required: Bool = false,
        sections: [(header: String?, options: [String])],
        text: Binding<String>,
        customMenuTitle: String,
        customPlaceholder: String,
        keyboardVisible: Binding<Bool>? = nil,
        optionSystemImage: ((String) -> String?)? = nil,
        customAutofocus: Bool = false
    ) {
        self.title = title
        self.required = required
        self.sections = sections
        _text = text
        self.customMenuTitle = customMenuTitle
        self.customPlaceholder = customPlaceholder
        self.keyboardVisible = keyboardVisible
        self.optionSystemImage = optionSystemImage
        self.customAutofocus = customAutofocus
    }

    private var flatOptions: [String] {
        sections.flatMap(\.options)
    }

    private var hasMenu: Bool { flatOptions.isEmpty == false }

    private var currentPick: SparkFormMenuCustomPick {
        guard hasMenu else { return .custom }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let hit = flatOptions.first(where: { $0 == t }) {
            return .option(hit)
        }
        return .custom
    }

    private var selectionIsCustom: Bool {
        if case .custom = currentPick { return true }
        return false
    }

    private var pickBinding: Binding<SparkFormMenuCustomPick> {
        Binding(
            get: { currentPick },
            set: { newPick in
                switch newPick {
                case .option(let option):
                    customFocused = false
                    text = option
                case .custom:
                    if flatOptions.contains(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        text = ""
                    }
                }
            }
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if required {
                    Text("*")
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }

            if hasMenu {
                menuAndOptionalField
            } else {
                soloCustomField
            }
        }
        .onChange(of: customFocused) { focused in
            keyboardVisible?.wrappedValue = focused
        }
    }

    private var menuAndOptionalField: some View {
        HStack(alignment: .center, spacing: 10) {
            menuPicker

            if selectionIsCustom {
                customInputField
            }
        }
    }

    private var menuPicker: some View {
        Picker("", selection: pickBinding) {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                if let h = section.header, h.isEmpty == false {
                    Section(header: Text(h)) {
                        ForEach(section.options, id: \.self) { opt in
                            pickerOptionLabel(opt)
                                .tag(SparkFormMenuCustomPick.option(opt))
                        }
                    }
                } else {
                    Section {
                        ForEach(section.options, id: \.self) { opt in
                            pickerOptionLabel(opt)
                                .tag(SparkFormMenuCustomPick.option(opt))
                        }
                    }
                }
            }
            Section {
                Text(customMenuTitle).tag(SparkFormMenuCustomPick.custom)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(minWidth: selectionIsCustom ? 120 : 0, maxWidth: selectionIsCustom ? 160 : .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func pickerOptionLabel(_ option: String) -> some View {
        if let systemImage = optionSystemImage?(option) {
            Label(option, systemImage: systemImage)
        } else {
            Text(option)
        }
    }

    private var customInputField: some View {
        TextField(customPlaceholder, text: $text)
            .textInputAutocapitalizationIfAvailable(.never)
            .autocorrectionDisabledIfAvailable()
            .focused($customFocused)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        customFocused ? Color.accentColor : Color(uiColor: .separator),
                        lineWidth: customFocused ? 1.5 : 1
                    )
            )
            .onAppear {
                if customAutofocus {
                    customFocused = true
                }
            }
    }

    private var soloCustomField: some View {
        customInputField
    }
}

// MARK: - 检验一级 + 二级联动

/// 一级：预设检验大类 + 自定义。二级：一级为预设时展示对应子项 + 自定义；一级为自定义时二级仅手输。
/// 菜单按当前语言显示中/英；绑定值写入 **中文** 预设名（自定义项则原样保存）。
public struct SparkLabExamCategoryCascadeRow: View {
    public let primaryTitle: String
    public let secondaryTitle: String
    public let primaryPlaceholder: String
    public let secondaryPlaceholder: String
    public let primaryRequired: Bool
    public let secondaryRequired: Bool
    @Binding public var primary: String
    @Binding public var secondary: String
    public var keyboardVisible: Binding<Bool>?

    public init(
        primaryTitle: String,
        secondaryTitle: String,
        primaryPlaceholder: String,
        secondaryPlaceholder: String,
        primaryRequired: Bool = true,
        secondaryRequired: Bool = false,
        primary: Binding<String>,
        secondary: Binding<String>,
        keyboardVisible: Binding<Bool>? = nil
    ) {
        self.primaryTitle = primaryTitle
        self.secondaryTitle = secondaryTitle
        self.primaryPlaceholder = primaryPlaceholder
        self.secondaryPlaceholder = secondaryPlaceholder
        self.primaryRequired = primaryRequired
        self.secondaryRequired = secondaryRequired
        _primary = primary
        _secondary = secondary
        self.keyboardVisible = keyboardVisible
    }

    private var primaryMapped: Binding<String> {
        Binding(
            get: { LabExamCategoryTaxonomy.primaryDisplayString(stored: primary) },
            set: { primary = LabExamCategoryTaxonomy.primaryCanonicalFromPickerDisplay($0) }
        )
    }

    private var secondaryMapped: Binding<String> {
        Binding(
            get: { LabExamCategoryTaxonomy.subcategoryDisplayString(primaryStored: primary, subStored: secondary) },
            set: { secondary = LabExamCategoryTaxonomy.subcategoryCanonicalFromPickerDisplay(primaryStored: primary, display: $0) }
        )
    }

    private var primarySections: [(header: String?, options: [String])] {
        [(nil, LabExamCategoryTaxonomy.displayPrimaryPickerOptions())]
    }

    private var secondarySections: [(header: String?, options: [String])] {
        guard let pCN = LabExamCategoryTaxonomy.resolvedCatalogPrimaryCN(primary) else { return [] }
        return [(nil, LabExamCategoryTaxonomy.displaySubcategoryPickerOptions(primaryCN: pCN))]
    }

    private var secondaryFieldIdentity: String {
        let p = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cn = LabExamCategoryTaxonomy.resolvedCatalogPrimaryCN(p) {
            return "submenu-\(cn)"
        }
        return "sub-solo-\(p)"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SparkFormMenuCustomRow(
                title: primaryTitle,
                required: primaryRequired,
                sections: primarySections,
                text: primaryMapped,
                customMenuTitle: L10n.text("medical_record.forms.lab_item.unit_custom_menu"),
                customPlaceholder: primaryPlaceholder,
                keyboardVisible: keyboardVisible
            )
            SparkFormMenuCustomRow(
                title: secondaryTitle,
                required: secondaryRequired,
                sections: secondarySections,
                text: secondaryMapped,
                customMenuTitle: L10n.text("medical_record.forms.lab_item.unit_custom_menu"),
                customPlaceholder: secondaryPlaceholder,
                keyboardVisible: keyboardVisible
            )
            .id(secondaryFieldIdentity)
        }
        .id(SparkFormCatalogMenuLocale.prefersEnglish ? "lab-cat-en" : "lab-cat-zh")
        .onAppear {
            seedDefaultsIfNeeded()
            reconcileSecondary(afterPrimaryChange: primary)
        }
        .onChange(of: primary) { newPrimary in
            reconcileSecondary(afterPrimaryChange: newPrimary)
        }
    }

    private func seedDefaultsIfNeeded() {
        let p = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty, primaryRequired {
            let d = LabExamCategoryTaxonomy.defaultPrimary
            primary = d
            let sub = LabExamCategoryTaxonomy.defaultSubcategory(for: d)
            if secondary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                secondary = sub
            }
        }
    }

    private func reconcileSecondary(afterPrimaryChange newPrimary: String) {
        let p = newPrimary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pCN = LabExamCategoryTaxonomy.resolvedCatalogPrimaryCN(p) else {
            secondary = ""
            return
        }
        let kids = LabExamCategoryTaxonomy.subcategories(for: pCN)
        let s = secondary.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty {
            secondary = kids.first ?? ""
            return
        }
        if kids.contains(s) { return }
        if let normalized = LabExamCategoryTaxonomy.resolvedCatalogSubcategoryCN(primaryCN: pCN, raw: s) {
            secondary = normalized
            return
        }
        secondary = kids.first ?? ""
    }
}

// MARK: - 影像一级 + 二级联动

/// 一级：预设影像大类 + 自定义。二级：一级为预设时展示对应子项 + 自定义；一级为自定义时二级仅手输。
/// 菜单按 `SparkFormCatalogMenuLocale` 显示中/英；绑定值写入 **中文** 预设名（自定义原样）。
public struct SparkImagingCategoryCascadeRow: View {
    public let primaryTitle: String
    public let secondaryTitle: String
    public let primaryPlaceholder: String
    public let secondaryPlaceholder: String
    public let primaryRequired: Bool
    public let secondaryRequired: Bool
    @Binding public var primary: String
    @Binding public var secondary: String
    public var keyboardVisible: Binding<Bool>?

    public init(
        primaryTitle: String,
        secondaryTitle: String,
        primaryPlaceholder: String,
        secondaryPlaceholder: String,
        primaryRequired: Bool = true,
        secondaryRequired: Bool = false,
        primary: Binding<String>,
        secondary: Binding<String>,
        keyboardVisible: Binding<Bool>? = nil
    ) {
        self.primaryTitle = primaryTitle
        self.secondaryTitle = secondaryTitle
        self.primaryPlaceholder = primaryPlaceholder
        self.secondaryPlaceholder = secondaryPlaceholder
        self.primaryRequired = primaryRequired
        self.secondaryRequired = secondaryRequired
        _primary = primary
        _secondary = secondary
        self.keyboardVisible = keyboardVisible
    }

    private var primaryMapped: Binding<String> {
        Binding(
            get: { ImagingCategoryTaxonomy.primaryDisplayString(stored: primary) },
            set: { primary = ImagingCategoryTaxonomy.primaryCanonicalFromPickerDisplay($0) }
        )
    }

    private var secondaryMapped: Binding<String> {
        Binding(
            get: { ImagingCategoryTaxonomy.subcategoryDisplayString(primaryStored: primary, subStored: secondary) },
            set: { secondary = ImagingCategoryTaxonomy.subcategoryCanonicalFromPickerDisplay(primaryStored: primary, display: $0) }
        )
    }

    private var primarySections: [(header: String?, options: [String])] {
        [(nil, ImagingCategoryTaxonomy.displayPrimaryPickerOptions())]
    }

    private var secondarySections: [(header: String?, options: [String])] {
        guard let pCN = ImagingCategoryTaxonomy.resolvedCatalogPrimaryCN(primary) else { return [] }
        return [(nil, ImagingCategoryTaxonomy.displaySubcategoryPickerOptions(primaryCN: pCN))]
    }

    private var secondaryFieldIdentity: String {
        let p = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cn = ImagingCategoryTaxonomy.resolvedCatalogPrimaryCN(p) {
            return "img-submenu-\(cn)"
        }
        return "img-sub-solo-\(p)"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SparkFormMenuCustomRow(
                title: primaryTitle,
                required: primaryRequired,
                sections: primarySections,
                text: primaryMapped,
                customMenuTitle: L10n.text("medical_record.forms.lab_item.unit_custom_menu"),
                customPlaceholder: primaryPlaceholder,
                keyboardVisible: keyboardVisible
            )
            SparkFormMenuCustomRow(
                title: secondaryTitle,
                required: secondaryRequired,
                sections: secondarySections,
                text: secondaryMapped,
                customMenuTitle: L10n.text("medical_record.forms.lab_item.unit_custom_menu"),
                customPlaceholder: secondaryPlaceholder,
                keyboardVisible: keyboardVisible
            )
            .id(secondaryFieldIdentity)
        }
        .id(SparkFormCatalogMenuLocale.prefersEnglish ? "img-cat-en" : "img-cat-zh")
        .onAppear {
            seedDefaultsIfNeeded()
            reconcileSecondary(afterPrimaryChange: primary)
        }
        .onChange(of: primary) { newPrimary in
            reconcileSecondary(afterPrimaryChange: newPrimary)
        }
    }

    private func seedDefaultsIfNeeded() {
        let p = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty, primaryRequired {
            let d = ImagingCategoryTaxonomy.defaultPrimary
            primary = d
            let sub = ImagingCategoryTaxonomy.defaultSubcategory(for: d)
            if secondary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                secondary = sub
            }
        }
    }

    private func reconcileSecondary(afterPrimaryChange newPrimary: String) {
        let p = newPrimary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pCN = ImagingCategoryTaxonomy.resolvedCatalogPrimaryCN(p) else {
            secondary = ""
            return
        }
        let kids = ImagingCategoryTaxonomy.subcategories(for: pCN)
        let s = secondary.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty {
            secondary = kids.first ?? ""
            return
        }
        if kids.contains(s) { return }
        if let normalized = ImagingCategoryTaxonomy.resolvedCatalogSubcategoryCN(primaryCN: pCN, raw: s) {
            secondary = normalized
            return
        }
        secondary = kids.first ?? ""
    }
}

// MARK: - 病理一级 + 二级联动

/// 一级：预设病理大类 + 自定义。二级：一级为预设时展示对应子项 + 自定义；一级为自定义时二级仅手输。
/// 菜单按 `SparkFormCatalogMenuLocale` 显示中/英；绑定值写入 **中文** 预设名（自定义原样）。
public struct SparkPathologyCategoryCascadeRow: View {
    public let primaryTitle: String
    public let secondaryTitle: String
    public let primaryPlaceholder: String
    public let secondaryPlaceholder: String
    public let primaryRequired: Bool
    public let secondaryRequired: Bool
    @Binding public var primary: String
    @Binding public var secondary: String
    public var keyboardVisible: Binding<Bool>?

    public init(
        primaryTitle: String,
        secondaryTitle: String,
        primaryPlaceholder: String,
        secondaryPlaceholder: String,
        primaryRequired: Bool = true,
        secondaryRequired: Bool = false,
        primary: Binding<String>,
        secondary: Binding<String>,
        keyboardVisible: Binding<Bool>? = nil
    ) {
        self.primaryTitle = primaryTitle
        self.secondaryTitle = secondaryTitle
        self.primaryPlaceholder = primaryPlaceholder
        self.secondaryPlaceholder = secondaryPlaceholder
        self.primaryRequired = primaryRequired
        self.secondaryRequired = secondaryRequired
        _primary = primary
        _secondary = secondary
        self.keyboardVisible = keyboardVisible
    }

    private var primaryMapped: Binding<String> {
        Binding(
            get: { PathologyCategoryTaxonomy.primaryDisplayString(stored: primary) },
            set: { primary = PathologyCategoryTaxonomy.primaryCanonicalFromPickerDisplay($0) }
        )
    }

    private var secondaryMapped: Binding<String> {
        Binding(
            get: { PathologyCategoryTaxonomy.subcategoryDisplayString(primaryStored: primary, subStored: secondary) },
            set: { secondary = PathologyCategoryTaxonomy.subcategoryCanonicalFromPickerDisplay(primaryStored: primary, display: $0) }
        )
    }

    private var primarySections: [(header: String?, options: [String])] {
        [(nil, PathologyCategoryTaxonomy.displayPrimaryPickerOptions())]
    }

    private var secondarySections: [(header: String?, options: [String])] {
        guard let pCN = PathologyCategoryTaxonomy.resolvedCatalogPrimaryCN(primary) else { return [] }
        return [(nil, PathologyCategoryTaxonomy.displaySubcategoryPickerOptions(primaryCN: pCN))]
    }

    private var secondaryFieldIdentity: String {
        let p = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cn = PathologyCategoryTaxonomy.resolvedCatalogPrimaryCN(p) {
            return "path-submenu-\(cn)"
        }
        return "path-sub-solo-\(p)"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SparkFormMenuCustomRow(
                title: primaryTitle,
                required: primaryRequired,
                sections: primarySections,
                text: primaryMapped,
                customMenuTitle: L10n.text("medical_record.forms.lab_item.unit_custom_menu"),
                customPlaceholder: primaryPlaceholder,
                keyboardVisible: keyboardVisible
            )
            SparkFormMenuCustomRow(
                title: secondaryTitle,
                required: secondaryRequired,
                sections: secondarySections,
                text: secondaryMapped,
                customMenuTitle: L10n.text("medical_record.forms.lab_item.unit_custom_menu"),
                customPlaceholder: secondaryPlaceholder,
                keyboardVisible: keyboardVisible
            )
            .id(secondaryFieldIdentity)
        }
        .id(SparkFormCatalogMenuLocale.prefersEnglish ? "path-cat-en" : "path-cat-zh")
        .onAppear {
            seedDefaultsIfNeeded()
            reconcileSecondary(afterPrimaryChange: primary)
        }
        .onChange(of: primary) { newPrimary in
            reconcileSecondary(afterPrimaryChange: newPrimary)
        }
    }

    private func seedDefaultsIfNeeded() {
        let p = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty, primaryRequired {
            let d = PathologyCategoryTaxonomy.defaultPrimary
            primary = d
            let sub = PathologyCategoryTaxonomy.defaultSubcategory(for: d)
            if secondary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                secondary = sub
            }
        }
    }

    private func reconcileSecondary(afterPrimaryChange newPrimary: String) {
        let p = newPrimary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pCN = PathologyCategoryTaxonomy.resolvedCatalogPrimaryCN(p) else {
            secondary = ""
            return
        }
        let kids = PathologyCategoryTaxonomy.subcategories(for: pCN)
        let s = secondary.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty {
            secondary = kids.first ?? ""
            return
        }
        if kids.contains(s) { return }
        if let normalized = PathologyCategoryTaxonomy.resolvedCatalogSubcategoryCN(primaryCN: pCN, raw: s) {
            secondary = normalized
            return
        }
        secondary = kids.first ?? ""
    }
}
