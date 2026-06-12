import Foundation

func medicineBoxStockText(_ box: SparkMedicalSyncAPI.RemoteMedicineBox) -> String {
    guard let q = box.totalQuantity else { return L10n.text("home.medical.medicine_box.not_filled") }
    return q.formatted(.number.precision(.fractionLength(0...2)))
}

func medicineStrengthText(_ strength: String?) -> String? {
    guard let raw = strength?.trimmingCharacters(in: .whitespacesAndNewlines), raw.isEmpty == false else { return nil }
    let spec = MedicineSpecification.parse(fromAPIStrength: raw)
    if spec.hasStructuredContent {
        return spec.displayString(prefersEnglish: SparkFormCatalogMenuLocale.prefersEnglish)
    }
    return raw
}

func medicineStrengthDetailValue(_ strength: String) -> String {
    let raw = strength.trimmingCharacters(in: .whitespacesAndNewlines)
    guard raw.isEmpty == false else { return "" }
    let spec = MedicineSpecification.parse(fromAPIStrength: raw)
    if spec.hasStructuredContent {
        return spec.displayString(prefersEnglish: SparkFormCatalogMenuLocale.prefersEnglish)
    }
    return raw
}

func medicineTypeText(_ type: String?) -> String? {
    guard let type, !type.isEmpty else { return nil }
    return MedicineBoxTypeCatalog.displayString(stored: type)
}
