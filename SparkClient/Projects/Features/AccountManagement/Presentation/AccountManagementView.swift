import AuthenticationServices
import SwiftUI

struct AccountManagementView: View {
    @ObservedObject var viewModel: AccountManagementViewModel
    let session: UserSession
    @State private var showSignOutConfirm = false
    @State private var showAdvancedOptions = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let profile = viewModel.profile {
                        AccountProfileCard(profile: profile)
                        accountInfoSection(profile)
                    } else if viewModel.isLoadingProfile {
                        ProgressView()
                            .padding(.top, 48)
                    }

                    sessionSection
                    dangerSection
                }
                .padding(16)
                .padding(.bottom, 48)
            }
            .background(Color(.systemGroupedBackground))

            if viewModel.flowState.isOverlayPresented {
                overlay
            }
        }
        .navigationTitle("账户管理")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load(session: session)
        }
        .alert("操作失败", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { presented in
                if presented == false {
                    viewModel.clearError()
                }
            }
        )) {
            Button("好") {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("确认退出登录？", isPresented: $showSignOutConfirm) {
            Button("退出登录", role: .destructive) {
                Task { await viewModel.signOut() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("退出后将清除本机登录态与缓存的会话信息。")
        }
        .onChange(of: viewModel.otpCode) { _ in
            viewModel.completeOTPIfReady()
        }
    }

    private func accountInfoSection(_ profile: AccountProfile) -> some View {
        AccountSection(title: "账户信息") {
            AccountInfoRow(icon: "person.text.rectangle", tint: .blue, title: "账户 ID", value: "\(profile.accountID)")
            Divider()
            AccountInfoRow(icon: profile.signInMethod == .phone ? "phone.fill" : "envelope.fill", tint: .green, title: profile.signInMethod == .phone ? "手机号" : "邮箱", value: profile.contact)
            Divider()
            AccountInfoRow(icon: "checkmark.shield.fill", tint: .purple, title: "登录方式", value: profile.signInMethodDescription)
            Divider()
            AccountInfoRow(icon: "clock.fill", tint: .orange, title: "登录时间", value: profile.signedInAt.formatted(date: .abbreviated, time: .shortened))
        }
    }

    private var sessionSection: some View {
        AccountSection(title: "会话") {
            Button {
                showSignOutConfirm = true
            } label: {
                HStack(spacing: 12) {
                    AccountSquareBadge(color: .orange, icon: "rectangle.portrait.and.arrow.right")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("退出登录")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.red)
                        Text("清除本机登录态与缓存的会话信息")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if viewModel.isSigningOut {
                        ProgressView()
                    }
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var dangerSection: some View {
        AccountSection(title: "危险操作") {
            VStack(alignment: .leading, spacing: 14) {
                Text("销户将停用当前账户，相关数据会按服务端策略匿名化或清理。该流程需要身份验证和最终短语确认。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showAdvancedOptions.toggle()
                    }
                } label: {
                    HStack {
                        Text(showAdvancedOptions ? "隐藏高级选项" : "显示高级选项")
                        Image(systemName: showAdvancedOptions ? "chevron.up" : "chevron.down")
                    }
                    .font(.footnote.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)

                if showAdvancedOptions {
                    VStack(spacing: 12) {
                        Toggle("立即销户", isOn: $viewModel.options.immediateDeactivation)
                        if viewModel.options.immediateDeactivation == false {
                            Stepper(value: $viewModel.options.countdownHours, in: 1...168) {
                                HStack {
                                    Text("销户倒计时")
                                    Spacer()
                                    Text("\(viewModel.options.countdownHours) 小时")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Toggle("匿名化个人数据", isOn: $viewModel.options.anonymizePersonalData)
                        Toggle("删除关联数据", isOn: $viewModel.options.deleteRelatedData)
                        Stepper(value: $viewModel.options.dataRetentionDays, in: 0...365) {
                            HStack {
                                Text("数据保留天数")
                                Spacer()
                                Text("\(viewModel.options.dataRetentionDays) 天")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        TextField("销户原因（可选）", text: $viewModel.options.reason)
                            .textFieldStyle(.roundedBorder)
                    }
                    .font(.subheadline)
                }
            }
            .padding(16)

            Divider()

            Button(role: .destructive) {
                viewModel.beginDeactivation()
            } label: {
                HStack(spacing: 12) {
                    AccountSquareBadge(color: .red, icon: "trash.fill")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("注销账户")
                            .font(.body.weight(.semibold))
                        Text("永久删除账户和所有数据")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var overlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    if case .chooseVerification = viewModel.flowState {
                        viewModel.cancelFlow()
                    }
                }

            switch viewModel.flowState {
            case .chooseVerification:
                VerificationMethodCard(
                    channels: viewModel.availableVerificationChannels,
                    maskedTarget: { viewModel.maskedTarget(for: $0) },
                    onSelect: { channel in
                        Task { await viewModel.requestVerification(channel) }
                    },
                    onCancel: viewModel.cancelFlow
                )
            case .enteringOTP(let channel, _):
                OTPVerificationCard(
                    title: "账户注销验证",
                    subtitle: "请输入收到的 6 位验证码",
                    target: viewModel.maskedTarget(for: channel),
                    code: $viewModel.otpCode,
                    countdown: viewModel.resendCountdown,
                    onBack: {
                        viewModel.beginDeactivation()
                    },
                    onResend: {
                        Task { await viewModel.requestVerification(channel) }
                    }
                )
            case .appleReauth:
                AppleReauthCard(
                    onCancel: viewModel.cancelFlow,
                    onCompletion: handleAppleReauthResult
                )
            case .finalConfirmation:
                FinalDeleteConfirmationDialog(
                    phrase: viewModel.requiredConfirmationPhrase,
                    onCancel: viewModel.cancelFlow,
                    onConfirm: {
                        Task { await viewModel.submitFinalDeactivation() }
                    }
                )
            case .submitting:
                VStack(spacing: 14) {
                    ProgressView()
                    Text("正在提交注销申请...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            case .failed(let message):
                AccountFailureCard(message: message, onBack: viewModel.beginDeactivation, onCancel: viewModel.cancelFlow)
            case .idle, .completed:
                EmptyView()
            }
        }
        .transition(.opacity)
        .animation(.easeOut(duration: 0.2), value: viewModel.flowState)
    }

    private func handleAppleReauthResult(_ result: Result<ASAuthorization, Error>) {
        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8),
                  identityToken.isEmpty == false
            else {
                throw AccountManagementError.invalidAppleCredential
            }
            let authorizationCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            viewModel.completeAppleReauth(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                userIdentifier: credential.user
            )
        } catch {
            viewModel.failAppleReauth(error)
        }
    }
}

private struct AccountSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(.separator).opacity(0.35))
            }
        }
    }
}
