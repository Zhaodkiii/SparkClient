import Foundation

struct ChatMergePolicy: Sendable {
    nonisolated init() {}

    nonisolated func resolve(local: ChatMessage?, remote: ChatMessage) -> ChatMessage {
        guard let local else {
            return remote
        }

        switch (local.serverUpdatedAt, remote.serverUpdatedAt) {
        case let (.some(localDate), .some(remoteDate)):
            return remoteDate >= localDate ? remote : local
        case (.none, .some):
            return remote
        case (.some, .none):
            return local
        case (.none, .none):
            return remote
        }
    }
}
