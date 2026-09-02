#if canImport(XCTest)
import Foundation
@testable import SparkClient

/// CHAT-000054：HospitalCareRemoteServing 的可配置测试替身。
final class StubHospitalCareRemoteAPI: HospitalCareRemoteServing, @unchecked Sendable {
    enum StubError: Error {
        case network
    }

    var hospitalsResult: Result<[HospitalPublicDTO], Error> = .success([])
    var departmentsResult: Result<[HospitalDepartmentPublicDTO], Error> = .success([])
    var agentsResult: Result<[HospitalAgentPublicDTO], Error> = .success([])
    var agentDetailResult: Result<HospitalAgentPublicDTO, Error> = .failure(StubError.network)
    var conversationsResult: Result<[HospitalConversationDTO], Error> = .success([])
    var allConversationsResult: Result<[HospitalConversationDTO], Error> = .success([])
    var contextResult: Result<HospitalConversationContextDTO?, Error> = .success(nil)
    var createConversationResult: Result<HospitalCreateConversationResponseDTO, Error>?
    /// CHAT-000055：KB pull 分页队列（按调用顺序出队；用尽后返回空页）。
    var pullPages: [Result<HospitalKnowledgePullPageDTO, Error>] = []

    private(set) var fetchContextCallCount = 0
    private(set) var listAllConversationsCallCount = 0
    private(set) var pullCallCount = 0
    private(set) var pullCursors: [String?] = []

    func listHospitals(page: Int, pageSize: Int) async throws -> [HospitalPublicDTO] {
        try hospitalsResult.get()
    }

    func listDepartments(hospitalID: UUID) async throws -> [HospitalDepartmentPublicDTO] {
        try departmentsResult.get()
    }

    func listAgents(
        hospitalID: UUID,
        departmentID: UUID?,
        keyword: String,
        page: Int,
        pageSize: Int
    ) async throws -> [HospitalAgentPublicDTO] {
        try agentsResult.get()
    }

    func fetchAgent(agentID: UUID) async throws -> HospitalAgentPublicDTO {
        try agentDetailResult.get()
    }

    func listConversations(memberID: Int, page: Int, pageSize: Int) async throws -> [HospitalConversationDTO] {
        try conversationsResult.get()
    }

    func listAllConversations(pageSize: Int) async throws -> [HospitalConversationDTO] {
        listAllConversationsCallCount += 1
        return try allConversationsResult.get()
    }

    func createConversation(agentID: UUID, memberID: Int) async throws -> HospitalCreateConversationResponseDTO {
        guard let createConversationResult else {
            throw StubError.network
        }
        return try createConversationResult.get()
    }

    func fetchConversationContext(threadID: UUID, memberID: Int?) async throws -> HospitalConversationContextDTO? {
        fetchContextCallCount += 1
        return try contextResult.get()
    }

    func pullHospitalKnowledge(
        knowledgeBaseID: UUID,
        cursor: String?,
        limit: Int
    ) async throws -> HospitalKnowledgePullPageDTO {
        pullCallCount += 1
        pullCursors.append(cursor)
        if pullPages.isEmpty == false {
            return try pullPages.removeFirst().get()
        }
        return HospitalKnowledgePullPageDTO(
            knowledgeBaseId: knowledgeBaseID,
            revision: 0,
            vectorStatus: "not_built",
            indexedRevision: nil,
            cursor: nil,
            hasMore: false,
            documents: []
        )
    }
}

enum HospitalCareTestFixtures {
    static func hospitalDTO(
        id: UUID = UUID(),
        code: String? = nil,
        name: String = "测试医院",
        introduction: String? = nil
    ) -> HospitalPublicDTO {
        HospitalPublicDTO(
            id: id,
            code: code,
            name: name,
            shortName: nil,
            introduction: introduction,
            status: "active"
        )
    }

    static func hospitalSummary(
        id: UUID = UUID(),
        code: String = "",
        name: String = "测试医院",
        introduction: String = ""
    ) -> HospitalSummary {
        HospitalSummary(
            id: id,
            code: code,
            name: name,
            shortName: "",
            introduction: introduction,
            status: "active"
        )
    }

    static func agentDTO(
        id: UUID = UUID(),
        hospitalID: UUID = UUID(),
        doctorID: UUID = UUID(),
        doctorName: String = "李医生",
        publishedAt: Date? = nil
    ) -> HospitalAgentPublicDTO {
        HospitalAgentPublicDTO(
            id: id,
            hospitalId: hospitalID,
            name: "\(doctorName)智能体",
            publicSummary: nil,
            greeting: nil,
            serviceBoundary: nil,
            publicationStatus: "published",
            publishedAt: publishedAt,
            department: nil,
            doctor: HospitalDoctorPublicDTO(
                id: doctorID,
                displayName: doctorName,
                title: "主任医师",
                specialties: nil,
                introduction: nil,
                avatarUrl: nil
            )
        )
    }

    static func conversationDTO(
        threadID: UUID = UUID(),
        agentID: UUID = UUID(),
        memberID: Int? = 7,
        hospitalID: UUID? = UUID()
    ) -> HospitalConversationDTO {
        HospitalConversationDTO(
            threadId: threadID,
            agent: HospitalConversationAgentDTO(id: agentID, name: "智能体", publicationStatus: "published"),
            memberId: memberID,
            hospital: hospitalID.map { hospitalDTO(id: $0) }
        )
    }

    static func contextDTO(
        threadID: UUID = UUID(),
        agentID: UUID = UUID(),
        memberID: Int? = 7,
        hospitalID: UUID = UUID()
    ) -> HospitalConversationContextDTO {
        HospitalConversationContextDTO(
            threadId: threadID,
            hospital: hospitalDTO(id: hospitalID),
            agent: HospitalConversationAgentDTO(id: agentID, name: "智能体", publicationStatus: "published"),
            memberId: memberID
        )
    }
}
#endif
