import SwiftUI

struct PrescriptionRecognitionResultContentView: View {
    let output: MedicalDocumentTypedExtractionOutput
    let isSaving: Bool
    let saveReceipt: MedicalDocumentSaveReceipt?
    let onBack: () -> Void
    let onSave: () -> Void

    @State private var batch: PrescriptionRecognitionDraft
    @State private var localEditor: PrescriptionResultLocalEditor?

    private let logger: Logger = ConsoleLogger()
    private let logModule: LogModule = .medical

    init(
        output: MedicalDocumentTypedExtractionOutput,
        isSaving: Bool,
        saveReceipt: MedicalDocumentSaveReceipt?,
        onBack: @escaping () -> Void,
        onSave: @escaping () -> Void
    ) {
        self.output = output
        self.isSaving = isSaving
        self.saveReceipt = saveReceipt
        self.onBack = onBack
        self.onSave = onSave

        if case .prescription(let draft) = output.typedResult {
            _batch = State(initialValue: draft)
        } else {
            _batch = State(initialValue: PrescriptionRecognitionDraft(
                medicalCase: nil,
                prescriberName: nil,
                institutionName: nil,
                prescribedAt: nil,
                diagnosis: nil,
                prescriptionNo: nil,
                status: nil,
                extra: nil,
                medicationPlans: []
            ))
        }
    }

    private var attachments: [PrescriptionResultLocalAttachmentItem] {
        output.envelope.sourceFiles.map { PrescriptionResultLocalAttachmentItem(file: $0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PrescriptionMemberConfirmSectionView(
                    memberID: output.envelope.memberID,
                    batch: batch
                )

                PrescriptionBatchListSectionView(
                    batch: batch,
                    onEditBatch: {
                        logger.info("Prescription result: open local batch editor", module: logModule)
                        localEditor = .batch(batch)
                    },
                    onEditMedication: { index, item in
                        logger.info("Prescription result: open local medication editor index=\(index)", module: logModule)
                        localEditor = .medication(index: index, draft: item)
                    }
                )

                PrescriptionAttachmentsSectionView(attachments: attachments)

                if let saveReceipt {
                    PrescriptionResultSectionCard(
                        title: L10n.text("medical.upload.result.common.save_status"),
                        subtitle: L10n.text("medical.upload.result.common.save_success"),
                        systemImage: "checkmark.circle",
                        badgeText: L10n.text("medical.upload.result.common.saved")
                    ) {
                        PrescriptionResultInfoLine(
                            title: L10n.text("medical.upload.result.common.record_id"),
                            value: "\(saveReceipt.recordID)"
                        )
                    }
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            bottomBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: batch.medicationPlans?.count ?? 0)
        .fullScreenCover(item: $localEditor) { editor in
            CompatibleNavigationContainer {
                editorDestination(editor)
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button(L10n.text("medical.upload.result.common.back"), action: onBack)
                .buttonStyle(.bordered)

            Button {
                logger.info("Prescription result: submit save tapped", module: logModule)
                onSave()
            } label: {
                Group {
                    if isSaving {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text(L10n.text("medical.upload.result.common.submit")).frame(maxWidth: .infinity)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving)
        }
    }

    @ViewBuilder
    private func editorDestination(_ editor: PrescriptionResultLocalEditor) -> some View {
        switch editor {
        case .batch(let existing):
            MedicationMultiCreateView(
                mode: .localEdit(existing: existing, onSubmit: { updated in
                    logger.info("Prescription result: local batch updated meds=\(updated.medicationPlans?.count ?? 0)", module: logModule)
                    batch = updated
                })
            )

        case .medication(let index, let med):
            MedicationFormView(
                mode: .localEdit(existing: med, onSubmit: { updated in
                    var meds = batch.medicationPlans ?? []
                    guard meds.indices.contains(index) else { return }
                    meds[index] = updated
                    batch = PrescriptionRecognitionDraft(
                        medicalCase: batch.medicalCase,
                        prescriberName: batch.prescriberName,
                        institutionName: batch.institutionName,
                        prescribedAt: batch.prescribedAt,
                        diagnosis: batch.diagnosis,
                        prescriptionNo: batch.prescriptionNo,
                        status: batch.status,
                        extra: batch.extra,
                        medicationPlans: meds
                    )
                    logger.info("Prescription result: local medication updated index=\(index)", module: logModule)
                })
            )
        }
    }
}
