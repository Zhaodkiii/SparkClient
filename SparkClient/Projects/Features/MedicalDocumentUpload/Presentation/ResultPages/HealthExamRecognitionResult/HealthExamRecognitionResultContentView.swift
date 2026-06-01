import SwiftUI

struct HealthExamRecognitionResultContentView: View {
    private let viewModel: MedicalDocumentUploadViewModel?
    @ObservedObject var memberContextStore: MemberContextStore
    let attachmentSource: HealthExamResultAttachmentSource
    let mode: HealthExamResultMode

    @State private var draft: HealthExamRecognitionDraft
    @State private var selectedMemberID: Int?
    @State private var summaryFilter: HealthExamResultSummaryFilter = .all
    @State private var localEditor: HealthExamResultLocalEditor?
    @State private var expandedCategories: Set<String> = []
    @State private var expandedValidationSections: Set<String> = []
    @State private var lastAutoRevealedIssueID: UUID?

    private let logger: Logger = ConsoleLogger()
    private let logModule: LogModule = .medical

    init(
        viewModel: MedicalDocumentUploadViewModel,
        memberContextStore: MemberContextStore
    ) {
        self.viewModel = viewModel
        let output = viewModel.typedOutput!
        self.memberContextStore = memberContextStore
        self.attachmentSource = .local(output.envelope.sourceFiles.map { MedicalDocumentLocalAttachmentItem(file: $0) })
        self.mode = .recognition
        _selectedMemberID = State(initialValue: output.envelope.memberID)

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

    init(
        item: SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments,
        fileTransferService: FileTransferService,
        memberContextStore: MemberContextStore
    ) {
        self.viewModel = nil
        self.memberContextStore = memberContextStore
        self.attachmentSource = .remote(item.attachments ?? [], fileTransferService)
        self.mode = .detail
        _selectedMemberID = State(initialValue: item.member)
        _draft = State(initialValue: HealthExamRecognitionDraft(remoteReport: item))
    }

    private var isSaving: Bool { viewModel?.isSaving ?? false }
    private var saveReceipt: MedicalDocumentSaveReceipt? { viewModel?.saveReceipt }
    private var validationIssues: [MedicalPreSubmitValidationIssue] {
        viewModel?.preSubmitValidationIssues ?? []
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
        ScrollViewReader { scrollProxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if mode.isEditable {
                    MedicalPreSubmitValidationSummaryBanner(issues: validationIssues) { issue in
                        MedicalPreSubmitValidationNavigation.reveal(
                            issue: issue,
                            expandedSectionIDs: $expandedValidationSections,
                            expandedHealthExamCategories: $expandedCategories,
                            healthExamCategoryForItemIndex: healthExamCategory(forItemIndex:),
                            scrollProxy: scrollProxy
                        )
                    }
                }

                HealthExamMemberSectionView(
                    memberContextStore: memberContextStore,
                    selectedMemberID: selectedMemberID,
                    draft: draft,
                    onSelectMember: mode.isEditable ? { memberID in
                        selectedMemberID = memberID
                        viewModel?.updateResultMemberID(memberID)
                    } : nil
                )

                HealthExamBasicInfoSectionView(
                    draft: draft,
                    validationIssues: validationIssues,
                    onEdit: mode.isEditable ? {
                        logger.info("Health exam result: open basic info editor", module: logModule)
                        localEditor = .basicInfo(draft)
                    } : nil
                )

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
                    validationIssues: validationIssues,
                    onEditItem: mode.isEditable ? { item in
                        logger.info("Health exam result: open risk item editor index=\(item.originalIndex)", module: logModule)
                        localEditor = .riskItem(index: item.originalIndex, item: item.item)
                    } : nil,
                    expandedCategories: $expandedCategories
                )

                HealthExamAttachmentsSectionView(source: attachmentSource)

                if mode.isEditable, let saveReceipt {
                    MedicalDocumentResultSectionCard(
                        title: L10n.text("medical.upload.result.common.save_status"),
                        subtitle: L10n.text("medical.upload.result.common.save_success"),
                        systemImage: "checkmark.circle",
                        badgeText: L10n.text("medical.upload.result.common.saved")
                    ) {
                        MedicalDocumentResultInfoLine(
                            title: L10n.text("medical.upload.result.common.record_id"),
                            value: "\(saveReceipt.recordID)"
                        )
                    }
                }
            }
            .padding(16)
        }
        .onChange(of: validationIssues.map(\.id)) { _ in
            guard mode.isEditable else { return }
            MedicalPreSubmitValidationNavigation.autoRevealFirstBlockingIssueIfNeeded(
                issues: validationIssues,
                lastAutoRevealedIssueID: &lastAutoRevealedIssueID,
                expandedSectionIDs: $expandedValidationSections,
                expandedHealthExamCategories: $expandedCategories,
                healthExamCategoryForItemIndex: healthExamCategory(forItemIndex:),
                scrollProxy: scrollProxy
            )
        }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            if mode.isEditable {
                bottomBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
            }
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
            Button(L10n.text("medical.upload.result.common.back")) {
                viewModel?.reset(keepAttachments: true)
            }
                .buttonStyle(.bordered)

            Button {
                logger.info("Health exam result: submit save tapped", module: logModule)
                submitSave()
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

    private func submitSave() {
        guard let viewModel else { return }
        viewModel.updateResultMemberID(selectedMemberID)
        viewModel.updateTypedResult(.healthExamReport(draft))
        Task { _ = await viewModel.saveResult() }
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

    private func healthExamCategory(forItemIndex index: Int) -> String? {
        guard draft.items.indices.contains(index) else { return nil }
        return draft.items[index].category.nilIfBlank
            ?? L10n.text("medical.upload.result.health_exam.category.other")
    }

    private func sortRows(lhs: HealthExamRiskDisplayItem, rhs: HealthExamRiskDisplayItem) -> Bool {
        if let l = Int(lhs.item.sortOrder ?? ""), let r = Int(rhs.item.sortOrder ?? "") {
            return l < r
        }
        return (lhs.item.itemName ?? "").localizedStandardCompare(rhs.item.itemName ?? "") == .orderedAscending
    }
}
