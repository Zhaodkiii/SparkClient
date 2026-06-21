import Foundation

struct SymptomCategoryGroup: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let systemImage: String
    let symptoms: [String]
}

enum SymptomFormSupport {
    static let durationOptions = ["1天", "3天", "1周", "2周", "1个月", "3个月以上"]

    static let symptomCategories: [SymptomCategoryGroup] = [
        .init(
            title: "全身与神经系统",
            systemImage: "figure.stand",
            symptoms: ["发热", "头痛", "疲劳/乏力", "睡眠障碍"]
        ),
        .init(
            title: "心肺与呼吸系统",
            systemImage: "heart.fill",
            symptoms: ["咳嗽", "胸痛", "心悸", "血压波动"]
        ),
        .init(
            title: "胃肠与代谢系统",
            systemImage: "fork.knife",
            symptoms: ["胃肠不适", "恶心/呕吐", "血糖波动", "食欲改变"]
        ),
        .init(
            title: "肌肉与体表",
            systemImage: "figure.walk",
            symptoms: ["关节疼痛", "肌肉酸痛", "异常浮肿", "皮疹"]
        )
    ]

    static func filteredCategories(matching searchText: String) -> [SymptomCategoryGroup] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return symptomCategories }

        let query = trimmed.lowercased()
        let queryPinyin = trimmed.toPinyinForSearch().lowercased()

        return symptomCategories.compactMap { category in
            let matchedSymptoms = category.symptoms.filter { symptom in
                symptom.localizedCaseInsensitiveContains(trimmed)
                    || symptom.toPinyinForSearch().lowercased().contains(queryPinyin)
                    || symptom.toPinyinForSearch().lowercased().contains(query)
            }
            guard matchedSymptoms.isEmpty == false else { return nil }
            return SymptomCategoryGroup(
                title: category.title,
                systemImage: category.systemImage,
                symptoms: matchedSymptoms
            )
        }
    }

    static func severityLabel(_ value: String) -> String {
        switch value {
        case "low": return "轻度"
        case "medium": return "中度"
        case "high": return "重度"
        default: return value
        }
    }

    static func parseDurationOption(_ option: String) -> (value: Int?, unit: String?) {
        switch option {
        case "1天": return (1, "天")
        case "3天": return (3, "天")
        case "1周": return (1, "周")
        case "2周": return (2, "周")
        case "1个月": return (1, "月")
        case "3个月以上": return (3, "月")
        default:
            guard option.isEmpty == false else { return (nil, nil) }
            return (nil, option)
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
        case "manual", "": return "手动添加"
        case "case_recognition", "case_document": return "病历识别"
        case "ai_extraction", "ai": return "AI 抽取"
        default: return raw
        }
    }

    static func medicalCaseLabel(for symptom: SparkMedicalSyncAPI.RemoteSymptom) -> String {
        symptom.medicalCase == nil ? "未关联" : "已关联病历"
    }

    static func startedAtText(for symptom: SparkMedicalSyncAPI.RemoteSymptom) -> String {
        guard let startedAt = symptom.startedAt else { return "" }
        return startedAt.formatted(date: .numeric, time: .omitted)
    }

    static func durationText(for symptom: SparkMedicalSyncAPI.RemoteSymptom) -> String {
        let option = durationOption(value: symptom.durationValue, unit: symptom.durationUnit.nilIfBlank)
        guard option.isEmpty == false else { return "" }
        return "持续\(option)"
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
            pieces.append(trimmedNames.joined(separator: "、"))
        }
        if duration.isEmpty == false {
            pieces.append("持续\(duration)")
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

        let parsedDuration = parseDurationOption(duration)
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
