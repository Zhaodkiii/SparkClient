import Foundation

struct MemoryRemoteEntryDTO: Codable, Sendable {
    let id: UUID
    let scope: String
    let scopeKey: String
    let memberId: Int64?
    let agentKey: String?
    let threadId: UUID?
    let layer: String
    let documentKey: String
    let sectionKey: String
    let memoryType: String
    let normalizedKey: String
    let title: String
    let content: String
    let structuredValue: [String: JSONValue]?
    let isPinned: Bool
    let sortOrder: Int32
    let source: String
    let confirmationStatus: String
    let sensitivity: String
    let status: String
    let expiresAt: Date?
    let contentHash: String
    let revision: Int64
    let isDeleted: Bool
    let deletedAt: Date?
    let createdAt: Date?
    let serverUpdatedAt: Date
}

struct MemoryMutationPayloadDTO: Codable, Sendable {
    var scope: String?
    var memberId: Int64?
    var agentKey: String?
    var threadId: UUID?
    var layer: String?
    var documentKey: String?
    var sectionKey: String?
    var memoryType: String?
    var normalizedKey: String?
    var title: String?
    var content: String?
    var structuredValue: [String: JSONValue]?
    var isPinned: Bool?
    var sortOrder: Int32?
    var source: String?
    var sensitivity: String?
    var confirmationStatus: String?
    var status: String?
    var expiresAt: Date?
}

struct MemoryMutationClientDTO: Codable, Sendable {
    let platform: String
    let version: String
    let deviceId: String?
}

struct MemoryMutationRequestDTO: Codable, Sendable {
    let mutationId: UUID
    let memoryId: UUID
    let operation: String
    let baseRevision: Int64?
    let memory: MemoryMutationPayloadDTO?
    let client: MemoryMutationClientDTO?
}

struct MemoryPushAckDTO: Codable, Sendable {
    let mutationId: UUID
    let memoryId: String?
    let status: String
    let replayed: Bool?
    let snapshot: MemoryRemoteEntryDTO?
    let resolution: String?
    let reasonCode: String?
    let revision: Int64?
}

struct MemoryPushResponseDTO: Decodable, Sendable {
    let results: [MemoryPushAckDTO]
}

struct MemoryPullResponseDTO: Decodable, Sendable {
    let items: [MemoryRemoteEntryDTO]
    let nextCursor: String?
    let hasMore: Bool?
    let serverTime: String?
}

nonisolated struct MemoryOutboxPayload: Codable, Sendable, Equatable {
    var scope: String?
    var layer: String?
    var documentKey: String?
    var sectionKey: String?
    var memoryType: String?
    var title: String?
    var content: String?
    var isPinned: Bool?
    var source: String?
    var sensitivity: String?

    nonisolated static let empty = MemoryOutboxPayload()

    nonisolated func encoded() -> Data {
        (try? JSONEncoder.chatRemote.encode(self)) ?? Data()
    }

    nonisolated static func decode(_ data: Data) -> MemoryOutboxPayload {
        (try? JSONDecoder.chatRemote.decode(MemoryOutboxPayload.self, from: data)) ?? .empty
    }
}

nonisolated enum MemorySyncDTOMapper {
    nonisolated static func remoteSnapshot(from dto: MemoryRemoteEntryDTO) -> MemoryRemoteSnapshot {
        MemoryRemoteSnapshot(
            id: dto.id,
            scope: dto.scope,
            scopeKey: dto.scopeKey,
            memberID: dto.memberId,
            agentKey: dto.agentKey,
            threadID: dto.threadId,
            layer: dto.layer,
            documentKey: dto.documentKey,
            sectionKey: dto.sectionKey,
            memoryType: dto.memoryType,
            normalizedKey: dto.normalizedKey,
            title: dto.title,
            content: dto.content,
            structuredValueData: try? JSONEncoder.chatRemote.encode(dto.structuredValue ?? [:]),
            isPinned: dto.isPinned,
            sortOrder: dto.sortOrder,
            source: dto.source,
            confirmationStatus: dto.confirmationStatus,
            sensitivity: dto.sensitivity,
            status: dto.status,
            expiresAt: dto.expiresAt,
            contentHash: dto.contentHash,
            revision: dto.revision,
            isDeleted: dto.isDeleted,
            deletedAt: dto.deletedAt,
            createdAt: dto.createdAt,
            serverUpdatedAt: dto.serverUpdatedAt
        )
    }

    nonisolated static func mutationRequest(
        record: MemoryOutboxRecord,
        payload: MemoryOutboxPayload,
        clientPlatform: String,
        clientVersion: String,
        deviceID: String?
    ) -> MemoryMutationRequestDTO {
        let memory: MemoryMutationPayloadDTO?
        switch record.operation {
        case .create, .update:
            memory = MemoryMutationPayloadDTO(
                scope: payload.scope ?? "account",
                layer: payload.layer ?? "L3",
                documentKey: payload.documentKey ?? "preferences",
                sectionKey: payload.sectionKey ?? "answer_style",
                memoryType: payload.memoryType ?? "preference",
                title: payload.title,
                content: payload.content,
                isPinned: payload.isPinned,
                source: payload.source ?? "user",
                sensitivity: payload.sensitivity ?? "normal"
            )
        case .confirm, .reject, .delete:
            memory = nil
        }
        return MemoryMutationRequestDTO(
            mutationId: record.mutationID,
            memoryId: record.memoryID,
            operation: record.operation.rawValue,
            baseRevision: record.operation == .create ? nil : record.baseRevision,
            memory: memory,
            client: MemoryMutationClientDTO(platform: clientPlatform, version: clientVersion, deviceId: deviceID)
        )
    }
}
