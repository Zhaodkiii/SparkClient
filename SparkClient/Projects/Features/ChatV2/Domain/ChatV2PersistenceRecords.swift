import Foundation

struct ChatV2ThreadRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let ownerAccountID: Int64
    let title: String
    let scenario: ChatV2Scenario
    let memberID: Int64?
    let status: ChatV2ThreadStatus
    let createdAt: Date
    let updatedAt: Date
    let lastSyncedAt: Date?

    init(
        id: UUID = UUID(),
        ownerAccountID: Int64,
        title: String,
        scenario: ChatV2Scenario = .chat,
        memberID: Int64? = nil,
        status: ChatV2ThreadStatus = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastSyncedAt: Date? = nil
    ) {
        self.id = id
        self.ownerAccountID = ownerAccountID
        self.title = title
        self.scenario = scenario
        self.memberID = memberID
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastSyncedAt = lastSyncedAt
    }
}

struct ChatV2MessageRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let threadID: UUID
    let ownerAccountID: Int64
    let clientMessageID: UUID
    let serverMessageID: String?
    let role: ChatV2Role
    let status: ChatV2MessageStatus
    let document: ChatV2MessageDocument
    let errorText: String?
    let version: Int
    let createdAt: Date
    let updatedAt: Date
    let committedAt: Date?

    init(
        id: UUID = UUID(),
        threadID: UUID,
        ownerAccountID: Int64,
        clientMessageID: UUID = UUID(),
        serverMessageID: String? = nil,
        role: ChatV2Role,
        status: ChatV2MessageStatus,
        document: ChatV2MessageDocument,
        errorText: String? = nil,
        version: Int = 1,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        committedAt: Date? = nil
    ) {
        self.id = id
        self.threadID = threadID
        self.ownerAccountID = ownerAccountID
        self.clientMessageID = clientMessageID
        self.serverMessageID = serverMessageID
        self.role = role
        self.status = status
        self.document = document
        self.errorText = errorText
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.committedAt = committedAt
    }
}

struct ChatV2OutboxRecord: Codable, Equatable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable {
        case pending
        case inFlight
        case sent
        case failed
    }

    let id: UUID
    let messageID: UUID
    let threadID: UUID
    let requestEnvelopeData: Data
    let status: Status
    let retryCount: Int
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        messageID: UUID,
        threadID: UUID,
        requestEnvelopeData: Data,
        status: Status = .pending,
        retryCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.messageID = messageID
        self.threadID = threadID
        self.requestEnvelopeData = requestEnvelopeData
        self.status = status
        self.retryCount = retryCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ChatV2SyncCheckpoint: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let scopeKey: String
    let cursor: String?
    let updatedAt: Date

    init(id: UUID = UUID(), scopeKey: String, cursor: String?, updatedAt: Date = Date()) {
        self.id = id
        self.scopeKey = scopeKey
        self.cursor = cursor
        self.updatedAt = updatedAt
    }
}
