import Foundation
import HealthKit

/// HealthKit 授权封装：统一管理与检查苹果健康读写权限。
///
/// 关键点：苹果健康的「读取」授权无法用 `authorizationStatus(for:)` 准确查询——
/// 该方法只反映「写入/share」状态，对只读类型通常返回 `.notDetermined`。
/// 因此统一改用 `getRequestStatusForAuthorization(toShare:read:)`：
///   - `.unnecessary`  → 已授权（无需再请求）
///   - `.shouldRequest` → 尚未授权，需要弹系统授权框
///   - `.unknown`      → 无法确定（HealthKit 不可用或查询失败）
final class HealthKitAuthorizationStore: @unchecked Sendable {
    let healthStore = HKHealthStore()

    private let readTypes = HealthKitAuthorizationStore.requiredReadTypes()

    /// 单飞保护：并发点击「绑定」时同一时刻只允许一个授权请求在途，避免系统回调丢失导致挂起。
    private let requestGate = RequestGate()

    /// 设备是否支持 HealthKit。
    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// 请求苹果健康读取权限（写权限仅在营养等写回场景需要时附带）。
    ///
    /// 若已授权（`.unnecessary`），不会再次弹系统授权框，直接返回 `.authorized`，避免重复请求导致回调挂起。
    func requestAuthorization(writeTypes: Set<HKSampleType> = []) async throws -> HealthAuthorizationStatus {
        guard isHealthDataAvailable else {
            return .denied
        }

        // 已授权或无需请求 → 直接判定为已授权，跳过系统授权请求。
        if await currentRequestStatus(writeTypes: writeTypes) == .unnecessary {
            return .authorized
        }

        // 已有授权请求在途，本次直接重新确认状态即可。
        guard await requestGate.tryBegin() else {
            return await checkAuthorizationStatus()
        }

        do {
            try await requestAuthorization(toShare: writeTypes, read: readTypes)
        } catch {
            await requestGate.end()
            throw error
        }

        await requestGate.end()
        return await checkAuthorizationStatus()
    }

    /// 实时检查当前读取授权状态。
    func checkAuthorizationStatus() async -> HealthAuthorizationStatus {
        guard isHealthDataAvailable else {
            return .denied
        }
        switch await currentRequestStatus(writeTypes: []) {
        case .unnecessary:
            return .authorized
        case .shouldRequest:
            return .notDetermined
        case .unknown, .none:
            return .denied
        @unknown default:
            return .denied
        }
    }

    // MARK: - Private

    /// 权威查询：当前设备的读取授权请求状态。
    private func currentRequestStatus(writeTypes: Set<HKSampleType>) async -> HKAuthorizationRequestStatus? {
        await withCheckedContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(toShare: writeTypes, read: readTypes) { status, _ in
                continuation.resume(returning: status)
            }
        }
    }

    private func requestAuthorization(toShare shareTypes: Set<HKSampleType>, read readTypes: Set<HKObjectType>) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private static func requiredReadTypes() -> Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
            HKObjectType.quantityType(forIdentifier: .dietaryProtein)!,
            HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .respiratoryRate)!,
            HKObjectType.quantityType(forIdentifier: .flightsClimbed)!,
            HKObjectType.quantityType(forIdentifier: .distanceCycling)!,
        ]
        if let runningSpeed = HKObjectType.quantityType(forIdentifier: .runningSpeed) {
            types.insert(runningSpeed)
        }
        if let wristTemperature = HKObjectType.quantityType(forIdentifier: .appleSleepingWristTemperature) {
            types.insert(wristTemperature)
        }
        return types
    }
}

/// 授权请求单飞门闩（actor 保证线程安全，替代在异步上下文中禁用的 `NSLock`）。
private actor RequestGate {
    private var isRequesting = false

    func tryBegin() -> Bool {
        if isRequesting { return false }
        isRequesting = true
        return true
    }

    func end() {
        isRequesting = false
    }
}