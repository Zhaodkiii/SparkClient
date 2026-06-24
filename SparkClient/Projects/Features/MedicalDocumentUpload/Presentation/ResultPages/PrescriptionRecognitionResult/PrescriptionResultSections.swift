import SwiftUI

// MARK: - 患者就诊人确认信息区块视图
/// 处方识别结果页：展示就诊人、成员切换与药盒候选概览
struct PrescriptionMemberConfirmSectionView: View {
    @ObservedObject var memberContextStore: MemberContextStore
    let selectedMemberID: Int?
    let batches: [PrescriptionRecognitionDraft]
    var onSelectMember: ((Int?) -> Void)?
    var overviewStats: PrescriptionMedicineBoxOverviewStats?
    var isLoadingFamilyMedicineBoxes: Bool = false
    var familyMedicineBoxLoadError: String?
    var onRetryLoadFamilyMedicineBoxes: (() -> Void)?

    private var selectedMemberName: String {
        guard let selectedMemberID else {
            return L10n.text("medical.upload.member.not_selected")
        }
        return memberContextStore.context.members.first(where: { $0.id == selectedMemberID })?.name
            ?? "\(selectedMemberID)"
    }

    private var showsOverview: Bool {
        guard let overviewStats else { return false }
        return overviewStats.candidateCount > 0
            || isLoadingFamilyMedicineBoxes
            || familyMedicineBoxLoadError != nil
    }

    var body: some View {
        MedicalDocumentResultSectionCard(
            title: L10n.text("medical.upload.result.member.title"),
            subtitle: L10n.text("medical.upload.result.member.subtitle"),
            systemImage: "person.crop.circle.badge.checkmark"
        ) {
            VStack(alignment: .leading, spacing: 24) {
                memberRow

                if showsOverview, let overviewStats {
                    overviewContent(stats: overviewStats)
                }
            }
        }
    }

    @ViewBuilder
    private func overviewContent(stats: PrescriptionMedicineBoxOverviewStats) -> some View {

        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.title3)
                    .foregroundStyle(Color(uiColor: .systemBlue))
                    .symbolRenderingMode(.hierarchical)

                Text(L10n.text("medical.upload.result.prescription.overview.title"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)
            }

            if isLoadingFamilyMedicineBoxes {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(L10n.text("medical.upload.result.prescription.overview.loading"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if let familyMedicineBoxLoadError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(familyMedicineBoxLoadError)
                        .font(.callout)
                        .foregroundStyle(.orange)
                    if let onRetryLoadFamilyMedicineBoxes {
                        Button(L10n.text("medical.upload.result.prescription.overview.retry")) {
                            onRetryLoadFamilyMedicineBoxes()
                        }
                        .font(.callout.weight(.semibold))
                    }
                }
            }

            Text(
                String(
                    format: L10n.text("medical.upload.result.prescription.overview.summary"),
                    locale: .current,
                    stats.prescriptionCount,
                    stats.medicationCount,
                    stats.candidateCount
                )
            )
            .font(.callout.weight(.semibold))

            if stats.candidateCount > 0 {
                Divider()

                HStack(alignment: .top, spacing: 8) {
                    MedicalDocumentResultInfoLine(
                        title: L10n.text("medical.upload.result.prescription.overview.pending"),
                        value: "\(stats.pendingCount)"
                    )
                    MedicalDocumentResultInfoLine(
                        title: L10n.text("medical.upload.result.prescription.overview.matched_existing"),
                        value: "\(stats.matchedExistingCount)"
                    )
                    MedicalDocumentResultInfoLine(
                        title: L10n.text("medical.upload.result.prescription.overview.create_new"),
                        value: "\(stats.createNewCount)"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var memberRow: some View {
        if let onSelectMember {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("medical.upload.result.member.title"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                MemberProfileBindingMenu(
                    memberContextStore: memberContextStore,
                    selectedMemberID: selectedMemberID,
                    onSelect: onSelectMember
                ) {
                    HStack {
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(Color.accentColor)
                        Text(selectedMemberName)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(uiColor: .secondarySystemGroupedBackground)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                }
            }
        } else {
            MedicalDocumentResultInfoLine(
                title: L10n.text("medical.upload.result.member.id"),
                value: selectedMemberName
            )
        }
    }
}

// MARK: - 处方批次列表区块视图
/// 处方上传结果页：多批次处方+药品清单+随访计划整体展示区块，支持折叠、编辑、校验报错、附件管理、详情跳转
struct PrescriptionBatchListSectionView: View {
    /// 多批次处方OCR识别草稿数组
    let batches: [PrescriptionRecognitionDraft]
    /// 表单预提交校验错误集合
    var validationIssues: [MedicalPreSubmitValidationIssue] = []
    /// 外部绑定：已展开的分区ID集合，控制折叠展开状态
    var expandedSectionIDs: Binding<Set<String>>?
    /// 随访计划识别草稿数组
    var followUps: [FollowUpRecognitionDraft] = []
    /// 区块标题，支持外部自定义
    var title: String = L10n.text("medical.upload.result.prescription.batch_section.title")
    /// 区块副标题，支持外部自定义
    var subtitle: String = L10n.text("medical.upload.result.prescription.batch_section.subtitle")
    /// 右上角角标文字（如药品数量）
    var badgeText: String?
    /// 主题色，默认系统蓝色
    var tintColor: Color = Color(uiColor: .systemBlue)
    /// 右上角操作按钮文字（编辑批次）
    var actionTitle: String? = L10n.text("medical.upload.result.prescription.edit_batch")
    /// 根据附件ID数组获取本地附件列表的闭包
    var attachmentsForIDs: (([UUID]) -> [MedicalDocumentLocalAttachmentItem])? = nil
    /// 详情页导航上下文（携带会员、API、存储等环境依赖）
    var detailNavigationContext: MedicalDocumentResultDetailNavigationContext?
    /// 编辑处方批次回调：批次索引、当前批次数据
    let onEditBatch: (Int, PrescriptionRecognitionDraft) -> Void
    /// 编辑单条药品回调：批次索引、药品行索引、药品识别草稿
    let onEditMedication: (Int, Int, MedicationPlanRecognitionDraft) -> Void
    var onUpdatePrescriptionDraft: ((Int, PrescriptionRecognitionDraft) -> Void)?
    var onDeletePrescriptionDraft: ((Int) -> Void)?
    var onUpdateMedicationDraft: ((Int, Int, MedicationPlanRecognitionDraft) -> Void)?
    var onDeleteMedicationDraft: ((Int, Int) -> Void)?
    /// 编辑随访计划回调（可选）
    var onEditFollowUp: ((FollowUpRecognitionDraft) -> Void)?
    /// 管理处方批次附件回调（可选）
    var onManageBatchAttachments: ((Int, PrescriptionRecognitionDraft) -> Void)?
    /// 管理单条药品附件回调（可选）
    var onManageMedicationAttachments: ((Int, Int, MedicationPlanRecognitionDraft) -> Void)?
    /// 药箱候选确认上下文（处方识别 000009）
    var medicineBoxCandidateContext: PrescriptionMedicineBoxCandidateContext?
    /// 管理随访计划附件回调（可选）
    var onManageFollowUpAttachments: ((Int, FollowUpRecognitionDraft) -> Void)?

    var body: some View {
        
        VStack(alignment: .leading, spacing: 24) {
            // 无处方批次：空占位提示
            if batches.isEmpty {
                emptyHint(L10n.text("medical.upload.result.prescription.empty_batches"))
            } else {
                // 遍历所有处方批次渲染卡片
                ForEach(Array(batches.enumerated()), id: \.offset) { pair in
                    batchCard(index: pair.offset, batch: pair.element)
                }
            }

            // 存在随访计划，追加分隔线+随访列表
            if followUps.isEmpty == false {
                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    // 随访计划分组标题栏
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.caption)
                            .foregroundStyle(tintColor)
                        Text("随访计划")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("\(followUps.count)组")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color(uiColor: .secondarySystemFill))
                            )
                    }

                    // 遍历渲染每条随访卡片
                    ForEach(Array(followUps.enumerated()), id: \.offset) { pair in
                        followUpCard(index: pair.offset, item: pair.element)
                    }
                }
            }
        }
        
        
//        MedicalDocumentResultSectionCard(
//            title: title,
//            subtitle: subtitle,
//            systemImage: "pills",
//            tintColor: tintColor,
//            badgeText: badgeText ?? defaultBadgeText,
//            // 无处方批次时隐藏右上角编辑按钮
//            actionTitle: firstBatch == nil ? nil : actionTitle,
//            action: { firstBatch.map { onEditBatch(0, $0) } },
//            enableCollapse: true,
//            defaultCollapsed: true,
//            collapseSectionID: MedicalPreSubmitValidationSectionID.treatmentPlan,
//            expandedSectionIDs: expandedSectionIDs
//        ) {
//            VStack(alignment: .leading, spacing: 12) {
//                // 无处方批次：空占位提示
//                if batches.isEmpty {
//                    emptyHint(L10n.text("medical.upload.result.prescription.empty_batches"))
//                } else {
//                    // 遍历所有处方批次渲染卡片
//                    ForEach(Array(batches.enumerated()), id: \.offset) { pair in
//                        batchCard(index: pair.offset, batch: pair.element)
//                    }
//                }
//
//                // 存在随访计划，追加分隔线+随访列表
//                if followUps.isEmpty == false {
//                    Divider()
//
//                    VStack(alignment: .leading, spacing: 12) {
//                        // 随访计划分组标题栏
//                        HStack(spacing: 8) {
//                            Image(systemName: "calendar.badge.clock")
//                                .font(.caption)
//                                .foregroundStyle(tintColor)
//                            Text("随访计划")
//                                .font(.subheadline.weight(.semibold))
//                                .foregroundStyle(.primary)
//                            Text("\(followUps.count)组")
//                                .font(.caption)
//                                .foregroundStyle(.secondary)
//                                .padding(.horizontal, 6)
//                                .padding(.vertical, 2)
//                                .background(
//                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
//                                        .fill(Color(uiColor: .secondarySystemFill))
//                                )
//                        }
//
//                        // 遍历渲染每条随访卡片
//                        ForEach(Array(followUps.enumerated()), id: \.offset) { pair in
//                            followUpCard(index: pair.offset, item: pair.element)
//                        }
//                    }
//                }
//            }
//        }
    }

    // MARK: 计算属性
    /// 获取第一条处方批次（用于判断是否展示编辑按钮）
    private var firstBatch: PrescriptionRecognitionDraft? {
        batches.first
    }

    /// 统计所有处方内药品总条数
    private var medicationCount: Int {
        batches.reduce(0) { $0 + ($1.medicationPlans?.count ?? 0) }
    }

    /// 默认角标文案：格式化药品总数多语言文本
    private var defaultBadgeText: String {
        String(
            format: L10n.text("medical.upload.result.prescription.medication_count"),
            locale: .current,
            medicationCount
        )
    }

    // MARK: 处方批次卡片（带导航跳转包装）
    @ViewBuilder
    private func batchCard(index: Int, batch: PrescriptionRecognitionDraft) -> some View {
        // 传入导航上下文则包装详情页跳转链接，否则只渲染纯卡片内容
        if let detailNavigationContext {
            MainNavigationLink {
                prescriptionDetailDestination(index: index, batch: batch, context: detailNavigationContext)
            } label: {
                batchCardContent(index: index, batch: batch)
            }
            .buttonStyle(.plain)
        } else {
            batchCardContent(index: index, batch: batch)
        }
    }

    // MARK: 处方批次卡片内部UI内容
    private func batchCardContent(index: Int, batch: PrescriptionRecognitionDraft) -> some View {
        // 筛选当前处方批次对应的校验错误
        let batchIssues = validationIssues.issues(matchingFieldPathPrefix: "prescriptions[\(index)]")
        let hasError = batchIssues.isEmpty == false

        return VStack(alignment: .leading, spacing: 16){
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    // 只展示开具日期相关第一条校验提示
                    ForEach(batchIssues.filter {
                        $0.fieldKey.contains("prescribed_at") || $0.fieldKey.hasSuffix(".status")
                    }.prefix(2)) { issue in
                        MedicalValidationIssueInlineView(message: issue.message)
                    }

                    // 拼接开方医师、开具时间、诊断信息
                    let head = [batch.prescriberName, batch.prescribedAt, batch.diagnosis]
                        .compactMap { $0?.nilIfBlank }
                        .joined(separator: " · ")
                    if head.isEmpty == false {
                        Text(head)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    let meds = batch.medicationPlans ?? []
                    // 无药品：空提示
                    if meds.isEmpty {
                        Text(L10n.text("medical.upload.result.prescription.empty_medications"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        // 遍历渲染每条药品行
                        ForEach(Array(meds.enumerated()), id: \.offset) { pair in
                            medicationRow(batchIndex: index, itemIndex: pair.offset, draft: pair.element)
                            Divider()
                        }
                    }

                    // 渲染处方附件网格
                    if let attachmentsForIDs {
                        CaseMatchedAttachmentsGridView(
                            title: "处方附件",
                            attachments: attachmentsForIDs(batch.attachmentFileIds),
                            onManage: {
                                onManageBatchAttachments?(index, batch)
                            }
                        )
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
//                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        .fill(Color(uiColor: .systemGroupedBackground))
                )
                // 绑定校验边框样式 + 滚动定位ID
                .medicalValidationCardChrome(
                    hasError: hasError,
                    scrollTargetID: "preSubmitValidation.card.prescription.\(index)"
                )
            } header: {
                // 头部：医院名称 + 错误角标 + 编辑按钮
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        if batches.count > 1 {
                            Text(
                                String(
                                    format: L10n.text("medical.upload.result.prescription.index_format"),
                                    locale: .current,
                                    index + 1,
                                    batches.count
                                )
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        }
                        Text(batch.institutionName ?? L10n.text("home.medical.prescription.batch_fallback_title"))
                            .font(.title3.bold())
                            .foregroundStyle(hasError ? .red : .primary)
                    }
                    Spacer()
                    // 存在校验错误展示错误标记
                    if hasError {
                        MedicalValidationIssueBadge()
                    }
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                    
//                    Button(L10n.text("medical.upload.result.prescription.edit_batch")) {
//                        onEditBatch(index, batch)
//                    }
//                    .font(.subheadline.weight(.semibold))
                }
                .contentShape(Rectangle())

            }
        }

    }

    // MARK: 单行药品视图（带导航跳转包装）
    @ViewBuilder
    private func medicationRow(batchIndex: Int, itemIndex: Int, draft: MedicationPlanRecognitionDraft) -> some View {
        if let detailNavigationContext {
            MainNavigationLink {
                medicationDetailDestination(
                    batchIndex: batchIndex,
                    itemIndex: itemIndex,
                    draft: draft,
                    context: detailNavigationContext
                )
            } label: {
                medicationRowContent(batchIndex: batchIndex, itemIndex: itemIndex, draft: draft)
            }
            .buttonStyle(.plain)
        } else {
            medicationRowContent(batchIndex: batchIndex, itemIndex: itemIndex, draft: draft)
        }
    }

    // MARK: 单行药品内部UI内容
    private func medicationRowContent(batchIndex: Int, itemIndex: Int, draft: MedicationPlanRecognitionDraft) -> some View {
        // 获取当前药品行对应的校验错误
        let itemIssues = validationIssues.issues(forMedicationPlan: batchIndex, itemIndex: itemIndex)
        let hasError = itemIssues.isEmpty == false
        // 生成滚动定位ID，用于校验报错自动滚动到对应行
        let scrollTargetID = itemIssues.first?.scrollTargetID
            ?? MedicalPreSubmitValidationIssue.makeScrollTargetID(
                resourceType: .medicationPlan,
                fieldKey: "prescriptions[\(batchIndex)].medication_plans[\(itemIndex)].drug_name",
                cardIndex: itemIndex,
                prescriptionIndex: batchIndex
            )

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "capsule")
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .systemIndigo))

                VStack(alignment: .leading, spacing: 4) {
                    
                    HStack{
                        // 药品名称多级兜底：识别药品名 -> 药品盒子名称 -> 品牌名 -> 无名称占位
                        Text(draft.medicineName ?? draft.medicineBox?.medicineName ?? draft.brandName ?? L10n.text("medical.upload.result.medication.unnamed"))
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(hasError ? .red : .primary)
                            .lineLimit(1)
                        
//                        Spacer(minLength: 0)
                        
                        // 拼接规格、单次服用剂量描述文案
                        let detail = [draft.strength, draft.dosePerTime ]
                            .compactMap { $0?.nilIfBlank }
                            .joined(separator: " · ")
                        if detail.isEmpty == false {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    
                    let frequencyText = [draft.frequencyText, prescriptionReminderTimesDisplay(draft.reminderTimes) ]
                        .compactMap { $0?.nilIfBlank }
                        .joined(separator: " · ")
                    if frequencyText.isEmpty == false {
                        Text(frequencyText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if let instructions = draft.instructions?.nilIfBlank {
                        HStack{
                            Text(L10n.text("medication_plan.form.field.instructions"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            
                            Text(instructions)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                if hasError {
                    MedicalValidationIssueBadge()
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                
//                Button(L10n.text("common.edit")) {
//                    onEditMedication(batchIndex, itemIndex, draft)
//                }
//                .font(.caption.weight(.semibold))
            }
            .contentShape(Rectangle())

            // 最多展示2条当前药品校验错误
            ForEach(itemIssues.prefix(2)) { issue in
                MedicalValidationIssueInlineView(message: issue.message)
            }

            if let medicineBoxCandidateContext {
                let key = MedicationCandidateKey(
                    prescriptionIndex: batchIndex,
                    medicationIndex: itemIndex
                )
                if let match = medicineBoxCandidateContext.matches[key], match != .noCandidate {
                    PrescriptionMedicineBoxCandidateCardView(
                        key: key,
                        plan: draft,
                        match: match,
                        confirmation: medicineBoxCandidateContext.confirmations[key] ?? .default,
                        isLoadingFamilyMedicineBoxes: medicineBoxCandidateContext.isLoadingFamilyMedicineBoxes,
                        detailNavigationContext: medicineBoxCandidateContext.detailNavigationContext,
                        familyMedicineBoxes: medicineBoxCandidateContext.familyMedicineBoxes,
                        attachmentsForIDs: medicineBoxCandidateContext.attachmentsForIDs,
                        onSelectExistingTarget: { medicineBoxCandidateContext.onSelectExistingTarget(key, $0) },
                        onToggleConfirmed: { medicineBoxCandidateContext.onToggleConfirmed(key, draft, match, $0) },
                        onEditCandidate: { medicineBoxCandidateContext.onEditCandidate(batchIndex, itemIndex, draft) },
                        onManageAttachments: {
                            medicineBoxCandidateContext.onManageMedicineBoxAttachments(batchIndex, itemIndex)
                        },
                        onLocalDraftMedicineBoxSaved: { medicineBoxCandidateContext.onLocalDraftMedicineBoxSaved(key, $0) },
                        onLocalDraftMedicineBoxDeleted: { medicineBoxCandidateContext.onLocalDraftMedicineBoxDeleted(key) }
                    )
                }
            }
            
            // 药品附件网格
            if let attachmentsForIDs, !draft.attachmentFileIds.isEmpty {
                CaseMatchedAttachmentsGridView(
                    title: "用药附件",
                    attachments: attachmentsForIDs(draft.attachmentFileIds),
                    onManage: {
                        onManageMedicationAttachments?(batchIndex, itemIndex, draft)
                    }
                )
            }
        }
        .medicalValidationCardChrome(
            hasError: hasError,
            scrollTargetID: scrollTargetID
        )
    }

    // MARK: 处方详情页导航目标构造
    private func prescriptionDetailDestination(index: Int, batch: PrescriptionRecognitionDraft, context: MedicalDocumentResultDetailNavigationContext) -> some View {
        let medicineBoxes = PrescriptionRecognitionDraftMapper.remoteMedicineBoxes(
            from: batch,
            memberID: context.memberID,
            prescriptionIndex: index
        )
        let plans = PrescriptionRecognitionDraftMapper.remoteMedicationPlans(
            from: batch,
            memberID: context.memberID,
            prescriptionIndex: index,
            medicineBoxes: medicineBoxes
        )
        return MedicationPrescriptionDetailPage(
            mode: .localDraft,
            prescription: PrescriptionRecognitionDraftMapper.remotePrescription(
                from: batch,
                memberID: context.memberID,
                prescriptionIndex: index
            ),
            plans: plans,
            medicineBoxes: medicineBoxes,
            recordsByPlanID: [:],
            memberID: context.memberID,
            completeData: nil,
            memberContextStore: context.memberContextStore,
            workflowAPI: context.workflowAPI,
            fileTransferService: context.fileTransferService,
            notificationClient: context.notificationClient,
            prescriptionIndex: index,
            sourceBatchDraft: batch,
            onPrescriptionSaved: { _ in },
            onPrescriptionDeleted: { _ in },
            onPlanSaved: { _ in },
            onPlanDeleted: { _ in },
            onLocalDraftPrescriptionUpdated: { updated in
                onUpdatePrescriptionDraft?(index, updated)
            },
            onLocalDraftPrescriptionDeleted: {
                onDeletePrescriptionDraft?(index)
            },
            onLocalDraftMedicationPlanSaved: { medicationIndex, updated in
                onUpdateMedicationDraft?(index, medicationIndex, updated)
            },
            onLocalDraftMedicationPlanDeleted: { medicationIndex in
                onDeleteMedicationDraft?(index, medicationIndex)
            },
            onLocalDraftMedicineBoxSaved: { _, _ in
                // 结果页更新由 onLocalDraftMedicationPlanSaved 统一处理
            },
            onLocalDraftMedicineBoxDeleted: { _ in
                // 结果页更新由 onLocalDraftMedicationPlanSaved 统一处理
            }
        )
    }

    // MARK: 单条药品详情页导航目标构造
    private func medicationDetailDestination(batchIndex: Int, itemIndex: Int, draft: MedicationPlanRecognitionDraft, context: MedicalDocumentResultDetailNavigationContext) -> some View {
        let explicitlyUnlinked = PrescriptionRecognitionDraftMapper.isMedicineBoxUnlinked(draft)
        let boxID = explicitlyUnlinked
            ? nil
            : PrescriptionRecognitionDraftMapper.temporaryMedicineBoxID(
                prescriptionIndex: batchIndex,
                medicationIndex: itemIndex
            )
        let plan = draft.remoteMedicationPlan(
            memberID: context.memberID,
            id: PrescriptionRecognitionDraftMapper.temporaryPlanID(
                prescriptionIndex: batchIndex,
                medicationIndex: itemIndex
            ),
            prescriptionID: PrescriptionRecognitionDraftMapper.temporaryPrescriptionID(prescriptionIndex: batchIndex),
            medicineBoxID: boxID,
            medicalCaseID: batches.indices.contains(batchIndex) ? batches[batchIndex].medicalCase : nil
        )
        let medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
        if let boxID, !explicitlyUnlinked {
            medicineBoxes = [draft.remoteMedicineBox(memberID: context.memberID, id: boxID)]
        } else {
            medicineBoxes = []
        }
        return MedicationPlanDetailPage(
            mode: .localDraft,
            plan: plan,
            medicineBoxes: medicineBoxes,
            memberID: context.memberID,
            completeData: nil,
            memberContextStore: context.memberContextStore,
            workflowAPI: context.workflowAPI,
            fileTransferService: context.fileTransferService,
            notificationClient: context.notificationClient,
            sourcePlanDraft: draft,
            onSaved: { _ in },
            onDeleted: { _ in },
            onMedicineBoxSaved: { _ in },
            onLocalDraftSaved: { updated in
                onUpdateMedicationDraft?(batchIndex, itemIndex, updated)
            },
            onLocalDraftDeleted: {
                onDeleteMedicationDraft?(batchIndex, itemIndex)
            },
            onLocalDraftMedicineBoxSaved: { _ in
                // 结果页更新由 onLocalDraftSaved 统一处理
            },
            onLocalDraftMedicineBoxDeleted: {
                // 结果页更新由 onLocalDraftSaved 统一处理
            }
        )
    }

    // MARK: 单条随访计划卡片UI
    private func followUpCard(index: Int, item: FollowUpRecognitionDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(item.method ?? "随访")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                // 有编辑回调才展示编辑按钮
                if let onEditFollowUp {
                    Button("编辑") {
                        onEditFollowUp(item)
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }

            // 拼接随访状态、计划时间、完成时间、下一步操作
            let detail = [item.status, item.plannedAt, item.completedAt, item.nextAction]
                .compactMap { $0?.nilIfBlank }
                .joined(separator: " · ")
            Text(detail.isEmpty ? "-" : detail)
                .font(.callout)
                .foregroundStyle(.secondary)

            // 随访附件网格
            if let attachmentsForIDs {
                CaseMatchedAttachmentsGridView(
                    title: "匹配附件",
                    attachments: attachmentsForIDs(item.attachmentFileIds),
                    onManage: {
                        onManageFollowUpAttachments?(index, item)
                    }
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    // MARK: 空状态提示视图封装
    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
    }
}

struct PrescriptionMedicineBoxCandidateContext {
    let matches: [MedicationCandidateKey: MedicineBoxCandidateMatch]
    let confirmations: [MedicationCandidateKey: MedicineBoxCandidateConfirmation]
    let isLoadingFamilyMedicineBoxes: Bool
    let detailNavigationContext: MedicalDocumentResultDetailNavigationContext?
    let familyMedicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    let attachmentsForIDs: (([UUID]) -> [MedicalDocumentLocalAttachmentItem])?
    let onSelectExistingTarget: (MedicationCandidateKey, Int) -> Void
    let onToggleConfirmed: (MedicationCandidateKey, MedicationPlanRecognitionDraft, MedicineBoxCandidateMatch, Bool) -> Void
    let onEditCandidate: (Int, Int, MedicationPlanRecognitionDraft) -> Void
    let onManageMedicineBoxAttachments: (Int, Int) -> Void
    let onLocalDraftMedicineBoxSaved: (MedicationCandidateKey, MedicineBoxRecognitionDraft) -> Void
    let onLocalDraftMedicineBoxDeleted: (MedicationCandidateKey) -> Void
}

struct PrescriptionMedicineBoxCandidateCardView: View {
    let key: MedicationCandidateKey
    let plan: MedicationPlanRecognitionDraft
    let match: MedicineBoxCandidateMatch
    let confirmation: MedicineBoxCandidateConfirmation
    let isLoadingFamilyMedicineBoxes: Bool
    let detailNavigationContext: MedicalDocumentResultDetailNavigationContext?
    let familyMedicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    let attachmentsForIDs: (([UUID]) -> [MedicalDocumentLocalAttachmentItem])?
    let onSelectExistingTarget: (Int) -> Void
    let onToggleConfirmed: (Bool) -> Void
    let onEditCandidate: () -> Void
    let onManageAttachments: () -> Void
    let onLocalDraftMedicineBoxSaved: (MedicineBoxRecognitionDraft) -> Void
    let onLocalDraftMedicineBoxDeleted: () -> Void

    private var candidate: MedicineBoxRecognitionDraft {
        switch match {
        case .noCandidate:
            return plan.medicineBox ?? MedicineBoxRecognitionDraft(
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
        case .noExisting(let candidate),
             .uniqueExisting(let candidate, _),
             .multipleExisting(let candidate, _),
             .loadFailed(let candidate, _):
            return confirmation.editedCandidate ?? candidate
        }
    }

    private var canToggleConfirm: Bool {
        if isLoadingFamilyMedicineBoxes { return false }
        if case .loadFailed = match { return false }
        if case .multipleExisting(_, let targets) = match {
            guard let selectedID = confirmation.selectedExistingBoxID else { return false }
            return targets.contains(where: { $0.id == selectedID })
        }
        return true
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { confirmation.isConfirmed },
            set: { onToggleConfirmed($0) }
        )
    }

    /// 已勾选绑定已有药箱时，跳转服务端药箱详情；否则预览本地草稿药箱。
    private var boundExistingTarget: SparkMedicalSyncAPI.RemoteMedicineBox? {
        guard confirmation.isConfirmed else { return nil }
        switch match {
        case .uniqueExisting(_, let target):
            return target
        case .multipleExisting(_, let targets):
            guard let selectedID = confirmation.selectedExistingBoxID else { return nil }
            return targets.first(where: { $0.id == selectedID })
        default:
            return nil
        }
    }

    private var medicineBoxDetailMode: MedicineBoxDetailMode {
        boundExistingTarget == nil ? .localDraft : .server
    }

    private func localDraftMedicineBox(memberID: Int) -> SparkMedicalSyncAPI.RemoteMedicineBox {
        candidate.remoteMedicineBox(
            memberID: memberID,
            id: PrescriptionRecognitionDraftMapper.temporaryMedicineBoxID(
                prescriptionIndex: key.prescriptionIndex,
                medicationIndex: key.medicationIndex
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            candidateSummaryNavigationLink

            if let attachmentsForIDs {
                CaseMatchedAttachmentsGridView(
                    title: "药箱附件",
                    attachments: attachmentsForIDs(candidate.attachmentFileIds),
                    onManage: onManageAttachments
                )
            }

//
//            Button(L10n.text("medical.upload.result.prescription.candidate.edit")) {
//                onEditCandidate()
//            }
//            .font(.caption.weight(.semibold))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    @ViewBuilder
    private var candidateSummaryNavigationLink: some View {
        if let detailNavigationContext {
            MainNavigationLink {
                medicineBoxDetailDestination(context: detailNavigationContext)
            } label: {
                candidateSummaryHeader
            }
            .buttonStyle(.plain)
        } else {
            candidateSummaryContent
        }
    }

    private var candidateSummaryHeader: some View {
        VStack(alignment: .leading, spacing: 4){
            HStack {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text("medical.upload.result.prescription.candidate.title"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(candidate.medicineName ?? plan.medicineName ?? L10n.text("medical.upload.result.medication.unnamed"))
                        .font(.callout.weight(.semibold))

    //                if let strength = candidate.strength?.nilIfBlank ?? plan.strength?.nilIfBlank {
    //                    Text(
    //                        String(
    //                            format: L10n.text("medical.upload.result.prescription.candidate.strength"),
    //                            locale: .current,
    //                            strength
    //                        )
    //                    )
    //                    .font(.caption)
    //                    .foregroundStyle(.secondary)
    //                }

//                    Text(
//                        String(
//                            format: L10n.text("medical.upload.result.prescription.candidate.expire"),
//                            locale: .current,
//                            candidate.expireDate?.nilIfBlank ?? L10n.text("medical.upload.result.prescription.candidate.expire_unknown")
//                        )
//                    )
//                    .font(.caption)
//                    .foregroundStyle(.secondary)
                    
                    
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                
            }
            if canToggleConfirm {
                Toggle(isOn: confirmationBinding) {
                    Text(confirmToggleTitle)
                        .font(.callout.weight(.semibold))
                }
            }
            matchResultView

        }
        .contentShape(Rectangle())
    }

    private var candidateSummaryContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            candidateSummaryHeader
            matchResultView
        }
    }

    @ViewBuilder
    private func medicineBoxDetailDestination(context: MedicalDocumentResultDetailNavigationContext) -> some View {
        let mode = medicineBoxDetailMode
        let box = boundExistingTarget ?? localDraftMedicineBox(memberID: context.memberID)

        MedicineBoxDetailPage(
            mode: mode,
            box: box,
            entryMemberID: context.memberID,
            memberOptions: context.memberContextStore.context.members,
            allowsHouseholdPublic: mode == .server,
            typeOptions: MedicineBoxTypeCatalog.defaultStoredOptions,
            specOptionBoxes: familyMedicineBoxes,
            workflowAPI: context.workflowAPI,
            fileTransferService: context.fileTransferService,
            sourceBoxDraft: mode == .localDraft ? candidate : nil,
            onSaved: { _ in },
            onDeleted: { _ in },
            onLocalDraftSaved: mode == .localDraft ? onLocalDraftMedicineBoxSaved : nil,
            onLocalDraftDeleted: mode == .localDraft ? onLocalDraftMedicineBoxDeleted : nil
        )
    }

    @ViewBuilder
    private var matchResultView: some View {
        switch match {
        case .noCandidate:
            EmptyView()
        case .loadFailed(_, let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.orange)
        case .noExisting:
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text("medical.upload.result.prescription.candidate.match.none"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                //                Text(L10n.text("medical.upload.result.prescription.candidate.submit.create_new"))
//                    .font(.caption)
//                    .foregroundStyle(.secondary)
            }
        case .uniqueExisting(_, let target):
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text("medical.upload.result.prescription.candidate.match.existing"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                //                Text(
//                    String(
//                        format: L10n.text("medical.upload.result.prescription.candidate.stock"),
//                        locale: .current,
//                        stockLabel(for: target)
//                    )
//                )
//                .font(.caption)
//                .foregroundStyle(.secondary)
//                Text(L10n.text("medical.upload.result.prescription.candidate.submit.bind_existing"))
//                    .font(.caption)
//                    .foregroundStyle(.secondary)
            }
        case .multipleExisting(_, let targets):
            Text(
                String(
                    format: L10n.text("medical.upload.result.prescription.candidate.match.multiple"),
                    locale: .current,
                    targets.count
                )
            )
            .font(.caption.weight(.semibold))
            ForEach(targets, id: \.id) { target in
                Button {
                    onSelectExistingTarget(target.id)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: confirmation.selectedExistingBoxID == target.id ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(Color.accentColor)
                        Text(existingTargetLabel(target))
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var confirmToggleTitle: String {
        switch match {
        case .noExisting:
            return L10n.text("medical.upload.result.prescription.candidate.confirm.create_new")
        case .uniqueExisting, .multipleExisting:
            return L10n.text("medical.upload.result.prescription.candidate.confirm.bind_existing")
        default:
            return L10n.text("medical.upload.result.prescription.candidate.confirm.default")
        }
    }

    private func existingTargetLabel(_ target: SparkMedicalSyncAPI.RemoteMedicineBox) -> String {
        let spec = target.strength.nilIfBlank ?? "-"
        return "\(target.medicineName) · \(spec) · \(stockLabel(for: target))"
    }

    private func stockLabel(for target: SparkMedicalSyncAPI.RemoteMedicineBox) -> String {
        let quantity = target.totalQuantity.map {
            $0.formatted(.number.precision(.fractionLength(0...2)))
        } ?? "-"
        let unit = target.doseUnit.nilIfBlank ?? ""
        if unit.isEmpty { return quantity }
        return "\(quantity) \(unit)"
    }
}

//private func prescriptionMedicationMetaRow(title: String, value: String) -> some View {
//    VStack(alignment: .leading, spacing: 2) {
//        Text(title)
//            .font(.caption2)
//            .foregroundStyle(.tertiary)
//        Text(value)
//            .font(.caption)
//            .foregroundStyle(.secondary)
//            .fixedSize(horizontal: false, vertical: true)
//    }
//    .frame(maxWidth: .infinity, alignment: .leading)
//}

private func prescriptionReminderTimesDisplay(_ times: [ReminderTime]?) -> String? {
    guard let times, times.isEmpty == false else { return nil }
    let formatted = times.map { entry -> String in
        if let doseText = entry.doseText?.nilIfBlank {
            return "\(entry.time) \(doseText)"
        }
        if let dose = entry.dose {
            let doseString = dose.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", dose)
                : String(dose)
            return "\(entry.time) \(doseString)"
        }
        return entry.time
    }
    let summary = formatted.joined(separator: "、")
    return summary.isEmpty ? nil : summary
}
