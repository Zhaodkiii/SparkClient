import Foundation

struct TaskCardPreviewContext: Equatable, Hashable, Sendable {
    let threadID: UUID
    let messageClientID: UUID
    let card: TaskCard

    static func == (lhs: TaskCardPreviewContext, rhs: TaskCardPreviewContext) -> Bool {
        lhs.threadID == rhs.threadID &&
        lhs.messageClientID == rhs.messageClientID &&
        lhs.card.id == rhs.card.id &&
        lhs.card.updatedAt == rhs.card.updatedAt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(threadID)
        hasher.combine(messageClientID)
        hasher.combine(card.id)
        hasher.combine(card.updatedAt)
    }
}

enum TaskDetailMode: Hashable, Identifiable, Sendable {
    case normal(taskID: Int)
    case preview(TaskCardPreviewContext)

    var id: String {
        switch self {
        case .normal(let taskID):
            return "task-\(taskID)"
        case .preview(let context):
            return "preview-\(context.threadID.uuidString)-\(context.messageClientID.uuidString)-\(context.card.id)"
        }
    }

    var isPreview: Bool {
        if case .preview = self { return true }
        return false
    }

    var taskID: Int? {
        if case .normal(let taskID) = self { return taskID }
        return nil
    }

    var previewContext: TaskCardPreviewContext? {
        if case .preview(let context) = self { return context }
        return nil
    }
}
