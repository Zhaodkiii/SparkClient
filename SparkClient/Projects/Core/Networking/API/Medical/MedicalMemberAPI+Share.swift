import Foundation

extension SparkMedicalMemberAPI {
    struct ShareTicketResponse: Decodable, Sendable {
        let shareTicket: String
        let qrPayload: String
    }

    struct ShareResolveResponse: Decodable, Sendable {
        struct MemberSummary: Decodable, Sendable, Equatable {
            let id: Int
            let name: String
            let gender: String
            let birthDate: Date?
            let avatarUrl: String
        }

        struct InviterSummary: Decodable, Sendable, Equatable {
            let userId: Int
            let displayName: String
            let relationship: String
        }

        let member: MemberSummary
        let inviter: InviterSummary
        let defaultRole: String
        let alreadyBound: Bool
        let existingBindingId: Int?
        let sharedUserCount: Int
    }

    struct MemberDetailResponse: Decodable, Sendable {
        let id: Int
        let bindingId: Int
        let name: String
        let gender: String
        let relationship: String
        let birthDate: Date?
        let bloodType: String
        let allergies: [String]
        let chronicConditions: [String]
        let notes: String
        let avatarUrl: String
        let isPrimary: Bool
        let bindingRole: String
        let sharedUserCount: Int
        let canShare: Bool
        let canEdit: Bool
        let canDelete: Bool
        let canUnbind: Bool
        let canManageBindings: Bool?
        let updatedAt: Date
        let medicalOverview: MedicalOverview?
        let sharedUsers: [SharedUserRow]?
        let myBinding: MyBindingRow?

        struct MedicalOverview: Decodable, Sendable {
            let medicalCaseCount: Int
            let healthExamReportCount: Int
            let examinationReportCount: Int
            let medicationPlanCount: Int
            let lastUpdatedAt: Date?
        }

        struct SharedUserRow: Decodable, Sendable, Identifiable {
            let bindingId: Int
            let userId: Int
            let displayName: String
            let relationship: String
            let role: String
            let permission: String?
            let isSelf: Bool
            let boundAt: Date

            var id: Int { bindingId }
        }

        struct MyBindingRow: Decodable, Sendable {
            let bindingId: Int
            let relationship: String
            let role: String
            let isPrimary: Bool
        }
    }

    struct GenerateShareTicketPayload: Encodable, Sendable {
        let channel: String
        let permission: String
    }

    struct ShareTicketPayload: Encodable, Sendable {
        let shareTicket: String
    }

    struct AcceptSharePayload: Encodable, Sendable {
        let shareTicket: String
        let relationship: String
        let customRelationship: String
    }

    struct UpdateBindingPayload: Encodable, Sendable {
        let relationship: String
    }

    func fetchMemberDetail(memberID: Int) async throws -> MemberDetailResponse {
        try await postRequest(
            method: .get,
            path: "/api/v1/medical/members/\(memberID)/",
            body: Optional<String>.none,
            responseType: MemberDetailResponse.self
        )
    }

    func generateShareTicket(
        memberID: Int,
        channel: String,
        permission: String = "edit"
    ) async throws -> ShareTicketResponse {
        try await postRequest(
            method: .post,
            path: "/api/v1/medical/members/\(memberID)/share-ticket/",
            body: GenerateShareTicketPayload(channel: channel, permission: permission),
            responseType: ShareTicketResponse.self
        )
    }

    func resolveShareTicket(_ ticket: String) async throws -> ShareResolveResponse {
        try await postRequest(
            method: .post,
            path: "/api/v1/medical/member-share-ticket/resolve/",
            body: ShareTicketPayload(shareTicket: ticket),
            responseType: ShareResolveResponse.self
        )
    }

    func acceptShareTicket(
        _ ticket: String,
        relationship: String,
        customRelationship: String = ""
    ) async throws -> RemoteMember {
        try await postRequest(
            method: .post,
            path: "/api/v1/medical/member-share-ticket/accept/",
            body: AcceptSharePayload(
                shareTicket: ticket,
                relationship: relationship,
                customRelationship: customRelationship
            ),
            responseType: RemoteMember.self
        )
    }

    func updateBinding(bindingID: Int, relationship: String) async throws -> RemoteMember {
        try await postRequest(
            method: .patch,
            path: "/api/v1/medical/member-bindings/\(bindingID)/",
            body: UpdateBindingPayload(relationship: relationship),
            responseType: RemoteMember.self
        )
    }

    func unbind(bindingID: Int) async throws {
        _ = try await postRequest(
            method: .delete,
            path: "/api/v1/medical/member-bindings/\(bindingID)/",
            body: Optional<String>.none,
            responseType: EmptyResponse.self
        )
    }

    private struct EmptyResponse: Decodable {}

    private func postRequest<T: Decodable, B: Encodable>(
        method: SparkHTTPMethod,
        path: String,
        body: B?,
        responseType: T.Type
    ) async throws -> T {
        let sparkBody: SparkBody = {
            guard let body else { return .none }
            return .json(AnyEncodable(body))
        }()
        let op = CacheableSparkNetworkOperation(
            name: "Medical.Member.\(path)",
            apiName: "SparkMedicalMemberAPI",
            request: SparkNetworkRequest(
                method: method,
                path: path,
                body: sparkBody,
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "medical.member.\(path)",
                    retryConfig: .default,
                    isIdempotent: method == .get,
                    queuePriority: .high
                )
            )
        )
        let response = try await configuration.execute(op)
        return try APIResponseDecoder.decodeWrappedData(T.self, from: response, decoder: .medicalAPI)
    }
}
