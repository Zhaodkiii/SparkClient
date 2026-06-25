import SwiftUI

/// 成员档案-症状随访分步填写页面
struct MemberMedicalSymptomFollowUpStepView: View {
    /// 医疗档案页面视图模型，承载症状列表、增删改业务逻辑
    @ObservedObject var viewModel: MemberMedicalSetupViewModel
    /// 是否存在随访症状状态：none无 / have有
    @Binding var symptomStatus: MedicalGuideDisclosureStatus

    /// 病历上传视图模型，用于病历OCR识别
    @ObservedObject var medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel
    /// AI设置视图模型，OCR识别依赖
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel

    // 弹窗本地状态
    @State private var showingUploadSheet = false
    @State private var showingSymptomFormSheet = false
    /// 当前选中查看详情的单条症状数据
    @State private var selectedSymptom: SparkMedicalSyncAPI.RemoteSymptom?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 第一步：有无随访症状选择卡片
            symptomScreeningCard

            // 选择「无随访症状」展示提示文案
            if symptomStatus == .none {
                friendlyTipRow
            }

            // 选择「有随访症状」展示症状列表、新增按钮
            if symptomStatus == .have {
//                quickUploadCard
                // 已有症状列表区域
                existingSymptomsSection
                // 手动新增症状按钮
                MemberSetupAccentAddButton(title: L10n.text("member.setup.medical.symptom.c8a51c")) {
                    showingSymptomFormSheet = true
                }
            }
        }
        // 上传病历弹窗，选择文件后进入OCR识别流程
        .sheet(isPresented: $showingUploadSheet) {
            MedicalAttachmentUploadListSheet(documentKind: .caseDocument, onConfirm: startCaseDocumentRecognition)
        }
        // 新建症状录入表单弹窗
        .sheet(isPresented: $showingSymptomFormSheet) {
            CompatibleNavigationContainer {
                SymptomFormView(
                    mode: .create(
                        .init(
                            memberID: viewModel.member?.id ?? 0,
                            medicalCaseID: nil,
                            submissionService: MedicalRecordFormSubmissionService(
                                workflowAPI: viewModel.medicalWorkflowAPI
                            ),
                            // 提交成功后同步更新本地症状列表
                            onMutation: { viewModel.applySymptomMutation($0) }
                        )
                    )
                )
            }
        }
        // 点击症状卡片，弹出详情编辑页面
        .sheet(item: $selectedSymptom) { symptom in
            CompatibleNavigationContainer {
                SymptomDetailView(
                    symptom: symptom,
                    memberID: viewModel.member?.id ?? symptom.member,
                    workflowAPI: viewModel.medicalWorkflowAPI,
                    // 编辑保存后刷新列表
                    onUpdated: { viewModel.applySymptomMutation($0) },
                    // 删除症状后同步本地缓存
                    onDeleted: { symptomID, response in
                        viewModel.applySymptomMutation(response, removedSymptomID: symptomID)
                    }
                )
            }
        }
        // 病历识别全屏页面
        .fullScreenCover(isPresented: $medicalDocumentUploadViewModel.isUploadPresented) {
            CompatibleNavigationContainer {
                MedicalDocumentUploadHostView(
                    viewModel: medicalDocumentUploadViewModel,
                    aiSettingsViewModel: aiSettingsViewModel
                )
            }
        }
        // 页面首次加载自动拉取成员症状列表
        .task {
            await viewModel.refreshMemberSymptomsIfNeeded()
        }
        // 切换有无症状状态时执行对应逻辑
        .onChange(of: symptomStatus) { newValue in
            if newValue == .none {
                // 切换为无，清空症状表单草稿
                viewModel.clearSymptomFollowUpDraft()
            } else if newValue == .have {
                // 切换为有，强制刷新最新症状数据
                Task { await viewModel.refreshMemberSymptomsIfNeeded(force: true) }
            }
        }
    }

    // MARK: 子视图拆分
    /// 有无随访症状单选选择卡片
    private var symptomScreeningCard: some View {
        MemberSetupSection(title: L10n.text("member.setup.medical.symptom.6cb2f5")) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.text("member.setup.medical.symptom.8edac7"))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                // 单选按钮：无 / 有随访症状
                HStack(spacing: 10) {
                    screeningChoice(
                        title: L10n.text("member.setup.medical.symptom.3d9476"),
                        isSelected: symptomStatus == .none,
                        action: { symptomStatus = .none }
                    )
                    screeningChoice(
                        title: L10n.text("member.setup.medical.symptom.dc316b"),
                        isSelected: symptomStatus == .have,
                        action: { symptomStatus = .have }
                    )
                }
            }
        }
    }

    /// 选择「无随访症状」后的灯泡提示文案
    private var friendlyTipRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(L10n.text("member.setup.medical.symptom.0a337b"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 拍照上传病历快速录入卡片（当前注释未启用）
    private var quickUploadCard: some View {
        MemberSetupSection(title: L10n.text("member.setup.medical.chronic.chronic.d6c422")) {
            Button {
                showingUploadSheet = true
            } label: {
                VStack(spacing: 10) {
                    Label(L10n.text("member.setup.medical.symptom.a851ac"), systemImage: "camera.viewfinder")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)

                    Text(L10n.text("member.setup.medical.symptom.b4ff8d"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
    }

    /// 已有随访症状列表区域
    private var existingSymptomsSection: some View {
        Group {
            if viewModel.isLoadingMemberSymptoms {
                // 加载中展示进度条
                MemberSetupSection(title: L10n.text("member.setup.medical.symptom.ae3b5e")) {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            } else if viewModel.memberSymptoms.isEmpty == false {
                // 遍历渲染每条症状卡片
                MemberSetupSection(title: L10n.text("member.setup.medical.symptom.ae3b5e")) {
                    VStack(spacing: 10) {
                        ForEach(viewModel.memberSymptoms, id: \.id) { symptom in
                            Button {
                                // 点击打开详情弹窗
                                selectedSymptom = symptom
                            } label: {
                                memberSymptomCard(symptom)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    /// 单条随访症状卡片
    private func memberSymptomCard(_ symptom: SparkMedicalSyncAPI.RemoteSymptom) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                // 拼接症状摘要文本（名称、发作情况、时长等）
                Text(SymptomFormSupport.summaryLine(for: symptom))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    /// 有无随访症状单选胶囊按钮组件
    private func screeningChoice(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
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
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(uiColor: .systemBackground))
            )
        }
        .buttonStyle(.plain)
    }

    /// 选择病历文件回调，启动病历OCR识别流程
    @MainActor
    private func startCaseDocumentRecognition(files: [MedicalUploadLocalFile]) {
        showingUploadSheet = false
        medicalDocumentUploadViewModel.prepareAndStart(files: files, kind: .caseDocument, member: viewModel.member)
    }
}
