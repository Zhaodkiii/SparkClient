import Foundation

/// 首页医疗摘要加载用例（直接走 ``SparkMedicalQueryAPI``，无本地聚合快照）。
struct LoadHomeMedicalOverviewUseCase: Sendable {
    let medicalQueryAPI: SparkMedicalQueryAPI
    let selectedMemberIDPersistence: any SelectedMemberIDPersisting
    let logger: Logger

    private let logModule = LogModule.home

    func execute(
        session: UserSession,
        selectedMemberID: Int?,
        refreshRemoteSnapshot: Bool
    ) async throws -> HomeMedicalLoadResult {
        let startedAt = Date()

        // 成员列表是首页的关键数据，失败时不应静默降级为空数组（会导致 UI 被“清空”）。
        // 这里改为显式抛错，让上层保留已有 dashboard 并展示错误提示。
        let remotes = try await medicalQueryAPI.listMembers()
        let members = remotes.map(\.domainModel).sorted { lhs, rhs in
            if lhs.isPrimary == rhs.isPrimary {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.isPrimary && !rhs.isPrimary
        }

        let resolvedSelectedID: Int? = {
            guard members.isEmpty == false else { return nil }
            let persisted = selectedMemberIDPersistence.load(for: session.accountID)
            let preferred = selectedMemberID ?? persisted
            if let preferred, members.contains(where: { $0.id == preferred }) {
                return preferred
            }
            return members.first?.id
        }()

        let medical: HomeMedicalOverview
        if let resolvedSelectedID {
            // 直接读取成员 complete-data，首页卡片与后续列表页共用同一份快照，避免重复请求。
            let complete = (try? await medicalQueryAPI.fetchMemberCompleteData(memberID: resolvedSelectedID)) ?? nil
            medical = HomeMedicalOverview(
                cards: makeMedicalCards(complete: complete),
                completeData: complete
            )
        } else {
            medical = HomeMedicalOverview(cards: emptyMedicalCards(), completeData: nil)
        }

        let cost = Date().timeIntervalSince(startedAt)
        logger.info(
            "医疗摘要完成 cost=\(String(format: "%.3f", cost))s refreshRemote=\(refreshRemoteSnapshot) accountID=\(session.accountID) memberID=\(resolvedSelectedID.map(String.init) ?? "nil") cards=\(medical.cards.count)",
            module: logModule
        )

        return HomeMedicalLoadResult(
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
            HomeDashboard.MedicalCard(id: .medicationPlans, count: 0, latestDate: nil, symbol: "calendar.badge.clock")
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
        let medicationPlans = complete.medicationPlans ?? []

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
                id: .medicationPlans,
                count: complete.medicationSummary?.activePlanCount ?? medicationPlans.filter { $0.status == "active" }.count,
                latestDate: medicationPlans.map(\.updatedAt).max(),
                symbol: "calendar.badge.clock"
            )
        ]
    }
}

struct HomeMedicalLoadResult: Equatable, Sendable {
    let members: [Member]
    let selectedMemberID: Int?
    let medical: HomeMedicalOverview

    var selectedMember: Member? {
        guard let selectedMemberID else { return members.first }
        return members.first(where: { $0.id == selectedMemberID }) ?? members.first
    }
}
