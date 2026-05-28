import Combine
import Foundation

@MainActor
/// Session 状态机：只暴露 UI 所需状态，屏蔽会话恢复细节。
final class AppSessionStore: ObservableObject {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(UserSession)
    }

    @Published private(set) var state: State = .loading

    private let restoreSessionUseCase: RestoreSessionUseCase
    private let sessionSnapshotStore: SessionSnapshotStore?
    private let logger: Logger = ConsoleLogger()
    private var didRestore = false

    init(
        restoreSessionUseCase: RestoreSessionUseCase,
        sessionSnapshotStore: SessionSnapshotStore? = nil
    ) {
        self.restoreSessionUseCase = restoreSessionUseCase
        self.sessionSnapshotStore = sessionSnapshotStore
    }

    /// App 冷启动仅恢复一次，避免重复触发网络与存储读取。
    func restoreIfNeeded() async {
        guard didRestore == false else { return }
        didRestore = true

        if let session = await restoreSessionUseCase.execute() {
            logger.info(
                "AppSessionStore：冷启动会话已恢复 accountID=\(session.accountID) isPro=\(session.isPro)",
                module: .auth
            )
            state = .signedIn(session)
            await verifyPersistedSnapshotMatchesMemory(session, context: "restoreIfNeeded")
        } else {
            logger.info("AppSessionStore：冷启动无可用会话，进入 signedOut", module: .auth)
            state = .signedOut
        }
    }

    func setAuthenticated(_ session: UserSession) {
        logger.info("AppSessionStore：设置已登录状态 accountID=\(session.accountID)", module: .auth)
        state = .signedIn(session)
        Task { await verifyPersistedSnapshotMatchesMemory(session, context: "setAuthenticated") }
    }

    func setSignedOut() {
        logger.info("AppSessionStore：设置未登录状态", module: .auth)
        state = .signedOut
    }

    /// 检测「内存 signedIn」与 `SessionSnapshotStore` 是否一致（快照缺失/解码失败/账号不一致）。
    private func verifyPersistedSnapshotMatchesMemory(_ session: UserSession, context: String) async {
        guard let sessionSnapshotStore else { return }
        guard let persisted = await sessionSnapshotStore.load() else {
            logger.warning(
                "AppSessionStore：\(context) 后内存为 signedIn(accountID=\(session.accountID))，但 SessionSnapshotStore.load()=nil（快照缺失或解码失败，易出现 token 与 accountID 分裂）",
                module: .auth
            )
            return
        }
        guard persisted.accountID == session.accountID else {
            logger.warning(
                "AppSessionStore：\(context) 后内存 accountID=\(session.accountID) 与快照 accountID=\(persisted.accountID) 不一致",
                module: .auth
            )
            return
        }
        logger.debug(
            "AppSessionStore：\(context) 后内存与快照一致 accountID=\(session.accountID)",
            module: .auth
        )
    }
}
