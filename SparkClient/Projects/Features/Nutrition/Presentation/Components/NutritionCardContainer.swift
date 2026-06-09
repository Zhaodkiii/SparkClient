import SwiftUI

struct NutritionCardContainer<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(uiColor: .separator).opacity(0.35), lineWidth: 1)
            )
    }
}

struct NutritionLoadingStateView: View {
    let messageKey: String

    var body: some View {
        NutritionCardContainer {
            VStack(spacing: 12) {
                ProgressView()
                Text(L10n.text(messageKey))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
        .accessibilityElement(children: .combine)
    }
}

struct NutritionEmptyStateView: View {
    let titleKey: String
    let subtitleKey: String

    var body: some View {
        NutritionCardContainer {
            VStack(spacing: 8) {
                Image(systemName: "fork.knife.circle")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text(L10n.text(titleKey))
                    .font(.headline)
                Text(L10n.text(subtitleKey))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }
}

struct NutritionErrorStateView: View {
    let messageKey: String
    let retryTitleKey: String
    let onRetry: () -> Void

    var body: some View {
        NutritionCardContainer {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)
                Text(L10n.text(messageKey))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(action: onRetry) {
                    Text(L10n.text(retryTitleKey))
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }
}

#Preview("Nutrition States Light") {
    ScrollView {
        VStack(spacing: 16) {
            NutritionLoadingStateView(messageKey: "nutrition.home.loading")
            NutritionEmptyStateView(
                titleKey: "nutrition.home.empty.title",
                subtitleKey: "nutrition.home.empty.subtitle"
            )
            NutritionErrorStateView(
                messageKey: "nutrition.home.error.load_failed",
                retryTitleKey: "nutrition.common.retry"
            ) {}
        }
        .padding()
    }
}
