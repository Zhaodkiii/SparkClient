import Foundation

struct SymptomCategoryGroup: Identifiable, Equatable {
    let titleItem: SparkBilingualItem
    let systemImage: String
    let symptomItems: [SparkBilingualItem]

    var id: String { titleItem.cn }
    var title: String { MedicalFormBilingualCatalog.display(titleItem) }
    var symptoms: [String] { symptomItems.map(\.cn) }
}

enum SymptomFormSupport {
    static var durationOptions: [String] {
        MedicalFormBilingualCatalog.symptomDurationOptions.map(\.cn)
    }

    static var symptomCategories: [SymptomCategoryGroup] {
        MedicalFormBilingualCatalog.symptomCategories.map {
            SymptomCategoryGroup(titleItem: $0.title, systemImage: $0.systemImage, symptomItems: $0.items)
        }
    }

    static var allPresetSymptoms: [String] {
        symptomCategories.flatMap(\.symptoms)
    }

    static func displaySymptom(_ stored: String) -> String {
        MedicalFormBilingualCatalog.displayStored(stored, in: MedicalFormBilingualCatalog.allSymptomItems)
    }

    static func displayDuration(_ stored: String) -> String {
        MedicalFormBilingualCatalog.displayStored(stored, in: MedicalFormBilingualCatalog.symptomDurationOptions)
    }

    static func symptomMatchesSearch(_ symptom: String, matching searchText: String) -> Bool {
        if let item = MedicalFormBilingualCatalog.allSymptomItems.first(where: { $0.cn == symptom }) {
            return CatalogItemSearch.matches(item, searchText: searchText)
        }
        return CatalogItemSearch.matches(symptom, searchText: searchText)
    }

    static func filteredCategories(matching searchText: String) -> [SymptomCategoryGroup] {
        MedicalFormBilingualCatalog.filteredGroups(MedicalFormBilingualCatalog.symptomCategories, matching: searchText)
            .map { SymptomCategoryGroup(titleItem: $0.title, systemImage: $0.systemImage, symptomItems: $0.items) }
    }

    static func severityLabel(_ value: String) -> String {
        MedicalFormBilingualCatalog.displaySymptomSeverity(value)
    }

    static func parseDurationOption(_ option: String) -> (value: Int?, unit: String?) {
        let canonical = MedicalFormBilingualCatalog.displayStored(option, in: MedicalFormBilingualCatalog.symptomDurationOptions)
        let cn = MedicalFormBilingualCatalog.symptomDurationOptions.first(where: {
            $0.cn == canonical || $0.en == canonical
        })?.cn ?? option

        switch cn {
        case "1天": return (1, "天")
        case "3天": return (3, "天")
        case "1周": return (1, "周")
        case "2周": return (2, "周")
        case "1个月": return (1, "月")
        case "3个月以上": return (3, "月")
        default:
            guard cn.isEmpty == false else { return (nil, nil) }
            return (nil, cn)
        }
    }

    static func durationOption(value: Int?, unit: String?) -> String {
        guard let value, let unit, unit.isEmpty == false else { return "" }
        let normalized = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        if value == 3, normalized == "月" {
            return "3个月以上"
        }
        return "\(value)\(normalized)"
    }

    static func sourceLabel(for symptom: SparkMedicalSyncAPI.RemoteSymptom) -> String {
        let raw = symptom.extra?["source"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch raw {
        case "manual", "": return L10n.text("medical_record.forms.symptom.source.manual")
        case "case_recognition", "case_document": return L10n.text("medical_record.forms.symptom.source.case_recognition")
        case "ai_extraction", "ai": return L10n.text("medical_record.forms.symptom.source.ai")
        default: return raw
        }
    }

    static func medicalCaseLabel(for symptom: SparkMedicalSyncAPI.RemoteSymptom) -> String {
        symptom.medicalCase == nil
            ? L10n.text("medical_record.forms.symptom.case.unlinked")
            : L10n.text("medical_record.forms.symptom.case.linked")
    }

    static func startedAtText(for symptom: SparkMedicalSyncAPI.RemoteSymptom) -> String {
        guard let startedAt = symptom.startedAt else { return "" }
        return startedAt.formatted(date: .numeric, time: .omitted)
    }

    static func durationText(for symptom: SparkMedicalSyncAPI.RemoteSymptom) -> String {
        let option = durationOption(value: symptom.durationValue, unit: symptom.durationUnit.nilIfBlank)
        guard option.isEmpty == false else { return "" }
        return L10n.format("medical_record.forms.symptom.duration_prefix", displayDuration(option))
    }

    static func summaryLine(for symptom: SparkMedicalSyncAPI.RemoteSymptom) -> String {
        summaryLine(
            names: [symptom.name],
            duration: durationOption(value: symptom.durationValue, unit: symptom.durationUnit.nilIfBlank),
            severity: symptom.severity.nilIfBlank ?? "",
            notes: symptom.notes.nilIfBlank ?? ""
        )
    }

    static func summaryLine(
        names: [String],
        duration: String,
        severity: String,
        notes: String
    ) -> String {
        var pieces: [String] = []
        let trimmedNames = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { $0.isEmpty == false }
        if trimmedNames.isEmpty == false {
            let displayNames = trimmedNames.map { displaySymptom($0) }
            pieces.append(displayNames.joined(separator: "、"))
        }
        if duration.isEmpty == false {
            pieces.append(L10n.format("medical_record.forms.symptom.duration_prefix", displayDuration(duration)))
        }
        if severity.isEmpty == false {
            pieces.append(severityLabel(severity))
        }
        if notes.isEmpty == false {
            pieces.append(notes)
        }
        return pieces.joined(separator: " · ")
    }

    static func joinedSymptomName(_ selectedSymptoms: [String]) -> String? {
        let trimmedNames = selectedSymptoms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        guard trimmedNames.isEmpty == false else { return nil }
        return trimmedNames.joined(separator: "、")
    }

    static func summaryLine(for draft: SymptomRecognitionDraft) -> String {
        let duration = durationOption(
            value: draft.durationValue.flatMap { Int($0) },
            unit: draft.durationUnit
        )
        return summaryLine(
            names: selectedSymptoms(from: draft),
            duration: duration,
            severity: draft.severity ?? "",
            notes: draft.notes ?? ""
        )
    }

    static func selectedSymptoms(from draft: SymptomRecognitionDraft) -> [String] {
        let trimmed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return [] }
        return trimmed
            .components(separatedBy: "、")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    static func makeDraft(
        selectedSymptoms: [String],
        duration: String,
        severity: String,
        notes: String,
        existing: SymptomRecognitionDraft? = nil
    ) -> SymptomRecognitionDraft? {
        guard let joinedName = joinedSymptomName(selectedSymptoms) else { return nil }

        let canonicalDuration = MedicalFormBilingualCatalog.symptomDurationOptions.first(where: {
            $0.cn == duration || $0.en == duration
        })?.cn ?? duration
        let parsedDuration = parseDurationOption(canonicalDuration)
        return SymptomRecognitionDraft(
            name: joinedName,
            code: existing?.code,
            severity: severity.nilIfBlank,
            startedAt: existing?.startedAt,
            durationValue: parsedDuration.value.map(String.init) ?? existing?.durationValue,
            durationUnit: parsedDuration.unit ?? existing?.durationUnit,
            bodyPart: existing?.bodyPart,
            notes: notes.nilIfBlank ?? existing?.notes
        )
    }
}
