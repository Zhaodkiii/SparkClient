import SwiftUI

/// 处方单识别结果页面
/// 功能：展示 AI 识别的处方数组 → 成员切换 → 药箱候选确认 → 本地草稿编辑 → 保存
struct PrescriptionRecognitionResultContentView: View {
    /// 上传流程的共享 ViewModel，负责保存、校验和成员上下文。
    @ObservedObject private var viewModel: MedicalDocumentUploadViewModel
    /// 本次 AI 结构化识别输出。
    let output: MedicalDocumentTypedExtractionOutput

    /// 当前页面正在编辑的处方草稿列表。
    @State private var batches: [PrescriptionRecognitionDraft]
    /// 当前选中的家庭成员 ID，用于保存归属和加载成员相关药盒。
    @State private var selectedMemberID: Int?
    /// 本地编辑器的路由状态，控制处方、用药计划或药盒候选编辑页。
    @State private var localEditor: PrescriptionResultLocalEditor?
    /// 当前正在管理附件归属的目标。
    @State private var attachmentTarget: PrescriptionAttachmentTarget?
    /// 已展开的校验问题区域 ID，用于从校验摘要跳转到具体条目。
    @State private var expandedValidationSections: Set<String> = []
    /// 记录最近一次自动展开的问题，避免同一问题重复触发滚动。
    @State private var lastAutoRevealedIssueID: UUID?

    /// 当前成员可访问的家庭药箱药盒列表。
    @State private var familyMedicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox] = []
    /// 是否正在加载家庭药箱药盒。
    @State private var isLoadingFamilyMedicineBoxes = false
    /// 家庭药箱加载失败时展示给用户的错误文案。
    @State private var familyMedicineBoxLoadError: String?
    /// 每个药品计划对应的药盒候选匹配结果。
    @State private var medicineCandidateMatches: [MedicationCandidateKey: MedicineBoxCandidateMatch] = [:]
    /// 用户对每个药盒候选的确认、编辑和绑定选择。
    @State private var medicineCandidateConfirmations: [MedicationCandidateKey: MedicineBoxCandidateConfirmation] = [:]
    /// 绑定已有药盒时，提示用户是否顺手更新库存信息。
    @State private var inventoryUpdatePrompt: PrescriptionInventoryUpdatePrompt?
    /// 服务端已有药盒编辑弹窗的路由状态。
    @State private var medicineBoxServerEditor: PrescriptionMedicineBoxEditorSheetItem?

    private let logger: Logger = ConsoleLogger()
    private let logModule: LogModule = .medical
    /// Preview 注入的家庭药箱数据；正式环境始终为 nil。
    private let previewFamilyMedicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]?

    /// 从上传 ViewModel 中取出处方识别结果，并初始化页面本地草稿。
    init(
        viewModel: MedicalDocumentUploadViewModel,
        previewFamilyMedicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]? = nil
    ) {
        self.viewModel = viewModel
        self.previewFamilyMedicineBoxes = previewFamilyMedicineBoxes
        let output = viewModel.typedOutput!
        self.output = output
        _selectedMemberID = State(initialValue: output.envelope.memberID)

        if case .prescription(let drafts) = output.typedResult {
            _batches = State(initialValue: drafts)
        } else {
            _batches = State(initialValue: [])
        }
    }

    private var isSaving: Bool { viewModel.isSaving }
    private var saveReceipt: MedicalDocumentSaveReceipt? { viewModel.saveReceipt }
    private var validationIssues: [MedicalPreSubmitValidationIssue] { viewModel.preSubmitValidationIssues }

    /// 进入详情或编辑页时需要携带的成员、工作流 API 和日志上下文。
    private var detailNavigationContext: MedicalDocumentResultDetailNavigationContext? {
        MedicalDocumentResultDetailNavigationContext(
            memberID: selectedMemberID,
            viewModel: viewModel,
            logger: logger
        )
    }

    /// 查询家庭药箱数据的 API，仅在成员上下文完整时可用。
    private var medicalQueryAPI: SparkMedicalQueryAPI? {
        detailNavigationContext.map { SparkMedicalQueryAPI(configuration: $0.workflowAPI.configuration) }
    }

    /// 根据候选匹配与用户确认状态实时计算页面概览。
    private var overviewStats: PrescriptionMedicineBoxOverviewStats {
        PrescriptionMedicineBoxCandidateMatcher.computeOverviewStats(
            batches: batches,
            matches: medicineCandidateMatches,
            confirmations: medicineCandidateConfirmations
        )
    }

    /// 传递给处方列表子视图的药盒候选交互上下文。
    private var medicineBoxCandidateContext: PrescriptionMedicineBoxCandidateContext? {
        guard overviewStats.candidateCount > 0 || isLoadingFamilyMedicineBoxes || familyMedicineBoxLoadError != nil else {
            return nil
        }
        return PrescriptionMedicineBoxCandidateContext(
            matches: medicineCandidateMatches,
            confirmations: medicineCandidateConfirmations,
            isLoadingFamilyMedicineBoxes: isLoadingFamilyMedicineBoxes,
            detailNavigationContext: detailNavigationContext,
            familyMedicineBoxes: familyMedicineBoxes,
            attachmentsForIDs: matchedAttachments(for:),
            onSelectExistingTarget: selectExistingMedicineBoxTarget(key:boxID:),
            onToggleConfirmed: handleCandidateConfirmToggle(key:plan:match:confirmed:),
            onEditCandidate: { batchIndex, itemIndex, draft in
                localEditor = .medicineCandidate(batchIndex: batchIndex, index: itemIndex, draft: draft)
            },
            onManageMedicineBoxAttachments: { batchIndex, itemIndex in
                attachmentTarget = .medicineBoxCandidate(batchIndex: batchIndex, index: itemIndex)
            },
            onLocalDraftMedicineBoxSaved: { key, updated in
                applyCandidateLocalMedicineBoxSaved(key: key, updatedBox: updated)
            },
            onLocalDraftMedicineBoxDeleted: { key in
                applyCandidateLocalMedicineBoxDeleted(key: key)
            }
        )
    }

    /// 本次上传的本地附件。
    private var attachments: [MedicalDocumentLocalAttachmentItem] {
        output.envelope.sourceFiles.map { MedicalDocumentLocalAttachmentItem(file: $0) }
    }

    /// 按附件 ID 取出当前处方或药品条目已关联的附件。
    private func matchedAttachments(for ids: [UUID]) -> [MedicalDocumentLocalAttachmentItem] {
        guard ids.isEmpty == false else { return [] }
        let idSet = Set(ids)
        return attachments.filter { idSet.contains($0.id) }
    }

    /// 尚未被任何处方或药品条目关联的附件。
    private var unlinkedAttachments: [MedicalDocumentLocalAttachmentItem] {
        attachments.excludingAssociatedIDs(batches.associatedAttachmentFileIDs)
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MedicalPreSubmitValidationSummaryBanner(issues: validationIssues) { issue in
                        MedicalPreSubmitValidationNavigation.reveal(
                            issue: issue,
                            expandedSectionIDs: $expandedValidationSections,
                            scrollProxy: scrollProxy
                        )
                    }

                    PrescriptionMemberConfirmSectionView(
                        memberContextStore: viewModel.memberContextStoreForLocalForms,
                        selectedMemberID: selectedMemberID,
                        batches: batches,
                        onSelectMember: { memberID in
                            selectedMemberID = memberID
                            viewModel.updateResultMemberID(memberID)
                            resetMedicineBoxCandidateState()
                            loadFamilyMedicineBoxes(for: memberID)
                        },
                        overviewStats: overviewStats,
                        isLoadingFamilyMedicineBoxes: isLoadingFamilyMedicineBoxes,
                        familyMedicineBoxLoadError: familyMedicineBoxLoadError,
                        onRetryLoadFamilyMedicineBoxes: {
                            loadFamilyMedicineBoxes(for: selectedMemberID)
                        }
                    )

                    PrescriptionBatchListSectionView(
                        batches: batches,
                        validationIssues: validationIssues,
                        expandedSectionIDs: $expandedValidationSections,
                        attachmentsForIDs: matchedAttachments(for:),
                        detailNavigationContext: detailNavigationContext,
                        onEditBatch: { index, batch in
                            logger.info("Prescription result: open local batch editor index=\(index)", module: logModule)
                            localEditor = .batch(index: index, batch: batch)
                        },
                        onEditMedication: { batchIndex, itemIndex, item in
                            logger.info("Prescription result: open local medication editor batch=\(batchIndex) index=\(itemIndex)", module: logModule)
                            localEditor = .medication(batchIndex: batchIndex, index: itemIndex, draft: item)
                        },
                        onUpdatePrescriptionDraft: updatePrescriptionDraft(at:draft:),
                        onDeletePrescriptionDraft: deletePrescriptionDraft(at:),
                        onUpdateMedicationDraft: updateMedicationDraft(prescriptionIndex:medicationIndex:draft:),
                        onDeleteMedicationDraft: deleteMedicationDraft(prescriptionIndex:medicationIndex:),
                        onManageBatchAttachments: { index, _ in
                            attachmentTarget = .batch(index: index)
                        },
                        onManageMedicationAttachments: { batchIndex, itemIndex, _ in
                            attachmentTarget = .medication(batchIndex: batchIndex, index: itemIndex)
                        },
                        medicineBoxCandidateContext: medicineBoxCandidateContext
                    )

                    MedicalDocumentUnlinkedAttachmentsSectionView(attachments: unlinkedAttachments)

                    if let saveReceipt {
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
                // 校验结果变化后，自动展开并滚动到第一个阻塞保存的问题。
                MedicalPreSubmitValidationNavigation.autoRevealFirstBlockingIssueIfNeeded(
                    issues: validationIssues,
                    lastAutoRevealedIssueID: &lastAutoRevealedIssueID,
                    expandedSectionIDs: $expandedValidationSections,
                    scrollProxy: scrollProxy
                )
            }
        }
//        .background(Color(uiColor: .systemBackground))
        .background(Color(uiColor: .secondarySystemGroupedBackground))
//        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            // 底部操作栏固定在安全区内，避免长列表滚动时提交入口消失。
            bottomBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: batches.count)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: batches.reduce(0) { $0 + ($1.medicationPlans?.count ?? 0) })
        .task {
            // 成员切换后重新加载该成员可见的家庭药箱。
            if familyMedicineBoxes.isEmpty{
                loadFamilyMedicineBoxes(for: selectedMemberID)
            }
        }
        .onChange(of: selectedMemberID, perform: { selectedMemberID in
            loadFamilyMedicineBoxes(for: selectedMemberID)
        })
        .onChange(of: batches) { _ in
            // 本地草稿变化可能改变候选药盒名称或数量，需要同步重建匹配结果。
            rebuildMedicineCandidateMatches()
        }
        .fullScreenCover(item: $localEditor) { editor in
            CompatibleNavigationContainer {
                editorDestination(editor)
            }
        }
        .sheet(item: $attachmentTarget) { target in
            MedicalDocumentAttachmentAssociationSheet(
                title: target.title,
                localAttachments: attachments,
                selectedIDs: attachmentIDs(for: target),
                onSubmit: { applyAttachmentIDs($0, to: target) }
            )
        }
        .sheet(item: $medicineBoxServerEditor) { item in
            if let detailNavigationContext {
                CompatibleNavigationContainer {
                    // 用户选择更新库存时，打开已有药盒的服务端编辑页。
                    MedicineBoxFormView(
                        mode: .serverEdit(existing: item.box),
                        entryMemberID: detailNavigationContext.memberID,
                        defaultBindingMemberID: item.box.member,
                        memberOptions: detailNavigationContext.memberContextStore.context.members,
                        allowsHouseholdPublic: true,
                        workflowAPI: detailNavigationContext.workflowAPI,
                        fileTransferService: detailNavigationContext.fileTransferService,
                        typeOptions: MedicineBoxTypeCatalog.defaultStoredOptions,
                        specOptionBoxes: familyMedicineBoxes,
                        onServerSaved: { _ in }
                    )
                }
            }
        }
        // TODO: 恢复绑定已有药盒时的库存更新确认弹窗
//        .alert(item: $inventoryUpdatePrompt) { prompt in
//            Alert(
//                title: Text(L10n.text("medical.upload.result.prescription.candidate.inventory_prompt.title")),
//                message: Text(L10n.text("medical.upload.result.prescription.candidate.inventory_prompt.message")),
//                primaryButton: .default(Text(L10n.text("medical.upload.result.prescription.candidate.inventory_prompt.yes"))) {
//                    medicineBoxServerEditor = PrescriptionMedicineBoxEditorSheetItem(box: prompt.target)
//                    applyBindExistingConfirmation(key: prompt.key, medicineBoxID: prompt.target.id)
//                },
//                secondaryButton: .cancel(Text(L10n.text("medical.upload.result.prescription.candidate.inventory_prompt.no"))) {
//                    applyBindExistingConfirmation(key: prompt.key, medicineBoxID: prompt.target.id)
//                }
//            )
//        }
    }

    /// 页面底部的返回和保存操作栏。
    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button(L10n.text("medical.upload.result.common.back")) {
                viewModel.reset(keepAttachments: true)
            }
            .buttonStyle(.bordered)

            Button {
                logger.info("Prescription result: submit save tapped batches=\(batches.count)", module: logModule)
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
            .disabled(isSaving || batches.isEmpty)
        }
    }

    /// 保存前将用户确认过的药盒候选写回处方草稿，再交给上传流程保存。
    private func submitSave() {
        let draftsForSave = batches.resolvingMedicineBoxCandidates(
            confirmations: medicineCandidateConfirmations
        )
        viewModel.updateTypedResult(.prescription(draftsForSave))
        Task { _ = await viewModel.saveResult() }
    }

    /// 将页面本地草稿同步回 ViewModel，供校验、保存和外层状态使用。
    private func syncBatchesToViewModel() {
        viewModel.updateTypedResult(.prescription(batches))
    }

    /// 成员切换或上下文失效时，清空药盒候选相关的远端数据和用户选择。
    private func resetMedicineBoxCandidateState() {
        familyMedicineBoxes = []
        familyMedicineBoxLoadError = nil
        medicineCandidateMatches = [:]
        medicineCandidateConfirmations = [:]
    }

    /// 加载当前成员的家庭药箱，并在成功或失败后重建候选匹配。
    private func loadFamilyMedicineBoxes(for memberID: Int?) {
        #if DEBUG
        if let previewFamilyMedicineBoxes {
            familyMedicineBoxes = previewFamilyMedicineBoxes
            isLoadingFamilyMedicineBoxes = false
            familyMedicineBoxLoadError = nil
            rebuildMedicineCandidateMatches()
            return
        }
        #endif

        guard let memberID, let medicalQueryAPI else {
            resetMedicineBoxCandidateState()
            return
        }
        isLoadingFamilyMedicineBoxes = true
        familyMedicineBoxLoadError = nil
        Task {
            do {
                let boxes = try await medicalQueryAPI.listFamilyMedicineCabinet(memberID: memberID)
                await MainActor.run {
                    familyMedicineBoxes = boxes
                    isLoadingFamilyMedicineBoxes = false
                    rebuildMedicineCandidateMatches()
                }
            } catch {
                await MainActor.run {
                    familyMedicineBoxes = []
                    isLoadingFamilyMedicineBoxes = false
                    familyMedicineBoxLoadError = L10n.text("medical.upload.result.prescription.overview.load_failed")
                    rebuildMedicineCandidateMatches()
                }
                logger.error("Prescription result: family medicine cabinet load failed \(error)", module: logModule)
            }
        }
    }

    /// 遍历所有药品计划，生成每个候选药盒与家庭药箱的匹配结果。
    private func rebuildMedicineCandidateMatches() {
        var matches: [MedicationCandidateKey: MedicineBoxCandidateMatch] = [:]
        for (prescriptionIndex, batch) in batches.enumerated() {
            for (medicationIndex, plan) in (batch.medicationPlans ?? []).enumerated() {
                let key = MedicationCandidateKey(
                    prescriptionIndex: prescriptionIndex,
                    medicationIndex: medicationIndex
                )
                let confirmation = medicineCandidateConfirmations[key] ?? .default
                matches[key] = PrescriptionMedicineBoxCandidateMatcher.matchCandidate(
                    plan: plan,
                    confirmation: confirmation,
                    familyBoxes: familyMedicineBoxes,
                    loadFailedMessage: familyMedicineBoxLoadError
                )
            }
        }
        medicineCandidateMatches = matches
        if isLoadingFamilyMedicineBoxes == false {
            applyDefaultCandidateConfirmations(matches: matches)
        }
    }

    /// 进入结果页后，未确认的候选药盒默认勾选：新建或绑定已有。
    private func applyDefaultCandidateConfirmations(
        matches: [MedicationCandidateKey: MedicineBoxCandidateMatch]
    ) {
        for (key, match) in matches {
            var confirmation = medicineCandidateConfirmations[key] ?? .default
            guard confirmation.isConfirmed == false, confirmation.action == .none else { continue }

            switch match {
            case .noExisting:
                confirmation.isConfirmed = true
                confirmation.action = .createNew
                medicineCandidateConfirmations[key] = confirmation
            case .uniqueExisting(_, let target):
                confirmation.isConfirmed = true
                confirmation.action = .bindExisting(medicineBoxID: target.id)
                confirmation.selectedExistingBoxID = target.id
                medicineCandidateConfirmations[key] = confirmation
            case .multipleExisting(_, let targets):
                guard let selectedID = confirmation.selectedExistingBoxID ?? targets.first?.id,
                      targets.contains(where: { $0.id == selectedID })
                else { continue }
                confirmation.selectedExistingBoxID = selectedID
                confirmation.isConfirmed = true
                confirmation.action = .bindExisting(medicineBoxID: selectedID)
                medicineCandidateConfirmations[key] = confirmation
            case .loadFailed, .noCandidate:
                break
            }
        }
    }

    /// 多个同名药盒命中时，记录用户选择的已有药盒并等待再次确认。
    private func selectExistingMedicineBoxTarget(key: MedicationCandidateKey, boxID: Int) {
        var confirmation = medicineCandidateConfirmations[key] ?? .default
        confirmation.selectedExistingBoxID = boxID
        confirmation.isConfirmed = false
        confirmation.action = .none
        medicineCandidateConfirmations[key] = confirmation
        rebuildMedicineCandidateMatches()
    }

    /// 处理药盒候选确认开关：新建直接确认，绑定已有药盒直接确认（库存弹窗已临时关闭）。
    private func handleCandidateConfirmToggle(
        key: MedicationCandidateKey,
        plan: MedicationPlanRecognitionDraft,
        match: MedicineBoxCandidateMatch,
        confirmed: Bool
    ) {
        if confirmed == false {
            medicineCandidateConfirmations[key] = MedicineBoxCandidateConfirmation(
                isConfirmed: false,
                action: .none,
                editedCandidate: medicineCandidateConfirmations[key]?.editedCandidate,
                selectedExistingBoxID: medicineCandidateConfirmations[key]?.selectedExistingBoxID
            )
            return
        }

        switch match {
        case .noExisting:
            var confirmation = medicineCandidateConfirmations[key] ?? .default
            confirmation.isConfirmed = true
            confirmation.action = .createNew
            medicineCandidateConfirmations[key] = confirmation
        case .uniqueExisting(_, let target):
//            inventoryUpdatePrompt = PrescriptionInventoryUpdatePrompt(key: key, target: target)
            // TODO: 恢复库存更新弹窗 — inventoryUpdatePrompt = PrescriptionInventoryUpdatePrompt(key: key, target: target)
            applyBindExistingConfirmation(key: key, medicineBoxID: target.id)
        case .multipleExisting(_, let targets):
            guard let selectedID = medicineCandidateConfirmations[key]?.selectedExistingBoxID,
                  let target = targets.first(where: { $0.id == selectedID })
            else { return }
//            inventoryUpdatePrompt = PrescriptionInventoryUpdatePrompt(key: key, target: target)
            // TODO: 恢复库存更新弹窗 — inventoryUpdatePrompt = PrescriptionInventoryUpdatePrompt(key: key, target: target)
            applyBindExistingConfirmation(key: key, medicineBoxID: target.id)
        case .loadFailed, .noCandidate:
            break
        }
    }

    /// 应用“绑定已有药盒”的最终确认结果。
    private func applyBindExistingConfirmation(key: MedicationCandidateKey, medicineBoxID: Int) {
        var confirmation = medicineCandidateConfirmations[key] ?? .default
        confirmation.isConfirmed = true
        confirmation.action = .bindExisting(medicineBoxID: medicineBoxID)
        confirmation.selectedExistingBoxID = medicineBoxID
        medicineCandidateConfirmations[key] = confirmation
    }

    /// 更新单个处方草稿。
    private func updatePrescriptionDraft(at index: Int, draft: PrescriptionRecognitionDraft) {
        guard batches.indices.contains(index) else { return }
        batches[index] = draft
        syncBatchesToViewModel()
    }

    /// 删除处方草稿，并同步修正后续处方的候选确认索引。
    private func deletePrescriptionDraft(at index: Int) {
        guard batches.indices.contains(index) else { return }
        batches.remove(at: index)
        medicineCandidateConfirmations = remapConfirmationsAfterPrescriptionDeletion(
            deletedPrescriptionIndex: index
        )
        syncBatchesToViewModel()
    }

    /// 更新某个处方下的单条用药计划草稿。
    private func updateMedicationDraft(
        prescriptionIndex: Int,
        medicationIndex: Int,
        draft: MedicationPlanRecognitionDraft
    ) {
        guard batches.indices.contains(prescriptionIndex) else { return }
        guard var plans = batches[prescriptionIndex].medicationPlans, plans.indices.contains(medicationIndex) else { return }
        plans[medicationIndex] = draft
        batches[prescriptionIndex].medicationPlans = plans
        syncBatchesToViewModel()
    }

    /// 候选药盒本地草稿保存：同步写回用药计划草稿，并重置候选确认状态。
    private func applyCandidateLocalMedicineBoxSaved(
        key: MedicationCandidateKey,
        updatedBox: MedicineBoxRecognitionDraft
    ) {
        guard let memberID = selectedMemberID else { return }
        guard batches.indices.contains(key.prescriptionIndex),
              var plans = batches[key.prescriptionIndex].medicationPlans,
              plans.indices.contains(key.medicationIndex)
        else { return }

        let currentPlan = plans[key.medicationIndex]
        let boxID = PrescriptionRecognitionDraftMapper.temporaryMedicineBoxID(
            prescriptionIndex: key.prescriptionIndex,
            medicationIndex: key.medicationIndex
        )
        let remoteBox = updatedBox.remoteMedicineBox(memberID: memberID, id: boxID)
        let updatedPlan = PrescriptionRecognitionDraftMapper.applyMedicineBox(
            remoteBox,
            to: currentPlan,
            preservingAttachmentIDs: currentPlan.attachmentFileIds
        )
        plans[key.medicationIndex] = updatedPlan
        batches[key.prescriptionIndex].medicationPlans = plans
        syncBatchesToViewModel()

        var confirmation = medicineCandidateConfirmations[key] ?? .default
        confirmation.editedCandidate = updatedBox
        confirmation.isConfirmed = false
        confirmation.action = .none
        medicineCandidateConfirmations[key] = confirmation
        rebuildMedicineCandidateMatches()
    }

    /// 候选药盒本地草稿删除：解除用药计划与药盒关联，并重置候选确认状态。
    private func applyCandidateLocalMedicineBoxDeleted(key: MedicationCandidateKey) {
        guard batches.indices.contains(key.prescriptionIndex),
              var plans = batches[key.prescriptionIndex].medicationPlans,
              plans.indices.contains(key.medicationIndex)
        else { return }

        let currentPlan = plans[key.medicationIndex]
        plans[key.medicationIndex] = PrescriptionRecognitionDraftMapper.medicationPlanDraftClearedMedicineBox(from: currentPlan)
        batches[key.prescriptionIndex].medicationPlans = plans
        syncBatchesToViewModel()

        medicineCandidateConfirmations[key] = .default
        rebuildMedicineCandidateMatches()
    }

    /// 删除某条用药计划，并移除其对应的药盒候选确认状态。
    private func deleteMedicationDraft(prescriptionIndex: Int, medicationIndex: Int) {
        guard batches.indices.contains(prescriptionIndex) else { return }
        guard var plans = batches[prescriptionIndex].medicationPlans, plans.indices.contains(medicationIndex) else { return }
        plans.remove(at: medicationIndex)
        batches[prescriptionIndex].medicationPlans = plans
        medicineCandidateConfirmations.removeValue(
            forKey: MedicationCandidateKey(
                prescriptionIndex: prescriptionIndex,
                medicationIndex: medicationIndex
            )
        )
        syncBatchesToViewModel()
    }

    /// 删除处方后重新映射候选确认字典，避免索引指向错误的处方。
    private func remapConfirmationsAfterPrescriptionDeletion(
        deletedPrescriptionIndex: Int
    ) -> [MedicationCandidateKey: MedicineBoxCandidateConfirmation] {
        var remapped: [MedicationCandidateKey: MedicineBoxCandidateConfirmation] = [:]
        for (key, confirmation) in medicineCandidateConfirmations {
            if key.prescriptionIndex == deletedPrescriptionIndex {
                continue
            }
            let newKey = MedicationCandidateKey(
                prescriptionIndex: key.prescriptionIndex > deletedPrescriptionIndex
                    ? key.prescriptionIndex - 1
                    : key.prescriptionIndex,
                medicationIndex: key.medicationIndex
            )
            remapped[newKey] = confirmation
        }
        return remapped
    }

    /// 读取指定处方、药品或药箱候选当前关联的附件 ID。
    private func attachmentIDs(for target: PrescriptionAttachmentTarget) -> [UUID] {
        switch target {
        case .batch(let index):
            guard batches.indices.contains(index) else { return [] }
            return batches[index].attachmentFileIds
        case .medication(let batchIndex, let index):
            guard batches.indices.contains(batchIndex),
                  let meds = batches[batchIndex].medicationPlans,
                  meds.indices.contains(index)
            else { return [] }
            return meds[index].attachmentFileIds
        case .medicineBoxCandidate(let batchIndex, let index):
            return medicineBoxCandidateAttachmentIDs(batchIndex: batchIndex, medicationIndex: index)
        }
    }

    private func medicineBoxCandidateAttachmentIDs(batchIndex: Int, medicationIndex: Int) -> [UUID] {
        let key = MedicationCandidateKey(prescriptionIndex: batchIndex, medicationIndex: medicationIndex)
        if let edited = medicineCandidateConfirmations[key]?.editedCandidate {
            return edited.attachmentFileIds
        }
        guard batches.indices.contains(batchIndex),
              let meds = batches[batchIndex].medicationPlans,
              meds.indices.contains(medicationIndex),
              let box = meds[medicationIndex].medicineBox
        else { return [] }
        return box.attachmentFileIds
    }

    /// 应用附件关联结果，并保证同一个附件不会同时挂到多个处方/药品条目上。
    private func applyAttachmentIDs(_ ids: [UUID], to target: PrescriptionAttachmentTarget) {
        removeAttachmentIDs(ids, except: target)

        switch target {
        case .batch(let index):
            guard batches.indices.contains(index) else { return }
            batches[index].attachmentFileIds = ids
        case .medication(let batchIndex, let index):
            guard batches.indices.contains(batchIndex) else { return }
            var meds = batches[batchIndex].medicationPlans ?? []
            guard meds.indices.contains(index) else { return }
            meds[index].attachmentFileIds = ids
            batches[batchIndex].medicationPlans = meds
        case .medicineBoxCandidate(let batchIndex, let index):
            applyMedicineBoxCandidateAttachmentIDs(ids, batchIndex: batchIndex, medicationIndex: index)
        }
        syncBatchesToViewModel()
    }

    private func applyMedicineBoxCandidateAttachmentIDs(
        _ ids: [UUID],
        batchIndex: Int,
        medicationIndex: Int
    ) {
        guard batches.indices.contains(batchIndex),
              var meds = batches[batchIndex].medicationPlans,
              meds.indices.contains(medicationIndex)
        else { return }

        let key = MedicationCandidateKey(prescriptionIndex: batchIndex, medicationIndex: medicationIndex)
        var plan = meds[medicationIndex]

        var box: MedicineBoxRecognitionDraft?
        if let edited = medicineCandidateConfirmations[key]?.editedCandidate {
            box = edited
        } else if let planBox = plan.medicineBox {
            box = planBox
        } else if let match = medicineCandidateMatches[key] {
            switch match {
            case .noExisting(let candidate),
                 .uniqueExisting(let candidate, _),
                 .multipleExisting(let candidate, _),
                 .loadFailed(let candidate, _):
                box = candidate
            case .noCandidate:
                break
            }
        }
        guard var resolvedBox = box else { return }

        resolvedBox.attachmentFileIds = ids
        plan = plan.updatingMedicineBoxCandidate(resolvedBox)
        meds[medicationIndex] = plan
        batches[batchIndex].medicationPlans = meds

        if var confirmation = medicineCandidateConfirmations[key], confirmation.editedCandidate != nil {
            confirmation.editedCandidate = resolvedBox
            medicineCandidateConfirmations[key] = confirmation
        }
    }

    /// 从其他条目中移除即将分配给目标条目的附件 ID，保持附件归属唯一。
    private func removeAttachmentIDs(_ ids: [UUID], except target: PrescriptionAttachmentTarget) {
        let idSet = Set(ids)
        guard idSet.isEmpty == false else { return }

        for batchIndex in batches.indices {
            if target.id != PrescriptionAttachmentTarget.batch(index: batchIndex).id {
                batches[batchIndex].attachmentFileIds.removeAll { idSet.contains($0) }
            }
            var meds = batches[batchIndex].medicationPlans ?? []
            for medIndex in meds.indices {
                let medicationTargetID = PrescriptionAttachmentTarget.medication(
                    batchIndex: batchIndex,
                    index: medIndex
                ).id
                let medicineBoxTargetID = PrescriptionAttachmentTarget.medicineBoxCandidate(
                    batchIndex: batchIndex,
                    index: medIndex
                ).id
                if target.id != medicationTargetID {
                    meds[medIndex].attachmentFileIds.removeAll { idSet.contains($0) }
                }
                if target.id != medicineBoxTargetID, var box = meds[medIndex].medicineBox {
                    box.attachmentFileIds.removeAll { idSet.contains($0) }
                    meds[medIndex] = meds[medIndex].updatingMedicineBoxCandidate(box)
                }
            }
            batches[batchIndex].medicationPlans = meds

            for (key, confirmation) in medicineCandidateConfirmations {
                guard key.prescriptionIndex == batchIndex else { continue }
                let medicineBoxTargetID = PrescriptionAttachmentTarget.medicineBoxCandidate(
                    batchIndex: batchIndex,
                    index: key.medicationIndex
                ).id
                guard target.id != medicineBoxTargetID else { continue }
                guard var edited = confirmation.editedCandidate else { continue }
                edited.attachmentFileIds.removeAll { idSet.contains($0) }
                var updatedConfirmation = confirmation
                updatedConfirmation.editedCandidate = edited
                medicineCandidateConfirmations[key] = updatedConfirmation
            }
        }
    }

    /// 根据本地编辑路由打开对应的编辑页。
    @ViewBuilder
    private func editorDestination(_ editor: PrescriptionResultLocalEditor) -> some View {
        switch editor {
        case .batch(let batchIndex, let existing):
            if let detailNavigationContext {
                // 编辑整张处方，提交后替换对应批次草稿。
                MedicationPrescriptionEditPage(
                    mode: .localEdit(existing: existing, onSubmit: { updated in
                        logger.info("Prescription result: local batch updated index=\(batchIndex) meds=\(updated.medicationPlans?.count ?? 0)", module: logModule)
                        updatePrescriptionDraft(at: batchIndex, draft: updated)
                    }),
                    workflowAPI: detailNavigationContext.workflowAPI,
                    fileTransferService: detailNavigationContext.fileTransferService,
                    notificationClient: detailNavigationContext.notificationClient
                )
            }

        case .medication(let batchIndex, let index, let med):
            if let detailNavigationContext {
                // 编辑单条用药计划，临时药盒仅用于表单展示当前识别出的药盒信息。
                MedicationPlanStepperView(
                    mode: .localEdit(existing: MedicationPlanDraft(recognition: med), onSubmit: { updatedDraft in
                        let updated = updatedDraft.recognitionDraft(preserving: med)
                        updateMedicationDraft(prescriptionIndex: batchIndex, medicationIndex: index, draft: updated)
                        logger.info("Prescription result: local medication updated batch=\(batchIndex) index=\(index)", module: logModule)
                    }),
                    memberID: detailNavigationContext.memberID,
                    medicineBoxes: [med.remoteMedicineBox(
                        memberID: detailNavigationContext.memberID,
                        id: PrescriptionRecognitionDraftMapper.temporaryMedicineBoxID(
                            prescriptionIndex: batchIndex,
                            medicationIndex: index
                        )
                    )],
                    workflowAPI: detailNavigationContext.workflowAPI,
                    fileTransferService: detailNavigationContext.fileTransferService,
                    notificationClient: detailNavigationContext.notificationClient,
                    onMedicineBoxSaved: { _ in }
                )
            }

        case .medicineCandidate(let batchIndex, let index, let plan):
            if let detailNavigationContext {
                let key = MedicationCandidateKey(prescriptionIndex: batchIndex, medicationIndex: index)
                // 候选药盒编辑优先使用已编辑内容，否则回退到识别出的原始药盒。
                let seedCandidate = PrescriptionMedicineBoxCandidateMatcher.effectiveCandidate(
                    for: plan,
                    confirmation: medicineCandidateConfirmations[key]
                ) ?? plan.medicineBox ?? MedicineBoxRecognitionDraft(
                    medicineName: nil,
                    medicineType: nil,
                    brandName: nil,
                    dosageForm: nil,
                    strength: nil,
                    doseUnit: nil,
                    totalQuantity: nil,
                    expireDate: nil,
                    notes: nil,
                    extra: nil,
                    sortOrder: nil
                )
                MedicineBoxFormView(
                    mode: .localEdit(existing: MedicineBoxDraft(recognition: seedCandidate), onSubmit: { draft in
                        applyCandidateLocalMedicineBoxSaved(
                            key: key,
                            updatedBox: draft.recognitionDraft()
                        )
                    }),
                    entryMemberID: detailNavigationContext.memberID,
                    memberOptions: detailNavigationContext.memberContextStore.context.members,
                    allowsHouseholdPublic: false,
                    workflowAPI: detailNavigationContext.workflowAPI,
                    fileTransferService: detailNavigationContext.fileTransferService,
                    typeOptions: MedicineBoxTypeCatalog.defaultStoredOptions,
                    specOptionBoxes: familyMedicineBoxes,
                    onServerSaved: { _ in }
                )
            }
        }
    }
}

/// 绑定已有药盒时用于驱动库存更新确认弹窗的数据。
private struct PrescriptionInventoryUpdatePrompt: Identifiable {
    let key: MedicationCandidateKey
    let target: SparkMedicalSyncAPI.RemoteMedicineBox

    var id: String { "\(key.prescriptionIndex)-\(key.medicationIndex)-\(target.id)" }
}

/// 包装服务端药盒编辑弹窗需要的 Identifiable 数据。
private struct PrescriptionMedicineBoxEditorSheetItem: Identifiable {
    let box: SparkMedicalSyncAPI.RemoteMedicineBox
    var id: Int { box.id }
}
