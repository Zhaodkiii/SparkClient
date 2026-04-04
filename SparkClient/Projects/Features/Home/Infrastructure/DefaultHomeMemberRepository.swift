import Foundation

final class DefaultHomeMemberRepository: HomeMemberRepository, @unchecked Sendable {
    private let medicalDataRepository: any MedicalDataRepository
    private let memberAPI: SparkMedicalMemberAPI
    private let logger: Logger

    init(
        medicalDataRepository: any MedicalDataRepository,
        memberAPI: SparkMedicalMemberAPI,
        logger: Logger = ConsoleLogger()
    ) {
        self.medicalDataRepository = medicalDataRepository
        self.memberAPI = memberAPI
        self.logger = logger
    }

    func refreshRemoteSnapshot() async throws {
        try await medicalDataRepository.pullSnapshotFromServer(priority: .balanced)
    }

    func loadSnapshot() async -> MedicalDataSnapshot {
        await medicalDataRepository.loadSnapshot()
    }

    func createMember(
        name: String,
        relationship: String,
        age: Int,
        gender: String,
        birthDate: Date?
    ) async throws {
        let payload = SparkMedicalMemberAPI.UpsertMemberPayload(
            clientUID: UUID(),
            name: name,
            relationship: relationship,
            age: age,
            gender: gender,
            avatar: "",
            birthDate: birthDate,
            isPrimary: false
        )

        do {
            _ = try await memberAPI.createMember(payload)
            try await refreshRemoteSnapshot()
        } catch {
            logger.warning("远端新增成员失败，将尝试通过快照上传兜底：\(error.localizedDescription)", category: "home")
            try await fallbackCreateMember(
                name: name,
                relationship: relationship,
                age: age,
                gender: gender,
                birthDate: birthDate
            )
        }
    }

    func updateMember(
        _ member: Member,
        name: String,
        relationship: String,
        age: Int,
        gender: String,
        birthDate: Date?
    ) async throws {
        let payload = SparkMedicalMemberAPI.UpsertMemberPayload(
            clientUID: member.id,
            name: name,
            relationship: relationship,
            age: age,
            gender: gender,
            avatar: member.avatar,
            birthDate: birthDate,
            isPrimary: member.isPrimary
        )

        if let remoteID = member.remoteID {
            do {
                _ = try await memberAPI.updateMember(remoteID: remoteID, payload: payload)
                try await refreshRemoteSnapshot()
                return
            } catch {
                logger.warning("远端更新成员失败，将尝试通过快照上传兜底：\(error.localizedDescription)", category: "home")
            }
        }

        try await fallbackUpdateMember(
            member,
            name: name,
            relationship: relationship,
            age: age,
            gender: gender,
            birthDate: birthDate
        )
    }

    func deleteMember(_ member: Member) async throws {
        if let remoteID = member.remoteID {
            do {
                try await memberAPI.deleteMember(remoteID: remoteID)
                try await refreshRemoteSnapshot()
                return
            } catch {
                logger.warning("远端删除成员失败，将尝试通过快照上传兜底：\(error.localizedDescription)", category: "home")
            }
        }

        try await fallbackDeleteMember(member)
    }

    private func fallbackCreateMember(
        name: String,
        relationship: String,
        age: Int,
        gender: String,
        birthDate: Date?
    ) async throws {
        var snapshot = await medicalDataRepository.loadSnapshot()
        snapshot.members.append(
            Member(
                name: name,
                age: age,
                gender: gender,
                relationship: relationship,
                birthDate: birthDate,
                isPrimary: snapshot.members.isEmpty,
                updatedAt: Date()
            )
        )
        try await medicalDataRepository.saveSnapshot(snapshot)
        try await medicalDataRepository.uploadSnapshotToServer(priority: .balanced)
        try await medicalDataRepository.pullSnapshotFromServer(priority: .balanced)
    }

    private func fallbackUpdateMember(
        _ member: Member,
        name: String,
        relationship: String,
        age: Int,
        gender: String,
        birthDate: Date?
    ) async throws {
        var snapshot = await medicalDataRepository.loadSnapshot()
        snapshot.members = snapshot.members.map { current in
            guard current.id == member.id else { return current }
            return Member(
                id: current.id,
                remoteID: current.remoteID,
                name: name,
                age: age,
                gender: gender,
                relationship: relationship,
                avatar: current.avatar,
                birthDate: birthDate,
                isPrimary: current.isPrimary,
                updatedAt: Date()
            )
        }
        try await medicalDataRepository.saveSnapshot(snapshot)
        try await medicalDataRepository.uploadSnapshotToServer(priority: .balanced)
        try await medicalDataRepository.pullSnapshotFromServer(priority: .balanced)
    }

    private func fallbackDeleteMember(_ member: Member) async throws {
        var snapshot = await medicalDataRepository.loadSnapshot()
        snapshot.members.removeAll { $0.id == member.id }
        snapshot.medicalCases.removeAll { $0.memberID == member.id }
        snapshot.examinationReports.removeAll { $0.memberID == member.id }
        snapshot.medicalReports.removeAll { $0.memberID == member.id }
        snapshot.prescriptions.removeAll { $0.memberID == member.id }
        try await medicalDataRepository.saveSnapshot(snapshot)
        try await medicalDataRepository.uploadSnapshotToServer(priority: .balanced)
        try await medicalDataRepository.pullSnapshotFromServer(priority: .balanced)
    }
}
