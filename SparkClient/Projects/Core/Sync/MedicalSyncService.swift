import Foundation

enum MedicalSyncServiceError: Error, LocalizedError, Sendable {
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "当前未登录，无法执行云端同步。请先登录后再试。"
        }
    }
}

/// 医疗同步偏好与轻量远端预热（成员列表 ETag），不再拉取本地聚合快照。
@MainActor
final class MedicalSyncService {
    private let preferenceRepository: any MedicalSyncPreferenceRepository
    private let medicalQueryAPI: SparkMedicalQueryAPI
    private let notificationClient: any NotificationClient
    private let logger: Logger

    init(
        preferenceRepository: any MedicalSyncPreferenceRepository,
        medicalQueryAPI: SparkMedicalQueryAPI,
        notificationClient: any NotificationClient,
        logger: Logger = ConsoleLogger()
    ) {
        self.preferenceRepository = preferenceRepository
        self.medicalQueryAPI = medicalQueryAPI
        self.notificationClient = notificationClient
        self.logger = logger
    }

    func currentPreference() async -> MedicalSyncPreference {
        await preferenceRepository.loadPreference()
    }

    func bootstrapIfNeeded() async {
        var preference = await preferenceRepository.loadPreference()
        guard preference.isSyncEnabled else { return }

        do {
            if preference.hasCompletedInitialUpload == false {
                preference.hasCompletedInitialUpload = true
            }
            _ = try await medicalQueryAPI.listMembers()
            preference.lastSyncAt = Date()
            await preferenceRepository.savePreference(preference)
            logger.info("健康数据同步引导已完成（成员列表预热）", module: .medical)
        } catch let authError as AuthTokenProviderError {
            if authError == .missingTokens || authError == .refreshFailed {
                logger.info("未登录态，已跳过启动同步。", module: .medical)
                return
            }
            logger.warning("健康数据同步引导失败：\(authError.localizedDescription)", module: .medical)
            presentBootstrapFailure(authError)
        } catch {
            logger.warning("健康数据同步引导失败：\(error.localizedDescription)", module: .medical)
            presentBootstrapFailure(error)
        }
    }

    private func presentBootstrapFailure(_ error: Error) {
        if let network = error as? SparkNetworkError, case .cancelled = network { return }
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let title = String(localized: String.LocalizationValue("common.error"), bundle: .main)
        notificationClient.error(message, title: title, source: "medical.sync.bootstrap")
    }

    func setSyncEnabled(_ enabled: Bool) async throws {
        var preference = await preferenceRepository.loadPreference()
        if preference.isSyncEnabled == enabled { return }

        preference.isSyncEnabled = enabled
        if enabled {
            do {
                _ = try await medicalQueryAPI.listMembers()
                preference.hasCompletedInitialUpload = true
                preference.lastSyncAt = Date()
            } catch let authError as AuthTokenProviderError {
                if authError == .missingTokens || authError == .refreshFailed {
                    throw MedicalSyncServiceError.notAuthenticated
                }
                throw authError
            }
        }
        await preferenceRepository.savePreference(preference)
    }

    func syncNow() async throws {
        var preference = await preferenceRepository.loadPreference()
        guard preference.isSyncEnabled else { return }

        do {
            _ = try await medicalQueryAPI.listMembers()
        } catch let authError as AuthTokenProviderError {
            if authError == .missingTokens || authError == .refreshFailed {
                throw MedicalSyncServiceError.notAuthenticated
            }
            throw authError
        }
        preference.lastSyncAt = Date()
        await preferenceRepository.savePreference(preference)
    }

    func setSyncPriority(_ priority: CloudSyncPriority) async {
        var preference = await preferenceRepository.loadPreference()
        guard preference.syncPriority != priority else { return }
        preference.syncPriority = priority
        await preferenceRepository.savePreference(preference)
    }
}
