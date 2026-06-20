import Foundation

/// 药箱药品类型目录：预设分类、展示文案与存储值互转
enum MedicineBoxTypeCatalog {
    struct DefaultItem: Sendable {
        let key: String
        let cn: String
        let en: String
    }

    nonisolated static let defaultStoredValue = ""

    nonisolated static let defaults: [DefaultItem] = [
        .init(key: "cold_fever", cn: "感冒发烧", en: "Cold & Fever"),
        .init(key: "gi_digestion", cn: "胃肠消化", en: "GI & Digestion"),
        .init(key: "cough_throat", cn: "咳嗽咽痛", en: "Cough & Throat"),
        .init(key: "skin_bone", cn: "皮肤骨痛", en: "Skin, Bone & Pain"),
        .init(key: "chronic", cn: "慢病用药", en: "Chronic Medication"),
        .init(key: "pediatric", cn: "儿童用药", en: "Pediatric")
    ]

    nonisolated static let defaultStoredOptions: [String] = defaults.map(\.cn)

    nonisolated private static let legacyCodeMap: [String: String] = [
        "cold_fever": defaults[0].cn,
        "gi_digestion": defaults[1].cn,
        "cough_throat": defaults[2].cn,
        "skin_bone": defaults[3].cn,
        "chronic": defaults[4].cn,
        "pediatric": defaults[5].cn,
        "uncategorized": ""
    ]

    nonisolated private static func localizedLabel(for item: DefaultItem) -> String {
        L10n.text(
            "home.medical.medicine_box.type.\(item.key)",
            fallback: prefersEnglish ? item.en : item.cn
        )
    }

    nonisolated private static func defaultItem(matching stored: String) -> DefaultItem? {
        defaults.first { $0.cn == stored || $0.en == stored || $0.key == stored }
    }

    nonisolated private static var prefersEnglish: Bool {
        let code = Locale.current.language.languageCode?.identifier ?? ""
        return code.hasPrefix("zh") == false
    }

    /// 从当前药箱数据合并出自定义 + 预设类型选项（存储值）
    nonisolated static func options(in boxes: [SparkMedicalSyncAPI.RemoteMedicineBox]) -> [String] {
        let custom = boxes.compactMap { blankToNil(storedValue(fromAny: $0.medicineType)) }
        return mergedOptions(defaultStoredOptions + custom)
    }

    nonisolated static func mergedOptions(_ values: [String]) -> [String] {
        uniqued(values.map(storedValue(fromAny:)))
    }

    nonisolated static func displayOptions(for values: [String]) -> [String] {
        uniqued(values).map(displayString(stored:))
    }

    nonisolated static func displayString(stored: String?) -> String {
        let stored = storedValue(fromAny: stored)
        guard let item = defaultItem(matching: stored) else {
            return blankToNil(stored) ?? defaultStoredValue
        }
        return localizedLabel(for: item)
    }

    nonisolated static func storedValue(fromDisplay display: String) -> String {
        let text = display.trimmingCharacters(in: .whitespacesAndNewlines)
        if let item = defaults.first(where: {
            $0.cn == text || $0.en == text || localizedLabel(for: $0) == text
        }) {
            return item.cn
        }
        return text
    }

    nonisolated static func storedValue(fromAny raw: String?) -> String {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), raw.isEmpty == false else {
            return defaultStoredValue
        }
        if let mapped = legacyCodeMap[raw] {
            return mapped
        }
        if let item = defaultItem(matching: raw) {
            return item.cn
        }
        return raw
    }

    nonisolated static func systemImage(for display: String) -> String? {
        guard let item = defaultItem(matching: storedValue(fromDisplay: display)) else {
            return "tag"
        }
        switch item.key {
        case "cold_fever":
            return "thermometer.medium"
        case "gi_digestion":
            return "cross.case"
        case "cough_throat":
            return "lungs"
        case "skin_bone":
            return "figure.walk"
        case "chronic":
            return "calendar.badge.clock"
        case "pediatric":
            return "person.crop.circle"
        default:
            return "tag"
        }
    }

    nonisolated private static func uniqued(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { continue }
            let key = storedValue(fromAny: trimmed)
            if seen.insert(key).inserted {
                result.append(key)
            }
        }
        return result
    }

    nonisolated private static func blankToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
