import SwiftUI

enum ChatSenderIcon: Equatable, Sendable {
    /// SF Symbol，对应 `AIScenarioRemoteModelRow.icon`
    case systemName(String)
    /// Assets 图片名，对应 `companyIconName(for:)`
    case companyLogo(String)
}

enum ChatMessageSenderKind: Equatable, Sendable {
    case aiModel(displayName: String, icon: ChatSenderIcon)
    case doctor(displayName: String, avatarURL: String?)
    /// 医生智能体（AI 发言）：展示服务端解析后的智能体头像。
    case aiAgent(displayName: String, avatarURL: String?)
}

/// assistant 消息气泡上方的发送者头部：头像 + 名称（仅 AI 模型使用）。
struct ChatMessageSenderHeaderView: View {
    let kind: ChatMessageSenderKind

    private let avatarSize: CGFloat = 24

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            avatar
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
    }

    private var name: String {
        switch kind {
        case .aiModel(let displayName, _):
            return displayName
        case .doctor(let displayName, _):
            return displayName
        case .aiAgent(let displayName, _):
            return displayName
        }
    }

    @ViewBuilder
    private var avatar: some View {
        switch kind {
        case .aiModel(_, let icon):
            modelAvatar(icon)
        case .doctor(let displayName, let avatarURL):
            ChatDoctorAvatarView(displayName: displayName, avatarURL: avatarURL, size: avatarSize)
        case .aiAgent(let displayName, let avatarURL):
            ChatDoctorAvatarView(displayName: displayName, avatarURL: avatarURL, size: avatarSize)
        }
    }

    @ViewBuilder
    private func modelAvatar(_ icon: ChatSenderIcon) -> some View {
        switch icon {
        case .systemName(let systemName):
            Image(systemName: systemName)
                .resizable()
                .scaledToFit()
                .frame(width: avatarSize, height: avatarSize)
                .foregroundStyle(.secondary)
        case .companyLogo(let imageName):
            Image(imageName)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: avatarSize, height: avatarSize)
        }
    }
}

/// 真人医生头像：圆角方图；无 URL 时用姓氏字。加载复用通用文件缓存并按比例保留上半部分。
struct ChatDoctorAvatarView: View {
    let displayName: String
    let avatarURL: String?
    var size: CGFloat = 40

    var body: some View {
        HospitalAvatarImageView(
            urlString: avatarURL ?? "",
            size: size,
            shape: .roundedSquare(ratio: 0.18),
            placeholderText: ChatMessageSenderHeaderResolver.surnameCharacter(from: displayName)
        )
    }
}

/// 微信式来信气泡：左侧小三角指向头像。
struct ChatDoctorIncomingBubbleShape: Shape {
    var cornerRadius: CGFloat = 10
    var tailWidth: CGFloat = 6
    var tailHeight: CGFloat = 8
    var tailTopOffset: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bubble = CGRect(
            x: tailWidth,
            y: 0,
            width: max(0, rect.width - tailWidth),
            height: rect.height
        )
        path.addRoundedRect(in: bubble, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))

        let tip = CGPoint(x: 0, y: tailTopOffset + tailHeight / 2)
        let top = CGPoint(x: tailWidth + 0.5, y: tailTopOffset)
        let bottom = CGPoint(x: tailWidth + 0.5, y: tailTopOffset + tailHeight)
        path.move(to: top)
        path.addLine(to: tip)
        path.addLine(to: bottom)
        path.closeSubpath()
        return path
    }
}
