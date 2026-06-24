import Foundation

struct SurgeryCategoryGroup: Identifiable, Equatable {
    let titleItem: SparkBilingualItem
    let systemImage: String
    let procedureItems: [SparkBilingualItem]

    var id: String { titleItem.cn }
    var title: String { MedicalFormBilingualCatalog.display(titleItem) }
    var procedures: [String] { procedureItems.map(\.cn) }
}

enum SurgeryFormSupport {
    static var recoveryOptions: [String] {
        MedicalFormBilingualCatalog.surgeryRecoveryOptions.map(\.cn)
    }

    static var categoryGroups: [SurgeryCategoryGroup] {
        MedicalFormBilingualCatalog.surgeryCategories.map {
            SurgeryCategoryGroup(titleItem: $0.title, systemImage: $0.systemImage, procedureItems: $0.items)
        }
    }

    static func displayProcedure(_ stored: String) -> String {
        MedicalFormBilingualCatalog.displayStored(stored, in: MedicalFormBilingualCatalog.allSurgeryProcedureItems)
    }

    static func displayRecoveryStatus(_ stored: String) -> String {
        MedicalFormBilingualCatalog.displayStored(stored, in: MedicalFormBilingualCatalog.surgeryRecoveryOptions)
    }

    static func filteredCategories(matching searchText: String) -> [SurgeryCategoryGroup] {
        MedicalFormBilingualCatalog.filteredGroups(MedicalFormBilingualCatalog.surgeryCategories, matching: searchText)
            .map { SurgeryCategoryGroup(titleItem: $0.title, systemImage: $0.systemImage, procedureItems: $0.items) }
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
        let canonicalName = MedicalFormBilingualCatalog.allSurgeryProcedureItems.first(where: {
            $0.cn == trimmedName || $0.en == trimmedName
        })?.cn ?? trimmedName
        return SurgeryRecognitionDraft(
            procedureName: canonicalName,
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
        let canonicalRecovery = MedicalFormBilingualCatalog.surgeryRecoveryOptions.first(where: {
            $0.cn == recoveryStatus || $0.en == recoveryStatus
        })?.cn ?? recoveryStatus
        if let recovery = canonicalRecovery.nilIfBlank {
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
        let name = displayProcedure(surgery.procedureName.nilIfBlank ?? L10n.text("medical_record.forms.surgery.unnamed"))
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
        let name = displayProcedure(procedureName.nilIfBlank ?? L10n.text("medical_record.forms.surgery.unnamed"))
        let details = [performedAt, site, hospitalName, displayRecoveryStatus(recoveryStatus)]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        guard details.isEmpty == false else { return name }
        return "\(name) · \(details.joined(separator: " · "))"
    }

    static func profileSummary(from focus: [SparkMedicalSyncAPI.RemoteSurgeryFocusItem]) -> String {
        guard focus.isEmpty == false else { return L10n.text("medical_record.forms.surgery.no_history") }
        return focus.map { item in
            let name = displayProcedure(item.procedureName.nilIfBlank ?? L10n.text("medical_record.forms.surgery.unnamed"))
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
        case "manual": return L10n.text("medical_record.forms.surgery.source.manual")
        case "photo_ai", "case_document_ai": return L10n.text("medical_record.forms.surgery.source.recognition")
        default: return surgery.extra?["source"] ?? L10n.text("medical_record.forms.surgery.source.manual")
        }
    }

    static func medicalCaseLabel(for surgery: SparkMedicalSyncAPI.RemoteSurgery) -> String {
        surgery.medicalCase == nil
            ? L10n.text("medical_record.forms.surgery.case.unlinked")
            : L10n.text("medical_record.forms.surgery.case.linked")
    }

    private static func detailParts(for surgery: SparkMedicalSyncAPI.RemoteSurgery) -> [String] {
        [
            performedAtText(for: surgery),
            surgery.site.nilIfBlank,
            hospitalName(for: surgery),
            displayRecoveryStatus(recoveryStatus(for: surgery))
        ].compactMap { $0?.nilIfBlank }.filter { $0.isEmpty == false }
    }
}
