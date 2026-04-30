import SwiftUI

/// 聊天消息渲染上下文
/// 承载渲染消息块所需的所有数据、状态、回调，统一传递给各个 UI 组件
struct ChatRenderContext {
    // MARK: - 基础数据
    let message: ChatMessage                               // 当前要渲染的聊天消息本体
    let isLastAssistantMessage: Bool                       // 是否是最后一条助手消息（用于控制样式/展开逻辑）
    let isMathMode: Bool                                   // 是否为数学公式模式（渲染等宽文本）
    
    // MARK: - 加载/保存状态 ID 集合
    let taskCardLoadingIDs: Set<Int>                       // 正在加载中的任务卡片 ID 集合
    let savingKnowledgeCardIDs: Set<UUID>                  // 正在保存中的知识库卡片 ID
    let savedKnowledgeCardIDs: Set<UUID>                   // 已保存的知识库卡片 ID
    let savingStructuredHealthCardIDs: Set<UUID>           // 正在保存的结构化健康卡片 ID
    
    // MARK: - 全局依赖
    let memberContextStore: MemberContextStore             // 成员上下文数据仓库
    let unifiedFilePreview: Binding<FilePreviewInput?>     // 统一文件预览（双向绑定）
    
    // MARK: - 展示文本
    let errorCardBodyText: String                          // 错误卡片默认提示文本
    
    // MARK: - 用户操作回调（事件响应）
    let onRetry: () -> Void                                // 重试按钮点击（发送失败时）
    let onSaveKnowledgeCard: (ChatKnowledgeCard) -> Void   // 保存知识库卡片
    let onTaskCardAction: (TaskCard.Action) -> Void        // 任务卡片操作（完成/删除等）
    let onPendingMemberToolSelect: (PendingMemberToolCard, Int?) -> Void  // 待处理成员工具选择
    let onStructuredHealthCardAction: (ChatStructuredHealthCardAction) -> Void  // 健康卡片操作
    let onCaptureOpenCamera: () -> Void                    // 打开相机
    let onCaptureOpenPhotoLibrary: () -> Void              // 打开相册
    let onCaptureOpenFiles: () -> Void                    // 打开文件
    /// 展示工具详情全局 Sheet（由消息行注入，传入预览载荷与当前渲染上下文）。
    let onPresentToolPreview: (ToolPreviewPrompt, ChatRenderContext) -> Void

    // MARK: - 异步文件操作
    let onCachedChatAttachmentLocalURL: (ChatAttachment) async -> URL?  // 获取附件缓存本地地址
    let onDownloadChatAttachmentToLocalFile: (ChatAttachment) async throws -> URL  // 下载附件到本地
}

extension ChatRenderContext {
    /// 用最新消息替换上下文（回调与 UI 状态保持不变），供工具详情 Sheet 等场景使用。
    func replacingMessage(_ message: ChatMessage) -> ChatRenderContext {
        ChatRenderContext(
            message: message,
            isLastAssistantMessage: isLastAssistantMessage,
            isMathMode: isMathMode,
            taskCardLoadingIDs: taskCardLoadingIDs,
            savingKnowledgeCardIDs: savingKnowledgeCardIDs,
            savedKnowledgeCardIDs: savedKnowledgeCardIDs,
            savingStructuredHealthCardIDs: savingStructuredHealthCardIDs,
            memberContextStore: memberContextStore,
            unifiedFilePreview: unifiedFilePreview,
            errorCardBodyText: errorCardBodyText,
            onRetry: onRetry,
            onSaveKnowledgeCard: onSaveKnowledgeCard,
            onTaskCardAction: onTaskCardAction,
            onPendingMemberToolSelect: onPendingMemberToolSelect,
            onStructuredHealthCardAction: onStructuredHealthCardAction,
            onCaptureOpenCamera: onCaptureOpenCamera,
            onCaptureOpenPhotoLibrary: onCaptureOpenPhotoLibrary,
            onCaptureOpenFiles: onCaptureOpenFiles,
            onPresentToolPreview: onPresentToolPreview,
            onCachedChatAttachmentLocalURL: onCachedChatAttachmentLocalURL,
            onDownloadChatAttachmentToLocalFile: onDownloadChatAttachmentToLocalFile
        )
    }
}
