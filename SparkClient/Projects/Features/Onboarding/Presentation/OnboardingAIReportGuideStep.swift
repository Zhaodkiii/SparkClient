import AVFoundation
import SwiftUI

struct OnboardingAIReportGuideStep: View {
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            let bottomInset = proxy.safeAreaInsets.bottom
            let contentHeight = max(proxy.size.height - topInset - bottomInset - 12, 560)
            let heroHeight = contentHeight * OnboardingVisualStyle.heroRatio
            let detailHeight = contentHeight * OnboardingVisualStyle.detailRatio

            VStack(spacing: 0) {
                OnboardingAIReportGuideHeroCard()
                    .frame(maxWidth: .infinity)
                    .frame(height: heroHeight, alignment: .top)

                VStack(alignment: .leading, spacing: 14) {
                    onboardingPager

                    VStack(alignment: .leading, spacing: 10) {
                        Text("拍照上传，AI 解读报告")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.primary)
                            .lineSpacing(2)
                            .minimumScaleFactor(0.9)

                        Text("对准体检单、检验单或影像结果，快速生成重点摘要、异常提示和可回看的健康存档。")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.secondary.opacity(0.82))
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 8) {
                        OnboardingAIReportGuideTag(icon: "doc.text.viewfinder", title: "拍照识别")
                        OnboardingAIReportGuideTag(icon: "brain.head.profile", title: "AI 解读")
                        OnboardingAIReportGuideTag(icon: "tray.full", title: "自动归档")
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
                    .buttonStyle(OnboardingAIReportGuidePrimaryButtonStyle())
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
        .background(OnboardingAIReportGuideBackground())
    }

    private var onboardingPager: some View {
        HStack(spacing: 10) {
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

            Capsule()
                .fill(OnboardingVisualStyle.accent.opacity(0.15))
                .frame(width: 42, height: 6)
        }
    }
}

private struct OnboardingAIReportGuideHeroCard: View {
    private let videoName = "onboarding-welcome-report-demo"

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if let url = Bundle.main.url(forResource: videoName, withExtension: "mov") {
                    OnboardingLoopingVideoPlayerView(url: url, videoGravity: .resizeAspect)
                } else {
                    OnboardingAIReportGuideVideoFallback()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: OnboardingVisualStyle.cardCornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.12), radius: 20, x: 0, y: 14)
        }
    }
}

private struct OnboardingAIReportGuideTag: View {
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

private struct OnboardingAIReportGuideBackground: View {
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

private struct OnboardingAIReportGuidePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

private struct OnboardingAIReportGuideVideoFallback: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.94, blue: 0.88),
                    Color.white
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 16) {
                Spacer(minLength: 0)

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.92))
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("AI 解读报告")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("自动抓重点、标异常、整理到成员档案")
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.secondary)
                        }
                        .padding(20)
                    }
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 10) {
                            OnboardingAIReportGuideMetric(title: "异常指标", value: "6 项")
                            OnboardingAIReportGuideMetric(title: "重点建议", value: "3 条")
                            OnboardingAIReportGuideMetric(title: "同步存档", value: "已完成")
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

private struct OnboardingAIReportGuideMetric: View {
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
