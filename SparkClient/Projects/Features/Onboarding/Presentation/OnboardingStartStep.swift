//
//  OnboardingStartStep.swift
//  SparkClient
//
//  Created by 話 on 2026/8/13.
//

import SwiftUI

struct OnboardingStartStep: View {
    let onStart: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            let bottomInset = proxy.safeAreaInsets.bottom
            let contentHeight = max(proxy.size.height - topInset - bottomInset - 12, 560)
            let heroHeight = contentHeight * 0.58
            let detailHeight = contentHeight * 0.42

            VStack(spacing: 0) {
                OnboardingStartHero()
                    .frame(maxWidth: .infinity)
                    .frame(height: heroHeight, alignment: .top)

                VStack(alignment: .leading, spacing: 16) {
                    onboardingPager

                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.text("onboarding.start.title", fallback: "准备好了，开始沉淀健康档案"))
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                            .lineSpacing(2)
                            .minimumScaleFactor(0.9)

                        Text(L10n.text("onboarding.start.subtitle", fallback: "成员、报告解读和用药识别能力已经就绪。接下来你可以直接进入 Spark，开始上传资料、管理健康记录。"))
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.secondary.opacity(0.82))
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 12) {
                        OnboardingStartCapabilityRow(
                            icon: "person.crop.circle.badge.checkmark",
                            title: "成员档案已建立",
                            subtitle: "后续资料会持续归入自己或家人的名下"
                        )
                        OnboardingStartCapabilityRow(
                            icon: "doc.text.magnifyingglass",
                            title: "报告可快速解读",
                            subtitle: "拍照上传后，Spark 会提炼重点摘要与异常提醒"
                        )
                        OnboardingStartCapabilityRow(
                            icon: "pills.fill",
                            title: "用药记录可继续沉淀",
                            subtitle: "识别药盒、药名与说明信息，逐步形成长期记录"
                        )
                    }

                    Spacer(minLength: 8)

                    Button(action: onStart) {
                        HStack(spacing: 12) {
                            Text(L10n.text("onboarding.action.enter", fallback: "进入 Spark"))
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
                    .buttonStyle(OnboardingStartPrimaryButtonStyle())
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
        .background(OnboardingStartBackground())
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
                .fill(OnboardingVisualStyle.accent.opacity(0.15))
                .frame(width: 42, height: 6)

            Capsule()
                .fill(OnboardingVisualStyle.accent.opacity(0.15))
                .frame(width: 42, height: 6)

            Capsule()
                .fill(OnboardingVisualStyle.accent)
                .frame(width: 62, height: 6)
        }
    }
}

private struct OnboardingStartHero: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: OnboardingVisualStyle.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.64))
                .overlay(
                    RoundedRectangle(cornerRadius: OnboardingVisualStyle.cardCornerRadius, style: .continuous)
                        .stroke(OnboardingVisualStyle.accent.opacity(0.10), lineWidth: 1)
                )

            VStack(spacing: 18) {
                HStack(alignment: .top) {
                    Label("Spark 已就绪", systemImage: "sparkles")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(0.9), in: Capsule(style: .continuous))
                        .foregroundStyle(OnboardingVisualStyle.accent)
                    Spacer()
                }

                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .fill(OnboardingVisualStyle.accent.opacity(0.10))
                        .frame(width: 164, height: 164)
                    Circle()
                        .fill(OnboardingVisualStyle.accent.opacity(0.16))
                        .frame(width: 116, height: 116)
                    Image(systemName: "checkmark")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(OnboardingVisualStyle.accent)
                }

                HStack(spacing: 12) {
                    OnboardingStartMetricCard(title: "成员", value: "已创建", icon: "person.2.fill")
                    OnboardingStartMetricCard(title: "报告", value: "可解读", icon: "waveform.path.ecg.text")
                    OnboardingStartMetricCard(title: "用药", value: "可识别", icon: "pills.fill")
                }

                Spacer(minLength: 0)
            }
            .padding(22)
        }
        .shadow(color: Color.black.opacity(0.10), radius: 20, x: 0, y: 14)
    }
}

private struct OnboardingStartMetricCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(OnboardingVisualStyle.accent)

            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(OnboardingVisualStyle.accent.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct OnboardingStartCapabilityRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(OnboardingVisualStyle.accentSoft)
                    .frame(width: 38, height: 38)

                Image(systemName: icon)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(OnboardingVisualStyle.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct OnboardingStartBackground: View {
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

private struct OnboardingStartPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: configuration.isPressed)
    }
}
