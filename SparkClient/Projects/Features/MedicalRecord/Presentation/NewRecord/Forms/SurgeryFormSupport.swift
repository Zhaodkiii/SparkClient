import Foundation

struct SurgeryCategoryGroup: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let systemImage: String
    let procedures: [String]
}

enum SurgeryFormSupport {
    static let recoveryOptions = ["恢复良好", "定期随访", "仍有不适", "不清楚"]

    static let categoryGroups: [SurgeryCategoryGroup] = [
        .init(
            title: "普外与胃肠系统",
            systemImage: "cross.case.fill",
            procedures: ["阑尾切除", "胆囊切除/微创", "疝气修补", "肠胃息肉摘除"]
        ),
        .init(
            title: "骨科与运动医学",
            systemImage: "figure.walk",
            procedures: ["骨折复位固定", "关节置换", "半月板/韧带修复", "腰椎手术"]
        ),
        .init(
            title: "心胸与血管",
            systemImage: "heart.fill",
            procedures: ["心脏支架(PCI)", "心脏起搏器植入", "肺结节/肺叶切除"]
        ),
        .init(
            title: "妇产与泌尿生殖",
            systemImage: "person.crop.circle.badge.plus",
            procedures: ["剖宫产", "子宫肌瘤/囊肿剔除", "肾/输尿管碎石术"]
        ),
        .init(
            title: "五官与头颈",
            systemImage: "eye.fill",
            procedures: ["甲状腺切除/消融", "白内障摘除", "扁桃体/腺样体切除"]
        )
    ]

    static func filteredCategories(matching searchText: String) -> [SurgeryCategoryGroup] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return categoryGroups }

        let query = trimmed.lowercased()
        let queryPinyin = trimmed.toPinyinForSearch().lowercased()

        return categoryGroups.compactMap { category in
            let matched = category.procedures.filter { procedure in
                procedure.localizedCaseInsensitiveContains(trimmed)
                    || procedure.toPinyinForSearch().lowercased().contains(queryPinyin)
                    || procedure.toPinyinForSearch().lowercased().contains(query)
            }
            if category.title.localizedCaseInsensitiveContains(trimmed) {
                return category
            }
            guard matched.isEmpty == false else { return nil }
            return SurgeryCategoryGroup(title: category.title, systemImage: category.systemImage, procedures: matched)
        }
    }

    static func makeDraft(
        procedureName: String,
        performedAt: String,
        recoveryStatus: String,
        hospitalName: String,
        site: String,
        notes: String,
        existing: SurgeryRecognitionDraft?
    ) -> SurgeryRecognitionDraft? {
        let trimmedName = procedureName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else { return nil }
        return SurgeryRecognitionDraft(
            procedureName: trimmedName,
            procedureCode: existing?.procedureCode,
            site: site.nilIfBlank ?? existing?.site,
            performedAt: performedAt.nilIfBlank ?? existing?.performedAt,
            surgeon: existing?.surgeon,
            anesthesiaType: existing?.anesthesiaType,
            incisionLevel: existing?.incisionLevel,
            asaClass: existing?.asaClass,
            notes: notes.nilIfBlank ?? existing?.notes
        )
    }

    static func buildExtra(
        draft: SurgeryRecognitionDraft,
        recoveryStatus: String,
        hospitalName: String,
        source: String = "manual"
    ) -> [String: String] {
        var extra: [String: String] = ["source": source]
        if let recovery = recoveryStatus.nilIfBlank {
            extra["recovery_status"] = recovery
        }
        if let hospital = hospitalName.nilIfBlank {
            extra["hospital_name"] = hospital
        }
        if let performedAt = draft.performedAt?.nilIfBlank, performedAt.contains("-") == false {
            extra["performed_at_text"] = performedAt
        }
        return extra
    }

    static func workflowPerformedAt(for draft: SurgeryRecognitionDraft) -> String? {
        guard let performedAt = draft.performedAt?.nilIfBlank else { return nil }
        if performedAt.contains("-") {
            return performedAt
        }
        return nil
    }

    static func summaryLine(for surgery: SparkMedicalSyncAPI.RemoteSurgery) -> String {
        let name = surgery.procedureName.nilIfBlank ?? "未命名手术"
        let details = detailParts(for: surgery)
        guard details.isEmpty == false else { return name }
        return "\(name) · \(details.joined(separator: " · "))"
    }

    static func summaryLine(
        procedureName: String,
        performedAt: String,
        recoveryStatus: String,
        hospitalName: String,
        site: String
    ) -> String {
        let name = procedureName.nilIfBlank ?? "未命名手术"
        let details = [performedAt, site, hospitalName, recoveryStatus]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        guard details.isEmpty == false else { return name }
        return "\(name) · \(details.joined(separator: " · "))"
    }

    static func profileSummary(from focus: [SparkMedicalSyncAPI.RemoteSurgeryFocusItem]) -> String {
        guard focus.isEmpty == false else { return "无手术史" }
        return focus.map { item in
            let name = item.procedureName.nilIfBlank ?? "未命名手术"
            let summary = item.summary.nilIfBlank
            return summary.map { "\(name) · \($0)" } ?? name
        }.joined(separator: " / ")
    }

    static func performedAtText(for surgery: SparkMedicalSyncAPI.RemoteSurgery) -> String {
        if let performedAt = surgery.performedAt {
            let formatter = DateFormatter()
            formatter.calendar = Calendar.current
            formatter.dateFormat = "yyyy年M月"
            return formatter.string(from: performedAt)
        }
        return surgery.extra?["performed_at_text"] ?? surgery.extra?["surgery_time"] ?? ""
    }

    static func recoveryStatus(for surgery: SparkMedicalSyncAPI.RemoteSurgery) -> String {
        surgery.extra?["recovery_status"] ?? ""
    }

    static func hospitalName(for surgery: SparkMedicalSyncAPI.RemoteSurgery) -> String {
        surgery.extra?["hospital_name"] ?? ""
    }

    static func sourceLabel(for surgery: SparkMedicalSyncAPI.RemoteSurgery) -> String {
        switch surgery.extra?["source"] {
        case "manual": return "手动添加"
        case "photo_ai", "case_document_ai": return "识别添加"
        default: return surgery.extra?["source"] ?? "手动添加"
        }
    }

    static func medicalCaseLabel(for surgery: SparkMedicalSyncAPI.RemoteSurgery) -> String {
        surgery.medicalCase == nil ? "未关联" : "已关联病例"
    }

    private static func detailParts(for surgery: SparkMedicalSyncAPI.RemoteSurgery) -> [String] {
        [
            performedAtText(for: surgery),
            surgery.site.nilIfBlank,
            hospitalName(for: surgery),
            recoveryStatus(for: surgery)
        ].compactMap { $0?.nilIfBlank }
    }
}
