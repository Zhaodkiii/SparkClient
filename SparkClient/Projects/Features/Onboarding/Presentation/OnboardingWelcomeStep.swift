import SwiftUI

struct OnboardingWelcomeStep: View {
    let onStart: () -> Void

    @State private var heroAnimationPhase: OnboardingWelcomeHero.AnimationPhase = .idle

    var body: some View {
        OnboardingWelcomeHero(
            animationPhase: heroAnimationPhase,
            onStart: onStart
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .background(OnboardingWelcomeBackground())
        .task {
            await playEntranceAnimation()
        }
    }

    @MainActor
    private func playEntranceAnimation() async {
        guard heroAnimationPhase == .idle else { return }

        heroAnimationPhase = .spark
        try? await Task.sleep(for: .milliseconds(520))
        heroAnimationPhase = .topCards
        try? await Task.sleep(for: .milliseconds(880))
        heroAnimationPhase = .bottomCards
        try? await Task.sleep(for: .milliseconds(1120))
        heroAnimationPhase = .resultCard
        try? await Task.sleep(for: .milliseconds(1560))
        heroAnimationPhase = .cta
    }
}

private struct OnboardingWelcomeHero: View {
    enum AnimationPhase: Int {
        case idle
        case spark
        case topCards
        case bottomCards
        case resultCard
        case cta
    }

    let animationPhase: AnimationPhase
    let onStart: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(Color.white.opacity(0.62))
                .overlay(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .stroke(OnboardingVisualStyle.accent.opacity(0.10), lineWidth: 1)
                )

            VStack(spacing: 18) {
                HStack(spacing: 12) {
                    OnboardingWelcomeMiniCard(
                        title: "上传结果",
                        subtitle: "拍照后自动整理",
                        icon: "doc.viewfinder",
                        tint: OnboardingVisualStyle.accent
                    )
                    .offset(y: 24)
                    .modifier(
                        OnboardingWelcomeBubbleRevealModifier(
                            isVisible: animationPhase.rawValue >= AnimationPhase.topCards.rawValue,
                            delay: 0.0
                        )
                    )

                    OnboardingWelcomeMiniCard(
                        title: "AI 解读",
                        subtitle: "提炼重点异常",
                        icon: "waveform.path.ecg.text",
                        tint: OnboardingVisualStyle.accent
                    )
                    .offset(y: -10)
                    .modifier(
                        OnboardingWelcomeBubbleRevealModifier(
                            isVisible: animationPhase.rawValue >= AnimationPhase.topCards.rawValue,
                            delay: 0.08
                        )
                    )
                }

                OnboardingWelcomeMiniCard(
                    title: "成员归档",
                    subtitle: "持续沉淀自己和家人的健康记录",
                    icon: "person.2.crop.square.stack.fill",
                    tint: OnboardingVisualStyle.accent
                )
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .modifier(
                    OnboardingWelcomeBubbleRevealModifier(
                        isVisible: animationPhase.rawValue >= AnimationPhase.bottomCards.rawValue,
                        delay: 0.0
                    )
                )

                OnboardingWelcomeMiniCard(
                    title: "结果追踪",
                    subtitle: "异常、趋势和建议都能继续回看",
                    icon: "chart.line.text.clipboard",
                    tint: OnboardingVisualStyle.accent
                )
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 44)
                .modifier(
                    OnboardingWelcomeBubbleRevealModifier(
                        isVisible: animationPhase.rawValue >= AnimationPhase.resultCard.rawValue,
                        delay: 0.0
                    )
                )

                VStack(spacing: 18) {
                    Button(action: onStart) {
                        HStack(spacing: 12) {
                            Text("开始乐健康")
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
                    .buttonStyle(OnboardingWelcomePrimaryButtonStyle())
                }
                .padding(.horizontal, 44)
                .padding(.top, 34)
                .modifier(
                    OnboardingWelcomeBubbleRevealModifier(
                        isVisible: animationPhase.rawValue >= AnimationPhase.cta.rawValue,
                        delay: 0.0,
                        yOffset: 56,
                        scale: 0.88
                    )
                )
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 26)

            VStack {
                HStack {
                    Label("Spark", systemImage: "sparkles")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(0.88), in: Capsule(style: .continuous))
                        .foregroundStyle(OnboardingVisualStyle.accent)
                        .modifier(
                            OnboardingWelcomeBubbleRevealModifier(
                                isVisible: animationPhase.rawValue >= AnimationPhase.spark.rawValue,
                                delay: 0.0,
                                yOffset: 18,
                                scale: 0.92
                            )
                        )
                    Spacer()
                }
                Spacer()
            } .padding(18)
        }
        .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 14)
    }

    private var onboardingPager: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(OnboardingVisualStyle.accent)
                .frame(width: 62, height: 6)

            Capsule()
                .fill(OnboardingVisualStyle.accent.opacity(0.15))
                .frame(width: 42, height: 6)

            Capsule()
                .fill(OnboardingVisualStyle.accent.opacity(0.15))
                .frame(width: 42, height: 6)

            Capsule()
                .fill(OnboardingVisualStyle.accent.opacity(0.15))
                .frame(width: 42, height: 6)
        }
    }
}

private struct OnboardingWelcomeMiniCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint.opacity(0.2))
                    .frame(width: 46, height: 46)
                Image(systemName: icon)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(OnboardingVisualStyle.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(OnboardingVisualStyle.accent.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct OnboardingWelcomeBubbleRevealModifier: ViewModifier {
    let isVisible: Bool
    let delay: Double
    let yOffset: CGFloat
    let scale: CGFloat

    init(
        isVisible: Bool,
        delay: Double,
        yOffset: CGFloat = 44,
        scale: CGFloat = 0.82
    ) {
        self.isVisible = isVisible
        self.delay = delay
        self.yOffset = yOffset
        self.scale = scale
    }

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : scale, anchor: .center)
            .offset(y: isVisible ? 0 : yOffset)
            .blur(radius: isVisible ? 0 : 12)
            .animation(
                .spring(response: 0.95, dampingFraction: 0.82)
                    .delay(delay),
                value: isVisible
            )
    }
}

private struct OnboardingWelcomeBackground: View {
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

private struct OnboardingWelcomePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: configuration.isPressed)
    }
}
