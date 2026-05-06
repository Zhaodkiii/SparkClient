import AuthenticationServices
import SwiftUI

struct AccountProfileCard: View {
    let profile: AccountProfile

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 76, height: 76)
                Image(systemName: "person.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text(profile.displayName.isEmpty ? profile.contact : profile.displayName)
                .font(.title3.weight(.semibold))
            Text(profile.signInMethodDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.35))
        }
    }
}

struct AccountInfoRow: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            AccountSquareBadge(color: tint, icon: icon)
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .font(.subheadline)
        }
        .padding(16)
    }
}

struct AccountSquareBadge: View {
    let color: Color
    let icon: String

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(color)
            .frame(width: 32, height: 32)
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

struct VerificationMethodCard: View {
    let channels: [AccountVerificationChannel]
    let maskedTarget: (AccountVerificationChannel) -> String
    let onSelect: (AccountVerificationChannel) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("安全验证", systemImage: "shield.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(.orange)
            Text("为了确保账户安全，注销账户前需要进行身份验证。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(Array(channels.enumerated()), id: \.offset) { _, channel in
                    Button {
                        onSelect(channel)
                    } label: {
                        HStack(spacing: 12) {
                            AccountSquareBadge(color: badgeColor(for: channel), icon: icon(for: channel))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(channel.title)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Text(maskedTarget(channel))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)
            }
        }
        .accountOverlayCard()
    }

    private func icon(for channel: AccountVerificationChannel) -> String {
        switch channel {
        case .apple:
            return "applelogo"
        case .phone:
            return "phone.fill"
        case .email:
            return "envelope.fill"
        }
    }

    private func badgeColor(for channel: AccountVerificationChannel) -> Color {
        switch channel {
        case .apple:
            return .black
        case .phone:
            return .green
        case .email:
            return .red
        }
    }
}

struct OTPVerificationCard: View {
    let title: String
    let subtitle: String
    let target: String
    @Binding var code: String
    let countdown: Int
    let onBack: () -> Void
    let onResend: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                }
                Spacer()
            }
            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.bold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("验证码已发送至 \(target)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VerificationCodeField(code: $code, length: 6)
            if countdown > 0 {
                Text("重新发送 \(countdown)s")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Button("重新发送", action: onResend)
                    .buttonStyle(.bordered)
            }
        }
        .accountOverlayCard()
    }
}

struct AppleReauthCard: View {
    let onCancel: () -> Void
    let onCompletion: (Result<ASAuthorization, Error>) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Apple 身份验证", systemImage: "applelogo")
                .font(.title3.weight(.bold))
            Text("请使用注册时的 Apple ID 重新验证身份。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = []
            } onCompletion: { result in
                onCompletion(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 46)
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)
            }
        }
        .accountOverlayCard()
    }
}

struct FinalDeleteConfirmationDialog: View {
    let phrase: String
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @State private var confirmText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("确认注销账户")
                .font(.headline)
            Text("注销账户将会：")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                BulletLine("永久删除所有聊天与知识库数据")
                BulletLine("删除所有健康档案与医疗记录")
                BulletLine("清除账户身份、设备和同步状态")
                BulletLine("该操作不可恢复")
            }
            .font(.subheadline)
            Text("此操作不可恢复！")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 8) {
                Text(#"请输入"删除我的账户"确认："#)
                    .font(.subheadline.weight(.medium))
                TextField(phrase, text: $confirmText)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)
                Button("确认删除", role: .destructive, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .disabled(confirmText != phrase)
                    .opacity(confirmText == phrase ? 1 : 0.6)
            }
        }
        .accountOverlayCard(maxWidth: 520)
    }
}

struct AccountFailureCard: View {
    let message: String
    let onBack: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("处理失败", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)
                Button("重新开始", action: onBack)
                    .buttonStyle(.borderedProminent)
            }
        }
        .accountOverlayCard()
    }
}

private struct BulletLine: View {
    let text: String
    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(Color.secondary)
                .frame(width: 4, height: 4)
            Text(text)
        }
    }
}

private extension View {
    func accountOverlayCard(maxWidth: CGFloat = 420) -> some View {
        self
            .padding(18)
            .frame(maxWidth: maxWidth)
            .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(.separator).opacity(0.4))
            }
            .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
            .padding(.horizontal, 16)
    }
}

