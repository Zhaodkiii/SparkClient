import Foundation

/// 首页医疗摘要加载用例。
///
/// 当前医疗数据以服务端为准：先加载成员，再按“选中成员”维度加载医疗数据，
/// 避免一次性查询用户下全部医疗资源。
struct LoadHomeMedicalOverviewUseCase: Sendable {
    let userProfileRepository: any UserProfileRepository
    let memberRepository: any HomeMemberRepository
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
            try? await memberRepository.refreshRemoteSnapshot()
        }
        let members = await memberRepository.loadMembers().sorted { lhs, rhs in
            if lhs.isPrimary == rhs.isPrimary {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.isPrimary && !rhs.isPrimary
        }

        let resolvedSelectedID: Int? = {
            if let selectedMemberID, members.contains(where: { $0.id == selectedMemberID }) {
                return selectedMemberID
            }
            return members.first?.id
        }()

        let snapshot: MedicalDataSnapshot
        if let resolvedSelectedID {
            snapshot = await memberRepository.loadSnapshot(memberID: resolvedSelectedID)
        } else {
            snapshot = .empty
        }

        let medical = HomeMedicalOverview(cards: makeMedicalCards(from: snapshot, selectedMemberID: resolvedSelectedID))
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

    private func makeMedicalCards(from snapshot: MedicalDataSnapshot, selectedMemberID: Int?) -> [HomeDashboard.MedicalCard] {
        guard let selectedMemberID else {
            return [
                HomeDashboard.MedicalCard(id: .medicalCases, count: 0, latestDate: nil, symbol: "doc.text.fill"),
                HomeDashboard.MedicalCard(id: .healthExamReports, count: 0, latestDate: nil, symbol: "heart.text.square.fill"),
                HomeDashboard.MedicalCard(id: .medicalReports, count: 0, latestDate: nil, symbol: "list.clipboard.fill"),
                HomeDashboard.MedicalCard(id: .medications, count: 0, latestDate: nil, symbol: "pills.fill")
            ]
        }

        let medicalCases = snapshot.medicalCases.filter { $0.memberID == selectedMemberID }
        let healthExamReports = snapshot.healthExamReports.filter { $0.memberID == selectedMemberID }
        let examinationReports = snapshot.examinationReports.filter { $0.memberID == selectedMemberID }
        let medications = snapshot.medications.filter { $0.memberID == selectedMemberID }
        let todayRecords = snapshot.medicationTakenRecords.filter {
            $0.memberID == selectedMemberID && Calendar.current.isDateInToday($0.scheduledAt)
        }
        let takenToday = todayRecords.filter { $0.status == "taken" }.count
        let adherenceRate = todayRecords.isEmpty ? 0 : Int((Double(takenToday) / Double(todayRecords.count)) * 100)

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
                count: adherenceRate,
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
