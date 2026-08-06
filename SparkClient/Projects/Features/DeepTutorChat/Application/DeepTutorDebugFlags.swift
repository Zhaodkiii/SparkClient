import Foundation

/// DeepTutor 调试开关。默认走真实 AI 链路。
nonisolated enum DeepTutorDebugFlags {
    /// 为 `true` 时主发送链路降级为本地 `DeepTutorLocalReplySimulator`。
    nonisolated static var useLocalSimulator: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "deeptutor.debug.useLocalSimulator")
        #else
        false
        #endif
    }
}
