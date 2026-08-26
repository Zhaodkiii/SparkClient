import Foundation

/// AI Runtime 调试开关（UserDefaults，仅 DEBUG 构建可读）。
nonisolated enum AIRuntimeDebugFlags {
    /// 为 `true` 时输出完整 AI 请求报文（脱敏后）。
    nonisolated static var verboseRequestLogs: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "airuntime.debug.verboseRequestLogs")
        #else
        false
        #endif
    }

    /// 为 `true` 时输出高频 stream partial 过程日志。
    nonisolated static var verboseStreamLogs: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "airuntime.debug.verboseStreamLogs")
        #else
        false
        #endif
    }
}