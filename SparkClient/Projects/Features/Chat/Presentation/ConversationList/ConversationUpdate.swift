import Foundation

/// 顶部「加载更多」占位行使用的稳定 UUID（勿与真实 `clientMessageID` 冲突）。
enum ConversationListLayoutConstants {
    static let loadMoreRowUUID = UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!
}

/// 会话列表更新粒度（对齐 Signal `CVUpdate` 的 minor / diff / reloadAll 思想）。
enum ConversationUpdateKind: Equatable, Sendable {
    /// 无结构变化（仅滚动按钮等），列表层可跳过 batch update。
    case minor
    /// 插入/删除/重排等结构性变化。
    case structural
    /// 全量重建（首屏、严重不一致、diff 失败回退）。
    case reloadAll
}

struct ConversationUpdatePlan: Sendable {
    let kind: ConversationUpdateKind
    let reloadedItemIDs: [UUID]
    let prependedItemIDs: [UUID]
    let appendedItemIDs: [UUID]

    var hasPrependedItems: Bool { prependedItemIDs.isEmpty == false }
    var hasAppendedItems: Bool { appendedItemIDs.isEmpty == false }
}

/// SwiftUI → UIKit 列表一帧的输入：由 ``ConversationUpdateBuilder`` 推导 minor / structural / reloadAll。
struct ConversationListApplyPayload: Equatable, Sendable {
    var messages: [ChatMessage]
    var hasMoreMessages: Bool
    var isLoadingMoreMessages: Bool
    /// 对齐 Signal `initialPosition` 的语义：打开会话期间临时保持底部锁，直到 newest 窗口稳定。
    var lockBottomViewport: Bool
    var streamingContentGeneration: UInt64
    /// 为 true 时以「空上一帧」参与 diff（如下拉刷新），避免与旧窗口做错误 structural diff。
    var forceFullListRediff: Bool
}
