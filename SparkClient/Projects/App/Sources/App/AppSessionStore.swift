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
    private let logger: Logger = ConsoleLogger()
    private var didRestore = false

    init(restoreSessionUseCase: RestoreSessionUseCase) {
        self.restoreSessionUseCase = restoreSessionUseCase
    }

    /// App 冷启动仅恢复一次，避免重复触发网络与存储读取。
    func restoreIfNeeded() async {
        guard didRestore == false else { return }
        didRestore = true

        if let session = await restoreSessionUseCase.execute() {
            state = .signedIn(session)
        } else {
            state = .signedOut
        }
    }

    func setAuthenticated(_ session: UserSession) {
        logger.info("AppSessionStore：设置已登录状态 accountID=\(session.accountID)", module: .auth)
        state = .signedIn(session)
    }

    func setSignedOut() {
        logger.info("AppSessionStore：设置未登录状态", module: .auth)
        state = .signedOut
    }
}
