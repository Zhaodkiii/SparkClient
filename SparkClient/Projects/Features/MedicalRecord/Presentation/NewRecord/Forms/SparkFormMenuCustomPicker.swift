import Foundation
import SwiftUI

/// 目录类表单菜单：非中文语言环境用英文选项展示；选中预设项时持久化仍用 **中文**（与各 `*Taxonomy` 一致）。
enum SparkFormCatalogMenuLocale {
    static var prefersEnglish: Bool {
        if #available(iOS 16, *) {
            let code = Locale.current.language.languageCode?.identifier ?? ""
            if code.hasPrefix("zh") { return false }
            return true
        }
        if let lang = Locale.preferredLanguages.first?.lowercased() {
            return lang.hasPrefix("zh") == false
        }
        return true
    }
}

// MARK: - 检验一级 / 二级分类（双语展示 + 中文落库）

/// 检验报告「一级分类 → 二级分类」：双语菜单按系统语言展示，**持久化字段使用中文**（`groups` / `subcategories(for:)` 与既有草稿、接口兼容）。
public enum LabExamCategoryTaxonomy {

    public struct LabCategory: Equatable {
        public let primaryCN: String
        public let primaryEN: String
        public let subCN: [String]
        public let subEN: [String]

        public init(primaryCN: String, primaryEN: String, subCN: [String], subEN: [String]) {
            self.primaryCN = primaryCN
            self.primaryEN = primaryEN
            self.subCN = subCN
            self.subEN = subEN
        }
    }

    public static let bilingualGroups: [LabCategory] = [
        .init(
            primaryCN: "血常规",
            primaryEN: "Complete Blood Count",
            subCN: ["全血细胞计数", "五分类血常规", "网织红细胞", "贫血三项"],
            subEN: ["CBC", "5-Class CBC", "Reticulocyte", "Anemia Panel"]
        ),
        .init(
            primaryCN: "尿常规",
            primaryEN: "Urine Test",
            subCN: ["尿常规", "尿沉渣", "尿微量白蛋白", "24 小时尿蛋白"],
            subEN: ["Routine Urine", "Urine Sediment", "Microalbuminuria", "24h Urine Protein"]
        ),
        .init(
            primaryCN: "生化全套",
            primaryEN: "Comprehensive Metabolic Panel",
            subCN: ["常规生化", "大生化", "小生化"],
            subEN: ["Basic CMP", "Full CMP", "Mini CMP"]
        ),
        .init(
            primaryCN: "肝功能",
            primaryEN: "Liver Function",
            subCN: ["肝功能常规", "肝功能全套", "胆红素", "转氨酶"],
            subEN: ["Basic LFT", "Full LFT", "Bilirubin", "Transaminase"]
        ),
        .init(
            primaryCN: "肾功能",
            primaryEN: "Renal Function",
            subCN: ["肾功能常规", "肾小球滤过率", "尿酸", "肌酐清除率"],
            subEN: ["Basic RFT", "eGFR", "Uric Acid", "Creatinine Clearance"]
        ),
        .init(
            primaryCN: "血脂",
            primaryEN: "Lipid Panel",
            subCN: ["血脂常规", "血脂全套", "脂蛋白"],
            subEN: ["Basic Lipid", "Full Lipid", "Lipoprotein"]
        ),
        .init(
            primaryCN: "血糖",
            primaryEN: "Glucose & Diabetes",
            subCN: ["空腹血糖", "餐后 2 小时血糖", "糖化血红蛋白", "糖耐量试验"],
            subEN: ["Fasting Glucose", "2h Postprandial Glucose", "HbA1c", "OGTT"]
        ),
        .init(
            primaryCN: "电解质",
            primaryEN: "Electrolytes",
            subCN: ["钾钠氯", "钙磷镁", "血气分析"],
            subEN: ["K Na Cl", "Ca P Mg", "Blood Gas Analysis"]
        ),
        .init(
            primaryCN: "心肌酶",
            primaryEN: "Cardiac Markers",
            subCN: ["心肌酶谱", "肌钙蛋白", "肌红蛋白", "BNP/NT-proBNP"],
            subEN: ["Cardiac Enzymes", "Troponin", "Myoglobin", "BNP/NT-proBNP"]
        ),
        .init(
            primaryCN: "淀粉酶",
            primaryEN: "Amylase & Lipase",
            subCN: ["血淀粉酶", "尿淀粉酶", "脂肪酶"],
            subEN: ["Serum Amylase", "Urine Amylase", "Lipase"]
        ),
        .init(
            primaryCN: "凝血功能",
            primaryEN: "Coagulation Profile",
            subCN: ["凝血四项", "D - 二聚体", "凝血全套"],
            subEN: ["Coagulation 4 Items", "D-Dimer", "Full Coagulation"]
        ),
        .init(
            primaryCN: "免疫功能",
            primaryEN: "Immune Function",
            subCN: ["免疫球蛋白", "补体", "淋巴细胞亚群"],
            subEN: ["Immunoglobulin", "Complement", "Lymphocyte Subsets"]
        ),
        .init(
            primaryCN: "甲状腺功能",
            primaryEN: "Thyroid Function",
            subCN: ["甲功三项", "甲功五项", "甲功七项", "甲状腺抗体"],
            subEN: ["Thyroid 3 Items", "Thyroid 5 Items", "Thyroid 7 Items", "Thyroid Antibodies"]
        ),
        .init(
            primaryCN: "肿瘤标志物",
            primaryEN: "Tumor Markers",
            subCN: ["广谱肿瘤标志物", "消化道肿瘤", "肺部肿瘤", "乳腺肿瘤", "前列腺肿瘤", "妇科肿瘤"],
            subEN: ["General Tumor Markers", "GI Tumor Markers", "Lung Tumor Markers", "Breast Tumor Markers", "Prostate Tumor Markers", "Gynecologic Tumor Markers"]
        ),
        .init(
            primaryCN: "炎症指标",
            primaryEN: "Inflammatory Markers",
            subCN: ["CRP", "血沉", "降钙素原 PCT", "IL-6"],
            subEN: ["CRP", "ESR", "PCT", "IL-6"]
        ),
        .init(
            primaryCN: "维生素",
            primaryEN: "Vitamins",
            subCN: ["维生素 D", "维生素 B12", "叶酸", "维生素 ADEK"],
            subEN: ["Vitamin D", "Vitamin B12", "Folic Acid", "Vitamin ADEK"]
        ),
        .init(
            primaryCN: "激素",
            primaryEN: "Hormones",
            subCN: ["性激素", "生长激素", "皮质醇", "促肾上腺激素"],
            subEN: ["Sex Hormones", "Growth Hormone", "Cortisol", "ACTH"]
        ),
        .init(
            primaryCN: "粪便常规",
            primaryEN: "Stool Test",
            subCN: ["便常规", "便潜血", "寄生虫", "粪便培养"],
            subEN: ["Routine Stool", "Occult Blood", "Parasites", "Stool Culture"]
        ),
        .init(
            primaryCN: "分泌物检查",
            primaryEN: "Secretion Test",
            subCN: ["白带常规", "前列腺液", "精液常规", "分泌物培养"],
            subEN: ["Vaginal Secretion", "Prostatic Fluid", "Semen Analysis", "Secretion Culture"]
        ),
        .init(
            primaryCN: "其他检验",
            primaryEN: "Other Tests",
            subCN: ["血型", "输血前检查", "过敏原", "幽门螺杆菌", "病毒检测"],
            subEN: ["Blood Type", "Pre-transfusion Test", "Allergen Test", "H. pylori", "Virus Test"]
        )
    ]

    /// 非中文界面用英文菜单；中文及繁体界面用中文菜单。
    public static var displaysEnglishLabCategories: Bool { SparkFormCatalogMenuLocale.prefersEnglish }

    public static let groups: [(primary: String, subcategories: [String])] =
        bilingualGroups.map { ($0.primaryCN, $0.subCN) }

    public static var primaryTitles: [String] { groups.map(\.primary) }

    public static func subcategories(for primary: String) -> [String] {
        let p = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        return groups.first { $0.primary == p }?.subcategories ?? []
    }

    public static var defaultPrimary: String { primaryTitles.first ?? "" }

    public static func defaultSubcategory(for primary: String) -> String {
        subcategories(for: primary).first ?? ""
    }

    public static var primaryTitlesEN: [String] { bilingualGroups.map(\.primaryEN) }

    public static func subcategoriesEN(for primaryEN: String) -> [String] {
        let p = primaryEN.trimmingCharacters(in: .whitespacesAndNewlines)
        return bilingualGroups.first { $0.primaryEN == p }?.subEN ?? []
    }

    public static func getEnglish(primaryCN: String) -> String? {
        bilingualGroups.first { $0.primaryCN == primaryCN }?.primaryEN
    }

    public static func getChinese(primaryEN: String) -> String? {
        bilingualGroups.first { $0.primaryEN == primaryEN }?.primaryCN
    }

    // MARK: - 联动 / UI 映射（存中文，显双语）

    public static func resolvedCatalogPrimaryCN(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if bilingualGroups.contains(where: { $0.primaryCN == t }) { return t }
        if let g = bilingualGroups.first(where: { $0.primaryEN == t }) { return g.primaryCN }
        return nil
    }

    public static func displayPrimaryPickerOptions() -> [String] {
        bilingualGroups.map { displaysEnglishLabCategories ? $0.primaryEN : $0.primaryCN }
    }

    public static func displaySubcategoryPickerOptions(primaryCN: String) -> [String] {
        guard let g = bilingualGroups.first(where: { $0.primaryCN == primaryCN }) else { return [] }
        return displaysEnglishLabCategories ? g.subEN : g.subCN
    }

    public static func primaryDisplayString(stored: String) -> String {
        let t = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cn = resolvedCatalogPrimaryCN(t),
              let g = bilingualGroups.first(where: { $0.primaryCN == cn }) else {
            return stored
        }
        return displaysEnglishLabCategories ? g.primaryEN : g.primaryCN
    }

    public static func primaryCanonicalFromPickerDisplay(_ display: String) -> String {
        let d = display.trimmingCharacters(in: .whitespacesAndNewlines)
        for g in bilingualGroups where g.primaryCN == d || g.primaryEN == d {
            return g.primaryCN
        }
        return d
    }

    public static func subcategoryDisplayString(primaryStored: String, subStored: String) -> String {
        let sub = subStored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pCN = resolvedCatalogPrimaryCN(primaryStored),
              let g = bilingualGroups.first(where: { $0.primaryCN == pCN }) else {
            return subStored
        }
        if let i = g.subCN.firstIndex(of: sub) {
            return displaysEnglishLabCategories ? g.subEN[i] : g.subCN[i]
        }
        if let i = g.subEN.firstIndex(of: sub) {
            return displaysEnglishLabCategories ? g.subEN[i] : g.subCN[i]
        }
        return subStored
    }

    public static func subcategoryCanonicalFromPickerDisplay(primaryStored: String, display: String) -> String {
        let d = display.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pCN = resolvedCatalogPrimaryCN(primaryStored),
              let g = bilingualGroups.first(where: { $0.primaryCN == pCN }) else {
            return d
        }
        if let i = g.subCN.firstIndex(of: d) { return g.subCN[i] }
        if let i = g.subEN.firstIndex(of: d) { return g.subCN[i] }
        return d
    }

    public static func resolvedCatalogSubcategoryCN(primaryCN: String, raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let g = bilingualGroups.first(where: { $0.primaryCN == primaryCN }) else { return nil }
        if primaryCN == "凝血功能", t == "D-二聚体" { return "D - 二聚体" }
        if g.subCN.contains(t) { return t }
        if let i = g.subEN.firstIndex(of: t) { return g.subCN[i] }
        return nil
    }
}

// MARK: - 影像一级 / 二级分类（双语展示 + 中文落库）

/// 影像检查「一级分类 → 二级分类」：菜单随 `SparkFormCatalogMenuLocale` 显示中/英，**持久化中文预设名**。
public enum ImagingCategoryTaxonomy {

    public struct ImagingCategory: Equatable {
        public let primaryCN: String
        public let primaryEN: String
        public let subCN: [String]
        public let subEN: [String]

        public init(primaryCN: String, primaryEN: String, subCN: [String], subEN: [String]) {
            self.primaryCN = primaryCN
            self.primaryEN = primaryEN
            self.subCN = subCN
            self.subEN = subEN
        }
    }

    public static let bilingualGroups: [ImagingCategory] = [
        .init(
            primaryCN: "X光检查",
            primaryEN: "X-Ray",
            subCN: ["胸部X光", "颈椎X光", "腰椎X光", "关节X光", "腹部X光", "其他X光"],
            subEN: ["Chest X-Ray", "Cervical Spine X-Ray", "Lumbar X-Ray", "Joint X-Ray", "Abdominal X-Ray", "Other X-Ray"]
        ),
        .init(
            primaryCN: "CT检查",
            primaryEN: "CT Scan",
            subCN: ["头部CT", "胸部CT", "腹部CT", "盆腔CT", "脊柱CT", "血管CTA", "其他CT"],
            subEN: ["Head CT", "Chest CT", "Abdominal CT", "Pelvic CT", "Spine CT", "CTA", "Other CT"]
        ),
        .init(
            primaryCN: "核磁共振",
            primaryEN: "MRI",
            subCN: ["头颅MRI", "脊柱MRI", "关节MRI", "腹部MRI", "盆腔MRI", "血管MR", "其他MRI"],
            subEN: ["Brain MRI", "Spine MRI", "Joint MRI", "Abdominal MRI", "Pelvic MRI", "MRA", "Other MRI"]
        ),
        .init(
            primaryCN: "超声检查",
            primaryEN: "Ultrasound",
            subCN: ["腹部超声", "心脏超声", "甲状腺超声", "乳腺超声", "妇科超声", "血管超声", "肌肉骨骼超声"],
            subEN: ["Abdominal US", "Echocardiography", "Thyroid US", "Breast US", "Pelvic US", "Vascular US", "MSK US"]
        ),
        .init(
            primaryCN: "内镜检查",
            primaryEN: "Endoscopy",
            subCN: ["胃镜", "肠镜", "支气管镜", "鼻咽镜", "宫腔镜", "腹腔镜"],
            subEN: ["Gastroscopy", "Colonoscopy", "Bronchoscopy", "Nasopharyngoscopy", "Hysteroscopy", "Laparoscopy"]
        ),
        .init(
            primaryCN: "病理检查",
            primaryEN: "Pathology",
            subCN: ["组织病理", "细胞病理", "穿刺病理", "术后病理", "免疫组化"],
            subEN: ["Histopathology", "Cytopathology", "Biopsy", "Postoperative Pathology", "IHC"]
        ),
        .init(
            primaryCN: "核医学",
            primaryEN: "Nuclear Medicine",
            subCN: ["PET-CT", "骨扫描", "甲状腺扫描", "肾动态显像"],
            subEN: ["PET-CT", "Bone Scan", "Thyroid Scan", "Renal Scan"]
        ),
        .init(
            primaryCN: "其他影像",
            primaryEN: "Other Imaging",
            subCN: ["骨密度", "乳腺钼靶", "心电图", "脑电图", "其他检查"],
            subEN: ["Bone Densitometry", "Mammography", "ECG", "EEG", "Other"]
        )
    ]

    public static let groups: [(primary: String, subcategories: [String])] =
        bilingualGroups.map { ($0.primaryCN, $0.subCN) }

    public static var primaryTitles: [String] { groups.map(\.primary) }

    public static func subcategories(for primary: String) -> [String] {
        let p = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        return groups.first { $0.primary == p }?.subcategories ?? []
    }

    public static var defaultPrimary: String { primaryTitles.first ?? "" }

    public static func defaultSubcategory(for primary: String) -> String {
        subcategories(for: primary).first ?? ""
    }

    public static var primaryTitlesEN: [String] { bilingualGroups.map(\.primaryEN) }

    public static func subcategoriesEN(for primaryEN: String) -> [String] {
        let p = primaryEN.trimmingCharacters(in: .whitespacesAndNewlines)
        return bilingualGroups.first { $0.primaryEN == p }?.subEN ?? []
    }

    public static func getEnglish(primaryCN: String) -> String? {
        bilingualGroups.first { $0.primaryCN == primaryCN }?.primaryEN
    }

    public static func getChinese(primaryEN: String) -> String? {
        bilingualGroups.first { $0.primaryEN == primaryEN }?.primaryCN
    }

    public static var displaysEnglishImagingCategories: Bool { SparkFormCatalogMenuLocale.prefersEnglish }

    public static func resolvedCatalogPrimaryCN(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if bilingualGroups.contains(where: { $0.primaryCN == t }) { return t }
        if let g = bilingualGroups.first(where: { $0.primaryEN == t }) { return g.primaryCN }
        return nil
    }

    public static func displayPrimaryPickerOptions() -> [String] {
        bilingualGroups.map { displaysEnglishImagingCategories ? $0.primaryEN : $0.primaryCN }
    }

    public static func displaySubcategoryPickerOptions(primaryCN: String) -> [String] {
        guard let g = bilingualGroups.first(where: { $0.primaryCN == primaryCN }) else { return [] }
        return displaysEnglishImagingCategories ? g.subEN : g.subCN
    }

    public static func primaryDisplayString(stored: String) -> String {
        let t = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cn = resolvedCatalogPrimaryCN(t),
              let g = bilingualGroups.first(where: { $0.primaryCN == cn }) else {
            return stored
        }
        return displaysEnglishImagingCategories ? g.primaryEN : g.primaryCN
    }

    public static func primaryCanonicalFromPickerDisplay(_ display: String) -> String {
        let d = display.trimmingCharacters(in: .whitespacesAndNewlines)
        for g in bilingualGroups where g.primaryCN == d || g.primaryEN == d {
            return g.primaryCN
        }
        return d
    }

    public static func subcategoryDisplayString(primaryStored: String, subStored: String) -> String {
        let sub = subStored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pCN = resolvedCatalogPrimaryCN(primaryStored),
              let g = bilingualGroups.first(where: { $0.primaryCN == pCN }) else {
            return subStored
        }
        if let i = g.subCN.firstIndex(of: sub) {
            return displaysEnglishImagingCategories ? g.subEN[i] : g.subCN[i]
        }
        if let i = g.subEN.firstIndex(of: sub) {
            return displaysEnglishImagingCategories ? g.subEN[i] : g.subCN[i]
        }
        return subStored
    }

    public static func subcategoryCanonicalFromPickerDisplay(primaryStored: String, display: String) -> String {
        let d = display.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pCN = resolvedCatalogPrimaryCN(primaryStored),
              let g = bilingualGroups.first(where: { $0.primaryCN == pCN }) else {
            return d
        }
        if let i = g.subCN.firstIndex(of: d) { return g.subCN[i] }
        if let i = g.subEN.firstIndex(of: d) { return g.subCN[i] }
        return d
    }

    public static func resolvedCatalogSubcategoryCN(primaryCN: String, raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let g = bilingualGroups.first(where: { $0.primaryCN == primaryCN }) else { return nil }
        if g.subCN.contains(t) { return t }
        if let i = g.subEN.firstIndex(of: t) { return g.subCN[i] }
        return nil
    }
}

// MARK: - 病理一级 / 二级分类（双语展示 + 中文落库）

/// 病理检查「一级分类 → 二级分类」：菜单随 `SparkFormCatalogMenuLocale` 显示中/英，**持久化中文预设名**。
public enum PathologyCategoryTaxonomy {

    public struct PathologyCategory: Equatable {
        public let primaryCN: String
        public let primaryEN: String
        public let subCN: [String]
        public let subEN: [String]

        public init(primaryCN: String, primaryEN: String, subCN: [String], subEN: [String]) {
            self.primaryCN = primaryCN
            self.primaryEN = primaryEN
            self.subCN = subCN
            self.subEN = subEN
        }
    }

    public static let bilingualGroups: [PathologyCategory] = [
        .init(
            primaryCN: "组织病理",
            primaryEN: "Histopathology",
            subCN: ["穿刺活检", "内镜活检", "手术切除标本", "宫颈活检", "皮肤活检"],
            subEN: ["Needle Biopsy", "Endoscopic Biopsy", "Surgical Specimen", "Cervical Biopsy", "Skin Biopsy"]
        ),
        .init(
            primaryCN: "细胞病理",
            primaryEN: "Cytopathology",
            subCN: ["液基细胞学（TCT）", "胸水细胞学", "腹水细胞学", "痰液细胞学", "细针穿刺细胞学"],
            subEN: ["TCT/LCT", "Pleural Fluid", "Ascitic Fluid", "Sputum Cytology", "FNAC"]
        ),
        .init(
            primaryCN: "术中冰冻",
            primaryEN: "Frozen Section",
            subCN: ["手术中快速病理", "冰冻切片诊断"],
            subEN: ["Intraoperative Frozen", "Frozen Diagnosis"]
        ),
        .init(
            primaryCN: "免疫组化",
            primaryEN: "IHC",
            subCN: ["肿瘤免疫组化", "抗体标记检测", "分型诊断"],
            subEN: ["Tumor IHC", "Antibody Markers", "Subtype Diagnosis"]
        ),
        .init(
            primaryCN: "分子病理",
            primaryEN: "Molecular Pathology",
            subCN: ["基因检测", "PCR检测", "FISH检测", "靶向用药基因"],
            subEN: ["Gene Test", "PCR", "FISH", "Targeted Gene Panel"]
        ),
        .init(
            primaryCN: "特殊染色",
            primaryEN: "Special Stain",
            subCN: ["真菌染色", "抗酸染色", "网状纤维染色", "胶原染色"],
            subEN: ["Fungal Stain", "AFB Stain", "Reticulin Stain", "Collagen Stain"]
        ),
        .init(
            primaryCN: "细胞遗传学",
            primaryEN: "Cytogenetics",
            subCN: ["染色体核型分析", "微缺失检测"],
            subEN: ["Karyotyping", "Microdeletion Test"]
        ),
        .init(
            primaryCN: "其他病理",
            primaryEN: "Other Pathology",
            subCN: ["尸检病理", "会诊病理", "病理复查"],
            subEN: ["Autopsy", "Consultation", "Second Opinion"]
        )
    ]

    public static let groups: [(primary: String, subcategories: [String])] =
        bilingualGroups.map { ($0.primaryCN, $0.subCN) }

    public static var primaryTitles: [String] { groups.map(\.primary) }

    public static func subcategories(for primary: String) -> [String] {
        let p = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        return groups.first { $0.primary == p }?.subcategories ?? []
    }

    public static var defaultPrimary: String { primaryTitles.first ?? "" }

    public static func defaultSubcategory(for primary: String) -> String {
        subcategories(for: primary).first ?? ""
    }

    public static var primaryTitlesEN: [String] { bilingualGroups.map(\.primaryEN) }

    public static func subcategoriesEN(for primaryEN: String) -> [String] {
        let p = primaryEN.trimmingCharacters(in: .whitespacesAndNewlines)
        return bilingualGroups.first { $0.primaryEN == p }?.subEN ?? []
    }

    public static func getEnglish(primaryCN: String) -> String? {
        bilingualGroups.first { $0.primaryCN == primaryCN }?.primaryEN
    }

    public static func getChinese(primaryEN: String) -> String? {
        bilingualGroups.first { $0.primaryEN == primaryEN }?.primaryCN
    }

    public static var displaysEnglishPathologyCategories: Bool { SparkFormCatalogMenuLocale.prefersEnglish }

    public static func resolvedCatalogPrimaryCN(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if bilingualGroups.contains(where: { $0.primaryCN == t }) { return t }
        if let g = bilingualGroups.first(where: { $0.primaryEN == t }) { return g.primaryCN }
        return nil
    }

    public static func displayPrimaryPickerOptions() -> [String] {
        bilingualGroups.map { displaysEnglishPathologyCategories ? $0.primaryEN : $0.primaryCN }
    }

    public static func displaySubcategoryPickerOptions(primaryCN: String) -> [String] {
        guard let g = bilingualGroups.first(where: { $0.primaryCN == primaryCN }) else { return [] }
        return displaysEnglishPathologyCategories ? g.subEN : g.subCN
    }

    public static func primaryDisplayString(stored: String) -> String {
        let t = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cn = resolvedCatalogPrimaryCN(t),
              let g = bilingualGroups.first(where: { $0.primaryCN == cn }) else {
            return stored
        }
        return displaysEnglishPathologyCategories ? g.primaryEN : g.primaryCN
    }

    public static func primaryCanonicalFromPickerDisplay(_ display: String) -> String {
        let d = display.trimmingCharacters(in: .whitespacesAndNewlines)
        for g in bilingualGroups where g.primaryCN == d || g.primaryEN == d {
            return g.primaryCN
        }
        return d
    }

    public static func subcategoryDisplayString(primaryStored: String, subStored: String) -> String {
        let sub = subStored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pCN = resolvedCatalogPrimaryCN(primaryStored),
              let g = bilingualGroups.first(where: { $0.primaryCN == pCN }) else {
            return subStored
        }
        if let i = g.subCN.firstIndex(of: sub) {
            return displaysEnglishPathologyCategories ? g.subEN[i] : g.subCN[i]
        }
        if let i = g.subEN.firstIndex(of: sub) {
            return displaysEnglishPathologyCategories ? g.subEN[i] : g.subCN[i]
        }
        return subStored
    }

    public static func subcategoryCanonicalFromPickerDisplay(primaryStored: String, display: String) -> String {
        let d = display.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pCN = resolvedCatalogPrimaryCN(primaryStored),
              let g = bilingualGroups.first(where: { $0.primaryCN == pCN }) else {
            return d
        }
        if let i = g.subCN.firstIndex(of: d) { return g.subCN[i] }
        if let i = g.subEN.firstIndex(of: d) { return g.subCN[i] }
        return d
    }

    public static func resolvedCatalogSubcategoryCN(primaryCN: String, raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let g = bilingualGroups.first(where: { $0.primaryCN == primaryCN }) else { return nil }
        if g.subCN.contains(t) { return t }
        if let i = g.subEN.firstIndex(of: t) { return g.subCN[i] }
        return nil
    }
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

    @State private var pick: SparkFormMenuCustomPick = .custom
    @State private var customBuffer: String = ""
    @FocusState private var customFocused: Bool

    public init(
        title: String,
        required: Bool = false,
        sections: [(header: String?, options: [String])],
        text: Binding<String>,
        customMenuTitle: String,
        customPlaceholder: String,
        keyboardVisible: Binding<Bool>? = nil
    ) {
        self.title = title
        self.required = required
        self.sections = sections
        _text = text
        self.customMenuTitle = customMenuTitle
        self.customPlaceholder = customPlaceholder
        self.keyboardVisible = keyboardVisible
    }

    private var flatOptions: [String] {
        sections.flatMap(\.options)
    }

    private var hasMenu: Bool { flatOptions.isEmpty == false }

    private var selectionIsCustom: Bool {
        if case .custom = pick { return true }
        return false
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
        .onAppear {
            syncPickFromText()
        }
        .onChange(of: text) { _ in
            syncPickFromText()
        }
        .onChange(of: pick) { _ in
            if selectionIsCustom == false {
                customFocused = false
            }
            applyPickToText()
        }
        .onChange(of: customBuffer) { _ in
            if selectionIsCustom {
                text = customBuffer
            }
        }
        .onChange(of: customFocused) { focused in
            keyboardVisible?.wrappedValue = focused
        }
    }

    private var menuAndOptionalField: some View {
        HStack(alignment: .center, spacing: 10) {
            Picker("", selection: $pick) {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    if let h = section.header, h.isEmpty == false {
                        Section(header: Text(h)) {
                            ForEach(section.options, id: \.self) { opt in
                                Text(opt).tag(SparkFormMenuCustomPick.option(opt))
                            }
                        }
                    } else {
                        Section {
                            ForEach(section.options, id: \.self) { opt in
                                Text(opt).tag(SparkFormMenuCustomPick.option(opt))
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

            if selectionIsCustom {
                TextField(customPlaceholder, text: $customBuffer)
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
            }
        }
    }

    private var soloCustomField: some View {
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
    }

    private func syncPickFromText() {
        guard hasMenu else { return }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hit = flatOptions.first(where: { $0 == t }) {
            pick = .option(hit)
            customBuffer = ""
        } else if t.isEmpty {
            pick = .custom
            customBuffer = ""
        } else {
            pick = .custom
            customBuffer = text
        }
    }

    private func applyPickToText() {
        guard hasMenu else { return }
        switch pick {
        case .option(let s):
            text = s
            customBuffer = ""
        case .custom:
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if flatOptions.contains(t) {
                customBuffer = ""
                text = ""
            } else {
                customBuffer = text
            }
        }
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
