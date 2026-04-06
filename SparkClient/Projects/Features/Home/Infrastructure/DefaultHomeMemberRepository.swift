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
        gender: String,
        birthDate: Date?
    ) async throws {
        let payload = SparkMedicalMemberAPI.UpsertMemberPayload(
            name: name,
            relationship: relationship,
            gender: gender,
            birthDate: birthDate,
            bloodType: "",
            allergies: [],
            chronicConditions: [],
            notes: "",
            avatarUrl: "",
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
                gender: gender,
                birthDate: birthDate
            )
        }
    }

    func updateMember(
        _ member: Member,
        name: String,
        relationship: String,
        gender: String,
        birthDate: Date?
    ) async throws {
        let payload = SparkMedicalMemberAPI.UpsertMemberPayload(
            name: name,
            relationship: relationship,
            gender: gender,
            birthDate: birthDate,
            bloodType: member.bloodType,
            allergies: member.allergies,
            chronicConditions: member.chronicConditions,
            notes: member.notes,
            avatarUrl: member.avatarUrl,
            isPrimary: member.isPrimary
        )

        do {
            _ = try await memberAPI.updateMember(remoteID: member.id, payload: payload)
            try await refreshRemoteSnapshot()
            return
        } catch {
            logger.warning("远端更新成员失败，将尝试通过快照上传兜底：\(error.localizedDescription)", category: "home")
        }

        try await fallbackUpdateMember(
            member,
            name: name,
            relationship: relationship,
            gender: gender,
            birthDate: birthDate
        )
    }

    func deleteMember(_ member: Member) async throws {
        do {
            try await memberAPI.deleteMember(remoteID: member.id)
            try await refreshRemoteSnapshot()
            return
        } catch {
            logger.warning("远端删除成员失败，将尝试通过快照上传兜底：\(error.localizedDescription)", category: "home")
        }

        try await fallbackDeleteMember(member)
    }

    private func fallbackCreateMember(
        name: String,
        relationship: String,
        gender: String,
        birthDate: Date?
    ) async throws {
        var snapshot = await medicalDataRepository.loadSnapshot()
        snapshot.members.append(
            Member(
                id: (snapshot.members.map(\.id).max() ?? 0) + 1,
                name: name,
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
        gender: String,
        birthDate: Date?
    ) async throws {
        var snapshot = await medicalDataRepository.loadSnapshot()
        snapshot.members = snapshot.members.map { current in
            guard current.id == member.id else { return current }
            return Member(
                id: current.id,
                name: name,
                gender: gender,
                relationship: relationship,
                birthDate: birthDate,
                bloodType: current.bloodType,
                allergies: current.allergies,
                chronicConditions: current.chronicConditions,
                notes: current.notes,
                avatarUrl: current.avatarUrl,
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
        snapshot.symptoms.removeAll { $0.memberID == member.id }
        snapshot.visits.removeAll { $0.memberID == member.id }
        snapshot.surgeries.removeAll { $0.memberID == member.id }
        snapshot.followUps.removeAll { $0.memberID == member.id }
        snapshot.examinationReports.removeAll { $0.memberID == member.id }
        snapshot.medicalReports.removeAll { $0.memberID == member.id }
        snapshot.prescriptionBatches.removeAll { $0.memberID == member.id }
        snapshot.medications.removeAll { $0.memberID == member.id }
        snapshot.medicationTakenRecords.removeAll { $0.memberID == member.id }
        try await medicalDataRepository.saveSnapshot(snapshot)
        try await medicalDataRepository.uploadSnapshotToServer(priority: .balanced)
        try await medicalDataRepository.pullSnapshotFromServer(priority: .balanced)
    }
}
