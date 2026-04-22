import SwiftUI

struct HealthExamRecognitionResultContentView: View {
    let output: MedicalDocumentTypedExtractionOutput
    let isSaving: Bool
    let saveReceipt: MedicalDocumentSaveReceipt?
    let onBack: () -> Void
    let onSave: () -> Void

    @State private var draft: HealthExamRecognitionDraft
    @State private var summaryFilter: HealthExamResultSummaryFilter = .all
    @State private var localEditor: HealthExamResultLocalEditor?
    @State private var expandedCategories: Set<String> = []

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

        if case .healthExamReport(let report) = output.typedResult {
            _draft = State(initialValue: report)
        } else {
            _draft = State(initialValue: HealthExamRecognitionDraft(
                institutionName: nil,
                reportNo: nil,
                examDate: nil,
                examType: nil,
                summary: nil,
                items: []
            ))
        }
    }

    private var attachments: [HealthExamResultLocalAttachmentItem] {
        output.envelope.sourceFiles.map { HealthExamResultLocalAttachmentItem(file: $0) }
    }

    private var indexedItems: [HealthExamRiskDisplayItem] {
        draft.items.enumerated().map { pair in
            HealthExamRiskDisplayItem(
                originalIndex: pair.offset,
                item: pair.element,
                riskLevel: pair.element.inferredRiskLevel
            )
        }
    }

    private var filteredItems: [HealthExamRiskDisplayItem] {
        switch summaryFilter {
        case .all:
            return indexedItems
        case .normal:
            return indexedItems.filter { $0.riskLevel == .normal }
        case .abnormal:
            return indexedItems.filter { $0.riskLevel != .normal }
        }
    }

    private var groupedItems: [(category: String, rows: [HealthExamRiskDisplayItem])] {
        let dict = Dictionary(grouping: filteredItems, by: { $0.item.category.nilIfBlank ?? L10n.text("medical.upload.result.health_exam.category.other") })
        return dict
            .map { (key: $0.key, value: $0.value) }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { (category: $0.key, rows: $0.value.sorted(by: sortRows(lhs:rhs:))) }
    }

    private var highRiskCount: Int {
        indexedItems.filter { $0.riskLevel == .high }.count
    }

    private var midRiskCount: Int {
        indexedItems.filter { $0.riskLevel == .mid }.count
    }

    private var lowRiskCount: Int {
        indexedItems.filter { $0.riskLevel == .low }.count
    }

    private var normalCount: Int {
        indexedItems.filter { $0.riskLevel == .normal }.count
    }

    private var abnormalCount: Int {
        indexedItems.count - normalCount
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HealthExamMemberSectionView(memberID: output.envelope.memberID, draft: draft)

                HealthExamBasicInfoSectionView(draft: draft) {
                    logger.info("Health exam result: open basic info editor", module: logModule)
                    localEditor = .basicInfo(draft)
                }

                HealthExamRiskOverviewCard(
                    highCount: highRiskCount,
                    midCount: midRiskCount,
                    lowCount: lowRiskCount
                )

                HealthExamSummaryRow(
                    totalCount: indexedItems.count,
                    normalCount: normalCount,
                    abnormalCount: abnormalCount,
                    selectedFilter: summaryFilter,
                    onSelect: { selected in
                        logger.info("Health exam result: summary filter changed=\(selected.rawValue)", module: logModule)
                        summaryFilter = selected
                    }
                )

                HealthExamCategoryGroupsSectionView(
                    groups: groupedItems,
                    onEditItem: { item in
                        logger.info("Health exam result: open risk item editor index=\(item.originalIndex)", module: logModule)
                        localEditor = .riskItem(index: item.originalIndex, item: item.item)
                    },
                    expandedCategories: $expandedCategories
                )

                HealthExamAttachmentsSectionView(attachments: attachments)

                if let saveReceipt {
                    HealthExamResultSectionCard(
                        title: L10n.text("medical.upload.result.common.save_status"),
                        subtitle: L10n.text("medical.upload.result.common.save_success"),
                        systemImage: "checkmark.circle",
                        badgeText: L10n.text("medical.upload.result.common.saved")
                    ) {
                        HealthExamResultInfoLine(
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
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: summaryFilter)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: expandedCategories)
        .task {
            if expandedCategories.isEmpty {
                expandedCategories = Set(groupedItems.map(\.category))
            }
        }
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
                logger.info("Health exam result: submit save tapped", module: logModule)
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
    private func editorDestination(_ editor: HealthExamResultLocalEditor) -> some View {
        switch editor {
        case .basicInfo(let current):
            HealthExamBasicInfoEditorView(initial: current, onSubmit: { updated in
                draft = updated
                logger.info("Health exam result: basic info updated", module: logModule)
            })

        case .riskItem(let index, let item):
            HealthExamRiskItemEditorView(item: item, onSubmit: { updated in
                draft = draft.replacingItem(index: index, item: updated)
                logger.info("Health exam result: risk item updated index=\(index)", module: logModule)
            })
        }
    }

    private func sortRows(lhs: HealthExamRiskDisplayItem, rhs: HealthExamRiskDisplayItem) -> Bool {
        if let l = Int(lhs.item.sortOrder ?? ""), let r = Int(rhs.item.sortOrder ?? "") {
            return l < r
        }
        return (lhs.item.itemName ?? "").localizedStandardCompare(rhs.item.itemName ?? "") == .orderedAscending
    }
}
