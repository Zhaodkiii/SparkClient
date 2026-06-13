#if canImport(XCTest)
import XCTest
@testable import SparkClient

final class PrescriptionPreSubmitValidationTests: XCTestCase {
    private let validator = MedicalPreSubmitValidator()

    func testNormalizePrescriptionStatusMapsCommonTypeToActive() {
        let normalized = PrescriptionFieldNormalization.normalizePrescriptionStatus("普通", extra: nil)
        XCTAssertEqual(normalized.status, "active")
        XCTAssertEqual(normalized.extraUpdates[PrescriptionFieldNormalization.prescriptionTypeExtraKey], "普通")
    }

    func testNormalizePrescriptionStatusMapsPaidToActiveWithoutStructuredPaymentField() {
        let normalized = PrescriptionFieldNormalization.normalizePrescriptionStatus("paid", extra: nil)
        XCTAssertEqual(normalized.status, "active")
        XCTAssertEqual(normalized.extraUpdates[PrescriptionFieldNormalization.paymentStatusExtraKey], "paid")
    }

    func testPrescriptionSubmitBlocksIllegalStatusAfterNormalizationPath() {
        let draft = PrescriptionRecognitionDraft(
            institutionName: "测试医院",
            prescribedAt: "2024-01-01",
            status: "普通",
            medicationPlans: [
                MedicationPlanRecognitionDraft(
                    medicineName: "测试药品",
                    doseValue: "1",
                    frequencyType: "daily"
                )
            ]
        )
        let issues = validator.validate(output: makeOutput(.prescription([draft]))).blockingIssues
        XCTAssertTrue(issues.contains { $0.fieldKey == "prescriptions[0].status" })
    }

    func testNormalizedDraftAllowsSubmitForCommonPrescriptionTypeText() {
        let draft = PrescriptionFieldNormalization.normalizePrescriptionDraft(
            PrescriptionRecognitionDraft(
                institutionName: "测试医院",
                prescribedAt: "2024-01-01",
                status: "普通",
                medicationPlans: [
                    MedicationPlanRecognitionDraft(
                        medicineName: "测试药品",
                        doseValue: "1",
                        frequencyType: "daily",
                        startDate: "2024-01-01"
                    )
                ]
            )
        )
        let issues = validator.validate(output: makeOutput(.prescription([draft]))).blockingIssues
        XCTAssertFalse(issues.contains { $0.fieldKey == "prescriptions[0].status" })
    }

    func testBlocksHighRiskDoseValue() {
        let plan = MedicationPlanRecognitionDraft(
            medicineName: "测试药品",
            doseValue: "93",
            doseUnit: "片",
            frequencyType: "daily",
            startDate: "2024-01-01"
        )
        let draft = PrescriptionRecognitionDraft(
            institutionName: "测试医院",
            prescribedAt: "2024-01-01",
            status: "active",
            medicationPlans: [plan]
        )
        let issues = validator.validate(output: makeOutput(.prescription([draft]))).blockingIssues
        XCTAssertTrue(issues.contains { $0.fieldKey.hasSuffix(".dose_value") })
    }

    func testBlocksEveryNDaysWithoutValue() {
        let plan = MedicationPlanRecognitionDraft(
            medicineName: "测试药品",
            doseValue: "1",
            frequencyType: "every_n_days",
            startDate: "2024-01-01"
        )
        let draft = PrescriptionRecognitionDraft(
            institutionName: "测试医院",
            status: "active",
            medicationPlans: [plan]
        )
        let issues = validator.validate(output: makeOutput(.prescription([draft]))).blockingIssues
        XCTAssertTrue(issues.contains { $0.fieldKey.hasSuffix(".every_n_days") })
    }

    func testBlocksDualMedicineBoxBinding() {
        var extra: [String: String] = [:]
        extra[PrescriptionRecognitionDraftMapper.confirmedMedicineBoxIDExtraKey] = "42"
        let plan = MedicationPlanRecognitionDraft(
            medicineName: "测试药品",
            doseValue: "1",
            frequencyType: "daily",
            startDate: "2024-01-01",
            medicineBox: MedicineBoxRecognitionDraft(medicineName: "测试药品"),
            extra: extra
        )
        let draft = PrescriptionRecognitionDraft(
            institutionName: "测试医院",
            status: "active",
            medicationPlans: [plan]
        )
        let issues = validator.validate(output: makeOutput(.prescription([draft]))).blockingIssues
        XCTAssertTrue(issues.contains { $0.fieldKey.hasSuffix(".medicine_box") })
    }

    func testPreflightBlocksInvalidPayloadStatus() {
        let request = PrescriptionCreateRequest(
            medicalCase: nil,
            prescriberName: nil,
            institutionName: "测试医院",
            prescribedAt: "2024-01-01",
            diagnosis: nil,
            prescriptionNo: nil,
            status: "普通",
            extra: nil,
            medicationPlans: [],
            sourceFileIds: nil
        )
        let issues = PrescriptionPayloadPreflightValidator.validate(prescriptions: [request])
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.fieldKey, "prescriptions[0].status")
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
