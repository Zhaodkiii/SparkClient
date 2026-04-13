import SwiftUI
import UIKit

struct ChatKnowledgeCard: Codable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let content: String

    init(id: UUID = UUID(), title: String, content: String) {
        self.id = id
        self.title = title
        self.content = content
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case content
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        content = try c.decode(String.self, forKey: .content)
    }
}

/// 助手消息中的知识卡列表（AI_HLY 风格）。
/// 设计目标：
/// 1) 先在消息里预览知识卡内容；
/// 2) 用户逐卡点击保存；
/// 3) 保存中/已保存状态明确可见，避免重复提交。
struct ChatKnowledgeCardListView: View {
    let cards: [ChatKnowledgeCard]
    /// 点击某张卡片“保存”时回调给上层，由上层决定如何落库。
    let onSave: (ChatKnowledgeCard) -> Void
    /// 当前卡片是否处于保存中（用于按钮 loading 态）。
    let isSaving: (ChatKnowledgeCard) -> Bool
    /// 当前卡片是否已经保存（用于禁用按钮并展示“已保存”）。
    let isSaved: (ChatKnowledgeCard) -> Bool
    @State private var copiedCardID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(cards) { card in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label {
                            Text(card.title)
                                .font(.subheadline)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } icon: {
                            Image(systemName: "text.document")
                        }
                        .foregroundStyle(Color.accentColor)
                        Spacer(minLength: 0)

                        Button {
                            UIPasteboard.general.string = plainText(from: card.content)
                            copiedCardID = card.id
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                if copiedCardID == card.id {
                                    copiedCardID = nil
                                }
                            }
                        } label: {
                            Image(systemName: copiedCardID == card.id ? "checkmark" : "square.on.square")
                                .font(.caption)
                                .foregroundStyle(.white)
                        }
                        .padding(6)
                        .background(Color.accentColor)
                        .clipShape(Capsule())

                        Button {
                            // 组件只负责触发动作，不直接处理存储逻辑，保持 UI 与业务解耦。
                            onSave(card)
                        } label: {
                            if isSaving(card) {
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .scaleEffect(0.75)
                                    Text(L10n.text("chat.bubble.knowledge.saving"))
                                }
                                .font(.caption)
                                .padding(6)
                                .background(Color(uiColor: .systemGray5))
                                .foregroundStyle(.gray)
                                .clipShape(Capsule())
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: isSaved(card) ? "checkmark.circle.fill" : "backpack")
                                    Text(
                                        isSaved(card)
                                        ? L10n.text("chat.bubble.knowledge.saved_to_bag")
                                        : L10n.text("chat.bubble.knowledge.save_to_bag")
                                    )
                                }
                                .font(.caption)
                                .padding(6)
                                .background(isSaved(card) ? Color(uiColor: .systemGray5) : Color.accentColor)
                                .foregroundStyle(isSaved(card) ? .gray : .white)
                                .clipShape(Capsule())
                            }
                        }
                        // 保存中或已保存都禁用，防止重复请求。
                        .disabled(isSaving(card) || isSaved(card))
                    }

                    Divider()

                    Text(plainText(from: card.content))
                        .textSelection(.enabled)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: Color.accentColor.opacity(0.2), radius: 1)
            }
        }
    }

    private func plainText(from markdown: String) -> String {
        // 预览与复制时使用纯文本：剥离图片、链接包装和常见 Markdown 标记，避免噪声。
        markdown
            .replacingOccurrences(of: #"\!\[[^\]]*\]\([^\)]*\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"[#>*`_~\-]{1,}"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
