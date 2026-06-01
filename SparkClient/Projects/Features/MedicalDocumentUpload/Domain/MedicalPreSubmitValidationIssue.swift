import Foundation

enum MedicalPreSubmitValidationResourceType: String, Sendable {
    case caseDocument
    case symptom
    case visit
    case surgery
    case followUp
    case healthExamReport
    case examinationReport
    case prescription
    case medicationPlan
    case medicineBox
}

enum MedicalPreSubmitValidationSeverity: Sendable {
    case blocking
    case warning
}

/// 可折叠模块标识，用于预校验失败后自动展开对应区块。
enum MedicalPreSubmitValidationSectionID {
    static let caseHistory = "preSubmitValidation.section.caseHistory"
    static let examinationReports = "preSubmitValidation.section.examinationReports"
    static let treatmentPlan = "preSubmitValidation.section.treatmentPlan"
    static let medicationList = "preSubmitValidation.section.medicationList"
    static let medicineBoxList = "preSubmitValidation.section.medicineBoxList"
    static let healthExamGroups = "preSubmitValidation.section.healthExamGroups"
}

struct MedicalPreSubmitValidationIssue: Identifiable, Equatable, Sendable {
    let id: UUID
    let resourceType: MedicalPreSubmitValidationResourceType
    let fieldPath: String
    let fieldKey: String
    let fieldLabel: String
    let message: String
    let severity: MedicalPreSubmitValidationSeverity
    let sectionTitle: String
    let cardIndex: Int?
    /// 处方内药品在 `prescriptions[n].medication_plans[m]` 场景下的处方下标。
    let prescriptionIndex: Int?

    init(
        id: UUID = UUID(),
        resourceType: MedicalPreSubmitValidationResourceType,
        fieldPath: String,
        fieldKey: String,
        fieldLabel: String,
        message: String,
        severity: MedicalPreSubmitValidationSeverity = .blocking,
        sectionTitle: String,
        cardIndex: Int? = nil,
        prescriptionIndex: Int? = nil
    ) {
        self.id = id
        self.resourceType = resourceType
        self.fieldPath = fieldPath
        self.fieldKey = fieldKey
        self.fieldLabel = fieldLabel
        self.message = message
        self.severity = severity
        self.sectionTitle = sectionTitle
        self.cardIndex = cardIndex
        self.prescriptionIndex = prescriptionIndex
    }

    var scrollTargetID: String {
        Self.makeScrollTargetID(
            resourceType: resourceType,
            fieldKey: fieldKey,
            cardIndex: cardIndex,
            prescriptionIndex: prescriptionIndex
        )
    }

    /// 错误所在可折叠模块；无折叠容器时返回 `nil`。
    var collapseSectionID: String? {
        switch resourceType {
        case .caseDocument, .symptom, .visit, .surgery, .followUp:
            return MedicalPreSubmitValidationSectionID.caseHistory
        case .examinationReport:
            return MedicalPreSubmitValidationSectionID.examinationReports
        case .prescription:
            return MedicalPreSubmitValidationSectionID.treatmentPlan
        case .medicationPlan:
            if prescriptionIndex != nil {
                return MedicalPreSubmitValidationSectionID.treatmentPlan
            }
            return MedicalPreSubmitValidationSectionID.medicationList
        case .medicineBox:
            return MedicalPreSubmitValidationSectionID.medicineBoxList
        case .healthExamReport:
            return nil
        }
    }

    /// 体检指标在 `health_exam.items[n]` 中的下标。
    var healthExamItemIndex: Int? {
        guard fieldKey.hasPrefix("health_exam.items["),
              let openBracket = fieldKey.firstIndex(of: "["),
              let closeBracket = fieldKey[openBracket...].firstIndex(of: "]")
        else { return nil }
        let indexStart = fieldKey.index(after: openBracket)
        return Int(fieldKey[indexStart..<closeBracket])
    }

    static func makeScrollTargetID(
        resourceType: MedicalPreSubmitValidationResourceType,
        fieldKey: String,
        cardIndex: Int?,
        prescriptionIndex: Int?
    ) -> String {
        if let prescriptionIndex, let cardIndex, resourceType == .medicationPlan {
            return "preSubmitValidation.card.medicationPlan.\(prescriptionIndex).\(cardIndex)"
        }
        if resourceType == .healthExamReport, fieldKey.contains(".items[") {
            if let cardIndex {
                return "preSubmitValidation.card.healthExamReport.item.\(cardIndex)"
            }
        }
        if let cardIndex {
            switch resourceType {
            case .examinationReport, .medicineBox, .prescription:
                return "preSubmitValidation.card.\(resourceType.rawValue).\(cardIndex)"
            case .medicationPlan:
                return "preSubmitValidation.card.medicationPlan.\(cardIndex)"
            default:
                break
            }
        }
        return "preSubmitValidation.field.\(fieldKey)"
    }

    var summaryLine: String {
        if let cardIndex {
            return String(
                format: L10n.text("medical.upload.presubmit.summary.item_line"),
                cardIndex + 1,
                sectionTitle,
                fieldLabel,
                message
            )
        }
        return "\(fieldLabel)：\(message)"
    }
}

extension Array where Element == MedicalPreSubmitValidationIssue {
    var blockingIssues: [MedicalPreSubmitValidationIssue] {
        filter { $0.severity == .blocking }
    }

    func issues(forFieldKey fieldKey: String) -> [MedicalPreSubmitValidationIssue] {
        filter { $0.fieldKey == fieldKey }
    }

    func issues(
        forCardIndex cardIndex: Int,
        resourceType: MedicalPreSubmitValidationResourceType
    ) -> [MedicalPreSubmitValidationIssue] {
        filter { issue in
            issue.cardIndex == cardIndex
                && issue.resourceType == resourceType
                && issue.fieldKey.contains(".items[") == false
        }
    }

    func issues(
        forMedicationPlan prescriptionIndex: Int,
        itemIndex: Int
    ) -> [MedicalPreSubmitValidationIssue] {
        filter {
            $0.resourceType == .medicationPlan
                && $0.prescriptionIndex == prescriptionIndex
                && $0.cardIndex == itemIndex
        }
    }

    func issues(matchingFieldPathPrefix prefix: String) -> [MedicalPreSubmitValidationIssue] {
        filter { $0.fieldPath.hasPrefix(prefix) || $0.fieldKey.hasPrefix(prefix) }
    }

    func issues(matchingFieldKeyPrefix prefix: String) -> [MedicalPreSubmitValidationIssue] {
        filter { $0.fieldKey.hasPrefix(prefix) }
    }

    func hasIssue(
        forCardIndex cardIndex: Int,
        resourceType: MedicalPreSubmitValidationResourceType
    ) -> Bool {
        contains { $0.cardIndex == cardIndex && $0.resourceType == resourceType }
    }

    func hasIssue(forFieldKey fieldKey: String) -> Bool {
        contains { $0.fieldKey == fieldKey }
    }

    func firstMessage(forFieldKey fieldKey: String) -> String? {
        issues(forFieldKey: fieldKey).first?.message
    }
}
