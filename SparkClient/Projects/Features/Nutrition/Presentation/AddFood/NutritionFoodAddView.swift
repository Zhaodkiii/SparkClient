import SwiftUI

struct NutritionFoodAddView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: NutritionFoodAddViewModel

    private let dependencies: NutritionFeatureDependencies

    init(
        dependencies: NutritionFeatureDependencies,
        memberID: Int,
        date: Date,
        mealType: NutritionMealType
    ) {
        self.dependencies = dependencies
        _viewModel = StateObject(
            wrappedValue: NutritionFoodAddViewModel(
                memberID: memberID,
                date: date,
                mealType: mealType,
                searchUseCase: dependencies.searchUseCase,
                mealRecordUseCase: dependencies.mealRecordUseCase,
                healthKitSyncUseCase: dependencies.healthKitSyncUseCase,
                memberContextStore: dependencies.memberContextStore,
                notificationStore: dependencies.notificationStore,
                logger: dependencies.logger
            )
        )
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                quickActions
                searchFieldButton
                filters
                recommendedList
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 96)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(L10n.text(viewModel.mealType.localizationKey))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                selectionBadge
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(L10n.text("common.cancel")) {
                    dismiss()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            finishButton
        }
        .task(id: viewModel.contentFilter) {
            await viewModel.reloadRecommended()
        }
        .sheet(item: $viewModel.detailAddContext) { context in
            NutritionFoodDetailAddView(
                context: context,
                mealType: viewModel.mealType,
                searchUseCase: dependencies.searchUseCase,
                notificationStore: dependencies.notificationStore
            ) { servingRatio, quantity in
                viewModel.commitDetailAdd(servingRatio: servingRatio, quantity: quantity)
            }
        }
        .notificationFullScreenCover(
            item: $viewModel.presentedCover,
            store: dependencies.notificationStore
        ) { cover in
            switch cover {
            case .search(let mode, let initialQuery):
                NutritionFoodSearchView(
                    memberID: viewModel.memberID,
                    searchUseCase: dependencies.searchUseCase,
                    notificationStore: dependencies.notificationStore,
                    mode: mode,
                    initialQuery: initialQuery,
                    onAddResult: { result in
                        viewModel.addSelection(result)
                    },
                    onOpenDetail: { result in
                        viewModel.openDetailAdd(for: result)
                    }
                )

            case .barcodeScanner:
                NutritionBarcodeScannerView { barcode in
                    viewModel.handleBarcodeScanned(barcode)
                }

            case .cameraFlow:
                CompatibleNavigationContainer {
                    NutritionRecognitionFlowView(
                        dependencies: dependencies,
                        memberID: viewModel.memberID,
                        date: viewModel.date,
                        mealType: viewModel.mealType
                    )
                }

            case .naturalLanguageInput:
                NutritionNaturalLanguageInputView(
                    dependencies: dependencies,
                    memberID: viewModel.memberID,
                    date: viewModel.date,
                    mealType: viewModel.mealType
                )

            case .selectionPreview:
                NutritionSelectionPreviewView(
                    items: viewModel.selectionItems,
                    mealType: viewModel.mealType,
                    searchUseCase: dependencies.searchUseCase,
                    notificationStore: dependencies.notificationStore,
                    onClose: {
                        viewModel.presentedCover = nil
                    },
                    onUpdateSelection: { itemID, servingRatio, quantity in
                        viewModel.updateSelection(
                            id: itemID,
                            servingRatio: servingRatio,
                            quantity: quantity
                        )
                    },
                    onRemove: { itemID in
                        viewModel.removeSelection(id: itemID)
                    }
                )
            }
        }
        .alert(
            L10n.text("nutrition.confirm.save_failed.title"),
            isPresented: saveErrorAlertBinding
        ) {
            Button(L10n.text("common.ok"), role: .cancel) {}
        } message: {
            if let key = viewModel.saveErrorMessageKey {
                Text(L10n.text(key))
            }
        }
    }

    private var saveErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.saveErrorMessageKey != nil },
            set: { if $0 == false { viewModel.clearSaveError() } }
        )
    }

    private var selectionBadge: some View {
        Button {
            viewModel.openSelectionPreview()
        } label: {
            Text(viewModel.selectionBadgeText)
                .font(.headline.weight(.bold))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            String(
                format: L10n.text("nutrition.add.selection_count"),
                locale: Locale.current,
                viewModel.selectionCount
            )
        )
    }

    private var quickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 8) {
                quickAction(
                    icon: "magnifyingglass",
                    titleKey: "nutrition.add.action.search",
                    isSelected: true
                ) {
                    viewModel.openTextSearch()
                }

                quickAction(
                    icon: "camera.fill",
                    titleKey: "nutrition.add.action.camera"
                ) {
                    viewModel.presentedCover = .cameraFlow
                }

                quickAction(
                    icon: "barcode.viewfinder",
                    titleKey: "nutrition.add.action.barcode"
                ) {
                    viewModel.openBarcodeFlow()
                }

                quickAction(
                    icon: "doc.text.fill",
                    titleKey: "nutrition.add.action.input"
                ) {
                    viewModel.presentedCover = .naturalLanguageInput
                }

                quickAction(
                    icon: "ellipsis.circle.fill",
                    titleKey: "nutrition.add.action.more"
                ) {}
            }
        }
    }

    private func quickAction(
        icon: String,
        titleKey: String,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(isSelected ? Color(uiColor: .systemTeal).opacity(0.12) : Color(uiColor: .systemBackground))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(
                                    isSelected ? Color(uiColor: .systemTeal) : Color(uiColor: .systemGray4),
                                    lineWidth: isSelected ? 2 : 1
                                )
                        }

                    Image(systemName: icon)
                        .font(.largeTitle)
                        .symbolRenderingMode(.multicolor)
                        .foregroundStyle(isSelected ? Color(uiColor: .systemTeal) : Color(uiColor: .secondaryLabel))
                }
                .frame(width: 80, height: 72)

                Text(L10n.text(titleKey))
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }

    private var searchFieldButton: some View {
        Button {
            viewModel.openSearchField()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text(L10n.text(viewModel.searchPlaceholderKey))
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .systemBackground))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color(uiColor: .systemTeal), lineWidth: 2)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private var filters: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(NutritionFoodAddContentFilter.allCases) { filter in
                    Button(L10n.text(filter.localizationKey)) {
                        viewModel.contentFilter = filter
                    }
                }
            } label: {
                filterMenuLabel(title: L10n.text(viewModel.contentFilter.localizationKey))
            }

            Menu {
                Button(L10n.text("nutrition.add.sort.frequent")) {}
                Button(L10n.text("nutrition.add.sort.recent")) {}
                Button(L10n.text("nutrition.add.sort.recommended")) {}
            } label: {
                filterMenuLabel(title: L10n.text("nutrition.add.sort.frequent"))
            }
        }
    }

    private func filterMenuLabel(title: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            Spacer()

            Image(systemName: "chevron.down")
                .font(.caption.bold())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(uiColor: .systemGray4), lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private var recommendedList: some View {
        if viewModel.isLoadingRecommended {
            ProgressView(L10n.text("nutrition.add.loading"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else if let errorKey = viewModel.recommendedErrorKey {
            NutritionErrorStateView(
                messageKey: errorKey,
                retryTitleKey: "nutrition.common.retry"
            ) {
                Task { await viewModel.reloadRecommended() }
            }
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.recommendedFoods.enumerated()), id: \.element.id) { index, result in
                    recommendedRow(result)

                    if index < viewModel.recommendedFoods.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private func recommendedRow(_ result: NutritionFoodSearchResultViewData) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                viewModel.openDetailAdd(for: result)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if result.subtitle.isEmpty == false {
                        Text(result.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Text(result.calorieText)
                .font(.headline)
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Button {
                viewModel.addSelection(result)

                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            } label: {
                Image(systemName: "plus")
                    .font(.title3.bold())
                    .foregroundStyle(Color(uiColor: .systemTeal))
                    .frame(width: 36, height: 36)
                    .background {
                        Circle()
                            .stroke(Color(uiColor: .systemTeal), lineWidth: 2)
                    }
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .accessibilityLabel(L10n.text("nutrition.search.add_item"))
        }
        .padding(.vertical, 10)
    }

    private var finishButton: some View {
        Button {
            Task {
                await viewModel.save {
                    dismiss()
                }
            }
        } label: {
            finishButtonLabel
                .foregroundStyle(Color(uiColor: .systemBackground))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(viewModel.canFinish ? Color.black : Color(uiColor: .systemGray3))
            }
        }
        .disabled(viewModel.canFinish == false)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var finishButtonLabel: some View {
        if viewModel.isSaving {
            ProgressView()
                .tint(Color(uiColor: .systemBackground))
        } else {
            Text(L10n.text("nutrition.add.finish"))
                .font(.headline)
                .fontWeight(.bold)
        }
    }
}

#Preview("Food Add") {
    CompatibleNavigationContainer {
        NutritionFoodAddView(
            dependencies: .preview,
            memberID: 1,
            date: .now,
            mealType: .breakfast
        )
    }
}
