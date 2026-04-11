import Foundation

/// 首页运动健康：仅当选中成员为「本人」时访问 HealthKit；其他成员不发起系统健康请求。
struct LoadHomeMotionHealthUseCase: Sendable {
    let healthDataRepository: any HomeHealthDataRepository
    let logger: Logger

    private let logModule = LogModule.home

    func execute(selectedMember: Member?) async throws -> HomeMotionHealthOverview {
        let startedAt = Date()
        guard let selectedMember, selectedMember.canUseMotionHealthOnHome else {
            logger.info(
                "运动健康跳过 HealthKit（非本人或无成员） memberID=\(selectedMember.map { String($0.id) } ?? "nil")",
                module: logModule
            )
            return HomeMotionHealthOverview(
                healthBasics: [],
                healthAuthorizationStatus: .unavailable,
                isApplicable: false
            )
        }

        let status = await healthDataRepository.currentAuthorizationStatus()
        let basics = try await healthDataRepository.fetchHealthBasics()
        let cost = Date().timeIntervalSince(startedAt)
        logger.info(
            "运动健康完成 cost=\(String(format: "%.3f", cost))s auth=\(String(describing: status)) items=\(basics.count)",
            module: logModule
        )
        return HomeMotionHealthOverview(
            healthBasics: basics,
            healthAuthorizationStatus: status,
            isApplicable: true
        )
    }
}
