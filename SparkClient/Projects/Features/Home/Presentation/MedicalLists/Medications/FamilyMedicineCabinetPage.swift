import SwiftUI

struct FamilyMedicineCabinetPage: View {
    let entryMemberID: Int
    let dependencies: HomeFeatureDependencies

    @StateObject private var viewModel: FamilyMedicineCabinetViewModel
    @State private var sheetDestination: MedicineBoxSheetDestination?
    @State private var showingUploadSheet = false
    init(entryMemberID: Int, dependencies: HomeFeatureDependencies) {
        self.entryMemberID = entryMemberID
        self.dependencies = dependencies
        _viewModel = StateObject(
            wrappedValue: FamilyMedicineCabinetViewModel(
                entryMemberID: entryMemberID,
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                memberFilterBar
                typeTabBar
                medicineGrid
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("home.medical.family_cabinet.title"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $viewModel.searchText, prompt: L10n.text("home.medical.family_cabinet.search_prompt"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
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
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    sheetDestination = .create
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(L10n.text("home.medical.medicine_box.add_a11y"))
            }
        }
        .overlay {
            if viewModel.isLoading && viewModel.allBoxes.isEmpty {
                ProgressView()
            }
        }
        .refreshable {
            await viewModel.load()
        }
        .task {
            await viewModel.load()
        }
        .onChange(of: dependencies.medicalDocumentUploadViewModel.saveSucceededRevision) { _ in
            Task { await viewModel.load() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                showingUploadSheet = true
            } label: {
                Label(L10n.text("home.medical.medicine_box.camera_add"), systemImage: "camera.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color(uiColor: .systemPurple), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
        .sheet(item: $sheetDestination) { destination in
            MedicineBoxFormView(
                mode: destination.formMode,
                entryMemberID: entryMemberID,
                defaultBindingMemberID: nil,
                memberOptions: dependencies.memberContextStore.context.members,
                allowsHouseholdPublic: true,
                workflowAPI: dependencies.medicalWorkflowAPI,
                fileTransferService: dependencies.fileTransferService,
                typeOptions: medicineTypeOptions,
                specOptionBoxes: viewModel.allBoxes,
                onServerSaved: { box in
                    viewModel.upsert(box)
                    sheetDestination = nil
                }
            )
        }
        .sheet(isPresented: $showingUploadSheet) {
            MedicineBoxUploadSheet { files in
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

    private var memberFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(memberFilterOptions, id: \.0) { filter, title in
                    Button {
                        viewModel.memberFilter = filter
                    } label: {
                        Text(title)
                            .font(.subheadline.weight(viewModel.memberFilter == filter ? .semibold : .regular))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(
                                    viewModel.memberFilter == filter
                                        ? Color(uiColor: .systemPurple).opacity(0.15)
                                        : Color(uiColor: .secondarySystemGroupedBackground)
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var typeTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                typeTabButton(title: L10n.text("common.all"), storedValue: "")
                ForEach(MedicineBoxTypeCatalog.displayOptions(for: medicineTypeOptions), id: \.self) { display in
                    typeTabButton(
                        title: display,
                        storedValue: MedicineBoxTypeCatalog.storedValue(fromDisplay: display)
                    )
                }
            }
        }
    }

    private func typeTabButton(title: String, storedValue: String) -> some View {
        let selected = MedicineBoxTypeCatalog.storedValue(fromAny: viewModel.selectedTypeTab.nilIfBlank) == storedValue
        return Button {
            viewModel.selectedTypeTab = storedValue
        } label: {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(
                        selected
                            ? Color(uiColor: .systemBlue).opacity(0.15)
                            : Color(uiColor: .secondarySystemGroupedBackground)
                    )
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var medicineGrid: some View {
        let boxes = viewModel.filteredBoxes
        if boxes.isEmpty {
            Text(viewModel.isLoading ? L10n.text("home.medical.family_cabinet.loading") : L10n.text("home.medical.family_cabinet.empty"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(boxes, id: \.id) { box in
                    NavigationLink {
                        MedicineBoxDetailPage(
                            box: box,
                            entryMemberID: entryMemberID,
                            memberOptions: dependencies.memberContextStore.context.members,
                            allowsHouseholdPublic: true,
                            typeOptions: medicineTypeOptions,
                            specOptionBoxes: viewModel.allBoxes,
                            workflowAPI: dependencies.medicalWorkflowAPI,
                            fileTransferService: dependencies.fileTransferService,
                            onSaved: { viewModel.upsert($0) },
                            onDeleted: { viewModel.remove(id: $0) }
                        )
                    } label: {
                        FamilyMedicineCabinetCard(
                            box: box,
                            fileTransferService: dependencies.fileTransferService
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct FamilyMedicineCabinetCard: View {
    let box: SparkMedicalSyncAPI.RemoteMedicineBox
    let fileTransferService: FileTransferService

    private var imageAttachment: SparkMedicalSyncAPI.RemoteManagedFile? {
        box.attachments?.first(where: \.isMedicationImageLike)
    }

    private var statusBadge: FamilyMedicineCabinetStatusBadge.Resolved? {
        FamilyMedicineCabinetStatusBadge.resolve(for: box)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .frame(height: 120)
                    .overlay {
                        MedicationImageGlyph(
                            seed: box.id,
                            attachment: imageAttachment,
                            fileTransferService: fileTransferService
                        )
                        .frame(width: 72, height: 72)
                    }

                if let statusBadge {
                    Text(statusBadge.text)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            statusBadge.color.opacity(statusBadge.kind == .expired ? 0.55 : 1),
                            in: Capsule()
                        )
                        .padding(8)
                }
            }

            Text(box.medicineName.nilIfBlank ?? L10n.text("home.medical.medicine_box.unnamed"))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Text(specLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Spacer()
                Text(L10n.text("home.medical.family_cabinet.view_more"))
                    .font(.caption.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(Color(uiColor: .systemPurple))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        )
    }

    private var specLine: String {
        let strength = box.strength.nilIfBlank ?? ""
        let qty: String
        if let total = box.totalQuantity {
            qty = " ×\(total.formatted(.number.precision(.fractionLength(0...2))))"
        } else {
            qty = ""
        }
        return strength.isEmpty ? qty.trimmingCharacters(in: .whitespaces) : "\(strength)\(qty)"
    }
}

private enum FamilyMedicineCabinetStatusBadge {
    enum Kind {
        case expired
        case expiringSoon
        case lowStock
    }

    struct Resolved {
        let kind: Kind
        let text: String
        let color: Color
    }

    static func resolve(for box: SparkMedicalSyncAPI.RemoteMedicineBox) -> Resolved? {
        if let expire = box.expireDate {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let expireDay = calendar.startOfDay(for: expire)
            if expireDay < today {
                return Resolved(
                    kind: .expired,
                    text: L10n.text("home.medical.family_cabinet.badge.expired"),
                    color: Color(uiColor: .systemGray)
                )
            }
            if let soon = calendar.date(byAdding: .day, value: 30, to: today), expireDay <= soon {
                return Resolved(
                    kind: .expiringSoon,
                    text: L10n.text("home.medical.family_cabinet.badge.expiring_soon"),
                    color: .orange
                )
            }
        }
        if let qty = box.totalQuantity, qty <= 0 {
            return Resolved(
                kind: .lowStock,
                text: L10n.text("home.medical.family_cabinet.badge.low_stock"),
                color: .orange
            )
        }
        return nil
    }
}
