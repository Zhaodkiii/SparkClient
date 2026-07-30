import SwiftUI

/// 慢性病详情存储模型：确诊年份、控制情况、备注
struct MedicalGuideChronicConditionDetail: Equatable, Codable, Sendable {
    // 确诊年份文本
    var diagnosedYear: String = ""
    // 病情控制状态（良好/一般/较差等）
    var controlStatus: String = ""
    // 补充备注说明
    var notes: String = ""
}

/// 成员档案-慢性病填写分步页面
struct MemberMedicalChronicConditionStepView: View {
    /// 有无慢性病状态：none无 / have有
    @Binding var status: MedicalGuideDisclosureStatus
    /// 慢性病名称数组
    @Binding var chronicConditions: [String]
    /// 慢性病详情字典 key=病名 value=详细信息
    @Binding var conditionDetails: [String: MedicalGuideChronicConditionDetail]

    /// 当前编辑的成员对象
    let member: Member?
    /// 病历上传视图模型
    @ObservedObject var medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel
    /// AI设置视图模型（病历识别用到）
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel

    // 本地弹窗状态
    @State private var showingUploadSheet = false
    @State private var showingManualEntrySheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 第一步：有无慢性病单选卡片
            diseaseScreeningCard

            // 选择「无慢性病」时展示提示文案
            if status == .none {
                friendlyTipRow
            }

            // 选择「有慢性病」时展示列表、新增按钮
            if status == .have {
                // 已有慢性病列表区域
                existingConditionsSection
                // 手动添加慢性病按钮
                MemberSetupAccentAddButton(title: L10n.text("member.setup.medical.chronic.chronic.68b55f")) {
                    showingManualEntrySheet = true
                }
            }
        }
        // 上传病历弹窗（拍照/相册选择文件）
        .sheet(isPresented: $showingUploadSheet) {
            MedicalAttachmentUploadListSheet(documentKind: .caseDocument, onConfirm: startCaseDocumentRecognition)
        }
        // 手动录入慢性病表单弹窗
        .sheet(isPresented: $showingManualEntrySheet) {
            CompatibleNavigationContainer {
                ChronicConditionFormView(
                    initial: ChronicConditionFormDraft(
                        conditions: chronicConditions,
                        details: conditionDetails
                    ),
                    onSubmit: { draft in
                        // 提交表单后同步数据
                        chronicConditions = draft.conditions
                        conditionDetails = draft.details
                        // 有慢性病自动切换状态为have
                        if draft.conditions.isEmpty == false {
                            status = .have
                        }
                    }
                )
            }
        }
        // 病历识别全屏页面（上传后跳转）
//        .fullScreenCover(isPresented: $medicalDocumentUploadViewModel.isUploadPresented) {
//            CompatibleNavigationContainer {
//                MedicalDocumentUploadHostView(
//                    viewModel: medicalDocumentUploadViewModel,
//                    aiSettingsViewModel: aiSettingsViewModel
//                )
//            }
//        }
        // 切换「有无慢性病」时清空已有数据
        .onChange(of: status) { newValue in
            if newValue == .none {
                chronicConditions.removeAll()
                conditionDetails.removeAll()
            }
        }
    }

    // MARK: 子视图拆分
    /// 有无慢性病选择卡片
    private var diseaseScreeningCard: some View {
        MemberSetupSection(title: L10n.text("member.setup.medical.chronic.chronic.29e6fc")) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.text("member.setup.medical.chronic.chronic.3ec025"))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                // 单选按钮行：无 / 有
                HStack(spacing: 10) {
                    screeningChoice(
                        title: L10n.text("member.setup.medical.chronic.chronic.3d3103"),
                        isSelected: status == .none,
                        action: { status = .none }
                    )
                    screeningChoice(
                        title: L10n.text("member.setup.medical.chronic.chronic.31f558"),
                        isSelected: status == .have,
                        action: { status = .have }
                    )
                }
            }
        }
    }

    /// 选择「无慢性病」后的提示文案
    private var friendlyTipRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(L10n.text("member.setup.medical.chronic.chronic.8d38f0"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 已有慢性病列表区域
    private var existingConditionsSection: some View {
        Group {
            if chronicConditions.isEmpty == false {
                MemberSetupSection(title: L10n.text("member.setup.medical.chronic.chronic.57571c")) {
                    VStack(spacing: 10) {
                        // 遍历每条慢性病卡片
                        ForEach(chronicConditions, id: \.self) { disease in
                            Button {
                                // 点击卡片打开编辑表单
                                showingManualEntrySheet = true
                            } label: {
                                chronicConditionCard(disease)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    /// 单条慢性病卡片
    private func chronicConditionCard(_ disease: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            // 拼接病名+确诊年份+控制情况摘要
            Text(
                ChronicConditionFormSupport.summaryLine(
                    name: disease,
                    detail: conditionDetails[disease]
                )
            )
            .font(.subheadline)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            // 右侧跳转箭头
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        )
    }

    /// 有无慢性病单选胶囊按钮
    private func screeningChoice(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                // 选中时展示对勾
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            // 选中使用主题色浅底色
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(uiColor: .systemBackground))
            )
        }
        .buttonStyle(.plain)
    }

    /// 上传病历确认回调：启动OCR识别流程
    @MainActor
    private func startCaseDocumentRecognition(files: [MedicalUploadLocalFile]) {
        showingUploadSheet = false
        medicalDocumentUploadViewModel.prepareAndStart(files: files, kind: .caseDocument, member: member)
    }
}
