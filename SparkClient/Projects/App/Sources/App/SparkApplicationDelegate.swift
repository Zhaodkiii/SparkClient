import Foundation
import UIKit

/// 应用全局代理类，主线程执行，处理App生命周期、推送、外部文件唤起、场景连接逻辑
@MainActor
final class SparkApplicationDelegate: NSObject, UIApplicationDelegate {
    // MARK: - 静态引导单例缓存（启动前注入的全局适配器/协调器）
    /// 推送服务引导适配器，全局静态缓存
    static var bootstrapPushAdapter: PushAdapter?
    /// 外部医疗文档导入流程引导协调器，全局静态缓存
    static var bootstrapExternalMedicalDocumentImportCoordinator: ExternalMedicalDocumentImportCoordinator?

    // MARK: - 实例成员
    /// 当前实例持有的推送适配器，承载推送注册、消息回调逻辑
    var pushAdapter: PushAdapter?
    /// 当前实例持有的外部医疗文档导入协调器，处理文件唤起、启动参数解析
    var externalMedicalDocumentImportCoordinator: ExternalMedicalDocumentImportCoordinator?

    // MARK: - App 生命周期回调
    /// App 启动完成入口
    /// - Parameters:
    ///   - application: 当前应用实例
    ///   - launchOptions: App冷启动携带参数（推送点击、外部文件唤起等来源）
    /// - Returns: 固定返回true，代表启动流程正常执行
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 若实例推送适配器未初始化，从静态引导变量赋值
        if pushAdapter == nil {
            pushAdapter = Self.bootstrapPushAdapter
        }
        // 若文档导入协调器未初始化，从静态引导变量赋值
        if externalMedicalDocumentImportCoordinator == nil {
            externalMedicalDocumentImportCoordinator = Self.bootstrapExternalMedicalDocumentImportCoordinator
        }
        // 将推送适配器注册为系统通知中心代理，接管推送消息回调
        pushAdapter?.installAsNotificationCenterDelegate()
        // 协调器消费启动参数，解析冷启动携带的外部医疗文件/推送数据
        resolveCoordinator()?.consumeLaunchOptions(launchOptions)
        return true
    }

    /// 创建Scene场景配置，多窗口/分屏场景连接回调
    /// - Parameters:
    ///   - connectingSceneSession: 待连接的场景会话
    ///   - options: 场景连接携带参数（分屏唤起、外部文件打开参数）
    /// - Returns: 场景配置实例
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // 协调器消费场景连接参数，解析场景唤起携带的医疗文档数据
        resolveCoordinator()?.consumeConnectionOptions(options)
        // 返回默认场景配置，不指定自定义Scene名称
        return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    }

    /// App通过URL Scheme打开外部文件/跳转链接回调
    /// - Parameters:
    ///   - app: 当前应用实例
    ///   - url: 外部唤起的文件/跳转URL
    ///   - options: 唤起来源附加参数
    /// - Returns: 成功接收并处理URL返回true，无协调器处理则返回false
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        // 交由文档协调器尝试解析外部URL，标记来源为应用唤起
        return resolveCoordinator()?.tryReceive(url, source: .applicationOpen) ?? false
    }

    // MARK: - 远程推送设备令牌回调
    /// 成功获取APNs远程推送设备令牌
    /// - Parameters:
    ///   - application: 当前应用实例
    ///   - deviceToken: 苹果返回的设备二进制令牌，用于推送服务绑定设备
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // 推送适配器处理设备令牌，上传至后端推送服务
        pushAdapter?.handleDeviceToken(deviceToken)
    }

    /// 获取APNs推送令牌失败回调
    /// - Parameters:
    ///   - application: 当前应用实例
    ///   - error: 注册失败错误信息（权限关闭、网络、证书异常等）
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // 推送适配器统一处理令牌注册失败逻辑（日志、异常上报）
        pushAdapter?.handleDeviceTokenRegistrationError(error)
    }

    // MARK: - 私有工具方法
    /// 安全获取文档导入协调器实例，为空时自动从静态引导变量赋值
    /// - Returns: 可用的外部医疗文档导入协调器实例，nil代表未注入
    private func resolveCoordinator() -> ExternalMedicalDocumentImportCoordinator? {
        if externalMedicalDocumentImportCoordinator == nil {
            externalMedicalDocumentImportCoordinator = Self.bootstrapExternalMedicalDocumentImportCoordinator
        }
        return externalMedicalDocumentImportCoordinator
    }
}
