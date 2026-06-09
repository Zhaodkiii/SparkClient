import SwiftUI

struct NutritionFoodDetailAddView: View {
    @Environment(\.dismiss) private var dismiss

    let context: NutritionFoodDetailAddContext
    let mealType: NutritionMealType
    let searchUseCase: NutritionSearchUseCase
    let notificationStore: NotificationStore
    let primaryButtonKey: String
    let embedsNavigation: Bool
    let dismissOnPrimaryAction: Bool
    let isSaving: Bool
    let onPrimaryAction: (NutritionServingRatio, Double) -> Void

    @State private var servingRatio: NutritionServingRatio
    @State private var quantity: Double
    @State private var isFavorite: Bool
    @State private var isTogglingFavorite = false

    init(
        context: NutritionFoodDetailAddContext,
        mealType: NutritionMealType,
        searchUseCase: NutritionSearchUseCase,
        notificationStore: NotificationStore,
        primaryButtonKey: String = "nutrition.detail_add.add",
        embedsNavigation: Bool = true,
        dismissOnPrimaryAction: Bool = true,
        isSaving: Bool = false,
        onPrimaryAction: @escaping (NutritionServingRatio, Double) -> Void
    ) {
        self.context = context
        self.mealType = mealType
        self.searchUseCase = searchUseCase
        self.notificationStore = notificationStore
        self.primaryButtonKey = primaryButtonKey
        self.embedsNavigation = embedsNavigation
        self.dismissOnPrimaryAction = dismissOnPrimaryAction
        self.isSaving = isSaving
        self.onPrimaryAction = onPrimaryAction
        _servingRatio = State(initialValue: context.initialServingRatio)
        _quantity = State(initialValue: context.initialQuantity)
        _isFavorite = State(initialValue: context.searchResult.isFavorite)
    }

    private var scaledOverview: NutritionOverviewGridData {
        NutritionDraftBuilder.scaledOverview(
            context.searchResult.overview,
            ratio: servingRatio.rawValue * quantity
        )
    }

    private var detailInfo: NutritionDetailInfoData {
        NutritionViewDataMapper.detailInfo(from: scaledOverview)
    }

    private var ratingTags: [String] {
        NutritionFoodRatingTags.tags(for: context.searchResult.overview)
    }

    var body: some View {
        Group {
            if embedsNavigation {
                NavigationView {
                    detailContent
                }
                .navigationViewStyle(.stack)
            } else {
                detailContent
            }
        }
    }

    private var detailContent: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    foodHeader
                    NutritionOverviewGridCard(data: scaledOverview)

                    if context.searchResult.isVerified {
                        Text(L10n.text("nutrition.detail_add.verified"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(uiColor: .systemGreen))
                    }

                    if ratingTags.isEmpty == false {
                        ratingSection
                    }

                    NutritionDetailInfoCard(
                        titleKey: "nutrition.detail_add.nutrients",
                        data: detailInfo
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 160)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(L10n.text(mealType.localizationKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if embedsNavigation {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await toggleFavorite() }
                    } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .foregroundStyle(isFavorite ? Color(uiColor: .systemYellow) : .secondary)
                    }
                    .disabled(isTogglingFavorite)
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomAddPanel
            }
    }

    private var foodHeader: some View {
        Text(context.searchResult.title)
            .font(.title2.weight(.bold))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
    }

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("nutrition.detail_add.ratings"))
                .font(.subheadline.weight(.semibold))

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 96), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(ratingTags, id: \.self) { tagKey in
                    Text(L10n.text(tagKey))
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(uiColor: .tertiarySystemFill))
                        )
                }
            }
        }
    }

    private var bottomAddPanel: some View {
        VStack(spacing: 12) {
            Divider()

            HStack(spacing: 12) {
                quantityControl
                servingDescription
            }

            NutritionServingRatioPicker(selection: $servingRatio)

            Button {
                onPrimaryAction(servingRatio, quantity)
                if dismissOnPrimaryAction {
                    dismiss()
                }
            } label: {
                Group {
                    if isSaving {
                        ProgressView()
                            .tint(Color(uiColor: .systemBackground))
                    } else {
                        Text(L10n.text(primaryButtonKey))
                            .font(.headline.weight(.bold))
                    }
                }
                .foregroundStyle(Color(uiColor: .systemBackground))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black)
                }
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(.regularMaterial)
    }

    private var quantityControl: some View {
        HStack(spacing: 0) {
            Button {
                quantity = max(0.25, quantity - 0.25)
            } label: {
                Image(systemName: "minus")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)

            Text(NutritionFormatting.quantity(quantity))
                .font(.headline.weight(.semibold))
                .frame(minWidth: 36)

            Button {
                quantity += 0.25
            } label: {
                Image(systemName: "plus")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(uiColor: .systemGray4), lineWidth: 1)
        }
    }

    private var servingDescription: some View {
        HStack {
            Text(
                context.searchResult.subtitle.isEmpty
                    ? L10n.text("nutrition.detail_add.default_serving")
                    : context.searchResult.subtitle
            )
            .font(.subheadline)
            .lineLimit(2)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(uiColor: .systemGray4), lineWidth: 1)
        }
    }

    private func toggleFavorite() async {
        guard isTogglingFavorite == false else { return }
        isTogglingFavorite = true
        defer { isTogglingFavorite = false }

        let result = context.searchResult
        do {
            try await searchUseCase.toggleFavorite(
                targetType: result.favoriteTargetType,
                targetID: result.targetID,
                isFavorite: isFavorite
            )
            isFavorite.toggle()
        } catch {
            NutritionNotificationPresenter.presentError(
                store: notificationStore,
                messageKey: NutritionErrorMapper.messageKey(for: error),
                source: "nutrition.detail_add.favorite"
            )
        }
    }
}

enum NutritionFoodRatingTags {
    static func tags(for overview: NutritionOverviewGridData) -> [String] {
        var tags: [String] = []
        if overview.energyKcal <= 40 {
            tags.append("nutrition.rating.low_calorie")
        }
        if overview.carbohydrateGrams <= 5 {
            tags.append("nutrition.rating.low_carbohydrate")
        }
        if overview.fatGrams <= 3 {
            tags.append("nutrition.rating.low_fat")
        }
        if overview.proteinGrams >= 5 {
            tags.append("nutrition.rating.high_protein")
        }
        return tags
    }
}
