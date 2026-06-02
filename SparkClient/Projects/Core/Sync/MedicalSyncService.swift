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
/// 负责医疗模块同步配置管理、启动预热、手动立即同步、开关同步与优先级设置
@MainActor
final class MedicalSyncService {
    /// 同步偏好本地仓储：持久化读写同步开关、上次同步时间、初始化标记、同步优先级
    private let preferenceRepository: any MedicalSyncPreferenceRepository
    /// 医疗查询API：发起成员列表远端接口请求，用于预热缓存&ETag
    private let medicalQueryAPI: SparkMedicalQueryAPI
    /// 弹窗通知客户端：同步异常时弹出错误提示
    private let notificationClient: any NotificationClient
    /// 日志工具：输出同步流程、异常埋点日志
    private let logger: Logger

    /// 构造注入依赖
    /// - Parameters:
    ///   - preferenceRepository: 同步偏好数据仓库
    ///   - medicalQueryAPI: 医疗远端查询接口实例
    ///   - notificationClient: 全局错误弹窗组件
    ///   - logger: 日志实例，默认控制台输出日志
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

    /// 获取当前本地存储的同步配置偏好
    /// - Returns: 同步配置实体（开关、同步时间、初始化状态、优先级等）
    func currentPreference() async -> MedicalSyncPreference {
        await preferenceRepository.loadPreference()
    }

    /// 应用启动时按需执行初始化预热：开启同步时预拉取成员列表做远端ETag缓存
    func bootstrapIfNeeded() async {
        // 读取本地同步配置
        var preference = await preferenceRepository.loadPreference()
        // 同步总开关关闭，直接跳过启动预热
        guard preference.isSyncEnabled else { return }

        do {
            // 未完成过初始化标记则置为已完成
            if preference.hasCompletedInitialUpload == false {
                preference.hasCompletedInitialUpload = true
            }
            // 请求远端成员列表，完成接口预热、缓存ETag
            _ = try await medicalQueryAPI.listMembers()
            // 更新最后同步时间并落地本地存储
            preference.lastSyncAt = Date()
            await preferenceRepository.savePreference(preference)
            logger.info("健康数据同步引导已完成（成员列表预热）", module: .medical)
        } catch let authError as AuthTokenProviderError {
            // 缺失Token/刷新Token失败 = 未登录，静默跳过预热，不弹报错
            if case .missingTokens = authError {
                logger.info("未登录态，已跳过启动同步。", module: .medical)
                return
            }
            if case .refreshFailed = authError {
                logger.info("未登录态，已跳过启动同步。", module: .medical)
                return
            }
            // 其他鉴权异常：打日志+弹出错误提示
            logger.warning("健康数据同步引导失败：\(authError.localizedDescription)", module: .medical)
            presentBootstrapFailure(authError)
        } catch {
            // 非鉴权类异常：日志+弹窗提示
            logger.warning("健康数据同步引导失败：\(error.localizedDescription)", module: .medical)
            presentBootstrapFailure(error)
        }
    }

    /// 弹出同步启动失败提示弹窗（过滤主动取消的网络请求）
    /// - Parameter error: 异常对象
    private func presentBootstrapFailure(_ error: Error) {
        // 用户手动取消接口请求，不弹窗
        if let network = error as? SparkNetworkError, case .cancelled = network { return }
        // 优先取本地化错误文案，兜底系统默认描述
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let title = String(localized: String.LocalizationValue("common.error"), bundle: .main)
        notificationClient.error(message, title: title, source: "medical.sync.bootstrap")
    }

    /// 开关同步总配置：开启时立即预热成员列表接口
    /// - Parameter enabled: true开启同步 / false关闭同步
    func setSyncEnabled(_ enabled: Bool) async throws {
        var preference = await preferenceRepository.loadPreference()
        // 配置无变更直接返回
        if preference.isSyncEnabled == enabled { return }

        preference.isSyncEnabled = enabled
        // 打开同步：触发一次远端成员预热
        if enabled {
            do {
                _ = try await medicalQueryAPI.listMembers()
                preference.hasCompletedInitialUpload = true
                preference.lastSyncAt = Date()
            } catch let authError as AuthTokenProviderError {
                // 无登录凭证抛出未登录业务异常
                if case .missingTokens = authError { throw MedicalSyncServiceError.notAuthenticated }
                if case .refreshFailed = authError { throw MedicalSyncServiceError.notAuthenticated }
                throw authError
            }
        }
        // 持久化最新配置
        await preferenceRepository.savePreference(preference)
    }

    /// 手动触发立即同步：拉取远端成员刷新ETag、更新同步时间
    func syncNow() async throws {
        var preference = await preferenceRepository.loadPreference()
        // 同步开关关闭，无法手动同步
        guard preference.isSyncEnabled else { return }

        do {
            _ = try await medicalQueryAPI.listMembers()
        } catch let authError as AuthTokenProviderError {
            // 未登录抛出业务异常
            if case .missingTokens = authError { throw MedicalSyncServiceError.notAuthenticated }
            if case .refreshFailed = authError { throw MedicalSyncServiceError.notAuthenticated }
            throw authError
        }
        // 更新同步时间落地存储
        preference.lastSyncAt = Date()
        await preferenceRepository.savePreference(preference)
    }

    /// 修改云端同步优先级配置，无变更则忽略保存
    /// - Parameter priority: 同步优先级枚举
    func setSyncPriority(_ priority: CloudSyncPriority) async {
        var preference = await preferenceRepository.loadPreference()
        guard preference.syncPriority != priority else { return }
        preference.syncPriority = priority
        await preferenceRepository.savePreference(preference)
    }
}
