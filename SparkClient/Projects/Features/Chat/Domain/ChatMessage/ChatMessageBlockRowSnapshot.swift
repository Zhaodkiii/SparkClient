import Foundation

/// Core Data `ChatMessageBlockEntity` 行快照，供 `ChatMessageBlockCodec` 还原块。
nonisolated struct ChatMessageBlockRowSnapshot: Sendable {
    let id: UUID
    let kind: ChatMessageBlockKind?
    let payloadData: Data?
    let anchor: ChatBlockAnchor?
    let status: ChatMessageBlockStatus?
    let revision: Int64
    let orderKey: Double?
    let toolCallID: String?
    let parentToolCallID: String?
    let parentBlockID: UUID?
    let nodeRole: ChatMessageBlockNodeRole?
    let createdAt: Date?
    let updatedAt: Date?
}
