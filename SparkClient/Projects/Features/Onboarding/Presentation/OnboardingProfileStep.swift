import AVFoundation
import SwiftUI

struct OnboardingProfileStep: View {
    @ObservedObject var memberContextStore: MemberContextStore
    let homeDependencies: HomeFeatureDependencies?
    let onContinue: () -> Void
    @State private var activeMemberSetupRoute: MemberSetupCoverRoute?

    private enum MemberSetupCoverRoute: Identifiable {
        case create
        case maintain(Member)

        var id: String {
            switch self {
            case .create:
                return "create"
            case .maintain(let member):
                return "maintain-\(member.id)"
            }
        }
    }

    private var hasMembers: Bool {
        memberContextStore.context.members.isEmpty == false
    }

    var body: some View {
        ZStack {
            OnboardingProfileBackground()

            Group {
                if hasMembers {
                    OnboardingProfileMembersView(
                        members: memberContextStore.context.members,
                        onAdd: { activeMemberSetupRoute = .create },
                        onSelect: { member in
                            activeMemberSetupRoute = .maintain(member)
                        },
                        canMaintainMembers: homeDependencies != nil,
                        onContinue: onContinue
                    )
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .center))
                        )
                    )
                } else {
                    OnboardingProfileEmptyStateView(
                        onAdd: { activeMemberSetupRoute = .create }
                    )
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .leading)),
                            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .center))
                        )
                    )
                    .ignoresSafeArea(edges: .top)
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: hasMembers)
        }
        .fullScreenCover(item: $activeMemberSetupRoute) { route in
            CompatibleNavigationContainer(legacyStackStyle: true) {
                Group {
                    if let homeDependencies {
                        switch route {
                        case .create:
                            MemberSetupFlowView(store: memberContextStore, homeDependencies: homeDependencies)
                        case .maintain(let member):
                            MemberSetupFlowView(
                                mode: .maintain(member),
                                store: memberContextStore,
                                homeDependencies: homeDependencies
                            )
                        }
                    } else {
                        AddFamilyMemberView(mode: .create, store: memberContextStore)
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

private struct OnboardingProfileEmptyStateView: View {
    let onAdd: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            let bottomInset = proxy.safeAreaInsets.bottom
            let contentHeight = max(proxy.size.height - topInset - bottomInset - 12, 560)
            let heroHeight = contentHeight * OnboardingVisualStyle.heroRatio
            let detailHeight = contentHeight * OnboardingVisualStyle.detailRatio

            VStack(spacing: 0) {
                OnboardingProfileHeroCard()
                    .frame(maxWidth: .infinity)
                    .frame(height: heroHeight, alignment: .top)

                VStack(alignment: .leading, spacing: 14) {
                    OnboardingProfilePager()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("先添加成员，再开始记录")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.primary)
                            .lineSpacing(2)
                            .minimumScaleFactor(0.9)

                        Text("为自己或家人建立档案后，体检报告、检验结果、用药记录和 AI 解读都会自动归到对应成员名下。")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.secondary.opacity(0.82))
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 8) {
                        OnboardingProfileTag(icon: "person.crop.circle.badge.plus", title: "添加成员")
                        OnboardingProfileTag(icon: "heart.text.square", title: "健康归档")
                        OnboardingProfileTag(icon: "person.2.crop.square.stack", title: "家庭管理")
                    }

                    Spacer(minLength: 8)

                    Button(action: onAdd) {
                        HStack(spacing: 12) {
                            Text(L10n.text("onboarding.profile.add", fallback: "添加成员"))
                                .font(.headline)
                                .fontWeight(.semibold)
                            Image(systemName: "plus")
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
                    .buttonStyle(OnboardingProfilePrimaryButtonStyle())
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
    }
}

private struct OnboardingProfileMembersView: View {
    let members: [Member]
    let onAdd: () -> Void
    let onSelect: (Member) -> Void
    let canMaintainMembers: Bool
    let onContinue: () -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                OnboardingStepHeader(
                    icon: "person.text.rectangle",
                    title: L10n.text("onboarding.profile.title", fallback: "创建成员档案"),
                    subtitle: "成员是 Spark 的健康资料主线。你已经可以继续下一步，也可以先补充更多家人档案。"
                )

                VStack(spacing: 12) {
                    ForEach(members) { member in
                        Button {
                            onSelect(member)
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.12))
                                        .frame(width: 52, height: 52)
                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(Color.accentColor)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(member.name)
                                        .font(.headline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(MemberRelationshipCatalog.displayTitle(for: member.relationship))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 12)

                                VStack(alignment: .trailing, spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.green)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(Color.white.opacity(0.82))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(canMaintainMembers == false)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("继续之前，你还可以：")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        OnboardingProfileTag(icon: "plus", title: "继续添加家人")
                        OnboardingProfileTag(icon: "square.and.pencil", title: "完善档案")
                    }
                }

                Button(action: onAdd) {
                    HStack(spacing: 12) {
                        Text(L10n.text("onboarding.profile.add", fallback: "添加成员"))
                            .font(.headline)
                            .fontWeight(.semibold)
                        Image(systemName: "plus")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .foregroundStyle(OnboardingVisualStyle.accent)
                    .background(
                        RoundedRectangle(cornerRadius: OnboardingVisualStyle.buttonCornerRadius, style: .continuous)
                            .fill(OnboardingVisualStyle.pillBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: OnboardingVisualStyle.buttonCornerRadius, style: .continuous)
                            .stroke(OnboardingVisualStyle.accentStroke, lineWidth: 1)
                    )
                }
                .buttonStyle(OnboardingProfilePrimaryButtonStyle())
                           
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
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
            .buttonStyle(OnboardingProfilePrimaryButtonStyle())
            .padding(20)

        }
    }
}

private struct OnboardingProfileHeroCard: View {
    private let videoName = "onboarding-profile-member-guide"

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if let url = Bundle.main.url(forResource: videoName, withExtension: "mov") {
                    OnboardingLoopingVideoPlayerView(url: url, videoGravity: .resizeAspect)
                } else {
                    OnboardingProfileVideoFallback()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: OnboardingVisualStyle.cardCornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.12), radius: 20, x: 0, y: 14)
        }
    }
}

private struct OnboardingProfilePager: View {
    var body: some View {
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
                .fill(OnboardingVisualStyle.accent)
                .frame(width: 62, height: 6)

            Capsule()
                .fill(OnboardingVisualStyle.accent.opacity(0.15))
                .frame(width: 42, height: 6)
        }
    }
}

private struct OnboardingProfileTag: View {
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

private struct OnboardingProfileBackground: View {
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

private struct OnboardingProfilePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

private struct OnboardingProfileVideoFallback: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.97, blue: 1.0),
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
                            Text("成员档案")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("先绑定到人，再沉淀每一次记录和解读")
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.secondary)
                        }
                        .padding(20)
                    }
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 10) {
                            OnboardingProfileFallbackMetric(title: "成员主页", value: "1 人起步")
                            OnboardingProfileFallbackMetric(title: "报告归档", value: "自动归类")
                            OnboardingProfileFallbackMetric(title: "家庭管理", value: "持续扩展")
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

private struct OnboardingProfileFallbackMetric: View {
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
