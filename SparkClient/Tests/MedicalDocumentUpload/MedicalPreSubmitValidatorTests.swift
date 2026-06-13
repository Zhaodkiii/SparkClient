#if canImport(XCTest)
import XCTest
@testable import SparkClient

final class MedicalPreSubmitValidatorTests: XCTestCase {
    private let validator = MedicalPreSubmitValidator()

    func testIsValidDecimalStringAcceptsPureNumbers() {
        XCTAssertTrue(MedicalPreSubmitValidationRules.isValidDecimalString(nil))
        XCTAssertTrue(MedicalPreSubmitValidationRules.isValidDecimalString(""))
        XCTAssertTrue(MedicalPreSubmitValidationRules.isValidDecimalString("   "))
        XCTAssertTrue(MedicalPreSubmitValidationRules.isValidDecimalString("1"))
        XCTAssertTrue(MedicalPreSubmitValidationRules.isValidDecimalString("1.5"))
        XCTAssertTrue(MedicalPreSubmitValidationRules.isValidDecimalString("0.5"))
        XCTAssertTrue(MedicalPreSubmitValidationRules.isValidDecimalString("20"))
        XCTAssertTrue(MedicalPreSubmitValidationRules.isValidDecimalString("225"))
    }

    func testIsValidDecimalStringRejectsUnitsAndText() {
        XCTAssertFalse(MedicalPreSubmitValidationRules.isValidDecimalString("20mg"))
        XCTAssertFalse(MedicalPreSubmitValidationRules.isValidDecimalString("225mg"))
        XCTAssertFalse(MedicalPreSubmitValidationRules.isValidDecimalString("1片"))
        XCTAssertFalse(MedicalPreSubmitValidationRules.isValidDecimalString("1滴"))
        XCTAssertFalse(MedicalPreSubmitValidationRules.isValidDecimalString("半片"))
        XCTAssertFalse(MedicalPreSubmitValidationRules.isValidDecimalString("一片"))
        XCTAssertFalse(MedicalPreSubmitValidationRules.isValidDecimalString("每日一次"))
    }

    func testPrescriptionSubmitBlocksNonNumericDoseValue() {
        let plan = MedicationPlanRecognitionDraft(
            medicineName: "阿托伐他汀钙片",
            dosePerTime: "1片",
            doseValue: "20mg",
            doseUnit: "片",
            frequencyType: "daily"
        )
        let draft = PrescriptionRecognitionDraft(
            medicalCase: nil,
            prescriberName: nil,
            institutionName: "测试医院",
            prescribedAt: "2024-01-01",
            diagnosis: nil,
            prescriptionNo: nil,
            status: "active",
            extra: nil,
            medicationPlans: [plan]
        )
        let output = makeOutput(.prescription([draft]))

        let issues = validator.validate(output: output).blockingIssues
        let doseIssues = issues.filter { $0.fieldKey.hasSuffix(".dose_value") }

        XCTAssertEqual(doseIssues.count, 1)
        XCTAssertEqual(doseIssues.first?.fieldKey, "prescriptions[0].medication_plans[0].dose_value")
        XCTAssertEqual(doseIssues.first?.scrollTargetID, "preSubmitValidation.card.medicationPlan.0.0")
    }

    func testPrescriptionSubmitAllowsPureNumericDoseValue() {
        let plan = MedicationPlanRecognitionDraft(
            medicineName: "阿托伐他汀钙片",
            dosePerTime: "1片",
            doseValue: "20",
            doseUnit: "片",
            frequencyType: "daily"
        )
        let draft = PrescriptionRecognitionDraft(
            medicalCase: nil,
            prescriberName: nil,
            institutionName: "测试医院",
            prescribedAt: "2024-01-01",
            diagnosis: nil,
            prescriptionNo: nil,
            status: "active",
            extra: nil,
            medicationPlans: [plan]
        )
        let output = makeOutput(.prescription([draft]))

        let issues = validator.validate(output: output).blockingIssues
        XCTAssertFalse(issues.contains { $0.fieldKey.hasSuffix(".dose_value") })
    }

    func testMultiPrescriptionDoseValueIssueUsesCorrectPrescriptionIndex() {
        let validPlan = MedicationPlanRecognitionDraft(
            medicineName: "药品A",
            doseValue: "1",
            frequencyType: "daily"
        )
        let invalidPlan = MedicationPlanRecognitionDraft(
            medicineName: "硫酸氨氯吡格雷片",
            dosePerTime: "3片",
            doseValue: "225mg",
            doseUnit: "片",
            frequencyType: "daily"
        )
        let firstPrescription = PrescriptionRecognitionDraft(
            medicalCase: nil,
            prescriberName: nil,
            institutionName: "医院A",
            prescribedAt: "2024-01-01",
            diagnosis: nil,
            prescriptionNo: nil,
            status: "active",
            extra: nil,
            medicationPlans: [validPlan]
        )
        let secondPrescription = PrescriptionRecognitionDraft(
            medicalCase: nil,
            prescriberName: nil,
            institutionName: "医院B",
            prescribedAt: "2024-01-02",
            diagnosis: nil,
            prescriptionNo: nil,
            status: "active",
            extra: nil,
            medicationPlans: [invalidPlan]
        )
        let output = makeOutput(.prescription([firstPrescription, secondPrescription]))

        let issues = validator.validate(output: output).blockingIssues
        let doseIssues = issues.filter { $0.fieldKey.hasSuffix(".dose_value") }

        XCTAssertEqual(doseIssues.count, 1)
        XCTAssertEqual(doseIssues.first?.fieldKey, "prescriptions[1].medication_plans[0].dose_value")
        XCTAssertEqual(doseIssues.first?.prescriptionIndex, 1)
        XCTAssertEqual(doseIssues.first?.scrollTargetID, "preSubmitValidation.card.medicationPlan.1.0")
    }

    func testStandaloneMedicationPlanDoseValueValidation() {
        let plan = MedicationPlanRecognitionDraft(
            medicineName: "测试药品",
            doseValue: "225mg",
            frequencyType: "daily"
        )
        let output = makeOutput(.medicationPlan([plan]))

        let issues = validator.validate(output: output).blockingIssues
        let doseIssues = issues.filter { $0.fieldKey.hasSuffix(".dose_value") }

        XCTAssertEqual(doseIssues.count, 1)
        XCTAssertEqual(doseIssues.first?.fieldKey, "medication_plans[0].dose_value")
        XCTAssertNil(doseIssues.first?.prescriptionIndex)
    }

    private func makeOutput(_ typedResult: MedicalDocumentTypedResult) -> MedicalDocumentTypedExtractionOutput {
        MedicalDocumentTypedExtractionOutput(
            envelope: MedicalDocumentRecognitionEnvelope(
                memberID: 1,
                sourceFiles: [],
                rawOCRText: "",
                typeResolution: MedicalDocumentTypeResolution(
                    kind: .prescription,
                    confidence: 1,
                    source: .manual
                )
            ),
            typedResult: typedResult,
            extractedJSON: "{}",
            payloadPreview: "{}"
        )
    }
}
#endif
