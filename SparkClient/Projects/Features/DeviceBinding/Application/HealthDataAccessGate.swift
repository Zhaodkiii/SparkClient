import Foundation
import HealthKit

/// 健康数据访问错误。
nonisolated struct HealthDataAccessFailure: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// 健康数据访问控制网关：所有健康数据访问必须经过此网关进行三重校验。
///
/// 三重校验：
/// 1. 验证当前成员是否已绑定设备；
/// 2. 确认设备健康数据授权状态有效；
/// 3. 检查当前成员与该数据源绑定关系一致。
///
/// 绑定数据按「当前登录账号」隔离读取，避免多账号之间数据串扰。
final class HealthDataAccessGate: @unchecked Sendable {
    static let shared = HealthDataAccessGate()

    private let storage: DeviceBindingStorage
    private let authStore: HealthKitAuthorizationStore
    private let sessionStore: SessionSnapshotStore

    init(
        storage: DeviceBindingStorage = .shared,
        authStore: HealthKitAuthorizationStore = HealthKitAuthorizationStore(),
        sessionStore: SessionSnapshotStore = SessionSnapshotStore()
    ) {
        self.storage = storage
        self.authStore = authStore
        self.sessionStore = sessionStore
    }

    /// 当前登录账号 ID；未登录返回 nil。
    private func currentAccountID() async -> Int64? {
        await sessionStore.load()?.accountID
    }

    /// 检查指定成员对指定数据源的访问权限。
    func checkAccess(
        for sourceType: HealthDataSourceType = .appleHealth,
        memberId: Int
    ) async -> HealthDataAccessResult {
        guard sourceType.isAvailable else {
            return .dataSourceNotAvailable(sourceType)
        }
        guard authStore.isHealthDataAvailable else {
            return .healthKitUnavailable
        }
        guard let accountID = await currentAccountID(),
              let binding = storage.loadBindings(accountID: accountID).first(where: { $0.sourceType == sourceType }) else {
            return .noBinding(sourceType)
        }
        guard binding.memberId == memberId else {
            return .memberNotBound
        }

        switch await authStore.checkAuthorizationStatus() {
        case .authorized, .partial:
            return .granted
        case .denied, .revoked:
            return .authorizationDenied
        case .notDetermined:
            return .authorizationDenied
        }
    }

    /// 校验通过后返回可用的 `HKHealthStore` 与绑定记录。
    func validatedHealthStore(
        for sourceType: HealthDataSourceType = .appleHealth,
        memberId: Int
    ) async throws -> (HKHealthStore, DeviceBinding) {
        let result = await checkAccess(for: sourceType, memberId: memberId)
        switch result {
        case .granted:
            guard let accountID = await currentAccountID(),
                  let binding = storage.loadBindings(accountID: accountID).first(where: { $0.sourceType == sourceType }) else {
                throw HealthDataAccessFailure(message: result.errorDescription)
            }
            return (authStore.healthStore, binding)
        default:
            throw HealthDataAccessFailure(message: result.errorDescription)
        }
    }
}