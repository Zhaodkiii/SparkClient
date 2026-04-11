import Foundation

/// 首页医疗摘要加载用例（直接走 ``SparkMedicalQueryAPI``，无本地聚合快照）。
struct LoadHomeMedicalOverviewUseCase: Sendable {
    let userProfileRepository: any UserProfileRepository
    let medicalQueryAPI: SparkMedicalQueryAPI
    let selectedMemberIDPersistence: any SelectedMemberIDPersisting
    let logger: Logger

    private let logModule = LogModule.home

    func execute(
        profileID: UUID,
        selectedMemberID: Int?,
        refreshRemoteSnapshot: Bool
    ) async throws -> HomeMedicalLoadResult {
        let startedAt = Date()
        guard let profile = try await userProfileRepository.fetchProfile(id: profileID) else {
            throw NSError(domain: "SparkClient.Home", code: 404, userInfo: [NSLocalizedDescriptionKey: "未找到当前档案"])
        }

        if refreshRemoteSnapshot {
            _ = try? await medicalQueryAPI.listMembers()
        }

        let remotes = (try? await medicalQueryAPI.listMembers()) ?? []
        let members = remotes.map(\.domainModel).sorted { lhs, rhs in
            if lhs.isPrimary == rhs.isPrimary {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.isPrimary && !rhs.isPrimary
        }

        let resolvedSelectedID: Int? = {
            guard members.isEmpty == false else { return nil }
            let persisted = selectedMemberIDPersistence.load(for: profileID)
            let preferred = selectedMemberID ?? persisted
            if let preferred, members.contains(where: { $0.id == preferred }) {
                return preferred
            }
            return members.first?.id
        }()

        let medical: HomeMedicalOverview
        if let resolvedSelectedID {
            let complete = (try? await medicalQueryAPI.fetchMemberCompleteData(memberID: resolvedSelectedID)) ?? nil
            medical = HomeMedicalOverview(
                cards: makeMedicalCards(complete: complete)
            )
        } else {
            medical = HomeMedicalOverview(cards: emptyMedicalCards())
        }

        let cost = Date().timeIntervalSince(startedAt)
        logger.info(
            "医疗摘要完成 cost=\(String(format: "%.3f", cost))s refreshRemote=\(refreshRemoteSnapshot) memberID=\(resolvedSelectedID.map(String.init) ?? "nil") cards=\(medical.cards.count)",
            module: logModule
        )

        return HomeMedicalLoadResult(
            profile: profile,
            members: members,
            selectedMemberID: resolvedSelectedID,
            medical: medical
        )
    }

    private func emptyMedicalCards() -> [HomeDashboard.MedicalCard] {
        [
            HomeDashboard.MedicalCard(id: .medicalCases, count: 0, latestDate: nil, symbol: "doc.text.fill"),
            HomeDashboard.MedicalCard(id: .healthExamReports, count: 0, latestDate: nil, symbol: "heart.text.square.fill"),
            HomeDashboard.MedicalCard(id: .medicalReports, count: 0, latestDate: nil, symbol: "list.clipboard.fill"),
            HomeDashboard.MedicalCard(id: .medications, count: 0, latestDate: nil, symbol: "pills.fill")
        ]
    }

    private func makeMedicalCards(
        complete: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    ) -> [HomeDashboard.MedicalCard] {
        guard let complete else {
            return emptyMedicalCards()
        }

        let medicalCases = (complete.medicalCases ?? []).map(\.domainModel)
        let healthExamReports = (complete.healthExamReports ?? []).map(\.domainModel)
        let examinationReports = (complete.examinationReports ?? []).map(\.domainModel)
        let batches = complete.prescriptionBatches ?? []
        let standalone = complete.standaloneMedications ?? []
        let medications = batches.flatMap { $0.medications ?? [] }.map(\.domainModel)
            + standalone.map(\.domainModel)

        return [
            HomeDashboard.MedicalCard(
                id: .medicalCases,
                count: medicalCases.count,
                latestDate: medicalCases.map(\.updatedAt).max(),
                symbol: "doc.text.fill"
            ),
            HomeDashboard.MedicalCard(
                id: .healthExamReports,
                count: healthExamReports.count,
                latestDate: healthExamReports.compactMap(\.examDate).max(),
                symbol: "heart.text.square.fill"
            ),
            HomeDashboard.MedicalCard(
                id: .medicalReports,
                count: examinationReports.count,
                latestDate: examinationReports.compactMap { $0.reportedAt ?? $0.performedAt }.max(),
                symbol: "list.clipboard.fill"
            ),
            HomeDashboard.MedicalCard(
                id: .medications,
                count: medications.count,
                latestDate: medications.map(\.updatedAt).max(),
                symbol: "pills.fill"
            )
        ]
    }
}

struct HomeMedicalLoadResult: Equatable, Sendable {
    let profile: UserProfile
    let members: [Member]
    let selectedMemberID: Int?
    let medical: HomeMedicalOverview

    var selectedMember: Member? {
        guard let selectedMemberID else { return members.first }
        return members.first(where: { $0.id == selectedMemberID }) ?? members.first
    }
}
