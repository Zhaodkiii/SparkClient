import Combine
import SwiftUI
import UIKit

/// 应用版本更新协调器
/// 负责：版本检查、更新弹窗控制、用户操作记录、频率限制
@MainActor
final class AppVersionUpdateCoordinator: ObservableObject {

    // MARK: - 对外可观察状态
    /// 服务端返回的版本更新信息
    @Published private(set) var updateInfo: SparkVersionAPI.CheckResponse?
    /// 是否显示【强制更新】弹窗
    @Published var showForceUpdate = false
    /// 是否显示【可选更新】弹窗
    @Published var showOptionalUpdate = false
    /// 手动检查版本的提示信息
    @Published private(set) var manualCheckMessage: String?
    /// 是否正在手动检查版本
    @Published private(set) var isCheckingManually = false

    // MARK: - 依赖
    private let api: SparkVersionAPI              // 版本检查接口
    private let systemInfo: SparkSystemInfo      // 系统信息（设备、App 版本、渠道等）
    private let logger: Logger                   // 日志工具
    private let defaults: UserDefaults           // 本地存储

    // MARK: - 本地存储 Key
    private let lastCheckTimeKey = "spark.version.lastCheckTime"    // 上一次检查时间
    private let lastPromptTimeKey = "spark.version.lastPromptTime"  // 上一次弹窗时间

    // MARK: - 频率限制
    private let checkInterval: TimeInterval = 3600        // 自动检查间隔：1小时
    private let promptInterval: TimeInterval = 24 * 3600   // 可选更新弹窗间隔：24小时

    // MARK: - 初始化
    init(api: SparkVersionAPI, systemInfo: SparkSystemInfo = .shared, defaults: UserDefaults = .standard, logger: Logger = ConsoleLogger()) {
        self.api = api
        self.systemInfo = systemInfo
        self.defaults = defaults
        self.logger = logger
    }

    // MARK: - 对外方法

    /// 启动时按需检查版本（自动检查，带频率限制）
    func checkOnLaunchIfNeeded(force: Bool = false) async {
        // 非强制检查 + 距离上次检查不足1小时 → 不检查
        if !force, let last = defaults.object(forKey: lastCheckTimeKey) as? Date, Date().timeIntervalSince(last) < checkInterval {
            return
        }
        // 执行版本检查
        await performCheck(isManual: false)
    }

    /// 手动检查版本（用户主动触发，无频率限制）
    func manualCheck() async {
        isCheckingManually = true
        manualCheckMessage = nil
        defer { isCheckingManually = false } // 方法结束后重置状态
        await performCheck(isManual: true)
    }

    /// 用户点击「立即更新」
    func handleUpdateNow() {
        // 打开下载链接
        guard let text = updateInfo?.downloadUrl, let url = URL(string: text) else { return }
        UIApplication.shared.open(url)
        // 上报行为
        Task { await recordAction("update_clicked") }
    }

    /// 用户点击「稍后提醒」
    func handleLater() {
        // 记录本次弹窗时间，24小时内不再弹出
        defaults.set(Date(), forKey: lastPromptTimeKey)
        showOptionalUpdate = false
        Task { await recordAction("later_clicked") }
    }

    /// 用户关闭可选更新弹窗
    func handleDismiss() {
        showOptionalUpdate = false
        Task { await recordAction("dismissed") }
    }

    // MARK: - 内部方法

    /// 执行版本检查（核心逻辑）
    private func performCheck(isManual: Bool) async {
        do {
            // 请求服务端检查版本
            let response = try await api.checkVersion(systemInfo: systemInfo)
            // 保存检查时间
            defaults.set(Date(), forKey: lastCheckTimeKey)

            if response.hasUpdate {
                // 有新版本
                updateInfo = response
                manualCheckMessage = String(
                    format: L10n.text("settings.version.new_available", fallback: "发现新版本 %@"),
                    locale: Locale.current,
                    response.latestVersion ?? ""
                )

                if response.forceUpdate == true {
                    // 强制更新：直接弹窗
                    showForceUpdate = true
                    await recordAction("force_update_shown")
                }
                else if isManual || shouldShowOptionalPrompt() {
                    // 可选更新：手动检查 或 满足弹窗间隔 → 弹窗
                    showOptionalUpdate = true
                    await recordAction("optional_update_shown")
                }
            }
            else if isManual {
                // 无更新（仅手动检查时提示）
                manualCheckMessage = response.message ?? L10n.text("settings.version.up_to_date", fallback: "当前已是最新版本")
            }
        }
        catch {
            // 检查失败
            logger.warning("版本检查失败：\(error.localizedDescription)", module: .network)
            if isManual {
                manualCheckMessage = String(
                    format: L10n.text("settings.version.check_failed", fallback: "检查失败：%@"),
                    locale: Locale.current,
                    error.localizedDescription
                )
            }
        }
    }

    /// 判断是否可以弹出可选更新弹窗（24小时内只弹一次）
    private func shouldShowOptionalPrompt() -> Bool {
        guard let last = defaults.object(forKey: lastPromptTimeKey) as? Date else {
            return true // 从未弹过 → 可以弹
        }
        // 距离上次弹窗超过24小时 → 可以弹
        return Date().timeIntervalSince(last) >= promptInterval
    }

    /// 上报用户更新行为（展示/点击/关闭等）
    private func recordAction(_ action: String) async {
        do {
            _ = try await api.recordAction(action, checkLogId: updateInfo?.checkLogId, systemInfo: systemInfo)
        } catch {
            logger.debug("版本操作上报失败：\(error.localizedDescription)", module: .network)
        }
    }
}

// MARK: - SwiftUI 弹窗容器

/// 版本更新弹窗修饰器（给全局 View 添加弹窗能力）
struct VersionUpdateOverlay: ViewModifier {
    @ObservedObject var coordinator: AppVersionUpdateCoordinator

    func body(content: Content) -> some View {
        content
            // 强制更新弹窗（不可手动关闭）
            .sheet(isPresented: $coordinator.showForceUpdate) {
                VersionForceUpdateView(coordinator: coordinator)
                    .interactiveDismissDisabled()
            }
            // 可选更新弹窗
            .sheet(isPresented: $coordinator.showOptionalUpdate) {
                VersionOptionalUpdateView(coordinator: coordinator)
            }
    }
}

// MARK: - 强制更新弹窗 UI
private struct VersionForceUpdateView: View {
    @ObservedObject var coordinator: AppVersionUpdateCoordinator

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 52))
                .foregroundStyle(.red)

            Text(coordinator.updateInfo?.updateTitle ?? "需要更新")
                .font(.title2.bold())

            Text(coordinator.updateInfo?.updateMessage ?? "")
                .font(.body)
                .multilineTextAlignment(.center)

            Button("立即更新") { coordinator.handleUpdateNow() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(28)
    }
}

// MARK: - 可选更新弹窗 UI
private struct VersionOptionalUpdateView: View {
    @ObservedObject var coordinator: AppVersionUpdateCoordinator

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: 46))
                .foregroundStyle(.blue)

            Text(coordinator.updateInfo?.updateTitle ?? "发现新版本")
                .font(.title3.bold())

            Text(coordinator.updateInfo?.updateMessage ?? "")
                .font(.body)
                .multilineTextAlignment(.center)

            HStack {
                Button("稍后提醒") { coordinator.handleLater() }
                    .buttonStyle(.bordered)

                Button("立即更新") { coordinator.handleUpdateNow() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
    }
}
