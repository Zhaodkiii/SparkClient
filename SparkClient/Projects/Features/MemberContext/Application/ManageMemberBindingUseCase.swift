import Foundation

enum DeleteOrUnbindResult: Sendable {
    case deleted
    case unbound
}

struct ManageMemberBindingUseCase: Sendable {
    let memberAPI: SparkMedicalMemberAPI

    func fetchDetail(memberID: Int) async throws -> SparkMedicalMemberAPI.MemberDetailResponse {
        try await memberAPI.fetchMemberDetail(memberID: memberID)
    }

    func updateRelationship(bindingID: Int, relationship: String) async throws -> Member {
        let remote = try await memberAPI.updateBinding(bindingID: bindingID, relationship: relationship)
        return remote.domainModel
    }

    func unbind(bindingID: Int) async throws {
        try await memberAPI.unbind(bindingID: bindingID)
    }

    func changeRole(bindingID: Int, role: String) async throws -> Member {
        let remote = try await memberAPI.changeBindingRole(bindingID: bindingID, role: role)
        return remote.domainModel
    }

    func changePermission(bindingID: Int, permission: String) async throws {
        _ = try await memberAPI.changeBindingPermission(bindingID: bindingID, permission: permission)
    }

    func removeSharedUser(bindingID: Int) async throws {
        try await memberAPI.removeSharedBinding(bindingID: bindingID)
    }

    func transferOwner(bindingID: Int) async throws -> Member {
        let remote = try await memberAPI.transferOwner(bindingID: bindingID)
        return remote.domainModel
    }

    func deleteOrUnbind(memberID: Int, bindingID: Int, canDelete: Bool) async throws -> DeleteOrUnbindResult {
        if canDelete {
            try await memberAPI.deleteMember(remoteID: memberID)
            return .deleted
        }
        try await memberAPI.unbind(bindingID: bindingID)
        return .unbound
    }
}
