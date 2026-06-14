import SwiftUI

/// 药箱识别结果页（模块化：ResultPages/MedicineBoxRecognitionResult）
struct MedicineBoxRecognitionResultView: View {
    @ObservedObject private var viewModel: MedicalDocumentUploadViewModel

    init(viewModel: MedicalDocumentUploadViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        Group {
            if viewModel.typedOutput != nil {
                MedicineBoxRecognitionResultContentView(viewModel: viewModel)
            }
        }
        .navigationTitle(L10n.text("home.medical.list.medicine_box.title", fallback: "药箱"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview("Medicine box result - Light") {
    CompatibleNavigationContainer {
        MedicineBoxRecognitionResultView(viewModel: .preview(output: .previewMedicineBoxOutput))
    }
    .preferredColorScheme(.light)
}

#Preview("Medicine box result - Dark") {
    CompatibleNavigationContainer {
        MedicineBoxRecognitionResultView(viewModel: .preview(output: .previewMedicineBoxOutput))
    }
    .preferredColorScheme(.dark)
}

private extension MedicalDocumentTypedExtractionOutput {
    static var previewMedicineBoxOutput: MedicalDocumentTypedExtractionOutput {
        MedicalDocumentTypedExtractionOutput(
            envelope: MedicalDocumentRecognitionEnvelope(
                memberID: 100,
                sourceFiles: [
                    MedicalUploadLocalFile(
                        url: URL(fileURLWithPath: "/tmp/medicine-box-preview.jpg"),
                        displayName: "药盒照片.jpg",
                        mimeType: "image/jpeg"
                    )
                ],
                rawOCRText: "",
                typeResolution: MedicalDocumentTypeResolution(
                    kind: .medicineBox,
                    confidence: 0.92,
                    source: .ai,
                    reason: "命中药箱结构化字段"
                )
            ),
            typedResult: .medicineBoxes([
                MedicineBoxRecognitionDraft(
                    medicineName: "养血清脑颗粒",
                    medicineType: nil,
                    brandName: "",
                    dosageForm: "",
                    strength: "4g*15袋",
                    doseUnit: "",
                    totalQuantity: nil,
                    expireDate: nil,
                    notes: "Migrated from ZhaodkDream",
                    extra: [
                        "migration_legacy_id": "158",
                        "migration_legacy_table": "aera_medication_box"
                    ],
                    sortOrder: "0"
                ),
                MedicineBoxRecognitionDraft(
                    medicineName: "盐酸倍他司汀片",
                    medicineType: nil,
                    brandName: "",
                    dosageForm: "",
                    strength: "4mg*10片",
                    doseUnit: "",
                    totalQuantity: nil,
                    expireDate: nil,
                    notes: "Migrated from ZhaodkDream",
                    extra: [
                        "migration_legacy_id": "157",
                        "migration_legacy_table": "aera_medication_box"
                    ],
                    sortOrder: "1"
                ),
                MedicineBoxRecognitionDraft(
                    medicineName: "甲磺酸倍他司汀片",
                    medicineType: nil,
                    brandName: "",
                    dosageForm: "",
                    strength: "6mg*100片/盒",
                    doseUnit: "",
                    totalQuantity: nil,
                    expireDate: nil,
                    notes: "Migrated from ZhaodkDream",
                    extra: [
                        "migration_legacy_id": "159",
                        "migration_legacy_table": "aera_medication_box"
                    ],
                    sortOrder: "2"
                )
            ]),
            extractedJSON: "",
            payloadPreview: ""
        )
    }
}
#endif
