import Combine
import Foundation

@MainActor
final class ChatAutoSmallTaskIntentStore: ObservableObject {
    @Published private var intentsByThreadID: [UUID: ChatAutoSmallTaskIntent] = [:]
    private let persistentStore: UserDefaultsChatAutoSmallTaskIntentStore?
    private let logger: Logger

    init(
        persistentStore: UserDefaultsChatAutoSmallTaskIntentStore? = UserDefaultsChatAutoSmallTaskIntentStore(),
        logger: Logger = ConsoleLogger()
    ) {
        self.persistentStore = persistentStore
        self.logger = logger
    }

    func create(
        threadID: UUID,
        businessKey: ChatAutoSmallTaskBusinessKey,
        smallTaskCode: String,
        localSmallTaskID: Int?,
        source: String,
        initialDraftHash: String?
    ) {
        let intent = ChatAutoSmallTaskIntent(
            threadID: threadID,
            businessKey: businessKey,
            smallTaskCode: smallTaskCode,
            localSmallTaskID: localSmallTaskID,
            source: source,
            initialDraftHash: initialDraftHash
        )
        intentsByThreadID[threadID] = intent
        persistentStore?.save(intent)
        logger.info(
            "auto_small_task.intent.created thread=\(threadID.uuidString.prefix(8)) businessKey=\(businessKey.rawValue) source=\(source)",
            module: .general
        )
    }

    func pendingIntent(for threadID: UUID) -> ChatAutoSmallTaskIntent? {
        var intent = intentsByThreadID[threadID] ?? persistentStore?.load(threadID: threadID)
        if intent?.isExpired == true {
            intent?.status = .expired
            if let intent {
                intentsByThreadID[threadID] = intent
                persistentStore?.save(intent)
            }
            return nil
        }
        guard intent?.status == .pending else { return nil }
        return intent
    }

    func markRunning(_ intent: ChatAutoSmallTaskIntent) -> Bool {
        guard var current = pendingIntent(for: intent.threadID), current.id == intent.id else {
            return false
        }
        current.status = .running
        intentsByThreadID[current.threadID] = current
        persistentStore?.save(current)
        return true
    }

    func markConsumed(threadID: UUID) {
        update(threadID: threadID, status: .consumed)
    }

    func markPending(threadID: UUID) {
        update(threadID: threadID, status: .pending)
    }

    func markFailed(threadID: UUID) {
        update(threadID: threadID, status: .failed)
    }

    private func update(threadID: UUID, status: ChatAutoSmallTaskIntent.Status) {
        guard var intent = intentsByThreadID[threadID] ?? persistentStore?.load(threadID: threadID) else {
            return
        }
        intent.status = status
        intentsByThreadID[threadID] = intent
        persistentStore?.save(intent)
    }
}
