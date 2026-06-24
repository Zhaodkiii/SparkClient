import SwiftUI

struct MemberMedicalSetupSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject var viewModel: MemberMedicalSetupViewModel
    @StateObject var examArchiveFlowViewModel: MemberMedicalExamArchiveFlowViewModel
    @State var path: [MedicalGuideRoute] = []
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
        _examArchiveFlowViewModel = StateObject(
            wrappedValue: MemberMedicalExamArchiveFlowViewModel(
                memberID: member?.id ?? 0,
                healthExamReports: preloadedCompleteData?.healthExamReports ?? [],
                medicalQueryAPI: medicalQueryAPI,
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
        // 根页面为「基础档案介绍」；后续步骤通过 path 栈 push 对应 destination。
        CompatibleRouteNavigationContainer(path: $path, legacyStackStyle: true) {
            introStep
        } destination: { route in
            switch route {
            // MARK: - 基础档案
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

            // MARK: - 健康病史与症状记录
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

            // MARK: - 生活习惯
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

            // MARK: - 过往体检档案
            case .examArchiveIntro:
                examArchiveIntroPage
            case .examArchive:
                examArchiveStep
            case .examArchiveReportPicker:
                examArchiveStep // 与 examArchive 共用表单，便于汇总页回跳编辑
            case .examArchiveAIExtractConfirm:
                examArchiveAIExtractConfirmStep
            case .examArchiveFollowUpPlan:
                examArchiveFollowUpPlanStep
            case .examArchivePlanGenerating:
                examArchivePlanGeneratingStep
            case .examArchivePlanResult:
                examArchivePlanResultStep
            case .examArchiveBaselineIntro:
                examArchiveBaselineIntroStep
            case .examArchiveEvidenceConfirm:
                examArchiveEvidenceConfirmStep
            case .examArchiveSummary:
                examArchiveSummaryStep
            case .keyIndicators:
                keyIndicatorStep
            case .keyIndicatorSummary:
                keyIndicatorSummaryStep
            case .symptomFollowUp:
                symptomFollowUpStep

            // MARK: - 全流程收尾
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
            title: L10n.text("member.setup.medical.general.3a771e"),
            subtitle: L10n.text("member.setup.medical.chronic.9134ba"),
            isLoading: viewModel.isSaving,
            primaryTitle: L10n.text("member.setup.common.start"),
            secondaryTitle: L10n.text("member.setup.medical.general.0a096d"),
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
                Text(L10n.text("member.setup.medical.general.41795e"))
                    .font(.headline.weight(.semibold))

                MedicalGuideGroupedCard {
                    MedicalGuideListRow(icon: "person.fill", tint: .blue, title: L10n.text("home.members.field.basic_info"), subtitle: L10n.text("member.setup.medical.general.01a43e"))
                    Divider()
                    MedicalGuideListRow(icon: "scalemass.fill", tint: .purple, title: L10n.text("member.setup.medical.general.ed82bc"), subtitle: L10n.text("member.setup.medical.general.d61e3c"))
                    Divider()
                    MedicalGuideListRow(icon: "briefcase.fill", tint: .orange, title: L10n.text("member.setup.medical.general.58ed75"), subtitle: L10n.text("member.setup.medical.general.2619ca"))
                }

                HStack(alignment: .top, spacing: 8) {
                    Text("💡")
                        .font(.footnote)
                    Text(L10n.text("member.setup.medical.nutrition.5c4542"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text("member.setup.medical.general.a33532"))
                    .font(.headline.weight(.semibold))

                MedicalGuideGroupedCard {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.accent)
                            .frame(width: 28)
                        Text(L10n.text("member.setup.medical.general.5fb46a"))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                Text(L10n.text("member.setup.medical.general.e80ed5"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var genderStep: some View {
        MedicalGuideStepShell(
            title: L10n.text("member.setup.medical.general.787b56"),
            subtitle: L10n.text("member.setup.medical.general.8780a0"),
            step: 2,
            total: viewModel.totalGuideSteps,
            isLoading: viewModel.isSaving,
            onSkip: { nextVisible(after: .gender) },
            onNext: { nextVisible(after: .gender) }
        ) {
            VStack(spacing: 20) {
                Text(L10n.text("member.setup.medical.general.1e90af"))
                    .font(.headline.weight(.semibold))

                MedicalPickerChipRow(
                    items: [
                        (L10n.text("home.members.gender.male"), "male"),
                        (L10n.text("home.members.gender.female"), "female"),
                        (L10n.text("member.setup.medical.general.gender_unknown"), "unknown")
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
            title: L10n.text("member.setup.medical.general.abbe4b"),
            subtitle: L10n.text("member.setup.medical.chronic.93e2dd"),
            step: 3,
            total: viewModel.totalGuideSteps,
            isLoading: viewModel.isSaving,
            primaryTitle: basicInfoPrimaryTitle(after: .birthDate),
            onSkip: { nextVisible(after: .birthDate) },
            onNext: { nextVisible(after: .birthDate) }
        ) {
            VStack(spacing: 18) {
                Text(L10n.text("member.setup.medical.general.7b42f9"))
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
        .navigationTitle(L10n.text("member.setup.medical.nutrition.19a854"))
        .navigationBarTitleDisplayMode(.inline)
        .memberSetupBottomBar(
            primaryTitle: basicInfoPrimaryTitle(after: .height),
            primaryEnabled: viewModel.isSaving == false,
            isLoading: viewModel.isSaving,
            onPrimary: {
                viewModel.confirmHeightSelection()
                nextVisible(after: .height)
            },
            secondaryTitle: L10n.text("common.skip"),
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
        .navigationTitle(L10n.text("member.setup.medical.nutrition.440093"))
        .navigationBarTitleDisplayMode(.inline)
        .memberSetupBottomBar(
            primaryTitle: basicInfoPrimaryTitle(after: .weight),
            primaryEnabled: viewModel.isSaving == false,
            isLoading: viewModel.isSaving,
            onPrimary: {
                viewModel.confirmWeightSelection()
                nextVisible(after: .weight)
            },
            secondaryTitle: L10n.text("common.skip"),
            onSecondary: {
                viewModel.skipWeightSelection()
                nextVisible(after: .weight)
            }
        )
    }

    private var occupationStep: some View {
        MedicalGuideStepShell(
            title: L10n.text("member.setup.medical.general.30f0ce"),
            subtitle: L10n.text("member.setup.medical.general.8508ce"),
            step: 6,
            total: viewModel.totalGuideSteps,
            isLoading: viewModel.isSaving,
            primaryTitle: basicInfoPrimaryTitle(after: .occupation),
            onSkip: { nextVisible(after: .occupation) },
            onNext: { nextVisible(after: .occupation) }
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.text("member.setup.medical.general.35f905"))
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
                        Text(L10n.text("member.setup.medical.general.988ae1"))
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
            title: L10n.text("member.setup.medical.general.6fa270"),
            subtitle: L10n.text("member.setup.medical.general.5ab853"),
            step: 7,
            total: viewModel.totalGuideSteps,
            isLoading: viewModel.isSaving,
            primaryTitle: L10n.text("common.next"),
            primaryEnabled: viewModel.sedentaryLevel != nil,
            onSkip: { nextVisible(after: .sedentary) },
            onNext: { nextVisible(after: .sedentary) }
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.text("member.setup.medical.general.5ab853"))
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

                Text(L10n.text("member.setup.medical.lifestyle.6c9a5c"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var basicInfoSummaryStep: some View {
        MedicalGuideStepShell(
            title: L10n.text("member.setup.medical.guide.feaed5"),
            subtitle: L10n.text("member.setup.medical.general.94ddce"),
            step: 8,
            total: viewModel.totalGuideSteps,
            isLoading: viewModel.isSaving,
            primaryTitle: isSectionMode && entryMode == .basicProfile ? L10n.text("common.done") : "完成",
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
                        title: L10n.text("member.setup.medical.general.787b56"),
                        subtitle: viewModel.genderDisplayTitle,
                        action: {
                            path.append(.gender)
                        }
                    )
                    
                    Divider()
                    
                    MedicalGuideTextRow(
                        systemName: "calendar",
                        title: L10n.text("member.setup.medical.general.abbe4b"),
                        subtitle: viewModel.birthDate.map { Self.dateFormatter.string(from: $0) } ?? L10n.text("member.setup.common.not_filled"),
                        action: {
                            path.append(.birthDate)
                        }
                    )
                }

                MedicalGuideGroupedCard {
                    MedicalGuideTextRow(
                        systemName: "ruler",
                        title: L10n.text("member.setup.medical.nutrition.19a854"),
                        subtitle: viewModel.shouldSkipHeightStep ? (viewModel.heightCm > 0 ? String(format: "%.0f cm", viewModel.heightCm) : "已自动带入") : (viewModel.heightCm > 0 ? String(format: "%.0f cm", viewModel.heightCm) : L10n.text("member.setup.common.not_filled")),
                        action: {
                            path.append(.height)
                        }
                    )
                    Divider()
                    MedicalGuideTextRow(
                        systemName: "scalemass.fill",
                        title: L10n.text("member.setup.medical.nutrition.440093"),
                        subtitle: viewModel.shouldSkipWeightStep ? (viewModel.weightKg > 0 ? String(format: "%.1f kg", viewModel.weightKg) : "已自动带入") : (viewModel.weightKg > 0 ? String(format: "%.1f kg", viewModel.weightKg) : L10n.text("member.setup.common.not_filled")),
                        action: {
                            path.append(.weight)
                        }
                    )
                }

                MedicalGuideGroupedCard {
                    MedicalGuideTextRow(
                        systemName: "briefcase.fill",
                        title: L10n.text("member.setup.medical.general.7379c9"),
                        subtitle: viewModel.occupation.isEmpty ? L10n.text("member.setup.common.not_filled") : viewModel.occupation,
                        action: {
                            path.append(.occupation)
                        }
                    )
                    Divider()
                    MedicalGuideTextRow(
                        systemName: "chair.lounge.fill",
                        title: L10n.text("member.setup.medical.general.6fa270"),
                        subtitle: viewModel.sedentaryLevel?.title ?? L10n.text("member.setup.common.not_filled"),
                        action: {
                            path.append(.sedentary)
                        }
                    )
                }

                HStack(alignment: .top, spacing: 8) {
                    Text("💡")
                        .font(.footnote)
                    Text(L10n.text("member.setup.medical.nutrition.5c4542"))
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
            title: L10n.text("member.setup.medical.symptom.84d7df"),
            subtitle: L10n.text("member.setup.medical.symptom.6b2ca4"),
            isLoading: viewModel.isSaving,
            primaryTitle: L10n.text("member.setup.common.start"),
            secondaryTitle: L10n.text("member.setup.medical.general.0a096d"),
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
                Text(L10n.text("member.setup.medical.general.763be1"))
                    .font(.headline.weight(.semibold))

                MedicalGuideGroupedCard {
                    MedicalGuideListRow(icon: "waveform.path.ecg", tint: .pink, title: L10n.text("member.setup.medical.symptom.c1b96d"), subtitle: "")
                    Divider()
                    MedicalGuideListRow(icon: "cross.case.fill", tint: .red, title: L10n.text("member.setup.medical.chronic.8c6c77"), subtitle: "")
                    Divider()
                    MedicalGuideListRow(icon: "allergens.fill", tint: .orange, title: L10n.text("member.setup.medical.allergy.99ee3f"), subtitle: "")
                    Divider()
                    MedicalGuideListRow(icon: "person.3.fill", tint: .teal, title: L10n.text("member.setup.medical.family.401276"), subtitle: "")
                }

                HStack(alignment: .top, spacing: 8) {
                    Text("💡")
                        .font(.footnote)
                    Text(L10n.text("member.setup.medical.general.121635"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text("member.setup.medical.general.e1c9ed"))
                    .font(.headline.weight(.semibold))

                MedicalGuideGroupedCard {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.accent)
                            .frame(width: 28)
                        Text(L10n.text("member.setup.medical.general.6f0d95"))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                Text(L10n.text("member.setup.medical.general.572896"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // 既往疾病单题页。
    private var chronicConditionsStep: some View {
        MedicalGuideStepShell(
            title: L10n.text("member.setup.medical.chronic.d9e8b1"),
            subtitle: L10n.text("member.setup.medical.chronic.bbf28e"),
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
            return L10n.text("member.setup.medical.chronic.b40355");
        case .have:
            return L10n.text("member.setup.medical.chronic.b40355");
        case .unknown:
            return historyPrimaryTitle(after: .chronicConditions)
        }
    }

    // 长期用药单题页。
    private var longTermMedicationStep: some View {
        Group {
            if viewModel.member?.id != nil {
                MedicalGuideStepShell(
                    title: L10n.text("member.setup.medical.medication.b2baf4"),
                    subtitle: L10n.text("member.setup.medical.medication.4ce152"),
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
                    title: L10n.text("member.setup.medical.medication.b2baf4"),
                    subtitle: L10n.text("member.setup.medical.medication.4ce152"),
                    step: 11,
                    total: viewModel.totalGuideSteps,
                    isLoading: viewModel.isSaving,
                    primaryTitle: longTermMedicationPrimaryTitle,
                    primaryEnabled: viewModel.canAdvanceFromLongTermMedication,
                    onSkip: { nextVisibleHistory(after: .longTermMedication) },
                    onNext: { nextVisibleHistory(after: .longTermMedication) }
                ) {
                    Text(L10n.text("member.setup.medical.medication.7a6f13"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var longTermMedicationPrimaryTitle: String {
        switch viewModel.longTermMedicationStatus {
        case .none, .have:
            return L10n.text("member.setup.medical.medication.b5d1e1");
        case .unknown:
            return historyPrimaryTitle(after: .longTermMedication)
        }
    }

    // 手术史单题页。
    private var surgeryHistoryStep: some View {
        MedicalGuideStepShell(
            title: L10n.text("member.setup.medical.surgery.44426e"),
            subtitle: L10n.text("member.setup.medical.surgery.a8444b"),
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
            return L10n.text("member.setup.medical.general.97eb95");
        case .unknown:
            return historyPrimaryTitle(after: .surgeryHistory)
        }
    }

    // 过敏史单题页。
    private var allergyHistoryStep: some View {
        MedicalGuideStepShell(
            title: L10n.text("member.setup.medical.allergy.2ac7fd"),
            subtitle: L10n.text("member.setup.medical.allergy.c233d4"),
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
            title: L10n.text("member.setup.medical.family.401276"),
            subtitle: L10n.text("member.setup.medical.chronic.4324ae"),
            step: 14,
            total: viewModel.totalGuideSteps,
            isLoading: viewModel.isSaving,
            primaryTitle: L10n.text("common.next"),
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
            title: L10n.text("member.setup.medical.symptom.efefcb"),
            subtitle: L10n.text("member.setup.medical.general.295324"),
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
            return L10n.text("common.next");
        case .have:
            return L10n.text("member.setup.medical.symptom.e3da8f");
        case .unknown:
            return L10n.text("common.next");        }
    }

    // 健康病史与症状记录汇总页，点击任意卡片回到对应问题，便于逐项补充或修改。
    private var historySummaryStep: some View {
        MedicalGuideStepShell(
            title: L10n.text("member.setup.medical.general.937b8a"),
            subtitle: L10n.text("member.setup.medical.allergy.eba1d3"),
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
                Text(L10n.text("member.setup.medical.general.efb01c"))
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
            return L10n.text("member.setup.medical.general.897f3b");        }
        return L10n.text("common.next");    }

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
            title: L10n.text("member.setup.medical.general.50b90f"),
            subtitle: L10n.text("member.setup.medical.general.0efbaf"),
            isLoading: viewModel.isSaving,
            primaryTitle: L10n.text("member.setup.common.start"),
            secondaryTitle: L10n.text("member.setup.medical.general.0a096d"),
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
                Text(L10n.text("member.setup.medical.general.1ca012"))
                    .font(.headline.weight(.semibold))

                MedicalGuideGroupedCard {
                    MedicalGuideListRow(icon: "smoke.fill", tint: .orange, title: L10n.text("member.setup.medical.lifestyle.08f432"), subtitle: L10n.text("member.setup.medical.general.bef433"))
                    Divider()
                    MedicalGuideListRow(icon: "figure.run", tint: .green, title: L10n.text("member.setup.medical.lifestyle.f7cbb2"), subtitle: L10n.text("member.setup.medical.general.9f1394"))
                    Divider()
                    MedicalGuideListRow(icon: "bed.double.fill", tint: .indigo, title: L10n.text("member.setup.medical.lifestyle.8baa4c"), subtitle: L10n.text("member.setup.medical.lifestyle.sleep_row_subtitle"))
                }

                HStack(alignment: .top, spacing: 8) {
                    Text("💡")
                        .font(.footnote)
                    Text(L10n.text("member.setup.medical.general.667f91"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // 体检档案先给出说明，再进入报告导入与 AI 计划闭环表单。
    private var examArchiveIntroPage: some View {
        MedicalGuideIntroPageView(
            kind: .examArchive,
            title: L10n.text("medical.exam_archive.title"),
            subtitle: L10n.text("medical.exam_archive.entry.headline") + "，" + L10n.text("medical.exam_archive.entry.subtitle"),
            isLoading: isExamArchiveFlowLoading,
            primaryTitle: L10n.text("medical.exam_archive.action.start"),
            secondaryTitle: L10n.text("medical.exam_archive.action.later"),
            onStart: { startExamArchiveForm() },
            onLater: {
                if isSectionMode {
                    dismiss()
                } else {
                    skipExamArchiveFlow()
                }
            },
            onClose: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text("medical.exam_archive.intro.section_title"))
                    .font(.headline.weight(.semibold))

                MedicalGuideGroupedCard {
                    MedicalGuideListRow(
                        icon: "doc.text.fill",
                        tint: .blue,
                        title: L10n.text("medical.exam_archive.path.has_report.title"),
                        subtitle: L10n.text("medical.exam_archive.path.has_report.subtitle")
                    )
                    Divider()
                    MedicalGuideListRow(
                        icon: "sparkles",
                        tint: .purple,
                        title: L10n.text("medical.exam_archive.path.no_report.title"),
                        subtitle: L10n.text("medical.exam_archive.path.no_report.subtitle")
                    )
                    Divider()
                    MedicalGuideListRow(
                        icon: "exclamationmark.triangle.fill",
                        tint: .orange,
                        title: L10n.text("medical.exam_archive.extract.title"),
                        subtitle: L10n.text("medical.exam_archive.extract.subtitle")
                    )
                    Divider()
                    MedicalGuideListRow(
                        icon: "list.clipboard.fill",
                        tint: .teal,
                        title: L10n.text("medical.exam_archive.result.title"),
                        subtitle: L10n.text("medical.exam_archive.result.subtitle")
                    )
                }

                HStack(alignment: .top, spacing: 8) {
                    Text("💡")
                        .font(.footnote)
                    Text(L10n.text("medical.exam_archive.intro.tip"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text("member.setup.medical.general.e1c9ed"))
                    .font(.headline.weight(.semibold))

                MedicalGuideGroupedCard {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.accent)
                            .frame(width: 28)
                        Text(L10n.text("member.setup.medical.general.6f0d95"))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                Text(L10n.text("member.setup.medical.general.28d7dd"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            configureExamArchiveFlowIfNeeded()
            examArchiveFlowViewModel.logEntry()
        }
    }

    // 吸烟单题页。
    private var smokingStep: some View {
        MedicalGuideStepShell(
            title: L10n.text("member.setup.medical.lifestyle.fd0447"),
            subtitle: L10n.text("member.setup.medical.lifestyle.e80fad"),
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
                Text(L10n.text("member.setup.medical.lifestyle.640798"))
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
                            title: L10n.text("member.setup.medical.lifestyle.caed93"),
                            placeholder: L10n.text("member.setup.medical.general.c752d8"),
                            selection: $viewModel.smokingHistoryDuration,
                            options: MedicalLifestyleOptionCatalog.smokingHistoryDurations
                        )

                        if viewModel.smokingStatus == .quit {
                            Divider()
                            MedicalHabitMenuPickerRow(
                                icon: "nosign",
                                title: L10n.text("member.setup.medical.general.f4a414"),
                                placeholder: L10n.text("member.setup.medical.general.34874c"),
                                selection: $viewModel.smokingQuitDuration,
                                options: MedicalLifestyleOptionCatalog.quitDurations
                            )
                        }

                        if viewModel.smokingStatus == .sometimes || viewModel.smokingStatus == .often {
                            Divider()
                            MedicalHabitMenuPickerRow(
                                icon: "smoke.fill",
                                title: L10n.text("member.setup.medical.lifestyle.8464fe"),
                                placeholder: L10n.text("member.setup.medical.general.800c01"),
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
            title: L10n.text("member.setup.medical.lifestyle.42ab82"),
            subtitle: L10n.text("member.setup.medical.lifestyle.3d29ea"),
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
                Text(L10n.text("member.setup.medical.lifestyle.5dd94d"))
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
                            title: L10n.text("member.setup.medical.lifestyle.7a4d81"),
                            placeholder: L10n.text("member.setup.medical.general.0d391c"),
                            selection: $viewModel.drinkingHistoryDuration,
                            options: MedicalLifestyleOptionCatalog.drinkingHistoryDurations
                        )

                        if viewModel.drinkingStatus == .quit {
                            Divider()
                            MedicalHabitMenuPickerRow(
                                icon: "nosign",
                                title: L10n.text("member.setup.medical.general.582b60"),
                                placeholder: L10n.text("member.setup.medical.general.d1c536"),
                                selection: $viewModel.drinkingQuitDuration,
                                options: MedicalLifestyleOptionCatalog.quitDurations
                            )
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            Label(L10n.text("member.setup.medical.lifestyle.964e12"), systemImage: "wineglass.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            MedicalPickerChipGrid(
                                items: MemberSetupPresetOptionsCatalog.drinkingTypes,
                                selections: $viewModel.drinkingTypes
                            )
                        }
                        .padding(.vertical, 4)

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Label(L10n.text("member.setup.medical.general.1b1cbe"), systemImage: "plus.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            TextField("请输入其他酒类名称，如：自酿药酒、鸡尾酒...", text: $viewModel.customAlcoholType)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.vertical, 4)

                        if viewModel.drinkingStatus == .occasionally || viewModel.drinkingStatus == .often {
                            Divider()

                            VStack(alignment: .leading, spacing: 12) {
                                Label(L10n.text("member.setup.medical.lifestyle.56639d"), systemImage: "scalemass.fill")
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
            title: L10n.text("member.setup.medical.lifestyle.90997d"),
            subtitle: L10n.text("member.setup.medical.lifestyle.5cd8ae"),
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
                Text(L10n.text("member.setup.medical.lifestyle.bc1d4e"))
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
                            Label(L10n.text("member.setup.medical.lifestyle.33e5f7"), systemImage: "bolt.fill")
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
                            Label(L10n.text("member.setup.medical.lifestyle.d7ea67"), systemImage: "figure.run")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            MedicalPickerChipGrid(
                                items: MemberSetupPresetOptionsCatalog.exerciseTypes,
                                selections: $viewModel.exerciseTypes
                            )
                        }
                        .padding(.vertical, 4)

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Label(L10n.text("member.setup.medical.lifestyle.4e2c68"), systemImage: "plus.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            TextField("请输入其他运动，如：八段锦、攀岩、冲浪...", text: $viewModel.customExerciseType)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.vertical, 4)

                        Divider()

                        MedicalHabitMenuPickerRow(
                            icon: "timer",
                            title: L10n.text("member.setup.medical.lifestyle.aac751"),
                            placeholder: L10n.text("member.setup.medical.general.48711c"),
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
            title: L10n.text("member.setup.medical.lifestyle.04f647"),
            subtitle: L10n.text("member.setup.medical.lifestyle.5402a9"),
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
                Text(L10n.text("member.setup.medical.lifestyle.e68284"))
                    .font(.headline.weight(.semibold))

                MedicalLifestyleSleepSliderCard(hours: $viewModel.sleepHours)

                VStack(alignment: .leading, spacing: 12) {
                    Label(L10n.text("member.setup.medical.lifestyle.458c59"), systemImage: "bed.double.fill")
                        .font(.headline.weight(.semibold))

                    Text(L10n.text("member.setup.medical.lifestyle.065a51"))
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
            title: L10n.text("member.setup.medical.general.5bf059"),
            subtitle: L10n.text("member.setup.medical.medication.bbe51b"),
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
                Text(L10n.text("member.setup.medical.general.4933bd"))
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
            return L10n.text("member.setup.medical.general.25f588");        }
        return L10n.text("common.next");    }

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

    private var examArchiveSummaryStep: some View {
        MedicalGuideStepShell(
            title: L10n.text("medical.exam_archive.title"),
            subtitle: L10n.text("medical.exam_archive.summary.subtitle"),
            step: 29,
            total: viewModel.totalGuideSteps,
            isLoading: viewModel.isSaving,
            primaryTitle: isSectionMode && entryMode == .examArchive
                ? L10n.text("medical.exam_archive.action.finish")
                : "下一步",
            showsSkipButton: false,
            onSkip: {},
            onNext: {
                Task {
                    await viewModel.saveProgress()
                    proceedFromSectionSummary(.examArchiveSummary, fullFlowNext: .summary)
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.text("medical.exam_archive.summary.filled"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(examArchiveFilledSummaryLine)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 14) {
                    summaryRow(
                        title: L10n.text("medical.exam_archive.summary.reports"),
                        value: examArchiveReportStatusText
                    ) {
                        path.append(.examArchive)
                    }
                    summaryRow(
                        title: L10n.text("medical.exam_archive.summary.last_exam"),
                        value: viewModel.lastExamYear.isEmpty
                            ? "未填写"
                            : MemberMedicalSetupViewModel.displayYearMonth(viewModel.lastExamYear)
                    ) {
                        path.append(.examArchiveReportPicker)
                    }
                    summaryRow(
                        title: L10n.text("medical.exam_archive.summary.abnormal"),
                        value: examArchiveAbnormalCountText
                    ) {
                        path.append(.examArchiveAIExtractConfirm)
                    }
                    summaryRow(
                        title: L10n.text("medical.exam_archive.summary.follow_up"),
                        value: examArchiveFollowUpCountText
                    ) {
                        path.append(.examArchiveFollowUpPlan)
                    }
                    summaryRow(
                        title: L10n.text("medical.exam_archive.summary.plan"),
                        value: viewModel.examPlanLines.isEmpty
                            ? L10n.text("medical.exam_archive.summary.plan.none")
                            : L10n.text("medical.exam_archive.summary.plan.generated")
                    ) {
                        if viewModel.examPlanLines.isEmpty {
                            path.append(.examArchive)
                        } else {
                            path.append(.examArchivePlanResult)
                        }
                    }
                    summaryRow(
                        title: L10n.text("medical.exam_archive.summary.supplement_indicators"),
                        value: viewModel.keyIndicatorSummary
                    ) {
                        path.append(.keyIndicators)
                    }
                }
            }
        }
    }

    private var examArchiveFilledSummaryLine: String {
        var pieces: [String] = []
        if let latest = viewModel.memberHealthExamReports.max(by: {
            ($0.examDate ?? .distantPast) < ($1.examDate ?? .distantPast)
        }) {
            let title = MemberMedicalExamArchiveGuideContent.reportTitle(latest)
            pieces.append(title)
            let abnormalCount = examArchiveFlowViewModel.abnormalItems.isEmpty
                ? 0
                : examArchiveFlowViewModel.selectedAbnormalItemIDs.count
            if abnormalCount > 0 {
                pieces.append(L10n.format("medical.exam_archive.summary.abnormal_count", abnormalCount))
            }
        }
        if examArchiveFlowViewModel.createdTaskCount > 0 {
            pieces.append(L10n.format("medical.exam_archive.summary.follow_up_count", examArchiveFlowViewModel.createdTaskCount))
        }
        if viewModel.examPlanLines.isEmpty == false {
            pieces.append(L10n.text("medical.exam_archive.summary.plan.generated"))
        }
        return pieces.isEmpty ? viewModel.examArchiveSummary : pieces.joined(separator: " · ")
    }

    private var examArchiveReportStatusText: String {
        viewModel.memberHealthExamReports.isEmpty
            ? "未填写"
            : L10n.text("medical.exam_archive.summary.completed")
    }

    private var examArchiveAbnormalCountText: String {
        let count = examArchiveFlowViewModel.abnormalItems.isEmpty
            ? 0
            : examArchiveFlowViewModel.selectedAbnormalItemIDs.count
        return count == 0 ? L10n.text("member.setup.common.not_filled") : L10n.format("medical.exam_archive.summary.items_count", count)
    }

    private var examArchiveFollowUpCountText: String {
        let count = examArchiveFlowViewModel.createdTaskCount
        return count == 0 ? L10n.text("member.setup.common.not_filled") : L10n.format("medical.exam_archive.summary.items_count", count)
    }

    private var keyIndicatorStep: some View {
        MedicalGuideStepShell(
            title: L10n.text("medical.exam_archive.supplement_indicators.title"),
            subtitle: L10n.text("medical.exam_archive.supplement_indicators.subtitle"),
            step: 26,
            total: viewModel.totalGuideSteps,
            isLoading: viewModel.isSaving,
            primaryTitle: L10n.text("common.next"),
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
            title: L10n.text("medical.exam_archive.supplement_indicators.title"),
            subtitle: L10n.text("medical.exam_archive.supplement_indicators.summary_subtitle"),
            step: 27,
            total: viewModel.totalGuideSteps,
            isLoading: viewModel.isSaving,
            primaryTitle: L10n.text("common.next"),
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
                Text(L10n.text("member.setup.medical.nutrition.519b61"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(viewModel.keyIndicatorSummary)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 14) {
                    summaryRow(
                        title: L10n.text("medical.exam_archive.supplement_indicators.title"),
                        value: viewModel.keyIndicatorSummary
                    ) { path.append(.keyIndicators) }
                }
            }
        }
    }

    private var summaryPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MemberSetupStepHeaderView(
                    title: L10n.text("member.module.medical.title"),
                    subtitle: L10n.text("member.setup.medical.chronic.a054fd"),
                    step: 29,
                    total: viewModel.totalGuideSteps
                )

                questionCard(title: L10n.text("member.setup.medical.nutrition.519b61")) {
                    Text(summaryText)
                        .font(.title3.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 14) {
                    summaryRow(title: "基础档案说明", value: L10n.text("member.setup.common.completed")) { path.append(.intro) }
                    summaryRow(title: "性别", value: viewModel.genderDisplayTitle) { path.append(.gender) }
                    summaryRow(title: "出生日期", value: viewModel.birthDate.map { Self.dateFormatter.string(from: $0) } ?? L10n.text("member.setup.common.not_filled")) { path.append(.birthDate) }
                    summaryRow(title: "身高", value: viewModel.heightCm > 0 ? String(format: "%.0f cm", viewModel.heightCm) : L10n.text("member.setup.common.not_filled")) { path.append(.height) }
                    summaryRow(title: "体重", value: viewModel.weightKg > 0 ? String(format: "%.1f kg", viewModel.weightKg) : L10n.text("member.setup.common.not_filled")) { path.append(.weight) }
                    summaryRow(title: "职业", value: viewModel.occupation.isEmpty ? L10n.text("member.setup.common.not_filled") : viewModel.occupation) { path.append(.occupation) }
                    summaryRow(title: "久坐时间", value: viewModel.sedentaryLevel?.title ?? L10n.text("member.setup.common.not_filled")) { path.append(.sedentary) }
                    summaryRow(title: "健康病史与症状记录说明", value: viewModel.historyIntroSummaryText) { path.append(.history) }
                    summaryRow(title: "症状观察 / 随访", value: viewModel.symptomSummary) { path.append(.symptomFollowUp) }
                    summaryRow(title: "既往疾病", value: viewModel.chronicConditionsSummary) { path.append(.chronicConditions) }
                    summaryRow(title: "长期用药", value: viewModel.longTermMedicationSummary) { path.append(.longTermMedication) }
                    summaryRow(title: "手术史", value: viewModel.surgerySummary) { path.append(.surgeryHistory) }
                    summaryRow(title: "过敏史", value: viewModel.allergySummary) { path.append(.allergyHistory) }
                    summaryRow(title: "健康病史与症状记录汇总", value: viewModel.historySummary) { path.append(.historySummary) }
                    summaryRow(title: "家族病史", value: viewModel.familyHistorySummary) { path.append(.familyHistory) }
                    summaryRow(title: "生活习惯", value: viewModel.lifestyleSummary) { path.append(.lifestyleSummary) }
                    summaryRow(title: L10n.text("medical.exam_archive.title"), value: viewModel.examPlanSummary) {
                        path.append(.examArchive)
                    }
                    summaryRow(
                        title: L10n.text("medical.exam_archive.summary.supplement_indicators"),
                        value: viewModel.keyIndicatorSummary
                    ) {
                        path.append(.keyIndicators)
                    }
                    summaryRow(title: L10n.text("medical.exam_archive.summary.flow"), value: viewModel.examArchiveSummary) {
                        path.append(.examArchiveSummary)
                    }
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
        .navigationTitle(L10n.text("member.module.medical.title"))
        .navigationBarTitleDisplayMode(.inline)
        .memberSetupBottomBar(
            primaryTitle: L10n.text("common.save"),
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
            secondaryTitle: L10n.text("common.skip"),
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
            viewModel.examPlanSummary,
            viewModel.symptomSummary
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
        hasRemainingBasicInfoPage(after: route) ? L10n.text("common.next") : "完成"
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
        hasRemainingHistoryPage(after: route) ? L10n.text("common.next") : "完成"
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
            if viewModel.shouldSkipExamArchiveStep {
                proceedAfterExamArchiveStep()
            } else {
                path.append(.examArchive)
            }
        case .examArchive:
            break
        case .examArchiveReportPicker, .examArchiveAIExtractConfirm,
             .examArchiveFollowUpPlan, .examArchivePlanGenerating, .examArchivePlanResult,
             .examArchiveBaselineIntro, .examArchiveEvidenceConfirm:
            break
        case .examArchiveSummary:
            if isSectionMode && entryMode == .examArchive {
                finishCurrentSection()
            } else {
                path.append(.summary)
            }
        case .keyIndicators:
            path.append(.keyIndicatorSummary)
        case .keyIndicatorSummary:
            proceedAfterKeyIndicatorSummary()
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
            if viewModel.shouldSkipExamArchiveStep {
                proceedAfterExamArchiveStep()
            } else {
                path.append(.examArchive)
            }
        case .examArchive:
            break
        case .examArchiveReportPicker, .examArchiveAIExtractConfirm,
             .examArchiveFollowUpPlan, .examArchivePlanGenerating, .examArchivePlanResult,
             .examArchiveBaselineIntro, .examArchiveEvidenceConfirm:
            break
        case .examArchiveSummary:
            if isSectionMode && entryMode == .examArchive {
                finishCurrentSection()
            } else {
                path.append(.summary)
            }
        case .keyIndicators:
            path.append(.keyIndicatorSummary)
        case .keyIndicatorSummary:
            proceedAfterKeyIndicatorSummary()
        case .symptomFollowUp:
            path.append(.historySummary)
        case .summary:
            break
        }
    }

    private func proceedAfterExamArchiveStep() {
        path.append(.examArchiveSummary)
    }

    private func proceedAfterKeyIndicatorSummary() {
        if examArchiveFlowViewModel.selectedReport != nil {
            path.append(.examArchiveAIExtractConfirm)
        } else {
            path.append(.examArchiveSummary)
        }
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
            break
        case .examArchiveReportPicker, .examArchiveAIExtractConfirm,
             .examArchiveFollowUpPlan, .examArchivePlanGenerating, .examArchivePlanResult,
             .examArchiveBaselineIntro, .examArchiveEvidenceConfirm:
            break
        case .examArchiveSummary:
            if isSectionMode && entryMode == .examArchive {
                finishCurrentSection()
            } else {
                path.append(.summary)
            }
        case .keyIndicators, .keyIndicatorSummary:
            proceedAfterKeyIndicatorSummary()
        default:
            proceedAfterExamArchiveStep()
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
                    .foregroundStyle(value == L10n.text("member.setup.common.not_filled") ? .secondary : .primary)
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
            MedicalSummaryRow(title: title, subtitle: subtitle, isCompleted: subtitle.isEmpty == false && subtitle != L10n.text("member.setup.common.not_filled"))
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
        MemberSetupOccupationCatalog.groups.map { option in
            OccupationGroup(
                icon: option.icon,
                tint: occupationTint(for: option.icon),
                title: option.displayTitle,
                subtitle: option.displaySubtitle,
                value: option.value
            )
        }
    }

    private func occupationTint(for icon: String) -> Color {
        switch icon {
        case "desktopcomputer": return .blue
        case "building.2.fill": return .indigo
        case "graduationcap.fill": return .orange
        case "cross.case.fill": return .red
        case "briefcase.fill": return .green
        case "truck.box.fill": return .brown
        default: return .blue
        }
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
        MedicalGuideSedentaryLevel.allCases.map { level in
            (
                title: level.title,
                subtitle: level.subtitle,
                color: sedentaryColor(for: level),
                value: level
            )
        }
    }

    private func sedentaryColor(for level: MedicalGuideSedentaryLevel) -> Color {
        switch level {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .red
        }
    }

    private var historyDisclosureItems: [(title: String, value: String)] {
        MedicalGuideDisclosureStatus.allCases
            .filter { $0 != .unknown }
            .map { ($0.title, $0.rawValue) }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
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
                        Text(L10n.text("home.members.save.success"))
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

private struct MedicalHabitMenuPickerRow: View {
    let icon: String
    let title: String
    let placeholder: String
    @Binding var selection: String
    let options: [SparkBilingualItem]

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
                ForEach(options, id: \.cn) { option in
                    Button(MemberSetupBilingualCatalog.display(option)) {
                        selection = option.cn
                    }
                }
                if selection.isEmpty == false {
                    Divider()
                    Button(L10n.text("member.setup.medical.general.clear_selection"), role: .destructive) {
                        selection = ""
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(
                        selection.isEmpty
                            ? L10n.text("member.setup.medical.general.708c9d")
                            : MemberSetupBilingualCatalog.displayString(stored: selection, in: options)
                    )
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
                Text(L10n.text("member.setup.medical.general.b8a232"))
                Spacer()
                Text(L10n.text("member.setup.medical.general.d04708"))
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
    let items: [SparkBilingualItem]
    @Binding var selections: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(items, id: \.cn) { item in
                Button {
                    toggle(item.cn)
                } label: {
                    Text(MemberSetupBilingualCatalog.display(item))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected(item.cn) ? Color.accentColor : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected(item.cn) ? Color.accentColor.opacity(0.14) : Color(uiColor: .systemBackground))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggle(_ canonicalCN: String) {
        if selections.contains(canonicalCN) {
            selections.removeAll { $0 == canonicalCN }
        } else {
            selections.append(canonicalCN)
        }
    }

    private func isSelected(_ canonicalCN: String) -> Bool {
        selections.contains(canonicalCN)
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
