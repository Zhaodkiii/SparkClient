import Foundation

struct DecodedHealthExamExtractionDTO: Decodable {
    let institutionName: String?
    let reportNo: String?
    let examDate: String?
    let examType: String?
    let summary: String?
    let items: [DecodedHealthExamItemDTO]

    enum CodingKeys: String, CodingKey {
        case institutionName = "institutionName"
        case institutionNameSnake = "institution_name"
        case hospital
        case hospitalName = "hospital_name"
        case reportNo = "reportNo"
        case reportNoSnake = "report_no"
        case examNo = "examNo"
        case examNoSnake = "exam_no"
        case examDate = "examDate"
        case examDateSnake = "exam_date"
        case date
        case examType = "examType"
        case examTypeSnake = "exam_type"
        case summary
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        institutionName = container.decodeFlexibleString(forKeys: [.institutionName, .institutionNameSnake, .hospital, .hospitalName])
        reportNo = container.decodeFlexibleString(forKeys: [.reportNo, .reportNoSnake, .examNo, .examNoSnake])
        examDate = container.decodeFlexibleString(forKeys: [.examDate, .examDateSnake, .date])
        examType = container.decodeFlexibleString(forKeys: [.examType, .examTypeSnake])
        summary = container.decodeFlexibleString(forKeys: [.summary])
        items = (try? container.decodeIfPresent([DecodedHealthExamItemDTO].self, forKey: .items)) ?? []
    }
}

struct DecodedCaseExtractionDTO: Decodable {
    let title: String?
    let summary: String?
    let diagnosis: String?
    let occurredAt: String?

    enum CodingKeys: String, CodingKey {
        case title
        case summary
        case diagnosis
        case occurredAt = "occurredAt"
        case occurredAtSnake = "occurred_at"
        case date
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = container.decodeFlexibleString(forKeys: [.title])
        summary = container.decodeFlexibleString(forKeys: [.summary])
        diagnosis = container.decodeFlexibleString(forKeys: [.diagnosis])
        occurredAt = container.decodeFlexibleString(forKeys: [.occurredAt, .occurredAtSnake, .date])
    }
}

struct DecodedHealthExamItemDTO: Decodable {
    let category: String?
    let subCategory: String?
    let itemName: String?
    let itemCode: String?
    let resultValue: String?
    let unit: String?
    let referenceRange: String?
    let flag: String?
    let resultAt: String?
    let modality: String?
    let bodyPart: String?
    let diagnosis: String?
    let sortOrder: Int?
    let extra: [String: String]?

    enum CodingKeys: String, CodingKey {
        case category
        case subCategory = "subCategory"
        case subCategorySnake = "sub_category"
        case itemName = "itemName"
        case itemNameSnake = "item_name"
        case itemCode = "itemCode"
        case itemCodeSnake = "item_code"
        case resultValue = "resultValue"
        case resultValueSnake = "result_value"
        case unit
        case referenceRange = "referenceRange"
        case referenceRangeSnake = "reference_range"
        case flag
        case resultAt = "resultAt"
        case resultAtSnake = "result_at"
        case modality
        case bodyPart = "bodyPart"
        case bodyPartSnake = "body_part"
        case diagnosis
        case sortOrder = "sortOrder"
        case sortOrderSnake = "sort_order"
        case extra
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        category = container.decodeFlexibleString(forKeys: [.category])
        subCategory = container.decodeFlexibleString(forKeys: [.subCategory, .subCategorySnake])
        itemName = container.decodeFlexibleString(forKeys: [.itemName, .itemNameSnake])
        itemCode = container.decodeFlexibleString(forKeys: [.itemCode, .itemCodeSnake])
        resultValue = container.decodeFlexibleString(forKeys: [.resultValue, .resultValueSnake])
        unit = container.decodeFlexibleString(forKeys: [.unit])
        referenceRange = container.decodeFlexibleString(forKeys: [.referenceRange, .referenceRangeSnake])
        flag = container.decodeFlexibleString(forKeys: [.flag])
        resultAt = container.decodeFlexibleString(forKeys: [.resultAt, .resultAtSnake])
        modality = container.decodeFlexibleString(forKeys: [.modality])
        bodyPart = container.decodeFlexibleString(forKeys: [.bodyPart, .bodyPartSnake])
        diagnosis = container.decodeFlexibleString(forKeys: [.diagnosis])
        sortOrder = container.decodeFlexibleInt(forKeys: [.sortOrder, .sortOrderSnake])
        extra = container.decodeFlexibleStringDictionary(forKeys: [.extra])
    }
}

typealias DecodedMedicalDetailDTO = DecodedHealthExamItemDTO

struct DecodedMedicalReportExtractionDTO: Decodable {
    let reportType: String?
    let title: String?
    let hospital: String?
    let doctor: String?
    let content: String?
    let date: String?
    let items: [DecodedMedicalDetailDTO]

    enum CodingKeys: String, CodingKey {
        case reportType = "reportType"
        case reportTypeSnake = "report_type"
        case title
        case hospital
        case hospitalName = "hospital_name"
        case organizationName = "organization_name"
        case doctor
        case doctorName = "doctor_name"
        case content
        case findings
        case impression
        case date
        case performedAt = "performed_at"
        case reportedAt = "reported_at"
        case items
        case details
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reportType = container.decodeFlexibleString(forKeys: [.reportType, .reportTypeSnake])
        title = container.decodeFlexibleString(forKeys: [.title])
        hospital = container.decodeFlexibleString(forKeys: [.hospital, .hospitalName, .organizationName])
        doctor = container.decodeFlexibleString(forKeys: [.doctor, .doctorName])
        content = container.decodeFlexibleString(forKeys: [.content, .findings, .impression])
        date = container.decodeFlexibleString(forKeys: [.date, .performedAt, .reportedAt])
        items = (try? container.decodeIfPresent([DecodedMedicalDetailDTO].self, forKey: .items)) ?? (try? container.decodeIfPresent([DecodedMedicalDetailDTO].self, forKey: .details)) ?? []
    }
}

struct DecodedPrescriptionExtractionDTO: Decodable {
    let prescriberName: String?
    let institutionName: String?
    let prescribedAt: String?
    let diagnosis: String?
    let batchNo: String?
    let medications: [DecodedPrescriptionMedicationDTO]

    enum CodingKeys: String, CodingKey {
        case prescriberName = "prescriberName"
        case prescriberNameSnake = "prescriber_name"
        case doctorName = "doctor_name"
        case institutionName = "institutionName"
        case institutionNameSnake = "institution_name"
        case hospitalName = "hospital_name"
        case prescribedAt = "prescribedAt"
        case prescribedAtSnake = "prescribed_at"
        case issuedAt = "issued_at"
        case diagnosis
        case batchNo = "batchNo"
        case batchNoSnake = "batch_no"
        case prescriptionNo = "prescriptionNo"
        case prescriptionNoSnake = "prescription_no"
        case medications
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        prescriberName = container.decodeFlexibleString(forKeys: [.prescriberName, .prescriberNameSnake, .doctorName])
        institutionName = container.decodeFlexibleString(forKeys: [.institutionName, .institutionNameSnake, .hospitalName])
        prescribedAt = container.decodeFlexibleString(forKeys: [.prescribedAt, .prescribedAtSnake, .issuedAt])
        diagnosis = container.decodeFlexibleString(forKeys: [.diagnosis])
        batchNo = container.decodeFlexibleString(forKeys: [.batchNo, .batchNoSnake, .prescriptionNo, .prescriptionNoSnake])
        medications = (try? container.decodeIfPresent([DecodedPrescriptionMedicationDTO].self, forKey: .medications)) ?? []
    }
}

struct DecodedPrescriptionMedicationDTO: Decodable {
    let name: String?
    let specification: String?
    let dosage: String?
    let frequency: String?
    let duration: String?
    let instructions: String?

    enum CodingKeys: String, CodingKey {
        case name
        case drugName = "drugName"
        case drugNameSnake = "drug_name"
        case genericName = "genericName"
        case genericNameSnake = "generic_name"
        case brandName = "brandName"
        case brandNameSnake = "brand_name"
        case specification
        case strength
        case dosage
        case dosePerTime = "dosePerTime"
        case dosePerTimeSnake = "dose_per_time"
        case frequency
        case frequencyText = "frequencyText"
        case frequencyTextSnake = "frequency_text"
        case duration
        case durationDays = "durationDays"
        case durationDaysSnake = "duration_days"
        case instructions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = container.decodeFlexibleString(forKeys: [.name, .drugName, .drugNameSnake, .genericName, .genericNameSnake, .brandName, .brandNameSnake])
        specification = container.decodeFlexibleString(forKeys: [.specification, .strength])
        dosage = container.decodeFlexibleString(forKeys: [.dosage, .dosePerTime, .dosePerTimeSnake])
        frequency = container.decodeFlexibleString(forKeys: [.frequency, .frequencyText, .frequencyTextSnake])
        duration = container.decodeFlexibleString(forKeys: [.duration, .durationDays, .durationDaysSnake])
        instructions = container.decodeFlexibleString(forKeys: [.instructions])
    }
}

struct DecodedMedicationExtractionDTO: Decodable {
    let drugName: String?
    let dosage: String?
    let frequencyText: String?
    let durationDays: Int?
    let instructions: String?

    enum CodingKeys: String, CodingKey {
        case drugName = "drugName"
        case drugNameSnake = "drug_name"
        case genericName = "genericName"
        case genericNameSnake = "generic_name"
        case name
        case dosage
        case dosePerTime = "dosePerTime"
        case dosePerTimeSnake = "dose_per_time"
        case frequencyText = "frequencyText"
        case frequencyTextSnake = "frequency_text"
        case frequency
        case durationDays = "durationDays"
        case durationDaysSnake = "duration_days"
        case duration
        case instructions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        drugName = container.decodeFlexibleString(forKeys: [.drugName, .drugNameSnake, .genericName, .genericNameSnake, .name])
        dosage = container.decodeFlexibleString(forKeys: [.dosage, .dosePerTime, .dosePerTimeSnake])
        frequencyText = container.decodeFlexibleString(forKeys: [.frequencyText, .frequencyTextSnake, .frequency])
        durationDays = container.decodeFlexibleInt(forKeys: [.durationDays, .durationDaysSnake, .duration])
        instructions = container.decodeFlexibleString(forKeys: [.instructions])
    }
}

private struct FlexibleStringValue: Decodable {
    let stringValue: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            stringValue = value
        } else if let value = try? container.decode(Int.self) {
            stringValue = String(value)
        } else if let value = try? container.decode(Double.self) {
            stringValue = String(value)
        } else if let value = try? container.decode(Bool.self) {
            stringValue = String(value)
        } else {
            throw DecodingError.typeMismatch(
                String.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Unsupported value type for string coercion")
            )
        }
    }
}

extension KeyedDecodingContainer {
    func decodeFlexibleString(forKeys keys: [Key]) -> String? {
        for key in keys {
            if let value = try? decodeIfPresent(String.self, forKey: key) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty == false {
                    return trimmed
                }
            }
            if let value = try? decodeIfPresent(Int.self, forKey: key) {
                return String(value)
            }
            if let value = try? decodeIfPresent(Double.self, forKey: key) {
                return String(value)
            }
            if let value = try? decodeIfPresent(Bool.self, forKey: key) {
                return String(value)
            }
            if let value = try? decodeIfPresent(FlexibleStringValue.self, forKey: key) {
                let trimmed = value.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty == false {
                    return trimmed
                }
            }
        }
        return nil
    }

    func decodeFlexibleInt(forKeys keys: [Key]) -> Int? {
        for key in keys {
            if let value = try? decodeIfPresent(Int.self, forKey: key) {
                return value
            }
            if let value = try? decodeIfPresent(String.self, forKey: key) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if let intValue = Int(trimmed) {
                    return intValue
                }
            }
            if let value = try? decodeIfPresent(Double.self, forKey: key) {
                return Int(value)
            }
        }
        return nil
    }

    func decodeFlexibleStringDictionary(forKeys keys: [Key]) -> [String: String]? {
        for key in keys {
            if let value = try? decodeIfPresent([String: String].self, forKey: key) {
                return value
            }
            if let value = try? decodeIfPresent([String: FlexibleStringValue].self, forKey: key) {
                return value.mapValues(\.stringValue)
            }
        }
        return nil
    }
}
