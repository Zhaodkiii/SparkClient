import SwiftUI

struct MedicationRecognitionResultContentView: View {
    let output: MedicalDocumentTypedExtractionOutput
    let isSaving: Bool
    let saveReceipt: MedicalDocumentSaveReceipt?
    let onBack: () -> Void
    let onSave: () -> Void

    @State private var medicationPlans: [MedicationPlanRecognitionDraft]
    @State private var localEditor: MedicationResultLocalEditor?

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

        if case .medicationPlan(let meds) = output.typedResult {
            _medicationPlans = State(initialValue: meds)
        } else {
            _medicationPlans = State(initialValue: [])
        }
    }

    private var attachments: [MedicationResultLocalAttachmentItem] {
        output.envelope.sourceFiles.map { MedicationResultLocalAttachmentItem(file: $0) }
    }

    private var syntheticBatch: PrescriptionRecognitionDraft {
        PrescriptionRecognitionDraft(
            medicalCase: nil,
            prescriberName: nil,
            institutionName: nil,
            prescribedAt: nil,
            diagnosis: nil,
            prescriptionNo: nil,
            status: "active",
            extra: nil,
            medicationPlans: medicationPlans
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MedicationMemberConfirmSectionView(
                    memberID: output.envelope.memberID,
                    medications: medicationPlans
                )

                MedicationListSectionView(
                    medications: medicationPlans,
                    onBatchEdit: {
                        logger.info("Medication result: open local batch editor", module: logModule)
                        localEditor = .batch(syntheticBatch)
                    },
                    onEditItem: { index, item in
                        logger.info("Medication result: open local item editor index=\(index)", module: logModule)
                        localEditor = .item(index: index, draft: item)
                    }
                )

                MedicationAttachmentsSectionView(attachments: attachments)

                if let saveReceipt {
                    MedicationResultSectionCard(
                        title: L10n.text("medical.upload.result.common.save_status"),
                        subtitle: L10n.text("medical.upload.result.common.save_success"),
                        systemImage: "checkmark.circle",
                        badgeText: L10n.text("medical.upload.result.common.saved")
                    ) {
                        MedicationResultInfoLine(
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
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: medicationPlans.count)
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
                logger.info("Medication result: submit save tapped", module: logModule)
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
    private func editorDestination(_ editor: MedicationResultLocalEditor) -> some View {
        switch editor {
        case .batch(let batch):
            MedicationMultiCreateView(
                mode: .localEdit(existing: batch, onSubmit: { updated in
                    medicationPlans = updated.medicationPlans ?? []
                    logger.info("Medication result: local batch updated meds=\(medicationPlans.count)", module: logModule)
                })
            )

        case .item(let index, let item):
            MedicationFormView(
                mode: .localEdit(existing: item, onSubmit: { updated in
                    guard medicationPlans.indices.contains(index) else { return }
                    medicationPlans[index] = updated
                    logger.info("Medication result: local item updated index=\(index)", module: logModule)
                })
            )
        }
    }
}
