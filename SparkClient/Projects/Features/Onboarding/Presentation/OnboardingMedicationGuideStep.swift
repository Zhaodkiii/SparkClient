import AVFoundation
import SwiftUI

struct OnboardingMedicationGuideStep: View {
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            let bottomInset = proxy.safeAreaInsets.bottom
            let contentHeight = max(proxy.size.height - topInset - bottomInset - 12, 560)
            let heroHeight = contentHeight * OnboardingVisualStyle.heroRatio
            let detailHeight = contentHeight * OnboardingVisualStyle.detailRatio

            VStack(spacing: 0) {
                OnboardingMedicationGuideHeroCard()
                    .frame(maxWidth: .infinity)
                    .frame(height: heroHeight, alignment: .top)

                VStack(alignment: .leading, spacing: 14) {
                    onboardingPager

                    VStack(alignment: .leading, spacing: 10) {
                        Text("设置用药计划，按时提醒")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.primary)
                            .lineSpacing(2)
                            .minimumScaleFactor(0.9)

                        Text("把药品、剂量和服用时间整理成计划，Spark 会持续提醒并保留每天的执行记录。")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.secondary.opacity(0.82))
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 8) {
                        OnboardingMedicationGuideTag(icon: "pills.fill", title: "录入药品")
                        OnboardingMedicationGuideTag(icon: "bell.badge.fill", title: "准时提醒")
                        OnboardingMedicationGuideTag(icon: "checklist.checked", title: "完成记录")
                    }

                    Spacer(minLength: 8)

                    Button(action: onContinue) {
                        HStack(spacing: 12) {
                            Text("继续")
                                .font(.headline)
                                .fontWeight(.semibold)
                            Image(systemName: "arrow.right")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: OnboardingVisualStyle.buttonCornerRadius, style: .continuous)
                                .fill(OnboardingVisualStyle.accent)
                        )
                    }
                    .buttonStyle(OnboardingMedicationGuidePrimaryButtonStyle())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: detailHeight, alignment: .top)
                .padding(.top, 10)
            }
            .padding(.horizontal, OnboardingVisualStyle.horizontalPadding)
            .padding(.top, topInset + 2)
            .padding(.bottom, bottomInset + 10)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea(edges: .top)
        .background(OnboardingMedicationGuideBackground())
    }

    private var onboardingPager: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(OnboardingVisualStyle.accent.opacity(0.15))
                .frame(width: 42, height: 6)

            Capsule()
                .fill(OnboardingVisualStyle.accent.opacity(0.15))
                .frame(width: 42, height: 6)

            Capsule()
                .fill(OnboardingVisualStyle.accent)
                .frame(width: 62, height: 6)

            Capsule()
                .fill(OnboardingVisualStyle.accent.opacity(0.15))
                .frame(width: 42, height: 6)

            Capsule()
                .fill(OnboardingVisualStyle.accent.opacity(0.15))
                .frame(width: 42, height: 6)
        }
    }
}

private struct OnboardingMedicationGuideHeroCard: View {
    private let videoName = "onboarding-medication-guide"

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if let url = Bundle.main.url(forResource: videoName, withExtension: "m4v") {
                    OnboardingLoopingVideoPlayerView(url: url, videoGravity: .resizeAspect)
                } else {
                    OnboardingMedicationGuideVideoFallback()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: OnboardingVisualStyle.cardCornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.12), radius: 20, x: 0, y: 14)
        }
    }
}

private struct OnboardingMedicationGuideTag: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .fontWeight(.semibold)
            Text(title)
                .font(.callout)
                .fontWeight(.semibold)
        }
        .foregroundStyle(OnboardingVisualStyle.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(OnboardingVisualStyle.pillBackground)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(OnboardingVisualStyle.accentStroke, lineWidth: 1)
        )
    }
}

private struct OnboardingMedicationGuideBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color(.secondarySystemBackground),
                Color(.systemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(OnboardingVisualStyle.accent.opacity(0.16))
                .frame(width: 220, height: 220)
                .blur(radius: 12)
                .offset(x: 70, y: -30)
        }
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(OnboardingVisualStyle.accent.opacity(0.08))
                .frame(width: 180, height: 180)
                .blur(radius: 20)
                .offset(x: -60, y: 120)
        }
        .ignoresSafeArea()
    }
}

private struct OnboardingMedicationGuidePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

private struct OnboardingMedicationGuideVideoFallback: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.98, blue: 0.93),
                    Color.white
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 16) {
                Spacer(minLength: 0)

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.94))
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("今日用药")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("早餐后 1 次，晚饭后 1 次")
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                        .padding(20)
                    }
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 12) {
                            OnboardingMedicationGuideMetric(title: "提醒时间", value: "08:00 / 20:00")
                            OnboardingMedicationGuideMetric(title: "执行状态", value: "已记录")
                            OnboardingMedicationGuideMetric(title: "剩余疗程", value: "12 天")
                        }
                        .padding(20)
                    }
                    .frame(height: 360)

                Spacer(minLength: 0)
            }
            .padding(22)
        }
    }
}

private struct OnboardingMedicationGuideMetric: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.callout)
                .fontWeight(.medium)
                .foregroundStyle(Color.secondary)
            Spacer()
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(Color.primary)
        }
    }
}
