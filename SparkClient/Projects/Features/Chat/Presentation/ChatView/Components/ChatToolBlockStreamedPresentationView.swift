import SwiftUI

/// 流式回复工具块展示控制视图
/// 功能：确保工具执行态（加载中状态）首次出现后**至少展示 2 秒**，再切换到结果视图，避免状态闪烁、一闪而过
struct ChatToolBlockStreamedPresentationView: View {
    /// 工具执行态（加载中）最少展示时长：2 秒
    private static let minimumOperationalDisplay: TimeInterval = 2

    /// 对应聊天消息中的 `.tool` 块（含 `toolCallID` 等）
    let toolBlock: ChatMessageBlock
    /// 消息渲染上下文（包含消息状态、样式等信息）
    let context: ChatRenderContext
    /// 工具块数据负载（工具名称、内容等）
    let tool: ChatToolBlockPayload
    /// 是否需要展示结果（而非执行态）
    let wantsResult: Bool
    
    /// 视图首次挂载时间（用于计算最少展示时长）
    @State private var mountTime: Date?
    /// 是否允许展示结果视图
    @State private var allowResult = false
    /// 延迟展示结果的异步任务（用于控制 2 秒倒计时）
    @State private var revealTask: Task<Void, Never>?

    /// 是否处于流式加载状态（消息正在发送/接收中）
    private var isStreaming: Bool { context.message.deliveryState == .sending }

    var body: some View {
        Group {
            // 条件：需要展示结果 + (非流式 或 已满足最小展示时间) → 展示工具结果内容
            if wantsResult, !isStreaming || allowResult {
                ChatToolContentBlockView(
                    toolName: ChatToolRuntimeAttachmentBuilder.localizedDisplayName(for: tool.name),
                    toolContent: tool.content,
                    isStreaming: isStreaming,
                    onOpenDetail: {
                        guard let prompt = context.message.makeToolPreviewPrompt(forToolBlock: toolBlock) else { return }
                        context.onPresentToolPreview(prompt, context)
                    }
                )
            }
            // 否则 → 展示工具执行/加载中状态
            else {
                let invocationArguments = tool.invocationArguments
                let content: String = {
                    guard let invocationArguments, invocationArguments.isEmpty == false else { return "" }
                    return ToolPreviewPrompt.displayText(for: invocationArguments)
                }()
                // 构建工具执行状态元数据（状态标题 + 描述）
                let operational = ChatToolRuntimeAttachmentBuilder.makeOperationalMeta(
                    toolName: tool.name,
                    toolContent: content
                ) ?? (
                    state: ChatToolRuntimeAttachmentBuilder.localizedDisplayName(for: tool.name),
                    description: content
                )
                // 展示执行状态 UI
                ChatOperationalStatusBlockView(
                    operationalState: operational.state,
                    operationalDescription: operational.description
                )
            }
        }
        // 视图出现时：记录首次挂载时间
        .onAppear {
            if mountTime == nil {
                mountTime = Date()
            }
        }
        // 监听是否需要展示结果变化 → 重新调度倒计时
        .onChange(of: wantsResult) { _ in
            scheduleRevealIfNeeded()
        }
        // 监听流式状态变化
        .onChange(of: isStreaming) { newValue in
            // 流式结束 → 立即取消倒计时，直接展示结果
            if newValue == false {
                revealTask?.cancel()
                revealTask = nil
                allowResult = true
            }
            // 流式开始 → 调度倒计时
            else {
                scheduleRevealIfNeeded()
            }
        }
        // 视图消失 → 清理任务，防止内存泄漏
        .onDisappear {
            revealTask?.cancel()
            revealTask = nil
        }
    }

    /// 是否应该展示结果（内部逻辑封装）
    /// 流式：必须等 2 秒倒计时结束；非流式：直接根据 wantsResult 展示
    private var shouldShowResult: Bool {
        if isStreaming {
            return allowResult
        }
        return wantsResult
    }

    /// 根据条件调度「延迟展示结果」任务（核心逻辑）
    /// 保证流式回复中执行态至少展示 2 秒
    private func scheduleRevealIfNeeded() {
        // 先取消之前的任务，避免重复倒计时
        revealTask?.cancel()
        revealTask = nil
        
        // 不需要展示结果 → 直接隐藏结果
        guard wantsResult else {
            allowResult = false
            return
        }
        
        // 非流式加载 → 立即展示结果
        if isStreaming == false {
            allowResult = true
            return
        }
        
        // 获取视图挂载时间（锚点时间）
        let anchor = mountTime ?? Date()
        if mountTime == nil {
            mountTime = anchor
        }
        
        // 计算已过时间 & 剩余需要等待的时间
        let elapsed = Date().timeIntervalSince(anchor)
        let remaining = max(0, Self.minimumOperationalDisplay - elapsed)
        
        // 开启倒计时任务，时间到后允许展示结果
        revealTask = Task { @MainActor in
            if remaining > 0 {
                // 等待剩余时间（单位：纳秒）
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
            // 任务未取消才更新状态
            guard !Task.isCancelled else { return }
            allowResult = true
        }
    }
}
