import Foundation

extension SparkMedicalMemberAPI {
    nonisolated struct InvitePayload: Encodable, Sendable {
        let channel: String
        let targetContact: String
        let permission: String
        let phone: String?
        let countryCode: String?

        enum CodingKeys: String, CodingKey {
            case channel
            case targetContact = "target_contact"
            case permission
            case phone
            case countryCode = "country_code"
        }
    }

    nonisolated struct ChangeBindingPermissionPayload: Encodable, Sendable {
        let permission: String
    }

    struct ChangeBindingPermissionResponse: Decodable, Sendable {
        let bindingId: Int
        let permission: String
    }

    struct InviteResponse: Decodable, Sendable {
        let inviteId: Int
        let status: String
        let expiresAt: Date
        let deliveryChannel: String?
        let deliveryStatus: String?
        let displayMessage: String?
        let openUrl: String?
    }

    struct PendingInviteItem: Decodable, Sendable, Equatable {
        let inviteId: Int
        let member: ShareResolveResponse.MemberSummary
        let inviter: ShareResolveResponse.InviterSummary
        let role: String
        let channel: String
        let expiresAt: Date
    }

    nonisolated struct AcceptInvitePayload: Encodable, Sendable {
        let relationship: String
        let customRelationship: String
    }

    nonisolated struct ChangeBindingRolePayload: Encodable, Sendable {
        let role: String
    }

    func createInvite(memberID: Int, payload: InvitePayload) async throws -> InviteResponse {
        try await memberRequest(
            method: .post,
            path: "/api/v1/medical/members/\(memberID)/invites/",
            body: payload,
            responseType: InviteResponse.self
        )
    }

    func pendingInvites() async throws -> [PendingInviteItem] {
        try await memberRequest(
            method: .get,
            path: "/api/v1/medical/member-invites/pending/",
            body: Optional<String>.none,
            responseType: [PendingInviteItem].self
        )
    }

    func acceptInvite(inviteID: Int, relationship: String, customRelationship: String = "") async throws -> RemoteMember {
        try await memberRequest(
            method: .post,
            path: "/api/v1/medical/member-invites/\(inviteID)/accept/",
            body: AcceptInvitePayload(relationship: relationship, customRelationship: customRelationship),
            responseType: RemoteMember.self
        )
    }

    func rejectInvite(inviteID: Int) async throws {
        _ = try await memberRequest(
            method: .post,
            path: "/api/v1/medical/member-invites/\(inviteID)/reject/",
            body: Optional<String>.none,
            responseType: EmptyMemberResponse.self
        )
    }

    func cancelInvite(inviteID: Int) async throws {
        _ = try await memberRequest(
            method: .post,
            path: "/api/v1/medical/member-invites/\(inviteID)/cancel/",
            body: Optional<String>.none,
            responseType: EmptyMemberResponse.self
        )
    }

    func changeBindingRole(bindingID: Int, role: String) async throws -> RemoteMember {
        try await memberRequest(
            method: .patch,
            path: "/api/v1/medical/member-bindings/\(bindingID)/role/",
            body: ChangeBindingRolePayload(role: role),
            responseType: RemoteMember.self
        )
    }

    func changeBindingPermission(bindingID: Int, permission: String) async throws -> ChangeBindingPermissionResponse {
        try await memberRequest(
            method: .patch,
            path: "/api/v1/medical/member-bindings/\(bindingID)/permission/",
            body: ChangeBindingPermissionPayload(permission: permission),
            responseType: ChangeBindingPermissionResponse.self
        )
    }

    func removeSharedBinding(bindingID: Int) async throws {
        _ = try await memberRequest(
            method: .delete,
            path: "/api/v1/medical/member-bindings/\(bindingID)/remove/",
            body: Optional<String>.none,
            responseType: EmptyMemberResponse.self
        )
    }

    func transferOwner(bindingID: Int) async throws -> RemoteMember {
        try await memberRequest(
            method: .post,
            path: "/api/v1/medical/member-bindings/\(bindingID)/transfer-owner/",
            body: Optional<String>.none,
            responseType: RemoteMember.self
        )
    }

    func fetchInviteDetail(inviteID: Int) async throws -> PendingInviteItem {
        try await memberRequest(
            method: .get,
            path: "/api/v1/medical/member-invites/\(inviteID)/",
            body: Optional<String>.none,
            responseType: PendingInviteItem.self
        )
    }

    private struct EmptyMemberResponse: Decodable {}

    private func memberRequest<T: Decodable, B: Encodable & Sendable>(
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
