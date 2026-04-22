import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @ObservedObject var viewModel: LoginViewModel

    @State private var goPhone = false
    @State private var showPhoneLogin = false
    @State private var tapCount = 0
    @State private var lastTapTime: Date?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerCluster
                actionButtons
                safetyCard

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
            .background(
                NavigationLink(isActive: $goPhone) {
                    PhoneLoginView(viewModel: viewModel)
                        .navigationTitle("手机号登录")
                } label: {
                    EmptyView()
                }
                .hidden()
            )
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(L10n.text("auth.login.title"))
                    .font(.headline)
                    .fontWeight(.semibold)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .disabled(viewModel.isLoading)
        .overlay {
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
            }
        }
    }

    private var headerCluster: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(uiColor: .systemBlue), Color(uiColor: .systemIndigo)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "shield")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.95))
                    .font(.largeTitle.weight(.semibold))
            }
            .frame(width: 90, height: 90)
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
            .onTapGesture {
                handleIconTap()
            }

            VStack(spacing: 6) {
                Text(L10n.text("auth.login.welcome"))
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(L10n.text("auth.login.subtitle"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 6)
        }
        .padding(.top, 28)
    }

    private var actionButtons: some View {
        VStack(spacing: 14) {
            SignInWithAppleButton(
                .signIn,
                onRequest: { request in
                    viewModel.prepareAppleRequest(request)
                },
                onCompletion: { result in
                    Task {
                        await viewModel.signInWithApple(result: result)
                    }
                }
            )
            .signInWithAppleButtonStyle(.black)
            .frame(height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if showPhoneLogin {
                HStack {
                    Rectangle().fill(Color.gray.opacity(0.2)).frame(height: 1)
                    Text("或")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                    Rectangle().fill(Color.gray.opacity(0.2)).frame(height: 1)
                }
                .padding(.vertical, 6)

                Button {
                    goPhone = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "phone").font(.body)
                        Text(L10n.text("auth.login.phone_button"))
                            .font(.body)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(
                    OutlinedButtonStyle(
                        tint: Color.accentColor.opacity(0.35),
                        hover: Color.accentColor.opacity(0.12)
                    )
                )
            }
        }
    }

    private func handleIconTap() {
        let now = Date()
        if let lastTapTime, now.timeIntervalSince(lastTapTime) > 1.0 {
            tapCount = 0
        }

        tapCount += 1
        lastTapTime = now

        if tapCount >= 3 {
            showPhoneLogin = true
            tapCount = 0
        }
    }

    private var safetyCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shield")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(uiColor: .systemBlue))
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("auth.login.safety_title"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text(L10n.text("auth.login.safety_body"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.5))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview("Login - Light") {
    CompatibleNavigationContainer {
        LoginView(viewModel: AppContainer.preview.makeLoginViewModel())
    }
    .preferredColorScheme(.light)
}

#Preview("Login - Dark") {
    CompatibleNavigationContainer {
        LoginView(viewModel: AppContainer.preview.makeLoginViewModel())
    }
    .preferredColorScheme(.dark)
}
