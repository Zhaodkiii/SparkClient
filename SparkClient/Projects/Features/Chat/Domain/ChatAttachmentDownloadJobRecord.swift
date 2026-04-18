import Foundation

/// 持久化的聊天图片下载任务（由 ``ChatAttachmentPipeline`` 消费）。
struct ChatAttachmentDownloadJobRecord: Identifiable, Sendable, Equatable {
    enum State: String, Sendable, CaseIterable {
        case pending
        case processing
        case completed
        case failed
    }

    let id: UUID
    let dedupeKey: String
    let threadID: UUID
    let clientMessageID: UUID
    let attachmentID: UUID
    var attachmentSnapshot: ChatAttachment
    var state: State
    var localFileURLString: String?
}
