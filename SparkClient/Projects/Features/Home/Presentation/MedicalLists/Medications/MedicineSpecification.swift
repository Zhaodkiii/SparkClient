import Foundation

/// Structured medicine package / strength line (per-unit dose, pack count, outer pack). Serialized to API `strength` as a Chinese-style string, e.g. `5mg×28片/盒`.
struct MedicineSpecification: Codable, Hashable, Sendable {
    var doseValue: String = ""
    var doseUnit: String = ""
    var packageCount: String = ""
    var packageUnit: String = ""
    var outerPackageUnit: String = ""

    /// Legacy free-form `strength` when it cannot be parsed into the five fields; persisted verbatim until the user edits structured fields.
    var rawLegacyStrength: String?

    init(
        doseValue: String = "",
        doseUnit: String = "",
        packageCount: String = "",
        packageUnit: String = "",
        outerPackageUnit: String = "",
        rawLegacyStrength: String? = nil
    ) {
        self.doseValue = doseValue
        self.doseUnit = doseUnit
        self.packageCount = packageCount
        self.packageUnit = packageUnit
        self.outerPackageUnit = outerPackageUnit
        self.rawLegacyStrength = rawLegacyStrength
    }

    /// Preserve unrecognized `strength` text until the user switches to structured fields.
    init(rawLegacyOnly legacy: String) {
        self.rawLegacyStrength = legacy.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasStructuredContent: Bool {
        (doseValue.isEmpty == false && doseUnit.isEmpty == false)
            || (packageCount.isEmpty == false && packageUnit.isEmpty == false)
            || outerPackageUnit.isEmpty == false
    }

    /// Canonical string for `RemoteMedicineBox.strength` (Chinese-style, compact).
    var storedStrengthString: String {
        if let legacy = rawLegacyStrength?.trimmingCharacters(in: .whitespacesAndNewlines), legacy.isEmpty == false {
            return legacy
        }
        let dv = doseValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let du = doseUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        let pc = packageCount.trimmingCharacters(in: .whitespacesAndNewlines)
        let pu = packageUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        let ou = outerPackageUnit.trimmingCharacters(in: .whitespacesAndNewlines)

        let hasDose = dv.isEmpty == false && du.isEmpty == false
        let hasInnerPack = pc.isEmpty == false && pu.isEmpty == false
        let hasOuter = ou.isEmpty == false

        if hasDose, hasInnerPack, hasOuter {
            return "\(dv)\(du)×\(pc)\(pu)/\(ou)"
        }
        if hasDose, hasInnerPack {
            return "\(dv)\(du)×\(pc)\(pu)"
        }
        if hasDose, pu.isEmpty == false, pc.isEmpty {
            return "\(dv)\(du)/\(pu)"
        }
        if hasDose {
            return "\(dv)\(du)"
        }
        if hasInnerPack {
            return "\(pc)\(pu)"
        }
        if pu.isEmpty == false, ou.isEmpty == false {
            return "\(pu)/\(ou)"
        }
        return ""
    }

    /// Backend `MedicineBox.dose_unit`: compact per-dose text — numeric `doseValue` + `doseUnit` when both set (e.g. `5mg`, `10片`).
    var backendDoseUnitField: String {
        if let legacy = rawLegacyStrength?.trimmingCharacters(in: .whitespacesAndNewlines), legacy.isEmpty == false {
            return ""
        }
        let dv = doseValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let du = doseUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (dv.isEmpty, du.isEmpty) {
        case (true, true): return ""
        case (false, true): return dv
        case (true, false): return du
        case (false, false): return "\(dv)\(du)"
        }
    }

    /// Leading numeric (optional one `.`) prefix vs remainder, for API `dose_unit` like `5mg` / `0.5g`.
    static func splitLeadingDoseNumericPrefix(_ s: String) -> (String, String)? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.isEmpty == false else { return nil }
        var i = t.startIndex
        var dotSeen = false
        var sawDigit = false
        while i < t.endIndex {
            let c = t[i]
            if c.isWholeNumber {
                sawDigit = true
                i = t.index(after: i)
            } else if c == ".", !dotSeen, sawDigit {
                dotSeen = true
                i = t.index(after: i)
            } else {
                break
            }
        }
        guard sawDigit else { return nil }
        let num = String(t[..<i])
        let rest = String(t[i...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (num, rest)
    }

    /// Parses a compact backend `dose_unit` string (e.g. `5mg`, `10片`, or unit-only `片`) into an editable numeric prefix and stored unit token.
    static func doseValueAndStoredUnit(fromBackendDoseUnitField combined: String) -> (value: String, unit: String) {
        let t = combined.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.isEmpty == false else { return ("", "") }
        if let parts = splitLeadingDoseNumericPrefix(t) {
            let unit = parts.1.isEmpty ? "" : MedicineSpecificationCatalog.storedDoseUnit(fromAny: parts.1)
            return (parts.0, unit)
        }
        return ("", MedicineSpecificationCatalog.storedDoseUnit(fromAny: t))
    }

    /// Fills structured dose fields from OCR/API `dose_unit` when value or unit is still missing.
    static func mergeDoseUnitFromAPI(_ raw: String?, into spec: inout MedicineSpecification) {
        guard let raw else { return }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.isEmpty == false else { return }
        let dv = spec.doseValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let du = spec.doseUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        if dv.isEmpty == false && du.isEmpty == false { return }
        if let parts = splitLeadingDoseNumericPrefix(t) {
            if dv.isEmpty, parts.0.isEmpty == false { spec.doseValue = parts.0 }
            if du.isEmpty, parts.1.isEmpty == false {
                spec.doseUnit = MedicineSpecificationCatalog.storedDoseUnit(fromAny: parts.1)
            }
        } else if du.isEmpty {
            spec.doseUnit = MedicineSpecificationCatalog.storedDoseUnit(fromAny: t)
        }
    }

    /// Localized display for lists / previews (spaces in English where helpful).
    func displayString(prefersEnglish: Bool) -> String {
        if let legacy = rawLegacyStrength?.trimmingCharacters(in: .whitespacesAndNewlines), legacy.isEmpty == false {
            return legacy
        }
        let dv = doseValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let duCN = doseUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        let pc = packageCount.trimmingCharacters(in: .whitespacesAndNewlines)
        let puCN = packageUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        let ouCN = outerPackageUnit.trimmingCharacters(in: .whitespacesAndNewlines)

        let du = MedicineSpecificationCatalog.displayUnit(stored: duCN, prefersEnglish: prefersEnglish)
        let pu = MedicineSpecificationCatalog.displayUnit(stored: puCN, prefersEnglish: prefersEnglish)
        let ou = MedicineSpecificationCatalog.displayUnit(stored: ouCN, prefersEnglish: prefersEnglish)

        let hasDose = dv.isEmpty == false && duCN.isEmpty == false
        let hasInnerPack = pc.isEmpty == false && puCN.isEmpty == false
        let hasOuter = ouCN.isEmpty == false

        if prefersEnglish {
            if hasDose, hasInnerPack, hasOuter {
                return "\(dv) \(du) × \(pc) \(pu) / \(ou)"
            }
            if hasDose, hasInnerPack {
                return "\(dv) \(du) × \(pc) \(pu)"
            }
            if hasDose, puCN.isEmpty == false, pc.isEmpty {
                return "\(dv) \(du) / \(pu)"
            }
            if hasDose { return "\(dv) \(du)" }
            if hasInnerPack { return "\(pc) \(pu)" }
            if puCN.isEmpty == false, hasOuter { return "\(pu) / \(ou)" }
            return ""
        }

        if hasDose, hasInnerPack, hasOuter {
            return "\(dv)\(du)×\(pc)\(pu)/\(ou)"
        }
        if hasDose, hasInnerPack {
            return "\(dv)\(du)×\(pc)\(pu)"
        }
        if hasDose, puCN.isEmpty == false, pc.isEmpty {
            return "\(dv)\(du)/\(pu)"
        }
        if hasDose { return "\(dv)\(du)" }
        if hasInnerPack { return "\(pc)\(pu)" }
        if puCN.isEmpty == false, hasOuter { return "\(pu)/\(ou)" }
        return ""
    }

    /// Best-effort parse of API `strength` into structured fields.
    static func parse(fromAPIStrength raw: String) -> MedicineSpecification {
        var s = MedicineSpecification()
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.isEmpty == false else { return s }

        let mulScalars = "×＊*xX".unicodeScalars
        func containsMul(_ str: String) -> Bool {
            str.unicodeScalars.contains { mulScalars.contains($0) }
        }

        if let slash = t.firstIndex(of: "/") {
            let lhs = String(t[..<slash]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rhs = String(t[t.index(after: slash)...]).trimmingCharacters(in: .whitespacesAndNewlines)

            if containsMul(lhs) {
                s.outerPackageUnit = MedicineSpecificationCatalog.storedInnerOrOuter(fromAny: rhs)
                parseCore(lhs, into: &s)
            } else {
                fillDoseSegment(lhs, into: &s)
                s.packageCount = ""
                s.packageUnit = MedicineSpecificationCatalog.storedInnerOrOuter(fromAny: rhs)
            }
            return s
        }

        parseCore(t, into: &s)
        return s
    }

    private static func parseCore(_ core: String, into s: inout MedicineSpecification) {
        let separators = CharacterSet(charactersIn: "×＊*xX")
        let parts = core
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        if parts.count >= 2 {
            fillDoseSegment(parts[0], into: &s)
            fillPackageSegment(parts[1], into: &s)
        } else if let only = parts.first {
            fillDoseSegment(only, into: &s)
        }
    }

    private static func fillDoseSegment(_ segment: String, into s: inout MedicineSpecification) {
        let (num, unit) = splitLeadingNumber(from: segment)
        s.doseValue = num
        s.doseUnit = MedicineSpecificationCatalog.storedDoseUnit(fromAny: unit)
    }

    private static func fillPackageSegment(_ segment: String, into s: inout MedicineSpecification) {
        let (num, unit) = splitLeadingNumber(from: segment)
        s.packageCount = num
        s.packageUnit = MedicineSpecificationCatalog.storedInnerOrOuter(fromAny: unit)
    }

    /// Splits `"5mg"` → `("5", "mg")`, `"28片"` → `("28", "片")`.
    private static func splitLeadingNumber(from segment: String) -> (String, String) {
        let t = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.isEmpty == false else { return ("", "") }
        var idx = t.startIndex
        if t.first == "." {
            return ("", t)
        }
        while idx < t.endIndex {
            let ch = t[idx]
            if ch.isNumber || ch == "." {
                idx = t.index(after: idx)
                continue
            }
            break
        }
        if idx == t.startIndex {
            return ("", t)
        }
        let num = String(t[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = String(t[idx...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (num, rest)
    }
}

// MARK: - Unit catalogs (stored Chinese; UI can show English)

enum MedicineSpecificationCatalog {
    nonisolated static let doseUnitItems: [SparkBilingualItem] = [
        .init(cn: "mg", en: "mg"),
        .init(cn: "毫克", en: "mg"),
        .init(cn: "g", en: "g"),
        .init(cn: "克", en: "g"),
        .init(cn: "毫升", en: "mL"),
        .init(cn: "mL", en: "mL"),
        .init(cn: "IU", en: "IU"),
        .init(cn: "微克", en: "mcg"),
        .init(cn: "mcg", en: "mcg"),
        .init(cn: "%", en: "%")
    ]

    nonisolated static let innerPackageUnitItems: [SparkBilingualItem] = [
        .init(cn: "片", en: "tablets"),
        .init(cn: "粒", en: "capsules"),
        .init(cn: "支", en: "ampoules"),
        .init(cn: "袋", en: "sachets"),
        .init(cn: "瓶", en: "bottles"),
        .init(cn: "滴", en: "drops"),
        .init(cn: "贴", en: "patches"),
        .init(cn: "喷", en: "sprays"),
        .init(cn: "吸", en: "inhalations"),
        .init(cn: "包", en: "packs"),
        .init(cn: "杯", en: "cups"),
        .init(cn: "顿", en: "doses"),
        .init(cn: "盒", en: "boxes")
    ]

    nonisolated static let outerPackageUnitItems: [SparkBilingualItem] = [
        .init(cn: "盒", en: "box"),
        .init(cn: "瓶", en: "bottle"),
        .init(cn: "袋", en: "bag"),
        .init(cn: "箱", en: "case"),
        .init(cn: "包", en: "pack")
    ]

    nonisolated private static var prefersEnglish: Bool {
        SparkFormCatalogMenuLocale.prefersEnglish
    }

    nonisolated static var defaultDoseStoredOptions: [String] { doseUnitItems.map(\.cn) }
    nonisolated static var defaultInnerStoredOptions: [String] { innerPackageUnitItems.map(\.cn) }
    nonisolated static var defaultOuterStoredOptions: [String] { outerPackageUnitItems.map(\.cn) }

    nonisolated static func displayOptions(forStored stored: [String], catalog: [SparkBilingualItem]) -> [String] {
        let merged = uniquedStrings(stored.map { storedToken(fromAny: $0, catalog: catalog) })
        return merged.map { displayUnit(stored: $0, prefersEnglish: prefersEnglish) }
    }

    nonisolated static func storedDoseUnit(fromDisplay display: String) -> String {
        storedToken(fromDisplay: display, catalog: doseUnitItems)
    }

    nonisolated static func storedInnerOrOuter(fromDisplay display: String) -> String {
        let inner = storedToken(fromDisplay: display, catalog: innerPackageUnitItems)
        if inner.isEmpty == false { return inner }
        return storedToken(fromDisplay: display, catalog: outerPackageUnitItems)
    }

    nonisolated static func storedInnerOrOuter(fromAny raw: String) -> String {
        let inner = storedToken(fromAny: raw, catalog: innerPackageUnitItems)
        if inner.isEmpty == false { return inner }
        return storedToken(fromAny: raw, catalog: outerPackageUnitItems)
    }

    nonisolated static func storedDoseUnit(fromAny raw: String) -> String {
        storedToken(fromAny: raw, catalog: doseUnitItems)
    }

    nonisolated static func storedOuterPackage(fromDisplay display: String) -> String {
        storedToken(fromDisplay: display, catalog: outerPackageUnitItems)
    }

    nonisolated static func storedInnerPackage(fromDisplay display: String) -> String {
        storedToken(fromDisplay: display, catalog: innerPackageUnitItems)
    }

    nonisolated static func storedInnerPackage(fromAny raw: String) -> String {
        storedToken(fromAny: raw, catalog: innerPackageUnitItems)
    }

    nonisolated static func storedOuterPackage(fromAny raw: String) -> String {
        storedToken(fromAny: raw, catalog: outerPackageUnitItems)
    }

    nonisolated static func doseUnitMenuOptions(boxes: [SparkMedicalSyncAPI.RemoteMedicineBox]) -> [String] {
        let (d, _, _) = optionsFromBoxes(boxes)
        return displayOptions(forStored: d, catalog: doseUnitItems)
    }

    nonisolated static func innerPackageMenuOptions(boxes: [SparkMedicalSyncAPI.RemoteMedicineBox]) -> [String] {
        let (_, i, _) = optionsFromBoxes(boxes)
        return displayOptions(forStored: i, catalog: innerPackageUnitItems)
    }

    nonisolated static func outerPackageMenuOptions(boxes: [SparkMedicalSyncAPI.RemoteMedicineBox]) -> [String] {
        let (_, _, o) = optionsFromBoxes(boxes)
        return displayOptions(forStored: o, catalog: outerPackageUnitItems)
    }

    nonisolated static func displayUnit(stored: String, prefersEnglish: Bool) -> String {
        if let hit = doseUnitItems.first(where: { $0.cn == stored || $0.en == stored }) {
            return prefersEnglish ? hit.en : hit.cn
        }
        if let hit = innerPackageUnitItems.first(where: { $0.cn == stored || $0.en == stored }) {
            return prefersEnglish ? hit.en : hit.cn
        }
        if let hit = outerPackageUnitItems.first(where: { $0.cn == stored || $0.en == stored }) {
            return prefersEnglish ? hit.en : hit.cn
        }
        return stored.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func optionsFromBoxes(_ boxes: [SparkMedicalSyncAPI.RemoteMedicineBox]) -> (
        dose: [String],
        inner: [String],
        outer: [String]
    ) {
        var dose: [String] = defaultDoseStoredOptions
        var inner: [String] = defaultInnerStoredOptions
        var outer: [String] = defaultOuterStoredOptions
        for box in boxes {
            let spec = MedicineSpecification.parse(fromAPIStrength: box.strength)
            if spec.doseUnit.isEmpty == false { dose.append(spec.doseUnit) }
            let apiDoseUnit = box.doseUnit.trimmingCharacters(in: .whitespacesAndNewlines)
            if apiDoseUnit.isEmpty == false { dose.append(apiDoseUnit) }
            if spec.packageUnit.isEmpty == false { inner.append(spec.packageUnit) }
            if spec.outerPackageUnit.isEmpty == false { outer.append(spec.outerPackageUnit) }
        }
        return (uniquedStrings(dose), uniquedStrings(inner), uniquedStrings(outer))
    }

    nonisolated private static func storedToken(fromDisplay display: String, catalog: [SparkBilingualItem]) -> String {
        let text = display.trimmingCharacters(in: .whitespacesAndNewlines)
        if let item = catalog.first(where: { $0.cn == text || $0.en == text }) {
            return item.cn
        }
        return text
    }

    nonisolated private static func storedToken(fromAny raw: String, catalog: [SparkBilingualItem]) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return "" }
        if let item = catalog.first(where: { $0.cn == text || $0.en == text }) {
            return item.cn
        }
        return text
    }

    nonisolated private static func uniquedStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for v in values {
            let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.isEmpty == false else { continue }
            if seen.insert(t).inserted {
                out.append(t)
            }
        }
        return out
    }
}
