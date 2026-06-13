#if canImport(XCTest)
import XCTest
@testable import SparkClient

final class PrescriptionMedicineBoxCandidateTests: XCTestCase {
    private func sampleBox(id: Int, name: String, strength: String = "", stock: Double? = nil) -> SparkMedicalSyncAPI.RemoteMedicineBox {
        SparkMedicalSyncAPI.RemoteMedicineBox(
            id: id,
            member: 1,
            medicineName: name,
            medicineType: nil,
            brandName: "",
            dosageForm: "",
            strength: strength,
            doseUnit: "粒",
            totalQuantity: stock,
            expireDate: nil,
            notes: "",
            extra: nil,
            attachments: nil,
            updatedAt: Date()
        )
    }

    func testNormalizeMedicineNameTrimsAndLowercases() {
        XCTAssertEqual(
            PrescriptionMedicineBoxCandidateMatcher.normalizeMedicineName(" 阿莫西林胶囊 "),
            "阿莫西林胶囊"
        )
        XCTAssertEqual(
            PrescriptionMedicineBoxCandidateMatcher.normalizeMedicineName("Amoxicillin"),
            "amoxicillin"
        )
    }

    func testMatchCandidateFindsUniqueExistingByExactName() {
        let plan = MedicationPlanRecognitionDraft(
            medicineName: "阿莫西林胶囊",
            medicineBox: MedicineBoxRecognitionDraft(medicineName: "阿莫西林胶囊")
        )
        let boxes = [sampleBox(id: 10, name: "阿莫西林胶囊", stock: 12)]

        let match = PrescriptionMedicineBoxCandidateMatcher.matchCandidate(
            plan: plan,
            confirmation: nil,
            familyBoxes: boxes,
            loadFailedMessage: nil
        )

        guard case .uniqueExisting(_, let target) = match else {
            return XCTFail("Expected uniqueExisting, got \(match)")
        }
        XCTAssertEqual(target.id, 10)
    }

    func testMatchCandidateFindsMultipleExistingByExactName() {
        let plan = MedicationPlanRecognitionDraft(
            medicineBox: MedicineBoxRecognitionDraft(medicineName: "阿莫西林胶囊")
        )
        let boxes = [
            sampleBox(id: 10, name: "阿莫西林胶囊", strength: "0.25g"),
            sampleBox(id: 11, name: "阿莫西林胶囊", strength: "0.5g"),
        ]

        let match = PrescriptionMedicineBoxCandidateMatcher.matchCandidate(
            plan: plan,
            confirmation: nil,
            familyBoxes: boxes,
            loadFailedMessage: nil
        )

        guard case .multipleExisting(_, let targets) = match else {
            return XCTFail("Expected multipleExisting")
        }
        XCTAssertEqual(targets.count, 2)
    }

    func testResolvingStripsUnconfirmedMedicineBox() {
        let plan = MedicationPlanRecognitionDraft(
            medicineName: "布洛芬",
            medicineBox: MedicineBoxRecognitionDraft(medicineName: "布洛芬")
        )
        let batch = PrescriptionRecognitionDraft(medicationPlans: [plan])
        let resolved = [batch].resolvingMedicineBoxCandidates(confirmations: [:])

        XCTAssertNil(resolved[0].medicationPlans?[0].medicineBox)
    }

    func testResolvingBindExistingSetsConfirmedMedicineBoxID() {
        let key = MedicationCandidateKey(prescriptionIndex: 0, medicationIndex: 0)
        let plan = MedicationPlanRecognitionDraft(
            medicineName: "阿莫西林",
            medicineBox: MedicineBoxRecognitionDraft(medicineName: "阿莫西林")
        )
        let batch = PrescriptionRecognitionDraft(medicationPlans: [plan])
        let confirmations: [MedicationCandidateKey: MedicineBoxCandidateConfirmation] = [
            key: MedicineBoxCandidateConfirmation(
                isConfirmed: true,
                action: .bindExisting(medicineBoxID: 42),
                editedCandidate: nil,
                selectedExistingBoxID: 42
            ),
        ]

        let resolved = [batch].resolvingMedicineBoxCandidates(confirmations: confirmations)
        let extra = resolved[0].medicationPlans?[0].extra
        XCTAssertNil(resolved[0].medicationPlans?[0].medicineBox)
        XCTAssertEqual(extra?[PrescriptionRecognitionDraftMapper.confirmedMedicineBoxIDExtraKey], "42")
    }

    func testResolvingCreateNewKeepsMedicineBox() {
        let key = MedicationCandidateKey(prescriptionIndex: 0, medicationIndex: 0)
        let plan = MedicationPlanRecognitionDraft(
            medicineName: "布洛芬",
            medicineBox: MedicineBoxRecognitionDraft(medicineName: "布洛芬")
        )
        let batch = PrescriptionRecognitionDraft(medicationPlans: [plan])
        let confirmations: [MedicationCandidateKey: MedicineBoxCandidateConfirmation] = [
            key: MedicineBoxCandidateConfirmation(
                isConfirmed: true,
                action: .createNew,
                editedCandidate: nil,
                selectedExistingBoxID: nil
            ),
        ]

        let resolved = [batch].resolvingMedicineBoxCandidates(confirmations: confirmations)
        XCTAssertNotNil(resolved[0].medicationPlans?[0].medicineBox)
    }
}
#endif
