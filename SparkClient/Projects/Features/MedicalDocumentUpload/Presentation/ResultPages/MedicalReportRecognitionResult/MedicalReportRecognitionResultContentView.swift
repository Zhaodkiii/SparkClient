import SwiftUI

struct MedicalReportRecognitionResultContentView: View {
    let output: MedicalDocumentTypedExtractionOutput
    let isSaving: Bool
    let saveReceipt: MedicalDocumentSaveReceipt?
    let onBack: () -> Void
    let onSave: () -> Void

    @State private var reports: [MedicalReportRecognitionDraft]
    @State private var localEditor: MedicalReportResultLocalEditor?

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

        if case .medicalReport(let drafts) = output.typedResult {
            _reports = State(initialValue: drafts)
        } else {
            _reports = State(initialValue: [])
        }
    }

    private var attachments: [MedicalReportResultLocalAttachmentItem] {
        output.envelope.sourceFiles.map { MedicalReportResultLocalAttachmentItem(file: $0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MedicalReportMemberSectionView(memberID: output.envelope.memberID, reports: reports)
                MedicalReportStatsSectionView(reports: reports)
                MedicalReportCardsSectionView(
                    reports: reports,
                    onEdit: { index, draft in
                        logger.info("Medical report result: open local editor index=\(index)", module: logModule)
                        localEditor = .report(index: index, draft: draft)
                    }
                )
                MedicalReportAttachmentsSectionView(attachments: attachments)

                if let saveReceipt {
                    MedicalReportResultSectionCard(
                        title: L10n.text("medical.upload.result.common.save_status"),
                        subtitle: L10n.text("medical.upload.result.common.save_success"),
                        systemImage: "checkmark.circle",
                        badgeText: L10n.text("medical.upload.result.common.saved")
                    ) {
                        MedicalReportResultInfoLine(
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
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: reports.count)
        .fullScreenCover(item: $localEditor) { editor in
            NavigationView {
                editorDestination(editor)
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button(L10n.text("medical.upload.result.common.back"), action: onBack)
                .buttonStyle(.bordered)

            Button {
                logger.info("Medical report result: submit save tapped", module: logModule)
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
    private func editorDestination(_ editor: MedicalReportResultLocalEditor) -> some View {
        switch editor {
        case .report(let index, let draft):
            ExamReportFormView(
                mode: .localEdit(existing: draft, onSubmit: { updated in
                    guard reports.indices.contains(index) else { return }
                    reports[index] = updated
                    logger.info("Medical report result: local report updated index=\(index)", module: logModule)
                })
            )
        }
    }
}
