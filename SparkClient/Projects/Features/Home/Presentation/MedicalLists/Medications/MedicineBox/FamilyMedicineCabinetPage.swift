import SwiftUI

/// 家庭/个人药箱统一页面（工单 MEDICINE-CABINET-000005 / 000006 / 000007）
/// 通过 `mode` 区分家庭汇总与个人成员药箱，UI 与交互共用，仅人员筛选按模式显隐
struct FamilyMedicineCabinetPage: View {
    let entryMemberID: Int
    let mode: MedicineBoxMode
    let dependencies: HomeFeatureDependencies
    /// 家庭模式首页完整成员数据缓存；用于读取/回写 `familyMedicineBoxes`
    let memberCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    /// 家庭模式药箱变更时回写首页完整成员数据缓存
    let onMemberCompleteDataChanged: ((SparkMedicalSyncAPI.RemoteMemberCompleteData) -> Void)?
    /// 个人模式首页缓存药箱数据，进入页面时立即展示
    let initialMedicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    /// 个人模式下药箱变更时回写上层缓存（如用药执行中心 completeData）
    let onMedicineBoxesChanged: (([SparkMedicalSyncAPI.RemoteMedicineBox]) -> Void)?

    @StateObject private var viewModel: FamilyMedicineCabinetViewModel
    @State private var sheetDestination: MedicineBoxSheetDestination?
    @State private var showingUploadSheet = false

    init(
        entryMemberID: Int,
        mode: MedicineBoxMode = .family,
        memberCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData? = nil,
        onMemberCompleteDataChanged: ((SparkMedicalSyncAPI.RemoteMemberCompleteData) -> Void)? = nil,
        initialMedicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox] = [],
        dependencies: HomeFeatureDependencies,
        onMedicineBoxesChanged: (([SparkMedicalSyncAPI.RemoteMedicineBox]) -> Void)? = nil
    ) {
        self.entryMemberID = entryMemberID
        self.mode = mode
        self.memberCompleteData = mode == .family ? memberCompleteData : nil
        self.onMemberCompleteDataChanged = mode == .family ? onMemberCompleteDataChanged : nil
        // 家庭模式使用 familyMedicineBoxes 缓存；个人模式使用成员个人药箱缓存
        self.initialMedicineBoxes = mode == .personal ? initialMedicineBoxes : []
        self.dependencies = dependencies
        self.onMedicineBoxesChanged = onMedicineBoxesChanged
        _viewModel = StateObject(
            wrappedValue: FamilyMedicineCabinetViewModel(
                entryMemberID: entryMemberID,
                mode: mode,
                initialMedicineBoxes: mode == .personal ? initialMedicineBoxes : [],
                initialFamilyMedicineBoxes: mode == .family ? memberCompleteData?.familyMedicineBoxes : nil,
                medicalQueryAPI: dependencies.medicalQueryAPI,
                logger: dependencies.logger
            )
        )
    }

    private var medicineTypeOptions: [String] {
        MedicineBoxTypeCatalog.options(in: viewModel.allBoxes)
    }

    private var memberFilterOptions: [(FamilyMedicineCabinetViewModel.MemberFilter, String)] {
        viewModel.memberFilterOptions(members: dependencies.memberContextStore.context.members)
    }

    /// 家庭模式允许公共药品；个人模式仅绑定当前成员
    private var allowsHouseholdPublic: Bool {
        mode == .family
    }

    private var defaultBindingMemberID: Int? {
        mode == .personal ? entryMemberID : nil
    }

    private var navigationTitleText: String {
        switch mode {
        case .family:
            return L10n.text("home.medical.family_cabinet.title")
        case .personal:
            return L10n.text("home.medical.personal_cabinet.title")
        }
    }

    /// 家庭模式：familyMedicineBoxes 为空时页面内加载；个人模式：无首页缓存时加载
    private var shouldAutoLoadOnAppear: Bool {
        switch mode {
        case .family:
            return FamilyMedicineCabinetViewModel.shouldLoadFamilyMedicineOnAppear(
                cachedBoxes: memberCompleteData?.familyMedicineBoxes
            )
        case .personal:
            return initialMedicineBoxes.isEmpty
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 人员筛选仅家庭药箱模式展示
                if viewModel.showsMemberFilter {
                    MedicineBoxMemberFilterBar(
                        options: memberFilterOptions,
                        selectedFilter: viewModel.memberFilter,
                        onSelect: { viewModel.memberFilter = $0 }
                    )
                }
                MedicineBoxTypeTabBar(
                    typeOptions: medicineTypeOptions,
                    selectedTypeTab: viewModel.selectedTypeTab,
                    onSelect: { viewModel.selectedTypeTab = $0 }
                )
                MedicineBoxGridView(
                    boxes: viewModel.filteredBoxes,
                    isLoading: viewModel.isLoading,
                    entryMemberID: entryMemberID,
                    allowsHouseholdPublic: allowsHouseholdPublic,
                    memberOptions: dependencies.memberContextStore.context.members,
                    typeOptions: medicineTypeOptions,
                    specOptionBoxes: viewModel.allBoxes,
                    workflowAPI: dependencies.medicalWorkflowAPI,
                    fileTransferService: dependencies.fileTransferService,
                    onSaved: handleBoxSaved,
                    onDeleted: handleBoxDeleted
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $viewModel.searchText, prompt: L10n.text("home.medical.family_cabinet.search_prompt"))
        .toolbar {
            // 合并 trailing 按钮以兼容 iOS 15（toolbar 内条件 ToolbarItem 需 iOS 16+）
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    if viewModel.showsMemberFilter {
                        memberFilterMenu
                    }
                    Button {
                        sheetDestination = .create
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(L10n.text("home.medical.medicine_box.add_a11y"))
                }
            }
        }
        .overlay {
            if viewModel.isLoading && viewModel.allBoxes.isEmpty {
                ProgressView()
            }
        }
        .refreshable {
            await reloadAndNotifyParent()
        }
        .task {
            guard shouldAutoLoadOnAppear else { return }
            await reloadAndNotifyParent()
        }
        .onChange(of: dependencies.medicalDocumentUploadViewModel.saveSucceededRevision) { _ in
            Task { await reloadAndNotifyParent() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MedicineBoxBottomCameraButton {
                showingUploadSheet = true
            }
        }
        .sheet(item: $sheetDestination) { destination in
            MedicineBoxFormView(
                mode: destination.formMode,
                entryMemberID: entryMemberID,
                defaultBindingMemberID: defaultBindingMemberID,
                memberOptions: dependencies.memberContextStore.context.members,
                allowsHouseholdPublic: allowsHouseholdPublic,
                workflowAPI: dependencies.medicalWorkflowAPI,
                fileTransferService: dependencies.fileTransferService,
                typeOptions: medicineTypeOptions,
                specOptionBoxes: viewModel.allBoxes,
                onServerSaved: { box in
                    handleBoxSaved(box)
                    sheetDestination = nil
                }
            )
        }
        .sheet(isPresented: $showingUploadSheet) {
            MedicalAttachmentUploadListSheet(documentType: .medicineBox) { files in
                dependencies.medicalDocumentUploadViewModel.prepareAndStart(files: files, kind: .medicineBox)
            }
        }
        .alert(
            L10n.text("common.load_failed"),
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.clearError() } }
            )
        ) {
            Button(L10n.text("common.got_it"), role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var memberFilterMenu: some View {
        Menu {
            ForEach(memberFilterOptions, id: \.0) { filter, title in
                Button {
                    viewModel.memberFilter = filter
                } label: {
                    if viewModel.memberFilter == filter {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel(L10n.text("home.medical.family_cabinet.filter_a11y"))
    }

    private func handleBoxSaved(_ box: SparkMedicalSyncAPI.RemoteMedicineBox) {
        viewModel.upsert(box)
        notifyParentIfPersonal()
        notifyParentCompleteDataIfFamily()
    }

    private func handleBoxDeleted(id: Int) {
        viewModel.remove(id: id)
        notifyParentIfPersonal()
        notifyParentCompleteDataIfFamily()
    }

    /// 个人模式：将当前药箱列表按 updatedAt 倒序回写首页缓存
    private func notifyParentIfPersonal() {
        guard mode == .personal else { return }
        onMedicineBoxesChanged?(viewModel.boxesForHomeCacheSync)
    }

    /// 家庭模式：将当前药箱列表回写首页完整成员数据中的 familyMedicineBoxes 缓存
    private func notifyParentCompleteDataIfFamily() {
        guard mode == .family else { return }
        guard var completeData = memberCompleteData else { return }
        completeData.familyMedicineBoxes = viewModel.boxesForFamilyHomeCacheSync
        onMemberCompleteDataChanged?(completeData)
        dependencies.logger.info(
            "家庭药箱回写首页完整成员数据缓存 entryMemberID=\(entryMemberID) count=\(completeData.familyMedicineBoxes?.count ?? 0)",
            module: .home
        )
    }

    @MainActor
    private func reloadAndNotifyParent() async {
        let succeeded = await viewModel.load()
        // 刷新失败时保留首页缓存数据，不回写
        if succeeded {
            notifyParentIfPersonal()
            notifyParentCompleteDataIfFamily()
        }
    }
}
