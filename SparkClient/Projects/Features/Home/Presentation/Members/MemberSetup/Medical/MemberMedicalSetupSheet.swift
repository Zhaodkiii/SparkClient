import SwiftUI

struct MemberMedicalSetupSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: MemberMedicalSetupViewModel
    @State private var path: [MedicalGuideRoute] = []
    @State private var occupationSearchText = ""
    @State private var didApplyEntryRoute = false
    let homeDependencies: HomeFeatureDependencies
    let entryMode: MedicalSetupEntryMode
    let onCompleted: (String) -> Void
    let onSectionCompleted: (MedicalSetupEntryMode, String) -> Void

    init(
        member: Member?,
        medicalQueryAPI: SparkMedicalQueryAPI,
        setupUseCase: MemberModuleSetupUseCase,
        homeDependencies: HomeFeatureDependencies,
        preloadedCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData? = nil,
        preloadedNutritionGoalState: SparkNutritionAPI.RemoteNutritionGoalState? = nil,
        onCompleteDataPatch completeDataPatcher: ((@escaping (inout SparkMedicalSyncAPI.RemoteMemberCompleteData) -> Void) -> Void)? = nil,
        entryMode: MedicalSetupEntryMode = .full,
        onCompleted: @escaping (String) -> Void,
        onSectionCompleted: @escaping (MedicalSetupEntryMode, String) -> Void = { _, _ in }
    ) {
        _viewModel = StateObject(
            wrappedValue: MemberMedicalSetupViewModel(
                member: member,
                medicalQueryAPI: medicalQueryAPI,
                setupUseCase: setupUseCase,
                homeDependencies: homeDependencies,
                preloadedCompleteData: preloadedCompleteData,
                preloadedNutritionGoalState: preloadedNutritionGoalState,
                entryMode: entryMode,
                onCompleteDataPatch: completeDataPatcher
            )
        )
        self.homeDependencies = homeDependencies
        self.entryMode = entryMode
        self.onCompleted = onCompleted
        self.onSectionCompleted = onSectionCompleted
    }

    private var isSectionMode: Bool {
        entryMode.isSectionMode
    }

    var body: some View {
        CompatibleRouteNavigationContainer(path: $path, legacyStackStyle: true) {
            introStep
        } destination: { route in
            switch route {
            case .intro:
                introStep
            case .gender:
                genderStep
            case .birthDate:
                birthDateStep
            case .height:
                heightStep
            case .weight:
                weightStep
            case .occupation:
                occupationStep
            case .sedentary:
                sedentaryStep
            case .basicSummary:
                basicInfoSummaryStep
            case .history:
                historyIntroStep
            case .chronicConditions:
                chronicConditionsStep
            case .longTermMedication:
                longTermMedicationStep
            case .surgeryHistory:
                surgeryHistoryStep
            case .allergyHistory:
                allergyHistoryStep
            case .familyHistory:
                familyHistoryStep
            case .historySummary:
                historySummaryStep
            case .lifestyle:
                lifestyleIntroStep
            case .smoking:
                smokingStep
            case .drinking:
                drinkingStep
            case .exercise:
                exerciseStep
            case .sleep:
                sleepStep
            case .lifestyleSummary:
                lifestyleSummaryStep
            case .examArchiveIntro:
                examArchiveIntroStep
            case .examArchive:
                examArchiveStep
            case .examArchiveSummary:
                examArchiveSummaryStep
            case .keyIndicators:
                keyIndicatorStep
            case .keyIndicatorSummary:
                keyIndicatorSummaryStep
            case .symptomFollowUp:
                symptomFollowUpStep
            case .riskAssessment:
                riskAssessmentStep
            case .examPlan:
                examPlanStep
            case .summary:
                summaryPage
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .task {
            await viewModel.loadIfNeeded()
        }
        .onAppear {
            applyEntryRouteIfNeeded()
        }
    }

    private var introStep: some View {
        MedicalGuideIntroPageView(
            kind: .basicProfile,
            title: "基础档案",
            subtitle: "完善基础档案有助于为你量身定制体检项目推荐，并提供精准的慢病与癌症风险筛查。",
            isLoading: viewModel.isSaving,
            primaryTitle: "开始",
            secondaryTitle: "稍后在设置中完善",
            onStart: { nextVisible(after: .intro) },
            onLater: {
                if isSectionMode {
                    dismiss()
                } else {
                    path = [.history]
                }
            },
            onClose: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("包含以下分步内容")
                    .font(.headline.weight(.semibold))

                MedicalGuideGroupedCard {
                    MedicalGuideListRow(icon: "person.fill", tint: .blue, title: "基本信息", subtitle: "性别 / 出生日期")
                    Divider()
                    MedicalGuideListRow(icon: "scalemass.fill", tint: .purple, title: "身体指标", subtitle: "身高 / 体重")
                    Divider()
                    MedicalGuideListRow(icon: "briefcase.fill", tint: .orange, title: "日常习惯", subtitle: "职业 / 久坐时间")
                }

                HStack(alignment: .top, spacing: 8) {
                    Text("💡")
                        .font(.footnote)
                    Text("如果你之前在“饮食健康”中填写过相关数据，系统将为你自动带入。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("隐私与安全")
                    .font(.headline.weight(.semibold))

                MedicalGuideGroupedCard {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.accent)
                            .frame(width: 28)
                        Text("端到端加密保护")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                Text("“Look健康”会严格保护你的隐私，此数据仅用于为你生成个人健康报告。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var genderStep: some View {
        MedicalGuideStepShell(
            title: "性别",
            subtitle: "为什么要问？\n性别会影响乳腺、宫颈、前列腺等筛查项目推荐。",
            step: 2,
            total: viewModel.totalGuideSteps,
            isLoading: viewModel.isSaving,
            onSkip: { nextVisible(after: .gender) },
            onNext: { nextVisible(after: .gender) }
        ) {
            VStack(spacing: 20) {
                Text("请选择成员性别")
                    .font(.headline.weight(.semibold))

                MedicalPickerChipRow(
                    items: [
                        ("男", "male"),
                        ("女", "female"),
                        ("不确定 / 暂不填", "unknown")
                    ],
                    selection: Binding(
                        get: { viewModel.gender },
                        set: { viewModel.gender = $0 }
                    )
                )
            }
        }
    }

    private var birthDateStep: some View {
        MedicalGuideStepShell(
            title: "出生日期",
            subtitle: "为什么要问？\n年龄会影响体检频率、慢病风险和部分癌症筛查建议。",
            step: 3,
            total: viewModel.totalGuideSteps,
            isLoading: viewModel.isSaving,
            primaryTitle: basicInfoPrimaryTitle(after: .birthDate),
            onSkip: { nextVisible(after: .birthDate) },
            onNext: { nextVisible(after: .birthDate) }
        ) {
            VStack(spacing: 18) {
                Text("请选择出生日期")
                    .font(.headline.weight(.semibold))

                DatePicker(
                    "出生日期",
                    selection: birthDateBinding,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(.vertical)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(uiColor: .systemGroupedBackground)))
                if let ageYears = viewModel.ageYears {
                    Text("年龄：\(ageYears) 岁")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
  
            
        }
    }

    private var heightStep: some View {
        MemberNutritionHeightStepView(
            heightCm: $viewModel.heightCm,
            presentation: .fullScreen
        )
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("身高")
        .navigationBarTitleDisplayMode(.inline)
        .memberSetupBottomBar(
            primaryTitle: basicInfoPrimaryTitle(after: .height),
            primaryEnabled: viewModel.isSaving == false,
            isLoading: viewModel.isSaving,
            onPrimary: {
                viewModel.confirmHeightSelection()
                nextVisible(after: .height)
            },
            secondaryTitle: "跳过",
            onSecondary: {
                viewModel.skipHeightSelection()
                nextVisible(after: .height)
            }
        )
    }

    private var weightStep: some View {
        MemberNutritionWeightStepView(
            weightKg: $viewModel.weightKg,
            presentation: .fullScreen
        )
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("体重")
        .navigationBarTitleDisplayMode(.inline)
        .memberSetupBottomBar(
            primaryTitle: basicInfoPrimaryTitle(after: .weight),
            primaryEnabled: viewModel.isSaving == false,
            isLoading: viewModel.isSaving,
            onPrimary: {
                viewModel.confirmWeightSelection()
                nextVisible(after: .weight)
            },
            secondaryTitle: "跳过",
            onSecondary: {
                viewModel.skipWeightSelection()
                nextVisible(after: .weight)
            }
        )
    }

    private var occupationStep: some View {
        MedicalGuideStepShell(
            title: "职业类别",
            subtitle: "不同的职业特征伴随着不同的作息规律与环境暴露风险，这能让体检项目推荐和健康建议更贴近实际。",
            step: 6,
            total: viewModel.totalGuideSteps,
            isLoading: viewModel.isSaving,
            primaryTitle: basicInfoPrimaryTitle(after: .occupation),
            onSkip: { nextVisible(after: .occupation) },
            onNext: { nextVisible(after: .occupation) }
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Text("请选择最接近你日常工作状态的职业：")
                    .font(.headline.weight(.semibold))

//                HStack(spacing: 10) {
//                    Image(systemName: "magnifyingglass")
//                        .foregroundStyle(.secondary)
//                    TextField("搜索职业", text: $occupationSearchText)
//                        .textInputAutocapitalization(.never)
//                        .disableAutocorrection(true)
//                }
//                .padding(.horizontal, 14)
//                .padding(.vertical, 12)
//                .background(
//                    RoundedRectangle(cornerRadius: 14, style: .continuous)
//                        .fill(Color(uiColor: .secondarySystemBackground))
//                )

                MedicalGuideGroupedCard {
                    ForEach(filteredOccupationGroups.indices, id: \.self) { index in
                        let group = filteredOccupationGroups[index]
                        Button {
                            viewModel.occupation = group.value
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: group.icon)
                                    .font(.title3)
                                    .foregroundStyle(group.tint)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(group.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(group.subtitle)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                if viewModel.occupation == group.value {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < filteredOccupationGroups.count - 1 {
                            Divider()
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("手动补充其他职业名称")
                            .font(.subheadline.weight(.semibold))
                        TextField("请输入职业名称", text: $viewModel.occupation)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var sedentaryStep: some View {
        MedicalGuideStepShell(
            title: "久坐时间",
            subtitle: "平均每天在椅子或沙发上坐多久？",
            step: 7,
            total: viewModel.totalGuideSteps,
            isLoading: viewModel.isSaving,
            primaryTitle: "下一步",
            primaryEnabled: viewModel.sedentaryLevel != nil,
            onSkip: { nextVisible(after: .sedentary) },
            onNext: { nextVisible(after: .sedentary) }
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Text("平均每天在椅子或沙发上坐多久？")
                    .font(.headline.weight(.semibold))

                MedicalGuideGroupedCard {
                    ForEach(sedentaryOptions, id: \.value) { item in
                        Button {
                            viewModel.sedentaryLevel = item.value
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(item.color)
                                    .frame(width: 12, height: 12)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(item.subtitle)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if viewModel.sedentaryLevel == item.value {
                                    Image(systemName: "checkmark")
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(.accent)
                                }
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if item.value != sedentaryOptions.last?.value {
                            Divider()
                        }
                    }
                }

                Text("长期连续久坐会直接影响心血管与代谢机能，了解此项数据能为你定制针对性的运动唤醒与健康调理方案。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var basicInfoSummaryStep: some View {
        MedicalGuideStepShell(
            title: "基础档案概览",
            subtitle: "请确认你的基础健康档案信息，随时可以点击各项进行修正。",
            step: 8,
            total: viewModel.totalGuideSteps,
            isLoading: viewModel.isSaving,
            primaryTitle: isSectionMode && entryMode == .basicProfile ? "完成" : "完成",
            onSkip: {
                Task {
                    await viewModel.saveProgress()
                    proceedFromSectionSummary(.basicSummary, fullFlowNext: .history)
                }
            },
            onNext: {
                Task {
                    await viewModel.saveProgress()
                    proceedFromSectionSummary(.basicSummary, fullFlowNext: .history)
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 18) {
                MedicalGuideGroupedCard {
                    MedicalGuideTextRow(
                        systemName: "person.fill",
                        title: "性别",
                        subtitle: viewModel.genderDisplayTitle,
                        action: {
                            path.append(.gender)
                        }
                    )
                    
                    Divider()
                    
                    MedicalGuideTextRow(
                        systemName: "calendar",
                        title: "出生日期",
                        subtitle: viewModel.birthDate.map { Self.dateFormatter.string(from: $0) } ?? "未填写",
                        action: {
                            path.append(.birthDate)
                        }
                    )
                }

                MedicalGuideGroupedCard {
                    MedicalGuideTextRow(
                        systemName: "ruler",
                        title: "身高",
                        subtitle: viewModel.shouldSkipHeightStep ? (viewModel.heightCm > 0 ? String(format: "%.0f cm", viewModel.heightCm) : "已自动带入") : (viewModel.heightCm > 0 ? String(format: "%.0f cm", viewModel.heightCm) : "未填写"),
                        action: {
                            path.append(.height)
                        }
                    )
                    Divider()
                    MedicalGuideTextRow(
                        systemName: "scalemass.fill",
                        title: "体重",
                        subtitle: viewModel.shouldSkipWeightStep ? (viewModel.weightKg > 0 ? String(format: "%.1f kg", viewModel.weightKg) : "已自动带入") : (viewModel.weightKg > 0 ? String(format: "%.1f kg", viewModel.weightKg) : "未填写"),
                        action: {
                            path.append(.weight)
                        }
                    )
                }

                MedicalGuideGroupedCard {
                    MedicalGuideTextRow(
                        systemName: "briefcase.fill",
                        title: "职业",
                        subtitle: viewModel.occupation.isEmpty ? "未填写" : viewModel.occupation,
                        action: {
                            path.append(.occupation)
                        }
                    )
                    Divider()
                    MedicalGuideTextRow(
                        systemName: "chair.lounge.fill",
                        title: "久坐时间",
                        subtitle: viewModel.sedentaryLevel?.title ?? "未填写",
                        action: {
                            path.append(.sedentary)
                        }
                    )
                }

                HStack(alignment: .top, spacing: 8) {
                    Text("💡")
                        .font(.footnote)
                    Text("如果你之前在“饮食健康”中填写过相关数据，系统将为你自动带入。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // 健康病史与症状记录先给出说明，再逐题进入各个问题页，避免把多个问题塞进同一个表单。
    private var historyIntroStep: some View {
        MedicalGuideIntroPageView(
            kind: .healthHistory,
            title: "健康病史与症状记录",
            subtitle: "了解你的既往病史、症状观察与随访情况，有助于我们更早识别潜在医疗风险，并定制更精准的复查周期与健康跟踪计划。",
            isLoading: viewModel.isSaving,
            primaryTitle: "开始",
            secondaryTitle: "稍后在设置中完善",
            onStart: { nextVisibleHistory(after: .history) },
            onLater: {
                if isSectionMode {
                    dismiss()
                } else {
                    path.append(.lifestyle)
                }
            },
            onClose: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("将包含以下四块内容")
                    .font(.headline.weight(.semibold))

                MedicalGuideGroupedCard {
                    MedicalGuideListRow(icon: "waveform.path.ecg", tint: .pink, title: "症状观察 / 随访", subtitle: "")
                    Divider()
                    MedicalGuideListRow(icon: "cross.case.fill", tint: .red, title: "既往疾病 / 长期用药", subtitle: "")
                    Divider()
                    MedicalGuideListRow(icon: "allergens.fill", tint: .orange, title: "手术史 / 过敏史", subtitle: "")
                    Divider()
                    MedicalGuideListRow(icon: "person.3.fill", tint: .teal, title: "家族病史", subtitle: "")
                }

                HStack(alignment: .top, spacing: 8) {
                    Text("💡")
                        .font(.footnote)
                    Text("轻松点：如果平时身体健康，各项都可以直接选择“无”；如果记不太清，也可以随时选择“不清楚”。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("隐私与安全承诺")
                    .font(.headline.weight(.semibold))

                MedicalGuideGroupedCard {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.accent)
                            .frame(width: 28)
                        Text("医疗级数据加密保密")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                Text("我们深知医疗隐私的重要性。此数据将被严格隔离保护，绝不用于任何未经授权的商业用途。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // 既往疾病单题页。
    private var chronicConditionsStep: some View {
        MedicalGuideStepShell(
            title: "既往疾病",
            subtitle: "了解你过往的确诊疾病与慢病史，有助于我们为你避开潜在医疗风险，并定制更精准的体检项目与复查周期。",
            step: 10,
            total: viewModel.totalGuideSteps,
            isLoading: viewModel.isSaving,
            primaryTitle: chronicConditionsPrimaryTitle,
            primaryEnabled: viewModel.canAdvanceFromChronicConditions,
            onSkip: { nextVisibleHistory(after: .chronicConditions) },
            onNext: { nextVisibleHistory(after: .chronicConditions) }
        ) {
            MemberMedicalChronicConditionStepView(
                status: $viewModel.chronicConditionStatus,
                chronicConditions: $viewModel.chronicConditions,
                conditionDetails: $viewModel.chronicConditionDetails,
                member: viewModel.member,
                medicalDocumentUploadViewModel: homeDependencies.memberFlowMedicalDocumentUploadViewModel,
                aiSettingsViewModel: homeDependencies.aiSettingsViewModel
            )
        }
    }

    private var chronicConditionsPrimaryTitle: String {
        switch viewModel.chronicConditionStatus {
        case .none:
            return "完成既往疾病"
        case .have:
            return "完成既往疾病"
        case .unknown:
            return historyPrimaryTitle(after: .chronicConditions)
        }
    }

    // 长期用药单题页。
    private var longTermMedicationStep: some View {
        Group {
            if viewModel.member?.id != nil {
                MedicalGuideStepShell(
                    title: "长期用药",
                    subtitle: "了解您的用药史，有助于我们为您提供更精准的复查项目建议、服药提醒，并辅助报告的上下文解读。",
                    step: 11,
                    total: viewModel.totalGuideSteps,
                    isLoading: viewModel.isSaving,
                    primaryTitle: longTermMedicationPrimaryTitle,
                    primaryEnabled: viewModel.canAdvanceFromLongTermMedication,
                    onSkip: { nextVisibleHistory(after: .longTermMedication) },
                    onNext: { nextVisibleHistory(after: .longTermMedication) }
                ) {
                    MemberMedicalLongTermMedicationStepView(
                        viewModel: viewModel,
                        status: Binding(
                            get: { viewModel.longTermMedicationStatus },
                            set: { newValue in
                                viewModel.longTermMedicationStatus = newValue
                                if newValue != .unknown {
                                    viewModel.hasPrefilledLongTermMedicationStatus = true
                                }
                            }
                        ),
                        completeData: nil,
                        medicalQueryAPI: homeDependencies.medicalQueryAPI,
                        fileTransferService: homeDependencies.fileTransferService,
                        memberContextStore: homeDependencies.memberContextStore,
                        medicalDocumentUploadViewModel: homeDependencies.memberFlowMedicalDocumentUploadViewModel,
                        aiSettingsViewModel: homeDependencies.aiSettingsViewModel,
                        notificationClient: homeDependencies.notificationClient,
                        homeDependencies: homeDependencies
                    )
                }
            } else {
                MedicalGuideStepShell(
                    title: "长期用药",
                    subtitle: "了解您的用药史，有助于我们为您提供更精准的复查项目建议、服药提醒，并辅助报告的上下文解读。",
                    step: 11,
                    total: viewModel.totalGuideSteps,
                    isLoading: viewModel.isSaving,
                    primaryTitle: longTermMedicationPrimaryTitle,
                    primaryEnabled: viewModel.canAdvanceFromLongTermMedication,
                    onSkip: { nextVisibleHistory(after: .longTermMedication) },
                    onNext: { nextVisibleHistory(after: .longTermMedication) }
                ) {
                    Text("缺少成员信息，无法加载用药档案。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var longTermMedicationPrimaryTitle: String {
        switch viewModel.longTermMedicationStatus {
        case .none, .have:
            return "完成长期用药"
        case .unknown:
            return historyPrimaryTitle(after: .longTermMedication)
        }
    }

    // 手术史单题页。
    private var surgeryHistoryStep: some View {
        MedicalGuideStepShell(
            title: "手术史",
            subtitle: "了解您的过往手术史，有助于我们为您排查禁忌项目，并制定更安全的体检方案与长期随访计划。",
            step: 12,
            total: viewModel.totalGuideSteps,
            isLoading: viewModel.isSaving,
            primaryTitle: surgeryHistoryPrimaryTitle,
            primaryEnabled: viewModel.canAdvanceFromSurgeryHistory,
            onSkip: { nextVisibleHistory(after: .surgeryHistory) },
            onNext: { nextVisibleHistory(after: .surgeryHistory) }
        ) {
            MemberMedicalSurgeryHistoryStepView(
                viewModel: viewModel,
                surgeryStatus: Binding(
                    get: { viewModel.surgeryStatus },
                    set: { newValue in
                        viewModel.surgeryStatus = newValue
                        if newValue != .unknown {
                            viewModel.hasPrefilledSurgeryStatus = true
                        }
                    }
                )
            )
        }
    }

    private var surgeryHistoryPrimaryTitle: String {
        switch viewModel.surgeryStatus {
        case .none, .have:
            return "完成记录"
        case .unknown:
            return historyPrimaryTitle(after: .surgeryHistory)
        }
    }

    // 过敏史单题页。
    private var allergyHistoryStep: some View {
        MedicalGuideStepShell(
            title: "过敏史",
            subtitle: "了解您的过敏史，是保障用药安全、规避过敏原以及提供智能就医指导中最核心的防线。",
            step: 13,
            total: viewModel.totalGuideSteps,
            isLoading: viewModel.isSaving,
            primaryTitle: historyPrimaryTitle(after: .allergyHistory),
            primaryEnabled: viewModel.canAdvanceFromAllergyHistory,
            onSkip: { nextVisibleHistory(after: .allergyHistory) },
            onNext: { nextVisibleHistory(after: .allergyHistory) }
        ) {
            MemberMedicalAllergyHistoryStepView(
                status: Binding(
                    get: { viewModel.allergyStatus },
                    set: { newValue in
                        viewModel.allergyStatus = newValue
                        if newValue != .unknown {
                            viewModel.hasPrefilledAllergyStatus = true
                        }
                    }
                ),
                allergies: $viewModel.allergies,
                allergyDetails: $viewModel.allergyDetails,
                allergyHistory: $viewModel.allergyHistory
            )
        }
    }

    private var familyHistoryStep: some View {
        MedicalGuideStepShell(
            title: "家族病史",
            subtitle: "了解您直系亲属的过往病史，有助于我们为您识别潜在的遗传风险，并在体检中为您针对性地推荐慢病与癌症筛查项目。",
            step: 14,
            total: viewModel.totalGuideSteps,
            isLoading: viewModel.isSaving,
            primaryTitle: "下一步",
            primaryEnabled: viewModel.canAdvanceFromFamilyHistory,
            onSkip: { nextVisibleHistory(after: .familyHistory) },
            onNext: { nextVisibleHistory(after: .familyHistory) }
        ) {
            MemberMedicalFamilyHistoryStepView(
                status: Binding(
                    get: { viewModel.familyHistoryStatus },
                    set: { newValue in
                        viewModel.familyHistoryStatus = newValue
                        if newValue != .unknown {
                            viewModel.hasPrefilledFamilyHistoryStatus = true
                        }
                        if newValue != .have {
                            viewModel.familyHistory.removeAll()
                            viewModel.familyHistoryDetails.removeAll()
                        }
                    }
                ),
                familyHistory: $viewModel.familyHistory,
                familyHistoryDetails: $viewModel.familyHistoryDetails
            )
        }
    }

    // 健康病史与症状记录中的症状观察 / 随访单题页。
    private var symptomFollowUpStep: some View {
        MedicalGuideStepShell(
            title: "当前症状",
            subtitle: "记录近期的身体不适，以便在后续复查或就医时提供准确参考。",
            step: 15,
            total: viewModel.totalGuideSteps,
            isLoading: viewModel.isSaving,
            primaryTitle: symptomFollowUpPrimaryTitle,
            primaryEnabled: viewModel.canAdvanceFromSymptomFollowUp,
            onSkip: {
                viewModel.hasPrefilledSymptomFollowUp = true
                nextVisibleHistory(after: .symptomFollowUp)
            },
            onNext: {
                viewModel.hasPrefilledSymptomFollowUp = true
                nextVisibleHistory(after: .symptomFollowUp)
            }
        ) {
            MemberMedicalSymptomFollowUpStepView(
                viewModel: viewModel,
                symptomStatus: $viewModel.symptomFollowUpStatus,
                medicalDocumentUploadViewModel: homeDependencies.memberFlowMedicalDocumentUploadViewModel,
                aiSettingsViewModel: homeDependencies.aiSettingsViewModel
            )
        }
    }

    private var symptomFollowUpPrimaryTitle: String {
        switch viewModel.symptomFollowUpStatus {
        case .none:
            return "下一步"
        case .have:
            return "保存症状记录"
        case .unknown:
            return "下一步"
        }
    }

    // 健康病史与症状记录汇总页，点击任意卡片回到对应问题，便于逐项补充或修改。
    private var historySummaryStep: some View {
        MedicalGuideStepShell(
            title: "健康档案总览",
            subtitle: "您的核心健康基线已盘点完毕。系统已将您的日常症状、既往史、用药、手术、过敏及家族史进行多维整合，正用于为您量身定制 AI 深度体检方案。",
            step: 16,
            total: viewModel.totalGuideSteps,
            isLoading: viewModel.isSaving,
            primaryTitle: historySummaryPrimaryTitle,
            showsSkipButton: false,
            onSkip: {},
            onNext: {
                Task {
                    await viewModel.saveProgress()
                    proceedFromSectionSummary(.historySummary, fullFlowNext: .lifestyle)
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 18) {
                Text("已录入的健康医疗档案")
                    .font(.headline.weight(.semibold))

                ForEach(viewModel.healthHistoryOverviewCards) { card in
                    MedicalGuideOverviewCardView(card: card) {
                        navigateToHistoryOverviewCard(card.id)
                    }
                }
            }
        }
    }

    private var historySummaryPrimaryTitle: String {
        if isSectionMode && entryMode == .healthHistory {
            return "确认，去生成定制体检计划"
        }
        return "下一步"
    }

    private func navigateToHistoryOverviewCard(_ cardID: String) {
        switch cardID {
        case "symptom":
            path.append(.symptomFollowUp)
        case "chronic":
            path.append(.chronicConditions)
        case "medication":
            path.append(.longTermMedication)
        case "surgery":
            path.append(.surgeryHistory)
        case "allergy":
            path.append(.allergyHistory)
        case "family":
            path.append(.familyHistory)
        default:
            break
        }
    }

    // 生活习惯先给出说明，再拆成吸烟、饮酒、运动和睡眠四个单题页。
    private var lifestyleIntroStep: some View {
        MedicalGuideIntroPageView(
            kind: .lifestyle,
            title: "日常生活习惯",
            subtitle: "了解您的日常作息与生活方式，有助于更精准地评估心血管与代谢机能，并为您生成每天都能轻松执行的健康改善建议。",
            isLoading: viewModel.isSaving,
            primaryTitle: "开始",
            secondaryTitle: "稍后在设置中完善",
            onStart: { nextVisibleLifestyle(after: .lifestyle) },
            onLater: {
                if isSectionMode {
                    dismiss()
                } else {
                    path.append(.examArchiveIntro)
                }
            },
            onClose: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("将包含以下记录")
                    .font(.headline.weight(.semibold))

                MedicalGuideGroupedCard {
                    MedicalGuideListRow(icon: "smoke.fill", tint: .orange, title: "吸烟与饮酒习惯", subtitle: "频率 / 剂量")
                    Divider()
                    MedicalGuideListRow(icon: "figure.run", tint: .green, title: "每周运动状况", subtitle: "频次 / 强度")
                    Divider()
                    MedicalGuideListRow(icon: "bed.double.fill", tint: .indigo, title: "平均睡眠时长与质量", subtitle: "")
                }

                HStack(alignment: .top, spacing: 8) {
                    Text("💡")
                        .font(.footnote)
                    Text("贴心提示：诚实记录是对自己负责的第一步。即使现在的习惯不够完美也没关系，Look健康会陪你一起逐步改善。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // 吸烟单题页。
    private var smokingStep: some View {
        MedicalGuideStepShell(
            title: "吸烟习惯",
            subtitle: "评估吸烟习惯有助于精准预测心血管健康、肺部代谢及肿瘤潜在风险，从而为您定制更科学的专项体检防御方案。",
            step: 18,
            total: viewModel.totalGuideSteps,
            isLoading: viewModel.isSaving,
            onSkip: {
                viewModel.hasPrefilledSmokingStatus = true
                nextVisibleLifestyle(after: .smoking)
            },
            onNext: {
                viewModel.hasPrefilledSmokingStatus = true
                nextVisibleLifestyle(after: .smoking)
            }
        ) {
            VStack(alignment: .leading, spacing: 20) {
                Text("吸烟状态")
                    .font(.headline.weight(.semibold))

                MedicalGuideSegmentedPicker(
                    items: MedicalGuideSmokingStatus.allCases.map { ($0.title, $0.rawValue) },
                    selection: Binding(
                        get: { viewModel.smokingStatus.rawValue },
                        set: { viewModel.smokingStatus = MedicalGuideSmokingStatus(rawValue: $0) ?? .never }
                    )
                )

                if viewModel.smokingStatus != .never {
                    MedicalHabitGroupedDetailCard {
                        MedicalHabitMenuPickerRow(
                            icon: "clock.fill",
                            title: "历史吸烟时长",
                            placeholder: "例：5年、10年...",
                            selection: $viewModel.smokingHistoryDuration,
                            options: MedicalLifestyleOptionCatalog.smokingHistoryDurations
                        )

                        if viewModel.smokingStatus == .quit {
                            Divider()
                            MedicalHabitMenuPickerRow(
                                icon: "nosign",
                                title: "已戒烟时长",
                                placeholder: "例：2年，可不填",
                                selection: $viewModel.smokingQuitDuration,
                                options: MedicalLifestyleOptionCatalog.quitDurations
                            )
                        }

                        if viewModel.smokingStatus == .sometimes || viewModel.smokingStatus == .often {
                            Divider()
                            MedicalHabitMenuPickerRow(
                                icon: "smoke.fill",
                                title: "平均每日吸烟量",
                                placeholder: "例：半包/日、5支/日...",
                                selection: $viewModel.smokingCount,
                                options: MedicalLifestyleOptionCatalog.dailySmokingAmounts
                            )
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: viewModel.smokingStatus)
        }
    }

    // 饮酒单题页。
    private var drinkingStep: some View {
        MedicalGuideStepShell(
            title: "饮酒习惯",
            subtitle: "了解日常饮酒频率能够协助我们科学评估您的肝脏代谢负荷与血压波动趋势，以便在体检推荐中为您规避或加强特定项目的筛查。",
            step: 19,
            total: viewModel.totalGuideSteps,
            isLoading: viewModel.isSaving,
            onSkip: {
                viewModel.hasPrefilledDrinkingStatus = true
                nextVisibleLifestyle(after: .drinking)
            },
            onNext: {
                viewModel.hasPrefilledDrinkingStatus = true
                nextVisibleLifestyle(after: .drinking)
            }
        ) {
            VStack(alignment: .leading, spacing: 20) {
                Text("饮酒频率")
                    .font(.headline.weight(.semibold))

                MedicalGuideSegmentedPicker(
                    items: MedicalGuideDrinkingStatus.allCases.map { ($0.title, $0.rawValue) },
                    selection: Binding(
                        get: { viewModel.drinkingStatus.rawValue },
                        set: { viewModel.drinkingStatus = MedicalGuideDrinkingStatus(rawValue: $0) ?? .none }
                    )
                )

                if viewModel.drinkingStatus != .none {
                    MedicalHabitGroupedDetailCard {
                        MedicalHabitMenuPickerRow(
                            icon: "calendar",
                            title: "历史饮酒年限",
                            placeholder: "例：3年、8年...",
                            selection: $viewModel.drinkingHistoryDuration,
                            options: MedicalLifestyleOptionCatalog.drinkingHistoryDurations
                        )

                        if viewModel.drinkingStatus == .quit {
                            Divider()
                            MedicalHabitMenuPickerRow(
                                icon: "nosign",
                                title: "已戒酒时长",
                                placeholder: "例：1年，可不填",
                                selection: $viewModel.drinkingQuitDuration,
                                options: MedicalLifestyleOptionCatalog.quitDurations
                            )
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            Label("常见饮酒类型 (可多选)", systemImage: "wineglass.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            MedicalPickerChipGrid(
                                items: MemberMedicalSetupViewModel.presetDrinkingTypes,
                                selections: $viewModel.drinkingTypes
                            )
                        }
                        .padding(.vertical, 4)

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Label("其他偏好酒类 (自定义输入)", systemImage: "plus.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            TextField("请输入其他酒类名称，如：自酿药酒、鸡尾酒...", text: $viewModel.customAlcoholType)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.vertical, 4)

                        if viewModel.drinkingStatus == .occasionally || viewModel.drinkingStatus == .often {
                            Divider()

                            VStack(alignment: .leading, spacing: 12) {
                                Label("平均单次饮酒量", systemImage: "scalemass.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)

                                MedicalLifestyleDrinkingAmountPicker(
                                    selection: $viewModel.drinkingAmountLevel
                                )
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: viewModel.drinkingStatus)
        }
    }

    // 每周运动单题页。
    private var exerciseStep: some View {
        MedicalGuideStepShell(
            title: "运动习惯",
            subtitle: "合理的运动评估能帮助我们了解您的基础代谢率、肌肉质量与心肺耐力，从而为您提供更具针对性的体重管理与防病运动处方。",
            step: 20,
            total: viewModel.totalGuideSteps,
            isLoading: viewModel.isSaving,
            onSkip: {
                viewModel.hasPrefilledExerciseFrequency = true
                nextVisibleLifestyle(after: .exercise)
            },
            onNext: {
                viewModel.hasPrefilledExerciseFrequency = true
                nextVisibleLifestyle(after: .exercise)
            }
        ) {
            VStack(alignment: .leading, spacing: 20) {
                Text("每周运动频率")
                    .font(.headline.weight(.semibold))

                MedicalGuideSegmentedPicker(
                    items: MedicalGuideExerciseFrequency.allCases.map { ($0.title, $0.rawValue) },
                    selection: Binding(
                        get: { viewModel.exerciseFrequency.rawValue },
                        set: { viewModel.exerciseFrequency = MedicalGuideExerciseFrequency(rawValue: $0) ?? .oneToTwo }
                    )
                )

                if viewModel.exerciseFrequency != .none {
                    MedicalHabitGroupedDetailCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("运动强度感知", systemImage: "bolt.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            MedicalLifestyleIntensityPicker(
                                selection: Binding(
                                    get: { viewModel.exerciseIntensity.rawValue },
                                    set: { viewModel.exerciseIntensity = MedicalGuideExerciseIntensity(rawValue: $0) ?? .medium }
                                )
                            )
                        }
                        .padding(.vertical, 4)

                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            Label("习惯运动类型 (可多选)", systemImage: "figure.run")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            MedicalPickerChipGrid(
                                items: MemberMedicalSetupViewModel.presetExerciseTypes,
                                selections: $viewModel.exerciseTypes
                            )
                        }
                        .padding(.vertical, 4)

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Label("其他运动方式 (自定义输入)", systemImage: "plus.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            TextField("请输入其他运动，如：八段锦、攀岩、冲浪...", text: $viewModel.customExerciseType)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.vertical, 4)

                        Divider()

                        MedicalHabitMenuPickerRow(
                            icon: "timer",
                            title: "单次平均运动时长",
                            placeholder: "例：30分钟、1小时...",
                            selection: $viewModel.exerciseDurationMinutes,
                            options: MedicalLifestyleOptionCatalog.exerciseDurations
                        )
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: viewModel.exerciseFrequency)
        }
    }

    // 平均睡眠单题页。
    private var sleepStep: some View {
        MedicalGuideStepShell(
            title: "睡眠状况",
            subtitle: "高质量的睡眠是神经系统修复、免疫因子生成与血糖稳定的基石。记录您的日常睡眠，有助于我们全面分析您的日常精力与亚健康状态。",
            step: 21,
            total: viewModel.totalGuideSteps,
            isLoading: viewModel.isSaving,
            onSkip: {
                viewModel.hasPrefilledSleepHours = true
                nextVisibleLifestyle(after: .sleep)
            },
            onNext: {
                viewModel.hasPrefilledSleepHours = true
                nextVisibleLifestyle(after: .sleep)
            }
        ) {
            VStack(alignment: .leading, spacing: 20) {
                Text("每日平均睡眠时长")
                    .font(.headline.weight(.semibold))

                MedicalLifestyleSleepSliderCard(hours: $viewModel.sleepHours)

                VStack(alignment: .leading, spacing: 12) {
                    Label("睡眠质量自我感知", systemImage: "bed.double.fill")
                        .font(.headline.weight(.semibold))

                    Text("您的夜间睡眠通常感觉")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    MedicalLifestyleSleepQualityPicker(
                        selection: Binding(
                            get: { viewModel.sleepQuality?.rawValue ?? "" },
                            set: { newValue in
                                viewModel.sleepQuality = MedicalGuideSleepQuality(rawValue: newValue)
                                viewModel.hasPrefilledSleepQuality = newValue.isEmpty == false
                            }
                        )
                    )
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
            }
        }
    }

    // 生活习惯汇总页，点击任意卡片回到对应问题，便于逐项补充或修改。
    private var lifestyleSummaryStep: some View {
        MedicalGuideStepShell(
            title: "生活习惯总览",
            subtitle: "感谢您完成生活习惯评估。这些精细的日常行为数据，将与您的病史、用药深度整合，帮助 AI 为您制定更具针对性的体检防御方案。",
            step: 22,
            total: viewModel.totalGuideSteps,
            isLoading: viewModel.isSaving,
            primaryTitle: lifestyleSummaryPrimaryTitle,
            showsSkipButton: false,
            onSkip: {},
            onNext: {
                Task {
                    await viewModel.saveProgress()
                    proceedFromSectionSummary(.lifestyleSummary, fullFlowNext: .examArchiveIntro)
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 18) {
                Text("已为您生成的健康行为档案")
                    .font(.headline.weight(.semibold))

                ForEach(viewModel.lifestyleOverviewCards) { card in
                    MedicalGuideOverviewCardView(card: card) {
                        navigateToLifestyleOverviewCard(card.id)
                    }
                }
            }
        }
    }

    private var lifestyleSummaryPrimaryTitle: String {
        if isSectionMode && entryMode == .lifestyle {
            return "确认并生成健康报告"
        }
        return "下一步"
    }

    private func navigateToLifestyleOverviewCard(_ cardID: String) {
        switch cardID {
        case "smoking":
            path.append(.smoking)
        case "drinking":
            path.append(.drinking)
        case "exercise":
            path.append(.exercise)
        case "sleep":
            path.append(.sleep)
        default:
            break
        }
    }

    private var examArchiveIntroStep: some View {
        MedicalGuideIntroPageView(
            kind: .examArchive,
            title: "过往体检档案",
            subtitle: "整合并追踪你的体检报告，能让我们为你绘制出核心指标的长期变化趋势图，并及时提供科学的复查建议。",
            isLoading: viewModel.isSaving,
            primaryTitle: "开始",
            secondaryTitle: "稍后在设置中完善",
            onStart: { nextVisibleExam(after: .examArchiveIntro) },
            onLater: {
                if isSectionMode {
                    dismiss()
                } else {
                    path.append(.examPlan)
                }
            },
            onClose: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("档案建立方式")
                    .font(.headline.weight(.semibold))

                MedicalGuideGroupedCard {
                    MedicalGuideListRow(icon: "calendar", tint: .blue, title: "最近一次体检时间", subtitle: "")
                    Divider()
                    MedicalGuideListRow(icon: "exclamationmark.triangle.fill", tint: .orange, title: "已知的主要异常指标", subtitle: "如结节、囊肿、三高")
                    Divider()
                    MedicalGuideListRow(icon: "camera.viewfinder", tint: .green, title: "纸质报告智能解析", subtitle: "支持直接拍照或上传截图录入")
                }

                HStack(alignment: .top, spacing: 8) {
                    Text("💡")
                        .font(.footnote)
                    Text("贴心提示：如果手头暂时没有体检报告，可以先跳过，随时可以在首页使用“拍照识别”功能一键补全。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("隐私与安全承诺")
                    .font(.headline.weight(.semibold))

                MedicalGuideGroupedCard {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.accent)
                            .frame(width: 28)
                        Text("端到端加密保护")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                Text("我们承诺你的体检数据仅保存在你的个人健康账户中，享受最高级别的隐私安全保护。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var examArchiveStep: some View {
        Group {
            if viewModel.member?.id != nil {
                MedicalGuideStepShell(
                    title: "体检档案",
                    subtitle: "整合并追踪你的体检报告，能让我们为你绘制出核心指标的长期变化趋势图，并及时提供科学的复查建议。",
                    step: 24,
                    total: viewModel.totalGuideSteps,
                    isLoading: viewModel.isSaving,
                    primaryTitle: examArchivePrimaryTitle,
                    onSkip: { proceedAfterExamArchiveStep() },
                    onNext: { proceedAfterExamArchiveStep() }
                ) {
                    MemberMedicalExamArchiveStepView(
                        viewModel: viewModel,
                        hasExamHistory: $viewModel.hasExamHistory,
                        medicalQueryAPI: homeDependencies.medicalQueryAPI,
                        fileTransferService: homeDependencies.fileTransferService,
                        memberContextStore: homeDependencies.memberContextStore,
                        medicalDocumentUploadViewModel: homeDependencies.memberFlowMedicalDocumentUploadViewModel,
                        aiSettingsViewModel: homeDependencies.aiSettingsViewModel,
                        notificationClient: homeDependencies.notificationClient
                    )
                }
            } else {
                MedicalGuideStepShell(
                    title: "体检档案",
                    subtitle: "整合并追踪你的体检报告，能让我们为你绘制出核心指标的长期变化趋势图，并及时提供科学的复查建议。",
                    step: 24,
                    total: viewModel.totalGuideSteps,
                    isLoading: viewModel.isSaving,
                    primaryTitle: examArchivePrimaryTitle,
                    onSkip: { proceedAfterExamArchiveStep() },
                    onNext: { proceedAfterExamArchiveStep() }
                ) {
                    Text("缺少成员信息，无法加载体检档案。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var examArchivePrimaryTitle: String {
        if viewModel.hasExamHistory {
            return "完成体检档案"
        }
        return "下一步"
    }

    private var examArchiveSummaryStep: some View {
        MedicalGuideStepShell(
            title: "过往体检档案",
            subtitle: "为什么要汇总？\n这里会统一确认体检档案、关键指标与下一次体检计划，便于继续进入后续风险评估。",
            step: 25,
            total: viewModel.totalGuideSteps,
            isLoading: viewModel.isSaving,
            primaryTitle: isSectionMode && entryMode == .examArchive ? "完成" : "下一步",
            onSkip: {
                Task {
                    await viewModel.saveProgress()
                    proceedFromSectionSummary(.examArchiveSummary, fullFlowNext: .riskAssessment)
                }
            },
            onNext: {
                Task {
                    await viewModel.saveProgress()
                    proceedFromSectionSummary(.examArchiveSummary, fullFlowNext: .riskAssessment)
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text("已填写内容")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(viewModel.examArchiveSummary)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 14) {
                    summaryRow(title: "过往体检档案说明", value: "已完成") { path.append(.examArchiveIntro) }
                    summaryRow(title: "是否做过体检", value: viewModel.hasExamHistory ? "是" : "否") { path.append(.examArchive) }
                    if viewModel.hasExamHistory {
                        if viewModel.memberHealthExamReports.isEmpty == false {
                            summaryRow(
                                title: "体检报告列表",
                                value: "\(viewModel.memberHealthExamReports.count) 份"
                            ) { path.append(.examArchive) }
                        }
                        summaryRow(
                            title: "最近一次体检",
                            value: viewModel.lastExamYear.isEmpty ? "未填写" : MemberMedicalSetupViewModel.displayYearMonth(viewModel.lastExamYear)
                        ) { path.append(.examArchive) }
                        summaryRow(title: "体检机构", value: viewModel.examInstitution.isEmpty ? "未填写" : viewModel.examInstitution) { path.append(.examArchive) }
                        summaryRow(title: "体检报告摘要", value: viewModel.examReportSummary.isEmpty ? "未填写" : "已填写") { path.append(.examArchive) }
                    }
                    summaryRow(
                        title: "体检指标",
                        value: viewModel.hasExamHistory ? viewModel.keyIndicatorSummary : "无体检史，已跳过"
                    ) {
                        if viewModel.hasExamHistory {
                            path.append(.keyIndicatorSummary)
                        } else {
                            path.append(.examArchive)
                        }
                    }
                    summaryRow(title: "下一次体检计划", value: viewModel.examPlanSummary) { path.append(.examPlan) }
                }
            }
        }
    }

    private var keyIndicatorStep: some View {
        MedicalGuideStepShell(
            title: "体检指标",
            subtitle: "记录需要重点关注的体检项目，后续可用于风险评估与体检计划生成。",
            step: 26,
            total: viewModel.totalGuideSteps,
            isLoading: viewModel.isSaving,
            primaryTitle: "下一步",
            onSkip: { path.append(.keyIndicatorSummary) },
            onNext: { path.append(.keyIndicatorSummary) }
        ) {
            VStack(spacing: 14) {
                ForEach($viewModel.keyIndicatorRows) { $row in
                    questionCard(title: row.title) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                TextField("数值", text: $row.value)
                                    .textFieldStyle(.roundedBorder)
                                Text(row.unit.isEmpty ? "" : row.unit)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if row.referenceRange.isEmpty == false {
                                Text("参考：\(row.referenceRange)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var keyIndicatorSummaryStep: some View {
        MedicalGuideStepShell(
            title: "体检指标",
            subtitle: "为什么要问？\n关键指标会帮助系统做风险评估并细化体检计划。",
            step: 27,
            total: viewModel.totalGuideSteps,
            isLoading: viewModel.isSaving,
            primaryTitle: "下一步",
            onSkip: {
                Task {
                    await viewModel.saveProgress()
                    proceedAfterKeyIndicatorSummary()
                }
            },
            onNext: {
                Task {
                    await viewModel.saveProgress()
                    proceedAfterKeyIndicatorSummary()
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text("已填写内容")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(viewModel.keyIndicatorSummary)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 14) {
                    summaryRow(title: "体检指标", value: viewModel.keyIndicatorSummary) { path.append(.keyIndicators) }
                }
            }
        }
    }

    private var riskAssessmentStep: some View {
        MedicalGuideStepShell(
            title: "风险评估",
            subtitle: "系统将根据基础信息、病史与关键指标生成风险提示。",
            step: 29,
            total: viewModel.totalGuideSteps,
            isLoading: viewModel.isSaving,
            onSkip: {
                Task {
                    await viewModel.saveProgress()
                    if isSectionMode && entryMode == .riskAssessment {
                        finishCurrentSection()
                    } else {
                        advance(from: .riskAssessment)
                    }
                }
            },
            onNext: {
                Task {
                    await viewModel.saveProgress()
                    if isSectionMode && entryMode == .riskAssessment {
                        finishCurrentSection()
                    } else {
                        advance(from: .riskAssessment)
                    }
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(viewModel.riskAssessmentLines, id: \.self) { line in
                    Label(line, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    private var examPlanStep: some View {
        MedicalGuideStepShell(
            title: "过往体检档案",
            subtitle: "系统会结合体检历史、关键指标与风险提示，生成下一次体检计划。",
            step: 28,
            total: viewModel.totalGuideSteps,
            isLoading: viewModel.isSaving,
            onSkip: {
                path.append(.examArchiveSummary)
            },
            onNext: {
                path.append(.examArchiveSummary)
            }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text("系统生成的下一次体检计划")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(viewModel.examPlanLines, id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var summaryPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MemberSetupStepHeaderView(
                    title: "医疗模块",
                    subtitle: "分步维护慢病、用药、生活习惯、体检和症状随访",
                    step: 30,
                    total: viewModel.totalGuideSteps
                )

                questionCard(title: "已填写内容") {
                    Text(summaryText)
                        .font(.title3.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 14) {
                    summaryRow(title: "基础档案说明", value: "已完成") { path.append(.intro) }
                    summaryRow(title: "性别", value: viewModel.genderDisplayTitle) { path.append(.gender) }
                    summaryRow(title: "出生日期", value: viewModel.birthDate.map { Self.dateFormatter.string(from: $0) } ?? "未填写") { path.append(.birthDate) }
                    summaryRow(title: "身高", value: viewModel.heightCm > 0 ? String(format: "%.0f cm", viewModel.heightCm) : "未填写") { path.append(.height) }
                    summaryRow(title: "体重", value: viewModel.weightKg > 0 ? String(format: "%.1f kg", viewModel.weightKg) : "未填写") { path.append(.weight) }
                    summaryRow(title: "职业", value: viewModel.occupation.isEmpty ? "未填写" : viewModel.occupation) { path.append(.occupation) }
                    summaryRow(title: "久坐时间", value: viewModel.sedentaryLevel?.title ?? "未填写") { path.append(.sedentary) }
                    summaryRow(title: "健康病史与症状记录说明", value: viewModel.historyIntroSummaryText) { path.append(.history) }
                    summaryRow(title: "症状观察 / 随访", value: viewModel.symptomSummary) { path.append(.symptomFollowUp) }
                    summaryRow(title: "既往疾病", value: viewModel.chronicConditionsSummary) { path.append(.chronicConditions) }
                    summaryRow(title: "长期用药", value: viewModel.longTermMedicationSummary) { path.append(.longTermMedication) }
                    summaryRow(title: "手术史", value: viewModel.surgerySummary) { path.append(.surgeryHistory) }
                    summaryRow(title: "过敏史", value: viewModel.allergySummary) { path.append(.allergyHistory) }
                    summaryRow(title: "健康病史与症状记录汇总", value: viewModel.historySummary) { path.append(.historySummary) }
                    summaryRow(title: "家族病史", value: viewModel.familyHistorySummary) { path.append(.familyHistory) }
                    summaryRow(title: "生活习惯", value: viewModel.lifestyleSummary) { path.append(.lifestyleSummary) }
                    summaryRow(title: "过往体检档案 · 下一次体检计划", value: viewModel.examPlanSummary) { path.append(.examPlan) }
                    summaryRow(
                        title: "体检指标",
                        value: viewModel.hasExamHistory ? viewModel.keyIndicatorSummary : "无体检史，已跳过"
                    ) {
                        if viewModel.hasExamHistory {
                            path.append(.keyIndicatorSummary)
                        } else {
                            path.append(.examArchive)
                        }
                    }
                    summaryRow(title: "过往体检档案汇总", value: viewModel.examArchiveSummary) { path.append(.examArchiveSummary) }
                    summaryRow(title: "风险评估", value: viewModel.riskAssessmentSummary) { path.append(.riskAssessment) }
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
            .padding(.bottom, 120)
        }
        .navigationTitle("医疗模块")
        .navigationBarTitleDisplayMode(.inline)
        .memberSetupBottomBar(
            primaryTitle: "保存",
            primaryEnabled: viewModel.canSave,
            isLoading: viewModel.isSaving,
            onPrimary: {
                Task {
                    if let summary = await viewModel.save() {
                        onCompleted(summary)
                        dismiss()
                    }
                }
            },
            secondaryTitle: "跳过",
            onSecondary: {
                dismiss()
            }
        )
    }

    private var summaryText: String {
        [
            viewModel.basicInfoSummary,
            viewModel.historySummary,
            viewModel.familyHistorySummary,
            viewModel.lifestyleSummary,
            viewModel.examArchiveSummary,
            viewModel.hasExamHistory ? viewModel.keyIndicatorSummary : "无体检史，体检指标已跳过",
            viewModel.symptomSummary,
            viewModel.riskAssessmentSummary,
            viewModel.examPlanSummary
        ]
        .joined(separator: " · ")
    }

    private func applyEntryRouteIfNeeded() {
        guard didApplyEntryRoute == false else { return }
        didApplyEntryRoute = true
        guard isSectionMode else { return }
        switch entryMode {
        case .full, .basicProfile:
            break
        case .healthHistory:
            path = [.history]
        case .lifestyle:
            path = [.lifestyle]
        case .examArchive:
            path = [.examArchiveIntro]
        case .riskAssessment:
            path = [.riskAssessment]
        }
    }

    private func sectionSummary(for mode: MedicalSetupEntryMode) -> String {
        switch mode {
        case .full:
            return summaryText
        case .basicProfile:
            return viewModel.basicInfoSummaryText
        case .healthHistory:
            return viewModel.historySummary
        case .lifestyle:
            return viewModel.lifestyleSummary
        case .examArchive:
            return viewModel.examArchiveSummary
        case .riskAssessment:
            return viewModel.riskAssessmentSummary
        }
    }

    private func isTerminalRoute(_ route: MedicalGuideRoute) -> Bool {
        switch entryMode {
        case .full:
            return false
        case .basicProfile:
            return route == .basicSummary
        case .healthHistory:
            return route == .historySummary
        case .lifestyle:
            return route == .lifestyleSummary
        case .examArchive:
            return route == .examArchiveSummary
        case .riskAssessment:
            return route == .riskAssessment
        }
    }

    private func finishCurrentSection() {
        onSectionCompleted(entryMode, sectionSummary(for: entryMode))
        dismiss()
    }

    private func proceedFromSectionSummary(_ route: MedicalGuideRoute, fullFlowNext: MedicalGuideRoute) {
        if isSectionMode && isTerminalRoute(route) {
            finishCurrentSection()
        } else {
            path.append(fullFlowNext)
        }
    }

    private var birthDateBinding: Binding<Date> {
        Binding(
            get: { viewModel.birthDate ?? Date() },
            set: { viewModel.birthDate = $0 }
        )
    }

    private func basicInfoPrimaryTitle(after route: MedicalGuideRoute) -> String {
        hasRemainingBasicInfoPage(after: route) ? "下一步" : "完成"
    }

    private func hasRemainingBasicInfoPage(after route: MedicalGuideRoute) -> Bool {
        switch route {
        case .birthDate:
            return viewModel.shouldSkipHeightStep == false
                || viewModel.shouldSkipWeightStep == false
                || viewModel.shouldSkipOccupationStep == false
                || viewModel.shouldSkipSedentaryStep == false
        case .height:
            return viewModel.shouldSkipWeightStep == false
                || viewModel.shouldSkipOccupationStep == false
                || viewModel.shouldSkipSedentaryStep == false
        case .weight:
            return viewModel.shouldSkipOccupationStep == false
                || viewModel.shouldSkipSedentaryStep == false
        case .occupation:
            return viewModel.shouldSkipSedentaryStep == false
        case .sedentary:
            return false
        default:
            return true
        }
    }

    private func historyPrimaryTitle(after route: MedicalGuideRoute) -> String {
        hasRemainingHistoryPage(after: route) ? "下一步" : "完成"
    }

    private func hasRemainingHistoryPage(after route: MedicalGuideRoute) -> Bool {
        switch route {
        case .history:
            return viewModel.shouldSkipSymptomFollowUpStep == false
                || viewModel.shouldSkipChronicConditionsStep == false
                || viewModel.shouldSkipLongTermMedicationStep == false
                || viewModel.shouldSkipSurgeryHistoryStep == false
                || viewModel.shouldSkipAllergyHistoryStep == false
                || viewModel.shouldSkipFamilyHistoryStep == false
        case .symptomFollowUp:
            return viewModel.shouldSkipChronicConditionsStep == false
                || viewModel.shouldSkipLongTermMedicationStep == false
                || viewModel.shouldSkipSurgeryHistoryStep == false
                || viewModel.shouldSkipAllergyHistoryStep == false
                || viewModel.shouldSkipFamilyHistoryStep == false
        case .chronicConditions:
            return viewModel.shouldSkipLongTermMedicationStep == false
                || viewModel.shouldSkipSurgeryHistoryStep == false
                || viewModel.shouldSkipAllergyHistoryStep == false
                || viewModel.shouldSkipFamilyHistoryStep == false
        case .longTermMedication:
            return viewModel.shouldSkipSurgeryHistoryStep == false
                || viewModel.shouldSkipAllergyHistoryStep == false
                || viewModel.shouldSkipFamilyHistoryStep == false
        case .surgeryHistory:
            return viewModel.shouldSkipAllergyHistoryStep == false
                || viewModel.shouldSkipFamilyHistoryStep == false
        case .allergyHistory:
            return viewModel.shouldSkipFamilyHistoryStep == false
        case .familyHistory:
            return false
        default:
            return true
        }
    }

    private func nextVisibleHistory(after route: MedicalGuideRoute) {
        switch route {
        case .history:
            if viewModel.shouldSkipSymptomFollowUpStep {
                nextVisibleHistory(after: .symptomFollowUp)
            } else {
                path.append(.symptomFollowUp)
            }
        case .symptomFollowUp:
            if viewModel.shouldSkipChronicConditionsStep {
                nextVisibleHistory(after: .chronicConditions)
            } else {
                path.append(.chronicConditions)
            }
        case .chronicConditions:
            if viewModel.shouldSkipLongTermMedicationStep {
                nextVisibleHistory(after: .longTermMedication)
            } else {
                path.append(.longTermMedication)
            }
        case .longTermMedication:
            if viewModel.shouldSkipSurgeryHistoryStep {
                nextVisibleHistory(after: .surgeryHistory)
            } else {
                path.append(.surgeryHistory)
            }
        case .surgeryHistory:
            if viewModel.shouldSkipAllergyHistoryStep {
                nextVisibleHistory(after: .allergyHistory)
            } else {
                path.append(.allergyHistory)
            }
        case .allergyHistory:
            if viewModel.shouldSkipFamilyHistoryStep {
                path.append(.historySummary)
            } else {
                path.append(.familyHistory)
            }
        case .familyHistory:
            path.append(.historySummary)
        default:
            path.append(.historySummary)
        }
    }

    private func advance(from route: MedicalGuideRoute) {
        switch route {
        case .intro:
            path.append(.gender)
        case .gender:
            nextVisible(after: .gender)
        case .birthDate:
            nextVisible(after: .birthDate)
        case .height:
            nextVisible(after: .height)
        case .weight:
            nextVisible(after: .weight)
        case .occupation:
            nextVisible(after: .occupation)
        case .sedentary:
            nextVisible(after: .sedentary)
        case .basicSummary:
            if isSectionMode && entryMode == .basicProfile {
                finishCurrentSection()
            } else {
                path.append(.history)
            }
        case .history:
            nextVisibleHistory(after: .history)
        case .chronicConditions:
            nextVisibleHistory(after: .chronicConditions)
        case .longTermMedication:
            nextVisibleHistory(after: .longTermMedication)
        case .surgeryHistory:
            nextVisibleHistory(after: .surgeryHistory)
        case .allergyHistory:
            nextVisibleHistory(after: .allergyHistory)
        case .familyHistory:
            nextVisibleHistory(after: .familyHistory)
        case .symptomFollowUp:
            nextVisibleHistory(after: .symptomFollowUp)
        case .historySummary:
            if isSectionMode && entryMode == .healthHistory {
                finishCurrentSection()
            } else {
                path.append(.lifestyle)
            }
        case .lifestyle:
            nextVisibleLifestyle(after: .lifestyle)
        case .smoking:
            nextVisibleLifestyle(after: .smoking)
        case .drinking:
            nextVisibleLifestyle(after: .drinking)
        case .exercise:
            nextVisibleLifestyle(after: .exercise)
        case .sleep:
            nextVisibleLifestyle(after: .sleep)
        case .lifestyleSummary:
            if isSectionMode && entryMode == .lifestyle {
                finishCurrentSection()
            } else {
                path.append(.examArchiveIntro)
            }
        case .examArchiveIntro:
            nextVisibleExam(after: .examArchiveIntro)
        case .examArchive:
            proceedAfterExamArchiveStep()
        case .examArchiveSummary:
            if isSectionMode && entryMode == .examArchive {
                finishCurrentSection()
            } else {
                path.append(.riskAssessment)
            }
        case .keyIndicators:
            path.append(.keyIndicatorSummary)
        case .keyIndicatorSummary:
            proceedAfterKeyIndicatorSummary()
        case .examPlan:
            path.append(.examArchiveSummary)
        case .riskAssessment:
            if isSectionMode && entryMode == .riskAssessment {
                finishCurrentSection()
            } else {
                path.append(.summary)
            }
        case .summary:
            break
        }
    }

    private func nextVisible(after route: MedicalGuideRoute) {
        switch route {
        case .intro:
            if viewModel.shouldSkipGenderStep {
                nextVisible(after: .gender)
            } else {
                path.append(.gender)
            }
        case .gender:
            viewModel.refreshDefaultBodyMetricsIfNeeded()
            if viewModel.shouldSkipBirthDateStep {
                nextVisible(after: .birthDate)
            } else {
                path.append(.birthDate)
            }
        case .birthDate:
            viewModel.refreshDefaultBodyMetricsIfNeeded()
            if viewModel.shouldSkipHeightStep {
                if viewModel.shouldSkipWeightStep {
                    if viewModel.shouldSkipOccupationStep {
                        if viewModel.shouldSkipSedentaryStep {
                            path.append(.basicSummary)
                        } else {
                            path.append(.sedentary)
                        }
                    } else {
                        path.append(.occupation)
                    }
                } else {
                    path.append(.weight)
                }
            } else {
                path.append(.height)
            }
        case .height:
            if viewModel.shouldSkipWeightStep {
                if viewModel.shouldSkipOccupationStep {
                    if viewModel.shouldSkipSedentaryStep {
                        path.append(.basicSummary)
                    } else {
                        path.append(.sedentary)
                    }
                } else {
                    path.append(.occupation)
                }
            } else {
                path.append(.weight)
            }
        case .weight:
            if viewModel.shouldSkipOccupationStep {
                if viewModel.shouldSkipSedentaryStep {
                    path.append(.basicSummary)
                } else {
                    path.append(.sedentary)
                }
            } else {
                path.append(.occupation)
            }
        case .occupation:
            if viewModel.shouldSkipSedentaryStep {
                path.append(.basicSummary)
            } else {
                path.append(.sedentary)
            }
        case .sedentary:
            path.append(.basicSummary)
        case .basicSummary:
            if isSectionMode && entryMode == .basicProfile {
                finishCurrentSection()
            } else {
                path.append(.history)
            }
        case .history:
            nextVisibleHistory(after: .history)
        case .chronicConditions:
            nextVisibleHistory(after: .chronicConditions)
        case .longTermMedication:
            nextVisibleHistory(after: .longTermMedication)
        case .surgeryHistory:
            nextVisibleHistory(after: .surgeryHistory)
        case .allergyHistory:
            nextVisibleHistory(after: .allergyHistory)
        case .familyHistory:
            nextVisibleHistory(after: .familyHistory)
        case .symptomFollowUp:
            nextVisibleHistory(after: .symptomFollowUp)
        case .historySummary:
            if isSectionMode && entryMode == .healthHistory {
                finishCurrentSection()
            } else {
                path.append(.lifestyle)
            }
        case .lifestyle:
            nextVisibleLifestyle(after: .lifestyle)
        case .smoking:
            nextVisibleLifestyle(after: .smoking)
        case .drinking:
            nextVisibleLifestyle(after: .drinking)
        case .exercise:
            nextVisibleLifestyle(after: .exercise)
        case .sleep:
            nextVisibleLifestyle(after: .sleep)
        case .lifestyleSummary:
            if isSectionMode && entryMode == .lifestyle {
                finishCurrentSection()
            } else {
                path.append(.examArchiveIntro)
            }
        case .examArchiveIntro:
            nextVisibleExam(after: .examArchiveIntro)
        case .examArchive:
            proceedAfterExamArchiveStep()
        case .examArchiveSummary:
            if isSectionMode && entryMode == .examArchive {
                finishCurrentSection()
            } else {
                path.append(.riskAssessment)
            }
        case .keyIndicators:
            path.append(.keyIndicatorSummary)
        case .keyIndicatorSummary:
            proceedAfterKeyIndicatorSummary()
        case .examPlan:
            path.append(.examArchiveSummary)
        case .symptomFollowUp:
            path.append(.historySummary)
        case .riskAssessment:
            if isSectionMode && entryMode == .riskAssessment {
                finishCurrentSection()
            } else {
                path.append(.summary)
            }
        case .summary:
            break
        }
    }

    private func proceedAfterExamArchiveStep() {
        if viewModel.hasExamHistory {
            if viewModel.shouldSkipKeyIndicatorStep {
                proceedAfterKeyIndicatorSummary()
            } else {
                path.append(.keyIndicators)
            }
        } else {
            path.append(.examPlan)
        }
    }

    private func proceedAfterKeyIndicatorSummary() {
        path.append(.examPlan)
    }

    private func nextVisibleExam(after route: MedicalGuideRoute) {
        switch route {
        case .examArchiveIntro:
            if viewModel.shouldSkipExamArchiveStep {
                proceedAfterExamArchiveStep()
            } else {
                path.append(.examArchive)
            }
        case .examArchive:
            proceedAfterExamArchiveStep()
        case .examArchiveSummary:
            if isSectionMode && entryMode == .examArchive {
                finishCurrentSection()
            } else {
                path.append(.riskAssessment)
            }
        case .keyIndicators:
            path.append(.keyIndicatorSummary)
        case .keyIndicatorSummary:
            proceedAfterKeyIndicatorSummary()
        default:
            path.append(.examPlan)
        }
    }

    // 生活习惯也按“逐题可跳过”的方式推进，避免把多个问题塞到同一页。
    private func nextVisibleLifestyle(after route: MedicalGuideRoute) {
        switch route {
        case .lifestyle:
            if viewModel.shouldSkipSmokingStep {
                nextVisibleLifestyle(after: .smoking)
            } else {
                path.append(.smoking)
            }
        case .smoking:
            if viewModel.shouldSkipDrinkingStep {
                nextVisibleLifestyle(after: .drinking)
            } else {
                path.append(.drinking)
            }
        case .drinking:
            if viewModel.shouldSkipExerciseStep {
                nextVisibleLifestyle(after: .exercise)
            } else {
                path.append(.exercise)
            }
        case .exercise:
            if viewModel.shouldSkipSleepStep {
                path.append(.lifestyleSummary)
            } else {
                path.append(.sleep)
            }
        case .sleep:
            path.append(.lifestyleSummary)
        default:
            path.append(.lifestyleSummary)
        }
    }

    private func summaryRow(title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Text(value)
                    .foregroundStyle(value == "未填写" ? .secondary : .primary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func habitLabeledTextField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        questionCard(title: title) {
            TextField(placeholder, text: text)
                .keyboardType(keyboardType)
                .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private func summarySection(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            MedicalSummaryRow(title: title, subtitle: subtitle, isCompleted: subtitle.isEmpty == false && subtitle != "未填写")
        }
        .buttonStyle(.plain)
    }

    private var occupationOptions: [String] {
        [
            "学生", "程序员 / 开发", "产品 / 设计", "办公室文职", "教师 / 教培", "销售 / 商务",
            "医护人员", "公务员 / 事业单位", "企业管理", "财务 / 法务", "司机 / 物流 / 快递",
            "工人 / 制造业", "建筑 / 装修", "农林牧渔", "餐饮 / 服务业", "个体经营 / 店主",
            "自由职业", "家庭主妇 / 主夫", "退休", "其他"
        ]
    }

    private var occupationGroups: [OccupationGroup] {
        [
            .init(icon: "desktopcomputer", tint: .blue, title: "程序员 / 开发 / 产品 / 设计", subtitle: "偏久坐、用脑强度高、常伴随加班与屏幕暴露", value: "程序员 / 开发 / 产品 / 设计"),
            .init(icon: "building.2.fill", tint: .indigo, title: "办公室文职 / 财务 / 法务 / 企业管理", subtitle: "常规办公室工作、久坐明显、节奏相对固定", value: "办公室文职 / 财务 / 法务 / 企业管理"),
            .init(icon: "graduationcap.fill", tint: .orange, title: "教师 / 教培人员", subtitle: "教学授课、站立与沟通较多，作息受课程安排影响", value: "教师 / 教培人员"),
            .init(icon: "cross.case.fill", tint: .red, title: "医护与健康服务人员", subtitle: "倒班、站立、夜班与职业暴露风险相对更高", value: "医护与健康服务人员"),
            .init(icon: "briefcase.fill", tint: .green, title: "销售 / 商务 / 自由职业", subtitle: "出行沟通频繁，作息弹性大，饮食与休息不稳定", value: "销售 / 商务 / 自由职业"),
            .init(icon: "truck.box.fill", tint: .brown, title: "司机 / 物流 / 快递 / 制造业工人", subtitle: "久坐、体力劳动或重复作业并存，作息与负荷差异大", value: "司机 / 物流 / 快递 / 制造业工人")
        ]
    }

    private var filteredOccupationGroups: [OccupationGroup] {
        let keyword = occupationSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard keyword.isEmpty == false else { return occupationGroups }
        return occupationGroups.filter {
            $0.title.localizedCaseInsensitiveContains(keyword)
                || $0.subtitle.localizedCaseInsensitiveContains(keyword)
                || $0.value.localizedCaseInsensitiveContains(keyword)
        }
    }

    private var sedentaryOptions: [(title: String, subtitle: String, color: Color, value: MedicalGuideSedentaryLevel)] {
        [
            ("低", "少于 4 小时", .green, .low),
            ("中", "4 至 8 小时", .yellow, .medium),
            ("高", "超过 8 小时", .red, .high)
        ]
    }

    private var historyDisclosureItems: [(title: String, value: String)] {
        [
            ("有", MedicalGuideDisclosureStatus.have.rawValue),
            ("无", MedicalGuideDisclosureStatus.none.rawValue)
        ]
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private enum MedicalGuideRoute: Hashable {
    case intro
    case gender
    case birthDate
    case height
    case weight
    case occupation
    case sedentary
    case basicSummary
    case history
    case chronicConditions
    case longTermMedication
    case surgeryHistory
    case allergyHistory
    case historySummary
    case familyHistory
    case lifestyle
    case smoking
    case drinking
    case exercise
    case sleep
    case lifestyleSummary
    case examArchiveIntro
    case examArchive
    case examArchiveSummary
    case keyIndicators
    case keyIndicatorSummary
    case symptomFollowUp
    case riskAssessment
    case examPlan
    case summary
}

private struct MedicalGuideStepShell<Content: View>: View {
    let title: String
    let subtitle: String
    let step: Int
    let total: Int
    let isLoading: Bool
    let primaryTitle: String?
    let primaryEnabled: Bool
    let secondaryTitle: String?
    let showsSkipButton: Bool
    let onSkip: () -> Void
    let onNext: () -> Void
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        subtitle: String,
        step: Int,
        total: Int,
        isLoading: Bool,
        primaryTitle: String? = nil,
        primaryEnabled: Bool = true,
        secondaryTitle: String? = nil,
        showsSkipButton: Bool = true,
        onSkip: @escaping () -> Void,
        onNext: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.step = step
        self.total = total
        self.isLoading = isLoading
        self.primaryTitle = primaryTitle
        self.primaryEnabled = primaryEnabled
        self.secondaryTitle = secondaryTitle
        self.showsSkipButton = showsSkipButton
        self.onSkip = onSkip
        self.onNext = onNext
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MemberSetupStepHeaderView(
                    title: title,
                    subtitle: subtitle,
                    step: step,
                    total: total
                )

                content()
            }
            .padding(16)
            .padding(.bottom, 120)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.automatic)
        .memberSetupBottomBar(
            primaryTitle: primaryTitle ?? (step == total ? "保存" : "下一步"),
            primaryEnabled: primaryEnabled && isLoading == false,
            isLoading: isLoading,
            onPrimary: onNext,
            secondaryTitle: showsSkipButton ? (secondaryTitle ?? "跳过") : nil,
            onSecondary: showsSkipButton ? onSkip : nil
        )
    }
}

private struct MedicalGuideOverviewCardView: View {
    let card: MedicalGuideOverviewCardModel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: card.icon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.accent)
                        .frame(width: 28)

                    Text(card.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    Text(card.statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(overviewBadgeForeground(card.statusStyle))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(overviewBadgeBackground(card.statusStyle))
                        )

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(card.bullets) { bullet in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("\(bullet.prefix)：")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(bullet.content)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if let badge = bullet.badge {
                                        Text(badge.text)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(overviewBadgeForeground(badge.style))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(
                                                Capsule(style: .continuous)
                                                    .fill(overviewBadgeBackground(badge.style))
                                            )
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }

    private func overviewBadgeForeground(_ style: MedicalGuideOverviewBadgeStyle) -> Color {
        switch style {
        case .neutral:
            return .secondary
        case .success:
            return .green
        case .warning:
            return .orange
        case .danger:
            return .red
        case .accent:
            return .accentColor
        }
    }

    private func overviewBadgeBackground(_ style: MedicalGuideOverviewBadgeStyle) -> Color {
        overviewBadgeForeground(style).opacity(0.12)
    }
}

private struct MedicalSummaryRow: View {
    let title: String
    let subtitle: String
    let isCompleted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline.weight(.bold))
                    if isCompleted {
                        Text("已完成")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule(style: .continuous).fill(Color.accentColor.opacity(0.12)))
                    }
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

private struct MedicalGuideQuestionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline.weight(.semibold))
            content()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
    }
}

private func questionCard<Content: View>(title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
    MedicalGuideQuestionCard(title: title, content: content)
}

private struct MedicalGuideIllustrationCard: View {
    var body: some View {
        MedicalGuideIntroIllustration(kind: .basicProfile)
    }
}

private struct MedicalGuideIntroPageView<Content: View>: View {
    let kind: MedicalGuideIntroKind
    let title: String
    let subtitle: String
    let isLoading: Bool
    let primaryTitle: String
    let secondaryTitle: String
    let onStart: () -> Void
    let onLater: () -> Void
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            MedicalGuideIntroIllustration(kind: kind)
            VStack(alignment: .leading, spacing: 22) {

                VStack(alignment: .leading, spacing: 12) {
                    Text(title)
                        .font(.system(size: 30, weight: .bold))

                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 140)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                Button {
                    guard isLoading == false else { return }
                    onStart()
                } label: {
                    Text(primaryTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(Color(uiColor: .systemBlue))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    guard isLoading == false else { return }
                    onLater()
                } label: {
                    Text(secondaryTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .background(.regularMaterial)
        }
    }
}

private struct MedicalGuideIntroIllustration: View {
    let kind: MedicalGuideIntroKind

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.12),
                            Color.blue.opacity(0.08),
                            Color.purple.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(Color(uiColor: .systemBackground))
                .frame(width: 142, height: 142)
                .shadow(color: .black.opacity(0.05), radius: 18, y: 10)

            ForEach(kind.illustrationSymbols) { symbol in
                Image(systemName: symbol.systemName)
                    .font(.system(size: symbol.size, weight: symbol.weight))
                    .foregroundStyle(symbol.tint)
                    .symbolRenderingMode(.hierarchical)
                    .rotationEffect(.degrees(symbol.rotationDegrees))
                    .offset(x: symbol.offsetX, y: symbol.offsetY)
                    .shadow(color: symbol.tint.opacity(0.18), radius: 6, y: 3)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: UIScreen.main.bounds.height * 0.3)
    }
}

private struct MedicalGuideIllustrationSymbol: Identifiable {
    let id: String
    let systemName: String
    let size: CGFloat
    let weight: Font.Weight
    let tint: Color
    let offsetX: CGFloat
    let offsetY: CGFloat
    let rotationDegrees: Double

    init(
        systemName: String,
        size: CGFloat,
        weight: Font.Weight = .semibold,
        tint: Color,
        offsetX: CGFloat,
        offsetY: CGFloat,
        rotationDegrees: Double = 0
    ) {
        self.id = "\(systemName)-\(offsetX)-\(offsetY)-\(size)"
        self.systemName = systemName
        self.size = size
        self.weight = weight
        self.tint = tint
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.rotationDegrees = rotationDegrees
    }
}

private enum MedicalGuideIntroKind {
    case basicProfile
    case healthHistory
    case lifestyle
    case examArchive

    var illustrationSymbols: [MedicalGuideIllustrationSymbol] {
        switch self {
        case .basicProfile:
            return [
                .init(systemName: "chart.bar.fill", size: 18, tint: .yellow, offsetX: 18, offsetY: -40),
                .init(systemName: "person.crop.circle.fill", size: 34, tint: .blue, offsetX: -28, offsetY: -6),
                .init(systemName: "scalemass.fill", size: 28, tint: .purple, offsetX: 28, offsetY: -4),
                .init(systemName: "briefcase.fill", size: 24, tint: .orange, offsetX: 0, offsetY: 30)
            ]
        case .healthHistory:
            return [
                .init(systemName: "stethoscope", size: 18, tint: .red, offsetX: 20, offsetY: -40),
                .init(systemName: "list.clipboard.fill", size: 31, tint: .blue, offsetX: -28, offsetY: -5),
                .init(systemName: "pills.fill", size: 29, tint: .pink, offsetX: 29, offsetY: -4, rotationDegrees: -12),
                .init(systemName: "dna", size: 24, tint: .teal, offsetX: 0, offsetY: 30)
            ]
        case .lifestyle:
            return [
                .init(systemName: "lungs.fill", size: 18, tint: .green, offsetX: 18, offsetY: -40),
                .init(systemName: "smoke.fill", size: 30, tint: .orange, offsetX: -28, offsetY: -5),
                .init(systemName: "bed.double.fill", size: 28, tint: .indigo, offsetX: 28, offsetY: -4),
                .init(systemName: "wineglass.fill", size: 23, tint: .purple, offsetX: 0, offsetY: 30)
            ]
        case .examArchive:
            return [
                .init(systemName: "doc.text.fill", size: 18, tint: .blue, offsetX: 18, offsetY: -40),
                .init(systemName: "building.2.fill", size: 29, tint: .teal, offsetX: -28, offsetY: -5),
                .init(systemName: "magnifyingglass", size: 25, tint: .indigo, offsetX: 28, offsetY: -4),
                .init(systemName: "chart.line.uptrend.xyaxis", size: 22, tint: .green, offsetX: 0, offsetY: 30)
            ]
        }
    }
}

private struct MedicalGuideGroupedCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 5) {
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .systemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        )
    }
}

private struct MedicalGuideListRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }
}

private struct MedicalGuideTextRow: View {
    let systemName: String
    let title: String
    let subtitle: String
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    rowContent
                        .contentShape(Rectangle())

                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
        .padding(.vertical, 6)
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemName)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct MedicalGuideFormTextFieldRow: View {
    let systemName: String
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemName)
                .font(.subheadline.weight(.semibold))
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 8)
    }
}

private struct OccupationGroup {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    let value: String
}

private enum MedicalLifestyleOptionCatalog {
    static let smokingHistoryDurations = ["不足1年", "1-3年", "3-5年", "5-10年", "10年以上"]
    static let drinkingHistoryDurations = ["不足1年", "1-3年", "3-5年", "5-10年", "10年以上"]
    static let quitDurations = ["不足6个月", "6个月-1年", "1-2年", "2-5年", "5年以上"]
    static let dailySmokingAmounts = ["几支/日", "半包/日", "1包/日", "1-2包/日", "2包以上/日"]
    static let exerciseDurations = ["15分钟", "30分钟", "45分钟", "1小时", "1小时以上"]
}

private struct MedicalGuideSegmentedPicker: View {
    let items: [(title: String, value: String)]
    @Binding var selection: String

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(items, id: \.value) { item in
                Text(item.title).tag(item.value)
            }
        }
        .pickerStyle(.segmented)
        .onAppear {
            if selection.isEmpty, let first = items.first?.value {
                selection = first
            }
        }
    }
}

private struct MedicalHabitGroupedDetailCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

private struct MedicalHabitMenuPickerRow: View {
    let icon: String
    let title: String
    let placeholder: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if selection.isEmpty {
                    Text(placeholder)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Menu {
                ForEach(options, id: \.self) { option in
                    Button(option) { selection = option }
                }
                if selection.isEmpty == false {
                    Divider()
                    Button("清除", role: .destructive) { selection = "" }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selection.isEmpty ? "请选择" : selection)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selection.isEmpty ? .secondary : .primary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct MedicalLifestyleIntensityPicker: View {
    @Binding var selection: String

    var body: some View {
        VStack(spacing: 10) {
            ForEach(MedicalGuideExerciseIntensity.allCases) { item in
                Button {
                    selection = item.rawValue
                } label: {
                    HStack {
                        Text(item.lifestyleTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selection == item.rawValue ? Color.accentColor : .primary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        if selection == item.rawValue {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(selection == item.rawValue ? Color.accentColor.opacity(0.12) : Color(uiColor: .systemGroupedBackground))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct MedicalLifestyleSleepSliderCard: View {
    @Binding var hours: Double

    private var feedback: (emoji: String, label: String) {
        switch hours {
        case ..<6:
            return ("😴", "睡眠偏少，建议关注作息规律")
        case 6..<7:
            return ("🌙", "接近成人推荐睡眠下限")
        case 7..<8.5:
            return ("💡", "处于成人黄金睡眠区间")
        case 8.5..<10:
            return ("🛌", "睡眠时长充足")
        default:
            return ("⏰", "睡眠偏长，如持续可咨询医生")
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("🌙")
                    .font(.title2)
                Text(String(format: "%.1f 小时", hours))
                    .font(.title2.weight(.bold))
                Text(feedback.label)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            Slider(value: $hours, in: 4...12, step: 0.5)

            HStack {
                Text("4小时")
                Spacer()
                Text("12小时")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

private struct MedicalLifestyleSleepQualityPicker: View {
    @Binding var selection: String

    var body: some View {
        VStack(spacing: 10) {
            ForEach(MedicalGuideSleepQuality.allCases) { item in
                Button {
                    selection = item.rawValue
                } label: {
                    HStack {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selection == item.rawValue ? Color.accentColor : .primary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        if selection == item.rawValue {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(selection == item.rawValue ? Color.accentColor.opacity(0.12) : Color(uiColor: .systemGroupedBackground))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct MedicalLifestyleDrinkingAmountPicker: View {
    @Binding var selection: MedicalGuideDrinkingAmountLevel?

    var body: some View {
        VStack(spacing: 10) {
            ForEach(MedicalGuideDrinkingAmountLevel.allCases) { item in
                Button {
                    selection = item
                } label: {
                    HStack {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selection == item ? Color.accentColor : .primary)
                        Spacer()
                        if selection == item {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(selection == item ? Color.accentColor.opacity(0.12) : Color(uiColor: .systemGroupedBackground))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct MedicalPickerChipRow: View {
    let items: [(title: String, value: String)]
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(items, id: \.value) { item in
                Button {
                    selection = item.value
                } label: {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selection == item.value ? Color.accentColor : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selection == item.value ? Color.accentColor.opacity(0.14) : Color(uiColor: .systemGroupedBackground))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct MedicalPickerChipGrid: View {
    let items: [String]
    @Binding var selections: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(items, id: \.self) { item in
                Button {
                    toggle(item)
                } label: {
                    Text(item)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected(item) ? Color.accentColor : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected(item) ? Color.accentColor.opacity(0.14) : Color(uiColor: .systemBackground))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggle(_ item: String) {
        if item == "无" {
            selections = ["无"]
            return
        }
        if item == "不清楚" {
            if selections.contains(item) {
                selections.removeAll { $0 == item }
            } else {
                selections.removeAll { $0 == "无" }
                selections.append(item)
            }
            return
        }
        selections.removeAll { $0 == "无" || $0 == "不清楚" }
        if selections.contains(item) {
            selections.removeAll { $0 == item }
        } else {
            selections.append(item)
        }
    }

    private func isSelected(_ item: String) -> Bool {
        selections.contains(item)
    }
}

private struct MedicalInputRow: View {
    let title: String
    @Binding var value: Double
    let unit: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 12) {
            TextField(placeholder, value: $value, format: .number.precision(.fractionLength(1)))
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
            Text(unit)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
private extension MemberMedicalSetupViewModel {
    static func preview(member: Member? = nil) -> MemberMedicalSetupViewModel {
        let backend = AppContainer.preview.backend
        let homeDependencies = AppContainer.preview.makeMainTabDependencies(ownerAccountID: 0).homeDependencies
        return MemberMedicalSetupViewModel(
            member: member,
            medicalQueryAPI: backend.medicalQuery,
            setupUseCase: homeDependencies.memberModuleSetupUseCase,
            homeDependencies: homeDependencies
        )
    }
}

#Preview {
    let homeDependencies = AppContainer.preview.makeMainTabDependencies(ownerAccountID: 0).homeDependencies
    CompatibleNavigationContainer {
        MemberMedicalSetupSheetView(
            member: AppContainer.preview.memberContextStore.context.selectedMember,
            medicalQueryAPI: AppContainer.preview.backend.medicalQuery,
            setupUseCase: homeDependencies.memberModuleSetupUseCase,
            homeDependencies: homeDependencies
        ) { summary in
            print(summary)
        }
    }
}
#endif
