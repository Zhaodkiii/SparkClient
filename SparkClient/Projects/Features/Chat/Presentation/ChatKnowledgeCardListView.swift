import CryptoKit
import SwiftUI
import UIKit

struct ChatKnowledgeCard: Codable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let content: String
    /// `search_knowledge_bag` 检索预览为 `false`（仅展示）；`create_knowledge_document` 等新建草稿为 `true`。
    let showsSaveAndCopy: Bool

    /// 与服务端只下发 title/content、attachment 里无稳定 `id` 时一致：用正文派生确定性 UUID。
    /// 若每次 JSON 解析都 `UUID()`，同一张卡在每次 `body` 重算后都会换新 id，`savedKnowledgeCardIDs` 会永远对不上。
    static func stableID(title: String, content: String) -> UUID {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let seed = "\(normalizedTitle)|\(normalizedContent)"
        let digest = SHA256.hash(data: Data(seed.utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3],
                bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11],
                bytes[12], bytes[13], bytes[14], bytes[15]
            )
        )
    }

    init(id: UUID? = nil, title: String, content: String, showsSaveAndCopy: Bool = true) {
        self.id = id ?? Self.stableID(title: title, content: content)
        self.title = title
        self.content = content
        self.showsSaveAndCopy = showsSaveAndCopy
    }


    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodableKey.self)
        let title = try c.decode(String.self, forKey: .key("title"))
        let content = try c.decode(String.self, forKey: .key("content"))
        if let id = try c.decodeIfPresent(UUID.self, forKey: .key("id")) {
            self.id = id
        } else {
            self.id = Self.stableID(title: title, content: content)
        }
        self.title = title
        self.content = content
        self.showsSaveAndCopy = try c.decodeIfPresent(Bool.self, forKey: .key("showsSaveAndCopy")) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodableKey.self)
        try c.encode(id, forKey: .key("id"))
        try c.encode(title, forKey: .key("title"))
        try c.encode(content, forKey: .key("content"))
        try c.encode(showsSaveAndCopy, forKey: .key("showsSaveAndCopy"))
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

                        if card.showsSaveAndCopy {
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
