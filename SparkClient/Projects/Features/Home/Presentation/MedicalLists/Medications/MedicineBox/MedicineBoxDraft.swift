import Foundation

struct MedicineBoxDraft {
    var medicineName = ""
    var medicineType = MedicineBoxTypeCatalog.defaultStoredValue
    var brandName = ""
    var dosageForm = ""
    /// Structured specification; encoded to API `strength` via ``MedicineSpecification/storedStrengthString``.
    var specification = MedicineSpecification()
    var totalQuantity = ""
    var hasExpireDate = false
    var expireDate = Date()
    var notes = ""
    var attachments: [SparkMedicalSyncAPI.RemoteManagedFile] = []

    init() {}

    init(recognition: MedicineBoxRecognitionDraft) {
        medicineName = recognition.medicineName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        medicineType = MedicineBoxTypeCatalog.storedValue(fromAny: recognition.medicineType)
        brandName = recognition.brandName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        dosageForm = MedicineBoxDosageFormCatalog.storedValue(fromAny: recognition.dosageForm ?? "")
        let rawStrength = recognition.strength?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parsed = MedicineSpecification.parse(fromAPIStrength: rawStrength)
        if parsed.hasStructuredContent {
            specification = parsed
        } else if rawStrength.isEmpty == false {
            specification = MedicineSpecification(rawLegacyOnly: rawStrength)
        }
        totalQuantity = recognition.totalQuantity?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let expire = recognition.expireDate?.nilIfBlank {
            hasExpireDate = true
            expireDate = Date.parseOrNow(expire)
        }
        notes = recognition.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        MedicineSpecification.mergeDoseUnitFromAPI(recognition.doseUnit, into: &specification)
    }

    init(existing: SparkMedicalSyncAPI.RemoteMedicineBox) {
        medicineName = existing.medicineName
        medicineType = MedicineBoxTypeCatalog.storedValue(fromAny: existing.medicineType)
        brandName = existing.brandName
        dosageForm = existing.dosageForm
        let parsed = MedicineSpecification.parse(fromAPIStrength: existing.strength)
        if parsed.hasStructuredContent {
            specification = parsed
        } else if existing.strength.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            specification = MedicineSpecification(rawLegacyOnly: existing.strength)
        } else {
            specification = MedicineSpecification()
        }
        MedicineSpecification.mergeDoseUnitFromAPI(existing.doseUnit, into: &specification)
        if let q = existing.totalQuantity {
            totalQuantity = MedicineBoxDraft.formatQuantity(q)
        } else {
            totalQuantity = ""
        }
        if let expireDate = existing.expireDate {
            hasExpireDate = true
            self.expireDate = expireDate
        }
        notes = existing.notes
        attachments = existing.attachments ?? []
    }

    var totalQuantityValue: Double? {
        Double(totalQuantity.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func payload(entryMemberID: Int, bindingMemberID: Int?, fileIds: [Int] = []) throws -> SparkMedicalWorkflowAPI.MedicineBoxWritePayload {
        let trimmedQty = totalQuantity.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTotal: Double?
        if trimmedQty.isEmpty {
            resolvedTotal = nil
        } else if let v = Double(trimmedQty) {
            resolvedTotal = v
        } else {
            throw MedicineBoxFormError.invalidQuantity
        }
        return SparkMedicalWorkflowAPI.MedicineBoxWritePayload(
            member: bindingMemberID,
            entryMemberID: entryMemberID,
            medicineName: medicineName.trimmingCharacters(in: .whitespacesAndNewlines),
            medicineType: medicineType.nilIfBlank,
            brandName: brandName.nilIfBlank ?? "",
            dosageForm: dosageForm.nilIfBlank ?? "",
            strength: specification.storedStrengthString.nilIfBlank ?? "",
            doseUnit: specification.backendDoseUnitField,
            totalQuantity: resolvedTotal,
            expireDate: hasExpireDate ? MedicalDateCoding.encodeDateOnly(expireDate) : nil,
            notes: notes.nilIfBlank ?? "",
            extra: [:],
            fileIds: fileIds
        )
    }

    private static func formatQuantity(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    func recognitionDraft(sortOrder: String? = nil) -> MedicineBoxRecognitionDraft {
        MedicineBoxRecognitionDraft(
            medicineName: medicineName.nilIfBlank,
            medicineType: medicineType.nilIfBlank,
            brandName: brandName.nilIfBlank,
            dosageForm: dosageForm.nilIfBlank,
            strength: specification.storedStrengthString.nilIfBlank,
            doseUnit: specification.backendDoseUnitField.nilIfBlank,
            totalQuantity: totalQuantity.nilIfBlank,
            expireDate: hasExpireDate ? MedicalDateCoding.encodeDateOnly(expireDate) : nil,
            notes: notes.nilIfBlank,
            extra: nil,
            sortOrder: sortOrder
        )
    }
}

enum MedicineBoxFormError: LocalizedError {
    case invalidQuantity

    var errorDescription: String? {
        switch self {
        case .invalidQuantity:
            return L10n.text("home.medical.medicine_box.form.invalid_quantity")
        }
    }
}
