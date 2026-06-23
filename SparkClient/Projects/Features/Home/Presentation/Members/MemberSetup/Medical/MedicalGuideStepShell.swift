import SwiftUI

struct MedicalGuideStepShell<Content: View>: View {
    let title: String
    let subtitle: String
    let step: Int
    let total: Int
    let isLoading: Bool
    let primaryTitle: String?
    let primaryEnabled: Bool
    let secondaryTitle: String?
    let showsPrimaryButton: Bool
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
        showsPrimaryButton: Bool = true,
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
        self.showsPrimaryButton = showsPrimaryButton
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
            showsPrimaryButton: showsPrimaryButton,
            onPrimary: onNext,
            secondaryTitle: showsSkipButton ? (secondaryTitle ?? "跳过") : nil,
            onSecondary: showsSkipButton ? onSkip : nil
        )
    }
}
