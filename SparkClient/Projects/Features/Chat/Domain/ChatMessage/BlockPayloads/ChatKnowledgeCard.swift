import CryptoKit
import Foundation

nonisolated struct ChatKnowledgeCard: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let content: String
    let documentID: UUID?
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

    init(id: UUID? = nil, title: String, content: String, documentID: UUID? = nil, showsSaveAndCopy: Bool = true) {
        self.id = id ?? Self.stableID(title: title, content: content)
        self.title = title
        self.content = content
        self.documentID = documentID
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
        self.documentID = try c.decodeIfPresent(UUID.self, forKey: .key("documentID"))
            ?? c.decodeIfPresent(UUID.self, forKey: .key("documentId"))
            ?? c.decodeIfPresent(UUID.self, forKey: .key("document_id"))
        self.showsSaveAndCopy = try c.decodeIfPresent(Bool.self, forKey: .key("showsSaveAndCopy")) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodableKey.self)
        try c.encode(id, forKey: .key("id"))
        try c.encode(title, forKey: .key("title"))
        try c.encode(content, forKey: .key("content"))
        try c.encodeIfPresent(documentID, forKey: .key("documentID"))
        try c.encode(showsSaveAndCopy, forKey: .key("showsSaveAndCopy"))
    }
}
