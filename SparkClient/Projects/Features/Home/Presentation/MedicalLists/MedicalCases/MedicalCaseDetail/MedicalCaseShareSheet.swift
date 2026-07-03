import SwiftUI
import UIKit

struct MedicalCaseShareContext: Identifiable, Equatable {
    let id = UUID()
    let caseTitle: String
    let memberName: String
    let shareURL: URL
    let expiresAt: Date
}

private enum MedicalCaseShareChannel: String, CaseIterable, Identifiable {
    case wechat
    case xiaohongshu
    case copyLink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wechat: return "微信好友"
        case .xiaohongshu: return "小红书"
        case .copyLink: return "复制链接"
        }
    }

    var accentColor: Color {
        switch self {
        case .wechat: return Color(red: 0.18, green: 0.78, blue: 0.34)
        case .xiaohongshu: return Color(red: 0.95, green: 0.14, blue: 0.24)
        case .copyLink: return Color(uiColor: .secondarySystemBackground)
        }
    }

    var iconName: String {
        switch self {
        case .wechat: return "wechat"
        case .xiaohongshu: return "xiaohongshu"
        case .copyLink: return "link"
        }
    }
}

struct MedicalCaseShareSheet: View {
    let context: MedicalCaseShareContext
    let onDismiss: () -> Void

    @State private var statusText: String?

    private let wechatScheme = URL(string: "weixin://")!

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Spacer()
                Text("分享到")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }

            sharePreviewCard

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ],
                spacing: 12
            ) {
                ForEach(MedicalCaseShareChannel.allCases) { channel in
                    Button {
                        handle(channel: channel)
                    } label: {
                        VStack(spacing: 10) {
                            channelIcon(for: channel)
                            Text(channel.title)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 118)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if let statusText {
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Text("链接 10 天内有效")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: onDismiss) {
                Text("取消")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemBackground))
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .shareSheetPresentation()
    }

    private var sharePreviewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(context.caseTitle)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(context.memberName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("有效期至 \(Self.dateFormatter.string(from: context.expiresAt))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func channelIcon(for channel: MedicalCaseShareChannel) -> some View {
        switch channel {
        case .wechat:
            Image(channel.iconName)
                .resizable()
                .scaledToFit()
                .frame(width: 46, height: 46)
                .clipShape(Circle())
        case .xiaohongshu:
            Image(channel.iconName)
                .resizable()
                .scaledToFit()
                .frame(width: 46, height: 46)
                .clipShape(Circle())
        case .copyLink:
            Image(systemName: channel.iconName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 46, height: 46)
                .background(
                    Circle()
                        .fill(Color(uiColor: .systemBackground))
                )
        }
    }

    private func handle(channel: MedicalCaseShareChannel) {
        switch channel {
        case .wechat:
            copyShareLink()
            openTargetApp(url: wechatScheme, fallbackStatus: "已复制链接，可在微信中粘贴发送")
        case .xiaohongshu:
            copyShareLink()
            guard var components = URLComponents(string: "xhsdiscover://extweb") else {
                statusText = "已复制链接"
                return
            }
            components.queryItems = [
                URLQueryItem(
                    name: "link",
                    value: context.shareURL.absoluteString
                )
            ]
            guard let url = components.url else {
                statusText = "已复制链接"
                return
            }
            openTargetApp(url: url, fallbackStatus: "已复制链接，可在小红书中粘贴或继续编辑")
        case .copyLink:
            copyShareLink()
            statusText = "链接已复制"
        }
    }

    private func copyShareLink() {
//        UIPasteboard.general.string = "\(context.caseTitle)\n\(context.shareURL.absoluteString)"
        UIPasteboard.general.string = context.shareURL.absoluteString
    }

    private func openTargetApp(url: URL, fallbackStatus: String) {
        guard UIApplication.shared.canOpenURL(url) else {
            statusText = fallbackStatus
            return
        }
        UIApplication.shared.open(url, options: [:]) { success in
            statusText = success ? fallbackStatus : fallbackStatus
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

#Preview("MedicalCaseShareSheet") {
    MedicalCaseShareSheet(
        context: MedicalCaseShareContext(
            caseTitle: "发现乳腺结节 1天",
            memberName: "张**",
            shareURL: URL(string: "https://share.dreamwhale.top/s/AbC123xYz789")!,
            expiresAt: .now.addingTimeInterval(60 * 60 * 24 * 10)
        ),
        onDismiss: {}
    )
    .preferredColorScheme(.light)
}
