import Foundation

struct LoadHomeDashboardUseCase: Sendable {
    let userProfileRepository: any UserProfileRepository
    let memberRepository: any HomeMemberRepository
    let healthDataRepository: any HomeHealthDataRepository

    func execute(profileID: UUID, selectedMemberID: UUID?) async throws -> HomeDashboard {
        guard let profile = try await userProfileRepository.fetchProfile(id: profileID) else {
            throw NSError(domain: "SparkClient.Home", code: 404, userInfo: [NSLocalizedDescriptionKey: "未找到当前档案"])
        }

        do {
            try await memberRepository.refreshRemoteSnapshot()
        } catch {
            // 远端拉取失败时保底走本地快照，避免首页阻塞。
        }

        let snapshot = await memberRepository.loadSnapshot()
        let members = snapshot.members.sorted { lhs, rhs in
            if lhs.isPrimary == rhs.isPrimary {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.isPrimary && !rhs.isPrimary
        }

        let resolvedSelectedID: UUID? = {
            if let selectedMemberID, members.contains(where: { $0.id == selectedMemberID }) {
                return selectedMemberID
            }
            return members.first?.id
        }()

        let medicalCards = makeMedicalCards(from: snapshot, selectedMemberID: resolvedSelectedID)
        let healthAuthorizationStatus = await healthDataRepository.currentAuthorizationStatus()
        let healthBasics = try await healthDataRepository.fetchHealthBasics()

        return HomeDashboard(
            profile: profile,
            members: members,
            selectedMemberID: resolvedSelectedID,
            medicalCards: medicalCards,
            healthBasics: healthBasics,
            healthAuthorizationStatus: healthAuthorizationStatus
        )
    }

    private func makeMedicalCards(from snapshot: MedicalDataSnapshot, selectedMemberID: UUID?) -> [HomeDashboard.MedicalCard] {
        guard let selectedMemberID else {
            return [
                HomeDashboard.MedicalCard(id: .medicalCases, title: "病例记录", subtitle: "最近就诊", count: 0, latestDate: nil, symbol: "doc.text.fill"),
                HomeDashboard.MedicalCard(id: .examinationReports, title: "体检报告", subtitle: "年度体检", count: 0, latestDate: nil, symbol: "list.clipboard.fill"),
                HomeDashboard.MedicalCard(id: .medicalReports, title: "检查报告", subtitle: "专项检查", count: 0, latestDate: nil, symbol: "cross.case.fill"),
                HomeDashboard.MedicalCard(id: .prescriptions, title: "用药处方", subtitle: "长期用药", count: 0, latestDate: nil, symbol: "pills.fill")
            ]
        }

        let medicalCases = snapshot.medicalCases.filter { $0.memberID == selectedMemberID }
        let examinationReports = snapshot.examinationReports.filter { $0.memberID == selectedMemberID }
        let medicalReports = snapshot.medicalReports.filter { $0.memberID == selectedMemberID }
        let prescriptions = snapshot.prescriptions.filter { $0.memberID == selectedMemberID }

        return [
            HomeDashboard.MedicalCard(
                id: .medicalCases,
                title: "病例记录",
                subtitle: "最近就诊",
                count: medicalCases.count,
                latestDate: medicalCases.map(\.visitDate).max(),
                symbol: "doc.text.fill"
            ),
            HomeDashboard.MedicalCard(
                id: .examinationReports,
                title: "体检报告",
                subtitle: "年度体检",
                count: examinationReports.count,
                latestDate: examinationReports.map(\.date).max(),
                symbol: "list.clipboard.fill"
            ),
            HomeDashboard.MedicalCard(
                id: .medicalReports,
                title: "检查报告",
                subtitle: "专项检查",
                count: medicalReports.count,
                latestDate: medicalReports.map(\.date).max(),
                symbol: "cross.case.fill"
            ),
            HomeDashboard.MedicalCard(
                id: .prescriptions,
                title: "用药处方",
                subtitle: "长期用药",
                count: prescriptions.count,
                latestDate: prescriptions.compactMap { $0.startDate ?? $0.endDate }.max(),
                symbol: "pills.fill"
            )
        ]
    }
}
