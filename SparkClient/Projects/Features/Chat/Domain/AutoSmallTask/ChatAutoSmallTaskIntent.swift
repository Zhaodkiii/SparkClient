import Foundation

nonisolated struct ChatAutoSmallTaskIntent: Codable, Equatable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable {
        case pending
        case running
        case consumed
        case failed
        case expired
    }

    let id: UUID
    let threadID: UUID
    let businessKey: ChatAutoSmallTaskBusinessKey
    let smallTaskCode: String
    let localSmallTaskID: Int?
    let source: String
    let initialDraftHash: String?
    let createdAt: Date
    let expiresAt: Date
    var status: Status

    var isExpired: Bool {
        Date() >= expiresAt
    }

    init(
        id: UUID = UUID(),
        threadID: UUID,
        businessKey: ChatAutoSmallTaskBusinessKey,
        smallTaskCode: String,
        localSmallTaskID: Int?,
        source: String,
        initialDraftHash: String?,
        createdAt: Date = Date(),
        expiresAt: Date = Date().addingTimeInterval(5 * 60),
        status: Status = .pending
    ) {
        self.id = id
        self.threadID = threadID
        self.businessKey = businessKey
        self.smallTaskCode = smallTaskCode
        self.localSmallTaskID = localSmallTaskID
        self.source = source
        self.initialDraftHash = initialDraftHash
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.status = status
    }
}

