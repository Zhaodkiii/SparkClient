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

    /// 为 `true` 时输出 reload / load / open / database_change 等刷新链路过程日志。
    nonisolated static var verboseChatRefreshLogs: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "deeptutor.debug.verboseChatRefreshLogs")
        #else
        false
        #endif
    }

    /// 为 `true` 时输出 diffable apply、render transaction、cell configure、publish gate 等渲染过程日志。
    nonisolated static var verboseChatRenderLogs: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "deeptutor.debug.verboseChatRenderLogs")
        #else
        false
        #endif
    }

    /// 为 `true` 时输出 stream reasoning coalesce / commit 等流式过程日志。
    nonisolated static var verboseChatStreamLogs: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "deeptutor.debug.verboseChatStreamLogs")
        #else
        false
        #endif
    }

    /// 为 `true` 时输出 capability selected / effective 等能力判定过程日志。
    nonisolated static var verboseCapabilityLogs: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "deeptutor.debug.verboseCapabilityLogs")
        #else
        false
        #endif
    }

    /// 为 `true` 时输出 capability snapshot 快照过程日志。
    nonisolated static var verboseCapabilitySnapshots: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "deeptutor.debug.verboseCapabilitySnapshots")
        #else
        false
        #endif
    }

    /// 为 `true` 时输出完整 AI 流式网关请求报文（脱敏后）。
    nonisolated static var verboseAIRuntimeRequestLogs: Bool {
        AIRuntimeDebugFlags.verboseRequestLogs
    }

    /// 为 `true` 时输出高频 stream partial 过程日志。
    nonisolated static var verboseAIRuntimeStreamLogs: Bool {
        AIRuntimeDebugFlags.verboseStreamLogs
    }

    /// 为 `true` 时输出 quiz 题型解析 resolved / fallback 过程日志。
    nonisolated static var verboseQuizParseLogs: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "deeptutor.debug.verboseQuizParseLogs")
        #else
        false
        #endif
    }

    /// 为 `true` 时输出每次会话列表刷新（含无变化跳过摘要）。
    nonisolated static var verboseConversationListRefreshLogs: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "deeptutor.debug.verboseConversationListRefreshLogs")
        #else
        false
        #endif
    }
}
