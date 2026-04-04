import CoreData
import Foundation

actor CoreDataChatStore {
    private enum EntityName {
        static let thread = "ChatThreadEntity"
        static let message = "ChatMessageEntity"
        static let cursor = "ChatSyncCursorEntity"
    }

    private let coreDataStack: CoreDataStack
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(coreDataStack: CoreDataStack, logger: Logger = ConsoleLogger()) {
        self.coreDataStack = coreDataStack
    }

    func loadActiveThread() async -> ChatThread? {
        try? await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.thread)
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "isActive == YES")
            request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            return try context.fetch(request).first.flatMap(Self.toThread)
        }
    }

    func loadThread(id: UUID) async -> ChatThread? {
        try? await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.thread)
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            return try context.fetch(request).first.flatMap(Self.toThread)
        }
    }

    func loadThreads() async -> [ChatThread] {
        (try? await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.thread)
            request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            return try context.fetch(request).compactMap(Self.toThread)
        }) ?? []
    }

    func createThread(patientID: UUID?, title: String) async -> ChatThread {
        let now = Date()
        let thread = ChatThread(
            patientID: patientID,
            title: title,
            scenario: .chat,
            createdAt: now,
            updatedAt: now
        )

        _ = try? await coreDataStack.performBackgroundTask { context in
            let clearRequest = NSFetchRequest<NSManagedObject>(entityName: EntityName.thread)
            clearRequest.predicate = NSPredicate(format: "isActive == YES")
            for object in try context.fetch(clearRequest) {
                object.setValue(false, forKey: "isActive")
            }

            let object = NSEntityDescription.insertNewObject(forEntityName: EntityName.thread, into: context)
            object.setValue(thread.id, forKey: "id")
            object.setValue(thread.patientID, forKey: "patientID")
            object.setValue(thread.title, forKey: "title")
            object.setValue(thread.scenario.rawValue, forKey: "scenario")
            object.setValue(thread.createdAt, forKey: "createdAt")
            object.setValue(thread.updatedAt, forKey: "updatedAt")
            object.setValue(true, forKey: "isActive")
        }

        return thread
    }

    func setActiveThread(id: UUID) async {
        _ = try? await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.thread)
            for object in try context.fetch(request) {
                let objectID = object.value(forKey: "id") as? UUID
                object.setValue(objectID == id, forKey: "isActive")
            }
        }
    }

    func loadMessages(threadID: UUID) async -> [ChatMessage] {
        (try? await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.message)
            request.predicate = NSPredicate(format: "threadID == %@", threadID as CVarArg)
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            return try context.fetch(request).compactMap { object in
                Self.toMessage(object: object, decoder: self.decoder)
            }
        }) ?? []
    }

    func appendMessage(
        threadID: UUID,
        role: ChatMessageRole,
        kind: ChatMessageKind,
        content: String,
        attachments: [ChatAttachment],
        clientMessageID: UUID,
        serverMessageID: String?,
        deliveryState: ChatDeliveryState
    ) async throws -> ChatMessage {
        let message = ChatMessage(
            threadID: threadID,
            role: role,
            kind: kind,
            content: content,
            attachments: attachments,
            clientMessageID: clientMessageID,
            serverMessageID: serverMessageID,
            deliveryState: deliveryState,
            createdAt: Date(),
            serverUpdatedAt: nil,
            isTombstone: false
        )

        try await coreDataStack.performBackgroundTask { context in
            guard let threadObject = try Self.fetchThread(context: context, threadID: threadID) else {
                throw ChatFeatureError.threadNotFound
            }

            let object = NSEntityDescription.insertNewObject(forEntityName: EntityName.message, into: context)
            try Self.fillMessage(
                object: object,
                message: message,
                encoder: self.encoder
            )

            threadObject.setValue(Date(), forKey: "updatedAt")
        }

        return message
    }

    func updateMessageDeliveryState(clientMessageID: UUID, state: ChatDeliveryState) async {
        _ = try? await coreDataStack.performBackgroundTask { context in
            guard let object = try Self.fetchMessage(
                context: context,
                clientMessageID: clientMessageID,
                serverMessageID: nil
            ) else {
                return
            }
            object.setValue(state.rawValue, forKey: "deliveryState")
            if state == .sent || state == .read {
                object.setValue(Date(), forKey: "serverUpdatedAt")
            }
        }
    }

    func upsertRemoteMessages(_ messages: [ChatMessage], in threadID: UUID) async {
        guard messages.isEmpty == false else { return }

        _ = try? await coreDataStack.performBackgroundTask { context in
            if try Self.fetchThread(context: context, threadID: threadID) == nil {
                let threadObject = NSEntityDescription.insertNewObject(forEntityName: EntityName.thread, into: context)
                let now = Date()
                threadObject.setValue(threadID, forKey: "id")
                threadObject.setValue(nil, forKey: "patientID")
                threadObject.setValue(PromptLocalizer().newThreadTitle(), forKey: "title")
                threadObject.setValue(AIScenario.chat.rawValue, forKey: "scenario")
                threadObject.setValue(now, forKey: "createdAt")
                threadObject.setValue(now, forKey: "updatedAt")
                threadObject.setValue(false, forKey: "isActive")
            }

            for message in messages {
                guard message.threadID == threadID else { continue }

                let object = try Self.fetchMessage(
                    context: context,
                    clientMessageID: message.clientMessageID,
                    serverMessageID: message.serverMessageID
                ) ?? NSEntityDescription.insertNewObject(forEntityName: EntityName.message, into: context)

                if let local = Self.toMessage(object: object, decoder: self.decoder),
                   Self.shouldKeepLocal(local: local, remote: message) {
                    continue
                }

                try Self.fillMessage(object: object, message: message, encoder: self.encoder)
            }

            if let threadObject = try Self.fetchThread(context: context, threadID: threadID) {
                threadObject.setValue(Date(), forKey: "updatedAt")
            }
        }
    }

    func loadOutboxMessages(limit: Int) async -> [ChatMessage] {
        (try? await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.message)
            request.fetchLimit = max(1, limit)
            // 自动同步只处理 pending；failed 仅允许用户触发手动重试后再入队。
            request.predicate = NSPredicate(format: "deliveryState == %@", ChatDeliveryState.pending.rawValue)
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            return try context.fetch(request).compactMap { object in
                Self.toMessage(object: object, decoder: self.decoder)
            }
        }) ?? []
    }

    func deleteThread(id: UUID) async {
        _ = try? await coreDataStack.performBackgroundTask { context in
            let threadRequest = NSFetchRequest<NSManagedObject>(entityName: EntityName.thread)
            threadRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            for object in try context.fetch(threadRequest) {
                context.delete(object)
            }

            let messageRequest = NSFetchRequest<NSManagedObject>(entityName: EntityName.message)
            messageRequest.predicate = NSPredicate(format: "threadID == %@", id as CVarArg)
            for object in try context.fetch(messageRequest) {
                context.delete(object)
            }
        }
    }

    func loadSyncCursor() async -> ChatSyncCursor? {
        try? await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.cursor)
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "key == %@", "chat.main")
            guard
                let object = try context.fetch(request).first,
                let value = object.value(forKey: "value") as? String,
                let updatedAt = object.value(forKey: "updatedAt") as? Date
            else {
                return nil
            }
            return ChatSyncCursor(value: value, updatedAt: updatedAt)
        }
    }

    func saveSyncCursor(_ cursor: ChatSyncCursor) async {
        _ = try? await coreDataStack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.cursor)
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "key == %@", "chat.main")
            let object = try context.fetch(request).first
                ?? NSEntityDescription.insertNewObject(forEntityName: EntityName.cursor, into: context)
            object.setValue("chat.main", forKey: "key")
            object.setValue(cursor.value, forKey: "value")
            object.setValue(cursor.updatedAt, forKey: "updatedAt")
        }
    }

    private static func fetchThread(context: NSManagedObjectContext, threadID: UUID) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.thread)
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", threadID as CVarArg)
        return try context.fetch(request).first
    }

    private static func fetchMessage(
        context: NSManagedObjectContext,
        clientMessageID: UUID,
        serverMessageID: String?
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.message)
        request.fetchLimit = 1

        if let serverMessageID, serverMessageID.isEmpty == false {
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "clientMessageID == %@", clientMessageID as CVarArg),
                NSPredicate(format: "serverMessageID == %@", serverMessageID)
            ])
        } else {
            request.predicate = NSPredicate(format: "clientMessageID == %@", clientMessageID as CVarArg)
        }

        return try context.fetch(request).first
    }

    private static func fillMessage(object: NSManagedObject, message: ChatMessage, encoder: JSONEncoder) throws {
        object.setValue(message.id, forKey: "id")
        object.setValue(message.threadID, forKey: "threadID")
        object.setValue(message.role.rawValue, forKey: "role")
        object.setValue(message.kind.rawValue, forKey: "kind")
        object.setValue(message.content, forKey: "content")
        object.setValue(message.clientMessageID, forKey: "clientMessageID")
        object.setValue(message.serverMessageID, forKey: "serverMessageID")
        object.setValue(message.deliveryState.rawValue, forKey: "deliveryState")
        object.setValue(message.createdAt, forKey: "createdAt")
        object.setValue(message.serverUpdatedAt, forKey: "serverUpdatedAt")
        object.setValue(message.isTombstone, forKey: "isTombstone")
        object.setValue(try encoder.encode(message.attachments), forKey: "attachmentsData")
    }

    private static func toThread(_ object: NSManagedObject) -> ChatThread? {
        guard
            let id = object.value(forKey: "id") as? UUID,
            let title = object.value(forKey: "title") as? String,
            let scenarioRaw = object.value(forKey: "scenario") as? String,
            let scenario = AIScenario(rawValue: scenarioRaw),
            let createdAt = object.value(forKey: "createdAt") as? Date,
            let updatedAt = object.value(forKey: "updatedAt") as? Date
        else {
            return nil
        }

        return ChatThread(
            id: id,
            patientID: object.value(forKey: "patientID") as? UUID,
            title: title,
            scenario: scenario,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func toMessage(object: NSManagedObject, decoder: JSONDecoder) -> ChatMessage? {
        guard
            let id = object.value(forKey: "id") as? UUID,
            let threadID = object.value(forKey: "threadID") as? UUID,
            let roleRaw = object.value(forKey: "role") as? String,
            let role = ChatMessageRole(rawValue: roleRaw),
            let kindRaw = object.value(forKey: "kind") as? String,
            let kind = ChatMessageKind(rawValue: kindRaw),
            let content = object.value(forKey: "content") as? String,
            let clientMessageID = object.value(forKey: "clientMessageID") as? UUID,
            let deliveryRaw = object.value(forKey: "deliveryState") as? String,
            let deliveryState = ChatDeliveryState(rawValue: deliveryRaw),
            let createdAt = object.value(forKey: "createdAt") as? Date
        else {
            return nil
        }

        let attachmentsData = object.value(forKey: "attachmentsData") as? Data
        let attachments = (try? attachmentsData.flatMap { try decoder.decode([ChatAttachment].self, from: $0) }) ?? []

        return ChatMessage(
            id: id,
            threadID: threadID,
            role: role,
            kind: kind,
            content: content,
            attachments: attachments,
            clientMessageID: clientMessageID,
            serverMessageID: object.value(forKey: "serverMessageID") as? String,
            deliveryState: deliveryState,
            createdAt: createdAt,
            serverUpdatedAt: object.value(forKey: "serverUpdatedAt") as? Date,
            isTombstone: object.value(forKey: "isTombstone") as? Bool ?? false
        )
    }

    private static func shouldKeepLocal(local: ChatMessage, remote: ChatMessage) -> Bool {
        switch (local.serverUpdatedAt, remote.serverUpdatedAt) {
        case let (.some(localDate), .some(remoteDate)):
            return localDate > remoteDate
        case (.some, .none):
            return true
        default:
            return false
        }
    }
}
