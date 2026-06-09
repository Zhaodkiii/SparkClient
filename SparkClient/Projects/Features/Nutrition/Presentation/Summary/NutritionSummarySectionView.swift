import SwiftUI


struct NutritionSummarySectionView: View {
    let dashboard: NutritionDashboardViewData
    let dashboardUseCase: NutritionDashboardUseCase
    let dependencies: NutritionFeatureDependencies
    let memberID: Int
    let date: Date

    var body: some View {
        VStack(spacing: 20) {
            sectionHeader

            NutritionSummaryCardView(
                consumed: NutritionFormatting.compactEnergy(dashboard.consumedEnergyKcal),
                remaining: remainingText,
                burned: NutritionFormatting.compactEnergy(dashboard.burnedEnergyKcal),
                intakeProgress: dashboard.intakeProgress,
                carbohydrate: dashboard.carbohydrate,
                protein: dashboard.protein,
                fat: dashboard.fat,
                isOverBudget: dashboard.remainingEnergyKcal < 0
            )
        }
    }

    private var sectionHeader: some View {
        HStack {
            Text(L10n.text("nutrition.home.summary.title"))
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(.primary)

            Spacer()

            NavigationLink {
                NutritionSummaryDetailView(
                    dashboardUseCase: dashboardUseCase,
                    memberID: memberID,
                    date: date,
                    initialDashboard: dashboard
                )
            } label: {
                Text(L10n.text("nutrition.home.summary.detail"))
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(Color(uiColor: .systemTeal))
            }
            .buttonStyle(.plain)
        }
    }

    private var remainingText: String {
        if dashboard.remainingEnergyKcal < 0 {
            return String(
                format: L10n.text("nutrition.summary.over_budget"),
                locale: Locale.current,
                NutritionFormatting.compactEnergy(abs(dashboard.remainingEnergyKcal))
            )
        }

        return NutritionFormatting.compactEnergy(dashboard.remainingEnergyKcal)
    }
}

private struct NutritionSummaryCardView: View {
    let consumed: String
    let remaining: String
    let burned: String
    let intakeProgress: Double
    let carbohydrate: NutritionMacroProgress
    let protein: NutritionMacroProgress
    let fat: NutritionMacroProgress
    let isOverBudget: Bool

    private let accent = Color(uiColor: .systemTeal)

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 28) {
                topArea

                HStack(alignment: .top, spacing: 20) {
                    macroItem(
                        title: L10n.text("nutrition.macro.carbohydrate"),
                        progress: carbohydrate
                    )

                    macroItem(
                        title: L10n.text("nutrition.macro.protein"),
                        progress: protein
                    )

                    macroItem(
                        title: L10n.text("nutrition.macro.fat"),
                        progress: fat
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 36)
            .padding(.bottom, 32)

            fastingBar
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(uiColor: .separator), lineWidth: 1)
        }
    }

    private var topArea: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let ringSize = min(width * 0.42, 160)

            HStack(alignment: .center, spacing: 0) {
                metricColumn(
                    value: consumed,
                    title: L10n.text("nutrition.summary.consumed")
                )
                .frame(maxWidth: .infinity)

                ZStack {
                    intakeRing
                        .frame(width: ringSize, height: ringSize)

                    VStack(spacing: 6) {
                        Text(remaining)
                            .font(.title)
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .foregroundStyle(isOverBudget ? Color(uiColor: .systemRed) : .primary)

                        Text(L10n.text("nutrition.summary.remaining"))
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                }
                .frame(width: ringSize)

                metricColumn(
                    value: burned,
                    title: L10n.text("nutrition.summary.burned")
                )
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 170)
    }

    private var intakeRing: some View {
        ZStack {
            Circle()
                .trim(from: 0.08, to: 0.92)
                .stroke(
                    Color(uiColor: .systemGray5),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(90))

            Circle()
                .trim(
                    from: 0.08,
                    to: 0.08 + 0.84 * CGFloat(min(max(intakeProgress, 0), 1))
                )
                .stroke(
                    accent,
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: intakeProgress)
    }

    private func metricColumn(value: String, title: String) -> some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.primary)

            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func macroItem(title: String, progress: NutritionMacroProgress) -> some View {
        let value = progress.target > 0 ? min(progress.current / progress.target, 1) : 0

        return VStack(spacing: 12) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            CapsuleProgressView(value: value, tint: accent)
                .frame(height: 8)

            Text("\(NutritionFormatting.compactEnergy(progress.current)) / \(NutritionFormatting.compactEnergy(progress.target))\(progress.unit)")
                .font(.body)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private var fastingBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.stars.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(uiColor: .systemOrange))

            Text("现在：禁食")
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(uiColor: .tertiarySystemGroupedBackground))
    }
}

private struct CapsuleProgressView: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(uiColor: .systemGray5))

                Capsule()
                    .fill(tint)
                    .frame(width: max(8, proxy.size.width * CGFloat(min(max(value, 0), 1))))
            }
        }
        .clipShape(Capsule())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: value)
    }
}

private struct FoodAddMealSelection: Identifiable {
    let mealType: NutritionMealType
    var id: NutritionMealType { mealType }
}

struct NutritionMealsSectionView: View {
    let meals: [NutritionMealSectionViewData]
    let dependencies: NutritionFeatureDependencies
    let memberID: Int
    let date: Date

    @State private var foodAddMealType: FoodAddMealSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader

            VStack(spacing: 0) {
                ForEach(Array(meals.enumerated()), id: \.element.id) { index, meal in
                    mealRow(meal)

                    if index < meals.count - 1 {
                        Divider()
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color(uiColor: .separator), lineWidth: 1)
            }
        }
        .notificationFullScreenCover(
            item: $foodAddMealType,
            store: dependencies.notificationStore
        ) { selection in
            CompatibleNavigationContainer {
                NutritionFoodAddView(
                    dependencies: dependencies,
                    memberID: memberID,
                    date: date,
                    mealType: selection.mealType
                )
            }
        }
    }

    private var sectionHeader: some View {
        HStack {
            Text(L10n.text("nutrition.home.meals.title"))
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(.primary)

            Spacer()

            NavigationLink {
                NutritionDetailView(
                    dependencies: dependencies,
                    memberID: memberID,
                    date: date
                )
            } label: {
                Text(L10n.text("nutrition.home.meals.more"))
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(Color(uiColor: .systemTeal))
            }
            .buttonStyle(.plain)
        }
    }

    private func mealRow(_ meal: NutritionMealSectionViewData) -> some View {
        HStack(spacing: 20) {
            NavigationLink {
                NutritionMealDetailView(
                    dependencies: dependencies,
                    memberID: memberID,
                    date: date,
                    mealType: meal.mealType
                )
            } label: {
                HStack(spacing: 20) {
                    mealIcon(meal)

                    mealTextContent(meal)

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                foodAddMealType = FoodAddMealSelection(mealType: meal.mealType)
            } label: {
                addFoodButtonLabel
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(minHeight: 88)
    }

    private func mealIcon(_ meal: NutritionMealSectionViewData) -> some View {
        ZStack {
            Circle()
                .stroke(
                    Color(uiColor: .systemGray5),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )

            Circle()
                .trim(from: 0, to: mealProgress(meal))
                .stroke(
                    Color(uiColor: .systemTeal),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: mealProgress(meal))

            Image(systemName: meal.mealType.iconName)
                .font(.subheadline)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(meal.mealType.iconColor)
        }
        .frame(width: 60, height: 60)
        .accessibilityHidden(true)
    }

    private func mealTextContent(_ meal: NutritionMealSectionViewData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(L10n.text(meal.mealType.localizationKey))
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)

                if #available(iOS 16.0, *) {
                    Image(systemName: "arrow.right")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                } else {
                    Image(systemName: "arrow.right")
                        .font(.headline.bold())
                        .foregroundStyle(.primary)
                }
            }

            Text(
                NutritionFormatting.mealEnergyProgress(
                    consumed: meal.consumedEnergyKcal,
                    target: meal.targetEnergyKcal
                )
            )
            .font(.headline)
            .fontWeight(.semibold)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            if let summary = meal.foodSummary, summary.isEmpty == false {
                Text(summary)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private func mealProgress(_ meal: NutritionMealSectionViewData) -> CGFloat {
        guard meal.targetEnergyKcal > 0 else { return 0 }
        return CGFloat(min(max(meal.consumedEnergyKcal / meal.targetEnergyKcal, 0), 1))
    }

    @ViewBuilder
    private var addFoodButtonLabel: some View {
        if #available(iOS 16.0, *) {
            Image(systemName: "plus")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(Color(uiColor: .systemBackground))
                .frame(width: 42, height: 42)
                .background {
                    Circle()
                        .fill(Color.primary)
                }
                .contentShape(Circle())
        } else {
            Image(systemName: "plus")
                .font(.headline)
                .foregroundStyle(Color(uiColor: .systemBackground))
                .frame(width: 42, height: 42)
                .background {
                    Circle()
                        .fill(Color.primary)
                }
                .contentShape(Circle())
        }
    }
}

private extension NutritionMealType {
    var iconName: String {
        switch self {
        case .breakfast:
            return "cup.and.saucer.fill"
        case .lunch:
            return "fork.knife.circle.fill"
        case .dinner:
            return "carrot.fill"
        case .snack:
            return "apple.logo"
        }
    }

    var iconColor: Color {
        switch self {
        case .breakfast:
            return Color(uiColor: .systemBrown)
        case .lunch:
            return Color(uiColor: .systemOrange)
        case .dinner:
            return Color(uiColor: .systemGreen)
        case .snack:
            return Color(uiColor: .systemRed)
        }
    }
}
