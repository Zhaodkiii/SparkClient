import SwiftUI

/// 流式回复中，工具执行态（`ChatOperationalStatusBlockView`）自该块首次出现起至少展示 2 秒，再切到结果区，避免状态一闪而过。
struct ChatToolBlockStreamedPresentationView: View {
    private static let minimumOperationalDisplay: TimeInterval = 2

    let context: ChatRenderContext
    let tool: ChatToolBlockPayload
    let wantsResult: Bool
    
    @State private var mountTime: Date?
    @State private var allowResult = false
    @State private var revealTask: Task<Void, Never>?

    private var isStreaming: Bool { context.message.deliveryState == .sending }

    var body: some View {
        Group {
            if wantsResult, !isStreaming || allowResult {
                ChatToolContentBlockView(
                    toolName: ChatToolRuntimeAttachmentBuilder.localizedDisplayName(for: tool.name),
                    toolContent: tool.content,
                    isStreaming: isStreaming
                )
            } else {
                let operational = ChatToolRuntimeAttachmentBuilder.makeOperationalMeta(
                    toolName: tool.name,
                    toolContent: tool.content
                ) ?? (
                    state: ChatToolRuntimeAttachmentBuilder.localizedDisplayName(for: tool.name),
                    description: tool.content
                )
                ChatOperationalStatusBlockView(
                    operationalState: operational.state,
                    operationalDescription: operational.description
                )
            }
        }
         .onAppear {
            if mountTime == nil {
                mountTime = Date()
            }
        }
        .onChange(of: wantsResult) { _ in
            scheduleRevealIfNeeded()
        }
        .onChange(of: isStreaming) { newValue in
            if newValue == false {
                revealTask?.cancel()
                revealTask = nil
                allowResult = true
            } else {
                scheduleRevealIfNeeded()
            }
        }
        .onDisappear {
            revealTask?.cancel()
            revealTask = nil
        }
    }

    /// 流式中：执行态至少展示 2 秒后再切结果；非流式：遵循 `wantsResult` 直接展示结果。
    private var shouldShowResult: Bool {
        if isStreaming {
            return allowResult
        }
        return wantsResult
    }

    private func scheduleRevealIfNeeded() {
        revealTask?.cancel()
        revealTask = nil
        guard wantsResult else {
            allowResult = false
            return
        }
        if isStreaming == false {
            allowResult = true
            return
        }
         let anchor = mountTime ?? Date()
        if mountTime == nil {
            mountTime = anchor
        }
        let elapsed = Date().timeIntervalSince(anchor)
        let remaining = max(0, Self.minimumOperationalDisplay - elapsed)
        revealTask = Task { @MainActor in
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            allowResult = true
        }
    }
}
