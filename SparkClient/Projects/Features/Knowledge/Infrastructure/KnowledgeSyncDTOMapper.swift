import Foundation

/// Wire DTO ↔ 领域模型互转；收口在一处，避免 Push ACK / Pull / Outbox 冻结快照各自演化出不同字段解释。
enum KnowledgeSyncDTOMapper {
    static func remoteSnapshot(from dto: KnowledgeRemoteDocumentDTO) -> KnowledgeRemoteDocumentSnapshot {
        KnowledgeRemoteDocumentSnapshot(
            id: dto.id,
            knowledgeBaseID: dto.knowledgeBaseId,
            title: dto.title,
            content: dto.content,
            excerpt: dto.excerpt,
            scope: KnowledgeDocumentScope(rawValue: dto.scope) ?? .personal,
            boundModelID: dto.boundModelId,
            source: KnowledgeDocumentSource(rawValue: dto.source) ?? .user,
            revision: dto.revision,
            contentHash: dto.contentHash,
            isDeleted: dto.isDeleted,
            deletedAt: dto.deletedAt,
            serverUpdatedAt: dto.serverUpdatedAt
        )
    }

    /// 由 Outbox 记录 + 冻结快照构造 Push 请求体；create/update 携带完整 document 快照，delete/restore 不携带。
    static func mutationRequest(
        record: KnowledgeOutboxRecord,
        payload: KnowledgeOutboxPayload,
        clientPlatform: String,
        clientVersion: String,
        deviceID: String?
    ) -> KnowledgeMutationRequestDTO {
        let document: KnowledgeMutationDocumentDTO?
        switch record.operation {
        case .create, .update:
            document = KnowledgeMutationDocumentDTO(
                title: payload.title ?? "",
                content: payload.content ?? "",
                excerpt: payload.excerpt ?? "",
                scope: (payload.scope ?? .personal).rawValue,
                boundModelId: payload.boundModelID,
                source: (payload.source ?? .user).rawValue,
                clientCreatedAt: payload.clientCreatedAt,
                clientUpdatedAt: payload.clientUpdatedAt
            )
        case .delete, .restore:
            document = nil
        }

        return KnowledgeMutationRequestDTO(
            mutationId: record.mutationID,
            documentId: record.documentID,
            operation: record.operation.rawValue,
            baseRevision: record.operation == .create ? nil : record.baseRevision,
            knowledgeBaseId: payload.knowledgeBaseID,
            document: document,
            client: KnowledgeMutationClientDTO(platform: clientPlatform, version: clientVersion, deviceId: deviceID)
        )
    }
}
