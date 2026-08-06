# DEEPTUTORCHAT-000002 新建对话、日志接入与实现偏差修正工单

> 创建日期：2026-08-05  
> 所属模块：DeepTutorChat / iOS 本地对话  
> 工单状态：待修复  
> 关联文档：`DEEPTUTORCHAT-000001-iOS本地消息UI对齐DeepTutor-Web需求文档.md`  
> 处理边界：本工单只整理问题、修复方案、关键代码位置、验收标准；当前不直接改 Swift 代码实现。

---

## 1. 工单目标

当前 DeepTutorChat iOS 版本已经出现初步实现文件，但存在 3 类必须优先修正的问题：

1. 新建对话没有办法稳定创建并进入对话。
2. 日志不完善，关键流程不可观测，需要接入完整日志。
3. 当前实现与 DeepTutor Web 架构和前一版需求文档存在偏差，需要检查、补充、纠正。

本工单目标不是继续扩展新功能，而是先把 DeepTutorChat 的本地对话主链路打通：

```text
会话列表
  -> 新建对话
  -> 打开新对话
  -> 输入问题
  -> 本地写入用户消息
  -> 本地生成/追加助手消息
  -> UI 增量刷新
  -> 重启 App 后仍可恢复
  -> 全流程有日志可排查
```

---

## 2. 当前问题总览

| 编号 | 问题 | 当前表现 | 影响 | 优先级 |
| --- | --- | --- | --- | --- |
| P0-1 | 新建对话不可用 | 点击新增后没有稳定进入新会话，失败时无提示 | 主流程不可用 | P0 |
| P0-2 | 错误被吞掉 | 新建对话入口使用 `try?`，失败无 UI、无日志 | 无法定位认证、数据库、上下文问题 | P0 |
| P0-3 | 日志缺失 | ViewModel / Store / Reducer / 刷新流程缺少关键日志 | 问题不可观测，无法交付验收 | P0 |
| P1-1 | 实现状态与文档不一致 | 目录下已有实现，但未形成完整集成验收 | 需求、实现、测试容易错位 | P1 |
| P1-2 | 分支可见路径可能偏差 | iOS 只做浅层 parent-child 处理，未完整对齐 Web `buildVisiblePath` | 编辑分支、多版本消息展示可能错误 | P1 |
| P1-3 | 空态缺少强入口 | 空列表只提示，没有明显“创建并进入”动作 | 新用户路径不顺 | P1 |
| P1-4 | 打开不存在会话处理不足 | `openConversation` 加载不到会话时可能进入 ready 空状态 | UI 状态错误，排查困难 | P1 |

---

## 3. 关键代码位置

### 3.1 iOS 当前实现位置

```text
SparkClient/Projects/Features/DeepTutorChat/
├── Application/
│   ├── DeepTutorChatViewModel.swift
│   ├── DeepTutorMessageReducer.swift
│   ├── DeepTutorRefreshCoordinator.swift
│   ├── DeepTutorTraceFormatter.swift
│   ├── LoadDeepTutorMessagesUseCase.swift
│   └── SendLocalDeepTutorMessageUseCase.swift
├── Domain/
│   ├── DeepTutorBranchSelection.swift
│   ├── DeepTutorCapability.swift
│   ├── DeepTutorConversationState.swift
│   ├── DeepTutorMessage.swift
│   ├── DeepTutorMessageBlock.swift
│   └── DeepTutorStreamEvent.swift
├── Infrastructure/
│   ├── DeepTutorChatNotifications.swift
│   ├── DeepTutorLocalChatRepository.swift
│   ├── DeepTutorLocalChatStore.swift
│   └── DeepTutorMessageCodec.swift
└── Presentation/
    ├── DeepTutorChatPage.swift
    ├── DeepTutorComposerView.swift
    ├── DeepTutorConversationUpdateBuilder.swift
    ├── DeepTutorMessageListView.swift
    ├── DeepTutorMessageRowView.swift
    ├── Bubbles/
    ├── Cards/
    └── Rendering/
```

### 3.2 DeepTutor Web 对标位置

```text
DeepTutor-main/web/app/(workspace)/home/[[...sessionId]]/page.tsx
DeepTutor-main/web/components/chat/home/ChatMessages.tsx
DeepTutor-main/web/components/common/AssistantResponse.tsx
DeepTutor-main/web/components/common/MarkdownRenderer.tsx
DeepTutor-main/web/components/chat/home/TracePanels.tsx
DeepTutor-main/web/components/chat/home/AskUserOptions.tsx
DeepTutor-main/web/context/UnifiedChatContext.tsx
DeepTutor-main/web/lib/unified-ws.ts
DeepTutor-main/web/lib/message-branches.ts
DeepTutor-main/web/lib/chat-outline.ts
```

---

## 4. 问题一：新建对话没有办法创建对话

### 4.1 当前代码现象

位置：

```text
SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorChatPage.swift
```

当前列表页新增按钮逻辑类似：

```swift
Button {
    Task {
        if let created = try? await viewModel.createConversation() {
            // Navigation handled by list refresh; user can tap new row.
            _ = created
        }
    }
} label: {
    Image(systemName: "plus.bubble")
}
```

这里存在几个明显问题：

1. `try?` 会吞掉所有错误。
2. 创建失败时没有任何用户提示。
3. 创建失败时没有任何日志。
4. 创建成功后没有自动进入新对话。
5. 创建成功后只依赖列表刷新，再让用户手动点击新行。
6. 如果列表刷新失败、排序异常、空态未刷新，用户会感知为“没有创建成功”。
7. 空列表只显示提示文案，没有内嵌主按钮。

### 4.2 Store 层现象

位置：

```text
SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorLocalChatStore.swift
```

创建对话流程大致是：

```swift
func createConversation(title: String?) async throws -> DeepTutorConversation {
    guard let accountID = activeAccountID else {
        throw DeepTutorChatError.notAuthenticated
    }

    let conversation = DeepTutorConversation(...)

    try await kernel.writeWithoutNotification { context in
        let thread = ChatThreadEntity(context: context)
        thread.id = conversation.id
        thread.ownerAccountID = accountID
        thread.title = resolvedTitle
        thread.scenario = DeepTutorScenarioConstants.scenario
        thread.createdAt = now
        thread.updatedAt = now
        thread.isSoftDeleted = false
        thread.isActive = false
        ...
    }

    await postChange(.genericThreadsChanged)
    return conversation
}
```

需要关注：

1. 未登录或没有 `activeAccountID` 时直接抛错，但 UI 层吞掉错误。
2. `isActive = false` 不一定是 bug，但如果外部依赖 active thread，可能导致创建后不可见或不可进入。
3. 写库成功后虽然发送了 `genericThreadsChanged`，但 UI 没有强制导航到新会话。
4. Store 有 `logger` 字段，但创建流程没有记录开始、成功、失败、耗时。

### 4.3 根因判断

当前“新建对话没有办法创建对话”大概率不是单一数据库问题，而是 4 个点叠加：

```text
入口吞错
  + 成功后不导航
  + 空态缺少强创建入口
  + 日志缺失导致无法确认到底是创建失败还是创建后不可见
```

### 4.4 修复要求

#### 4.4.1 UI 入口要求

新增对话入口必须做到：

1. 点击新增按钮后进入创建中状态。
2. 创建中按钮不可重复点击。
3. 创建成功后自动进入新对话页面。
4. 创建失败后显示错误提示。
5. 创建失败必须写日志。
6. 空态必须提供“新建对话”主按钮。
7. 空态主按钮与右上角新增按钮使用同一套 ViewModel 方法。

推荐状态：

```swift
@Published private(set) var isCreatingConversation: Bool
@Published private(set) var conversationCreationError: String?
@Published var selectedConversationID: UUID?
```

如果项目已有全局 Router / NavigationPath，应优先接入现有路由，而不是在 DeepTutorChat 内私造导航系统。

#### 4.4.2 ViewModel 要求

`createConversation()` 不应该只返回 conversation，还需要支持“创建并打开”的主链路。

推荐新增语义方法：

```swift
@MainActor
func createAndOpenConversation() async
```

内部流程：

```text
log create_tap
set isCreatingConversation = true
clear creation error
try repository.createConversation
refresh conversations
set selectedConversationID / navigation target
openConversation(created.id)
log create_success
catch
  set creation error
  log create_failure
finally
  set isCreatingConversation = false
```

#### 4.4.3 Navigation 要求

创建成功后的交互必须是：

```text
用户点击 +
  -> 本地创建 ChatThreadEntity
  -> 列表刷新
  -> 自动打开 DeepTutorChatPage(conversationID: created.id)
  -> composer 聚焦或可输入
```

如果当前容器是 `NavigationSplitView`：

```text
selectedConversationID = created.id
```

如果当前容器是 `NavigationStack`：

```text
navigationPath.append(created.id)
```

如果 DeepTutorChat 是 tab 内页面：

```text
先更新 selectedConversationID
再让 detail 区域展示对应 ChatPage
```

#### 4.4.4 空态要求

当前空态：

```swift
ContentUnavailableView(
    "No DeepTutor chats",
    systemImage: "bubble.left.and.text.bubble.right",
    description: Text("Create a local DeepTutor conversation to get started.")
)
```

需要补充主操作按钮：

```text
标题：DeepTutor 对话
描述：创建一个本地对话，先对齐消息 UI、工具调用、思考过程与刷新流程。
按钮：新建对话
加载态：正在创建...
失败态：创建失败，显示可读错误
```

视觉要求：

1. 按钮必须是页面中最明显动作。
2. 空态不只展示说明，必须可直接完成创建。
3. 创建中要有轻量 loading，不要让用户重复点击。
4. 失败时不应该弹系统崩溃式提示，应使用 banner、toast 或 inline error。

### 4.5 验收标准

必须全部满足：

1. 首次进入 DeepTutorChat，会看到空态和“新建对话”按钮。
2. 点击空态按钮后，成功创建本地会话并自动进入对话页。
3. 点击右上角新增按钮，也成功创建并自动进入对话页。
4. 未登录或无 `activeAccountID` 时，页面显示“当前账号不可用，请重新登录后再试”一类提示。
5. 数据库写入失败时，页面显示失败提示，不吞错。
6. 创建成功后，返回列表能看到新对话。
7. 杀掉 App 重启后，新对话仍存在。
8. 创建流程日志中能看到开始、成功/失败、conversationID、耗时、错误分类。

---

## 5. 问题二：日志不完善，需要接入日志

### 5.1 当前日志缺口

当前 DeepTutorChat 已经有本地 Store 和 ViewModel，但日志不完整：

1. `DeepTutorChatViewModel` 没有明确 logger。
2. `DeepTutorLocalChatStore` 有 `logger` 字段，但多数业务节点没有使用。
3. 创建对话失败在 UI 层被 `try?` 吞掉。
4. 数据库通知刷新没有完整日志。
5. 消息发送、reducer、工具调用、思考过程、ask_user 提交等状态变化没有完整可观测链路。
6. 没有统一 request id / operation id，跨层排查困难。

### 5.2 日志接入目标

日志要覆盖 DeepTutorChat 本地版核心链路：

```text
Conversation List
  -> Load
  -> Create
  -> Open
  -> Send
  -> Reduce events
  -> Persist messages
  -> Notify database changes
  -> Refresh visible messages
  -> Render UI states
```

日志不是为了打印更多内容，而是为了能回答这些问题：

1. 用户点了新增吗？
2. ViewModel 收到了新增动作吗？
3. Store 是否写入成功？
4. 写入的是哪个账号、哪个 conversation？
5. 通知是否发出？
6. 列表是否刷新？
7. 页面是否导航到了新 conversation？
8. 失败发生在哪一层？
9. 消息发送是否写入了 user message？
10. assistant message 是否生成或追加？
11. trace / tool / thinking 是否被 reducer 正确转换？
12. UI 刷新是全量刷新还是增量刷新？

### 5.3 日志记录规则

本阶段是 DeepTutorChat iOS 本地实现排查期，日志目标以“完整复现问题、快速定位偏差”为主，不做对话内容脱敏。

需要完整记录：

1. 用户问题正文。
2. 助手回答正文。
3. thinking 原文。
4. 工具调用输入。
5. 工具调用输出。
6. ask_user 的选项选择和自由输入正文。
7. 附件、上下文引用、生成文件的关键路径或标识。
8. reducer 收到的原始 event payload。

仍不建议记录：

1. token、Authorization、Cookie、session key。
2. 明文密码、验证码、支付凭证。
3. 会导致账号被接管的长期有效密钥。

必须同时记录结构化字段，方便筛选：

1. `conversationID`。
2. `messageID`。
3. `role`。
4. `capability`。
5. `phase`。
6. `eventType`。
7. `messageCount`。
8. `durationMs`。
9. `errorType`。
10. `errorCode`。
11. `isStreaming`。
12. `hasAttachments`。
13. `blockCount`。

### 5.4 推荐日志字段

统一字段：

```text
module=DeepTutorChat
operationID=<UUID>
conversationID=<UUID?>
messageID=<UUID?>
phase=<state phase>
event=<event name>
result=<start|success|failure|skip>
durationMs=<Int?>
errorType=<String?>
errorCode=<String?>
count=<Int?>
```

示例：

```text
[DeepTutorChat] create_conversation start operationID=... account=available
[DeepTutorChat] create_conversation success operationID=... conversationID=... durationMs=18
[DeepTutorChat] create_conversation failure operationID=... errorType=notAuthenticated durationMs=3
```

### 5.5 必须补充的日志点

#### 5.5.1 会话列表

位置：

```text
Application/DeepTutorChatViewModel.swift
Infrastructure/DeepTutorLocalChatStore.swift
Presentation/DeepTutorChatPage.swift
```

日志点：

```text
conversation_list_load_start
conversation_list_load_success count durationMs
conversation_list_load_failure errorType durationMs
conversation_list_refresh_start source
conversation_list_refresh_success count durationMs
conversation_list_refresh_failure errorType durationMs
```

#### 5.5.2 新建对话

位置：

```text
Application/DeepTutorChatViewModel.swift
Infrastructure/DeepTutorLocalChatStore.swift
Presentation/DeepTutorChatPage.swift
```

日志点：

```text
conversation_create_tap source=toolbar|empty_state
conversation_create_start
conversation_create_auth_missing
conversation_create_store_write_start
conversation_create_store_write_success conversationID
conversation_create_notify_posted notificationName
conversation_create_refresh_start
conversation_create_open_start conversationID
conversation_create_open_success conversationID
conversation_create_success conversationID durationMs
conversation_create_failure errorType durationMs
```

#### 5.5.3 打开对话

位置：

```text
Application/DeepTutorChatViewModel.swift
Infrastructure/DeepTutorLocalChatStore.swift
```

日志点：

```text
conversation_open_start conversationID
conversation_open_load_thread_start
conversation_open_thread_not_found conversationID
conversation_open_load_messages_start pageSize
conversation_open_load_messages_success count
conversation_open_success conversationID messageCount durationMs
conversation_open_failure errorType durationMs
```

#### 5.5.4 发送消息

位置：

```text
Application/DeepTutorChatViewModel.swift
Application/SendLocalDeepTutorMessageUseCase.swift
Infrastructure/DeepTutorLocalChatStore.swift
Application/DeepTutorMessageReducer.swift
```

日志点：

```text
message_send_tap
message_send_skip_empty_draft
message_send_skip_no_active_conversation
message_send_start conversationID capability hasAttachments
message_user_persist_start
message_user_persist_success messageID
message_assistant_local_generate_start capability
message_reducer_apply_start eventCount
message_reducer_apply_success blockCount traceCount
message_assistant_persist_start
message_assistant_persist_success messageID
message_send_refresh_start
message_send_success conversationID durationMs
message_send_failure errorType durationMs
```

#### 5.5.5 工具调用、思考、trace

位置：

```text
Application/DeepTutorMessageReducer.swift
Application/DeepTutorTraceFormatter.swift
Presentation/Cards/DeepTutorTracePanelView.swift
Presentation/Rendering/DeepTutorThinkingCardView.swift
```

日志点：

```text
stream_event_reduce_start eventType
stream_event_reduce_unknown eventType
trace_item_decode_success type
trace_item_decode_failure type errorType
thinking_block_detected
thinking_block_rendered collapsedState
tool_call_detected toolName status
tool_call_rendered toolName status
tool_result_detected status
```

注意：本地调试阶段需要记录 thinking 原文、工具输入全文、工具输出全文，用于确认 reducer、trace formatter、UI 卡片展示是否与 DeepTutor Web 对齐。

#### 5.5.6 ask_user / 问题回答

位置：

```text
Presentation/Cards/DeepTutorAskUserCardView.swift
Application/DeepTutorChatViewModel.swift
Application/DeepTutorMessageReducer.swift
```

日志点：

```text
ask_user_card_rendered questionType optionCount allowFreeText
ask_user_option_selected optionIndex
ask_user_free_text_submit text
ask_user_submit_start conversationID parentMessageID
ask_user_submit_success conversationID durationMs
ask_user_submit_failure errorType durationMs
```

注意：本地调试阶段需要记录自由输入正文，便于复现 ask_user 卡片提交、状态刷新和回答回填问题。

#### 5.5.7 数据库通知与 UI 刷新

位置：

```text
Infrastructure/DeepTutorChatNotifications.swift
Application/DeepTutorChatViewModel.swift
Application/DeepTutorRefreshCoordinator.swift
```

日志点：

```text
database_change_received reason conversationID
database_change_ignored reason
database_change_refresh_list
database_change_refresh_messages conversationID
refresh_coordinator_schedule reason
refresh_coordinator_coalesce count
refresh_coordinator_apply_start
refresh_coordinator_apply_success messageCount durationMs
```

### 5.6 日志验收标准

必须全部满足：

1. 新建对话成功时，日志能串起 tap -> create -> store write -> notify -> refresh -> open -> success。
2. 新建对话失败时，日志能看到失败层级和错误类型。
3. 发送本地消息成功时，日志能看到 user message 和 assistant message 的持久化过程。
4. trace / tool / thinking 的解析失败不会静默失败。
5. ask_user 提交过程有日志，并能看到用户选择或自由输入正文。
6. 本地调试日志能看到完整用户问题、助手回答、thinking、工具输入输出，便于复现 UI 偏差。
7. 日志字段风格统一，便于后续筛选。

---

## 6. 问题三：检查实现偏差并补充纠正

### 6.1 当前状态偏差

前一份需求文档主要从 DeepTutor Web 架构向 iOS 落地做设计说明。当时重点是整理目标架构。当前工程中已经出现 DeepTutorChat 初步实现，因此需要把“目标设计”切换为“实现对照审计”。

当前风险：

1. `SparkClient/Projects/Features/DeepTutorChat/` 已有代码，但目前是未跟踪状态。
2. 需要确认这些文件是否已经加入 Xcode project / package target。
3. 需要确认入口是否已经挂到 App 导航。
4. 需要确认编译是否通过。
5. 需要确认 DeepTutorChat 是否复用了已有数据库流程，而不是孤立存储。
6. 需要确认 UI 是否真的对齐 DeepTutor Web 的消息链路，而不仅是有气泡外观。

### 6.2 Web 架构对齐基线

DeepTutor Web 消息链路：

```text
page.tsx
  -> UnifiedChatContext state.messages
  -> ChatMessageList
  -> UserMessage / AssistantMessage
  -> AssistantActivity
  -> AssistantResponse
  -> MarkdownRenderer
```

iOS 对齐链路应该是：

```text
DeepTutorChatPage
  -> DeepTutorChatViewModel.state
  -> DeepTutorMessageListView
  -> DeepTutorMessageRowView
  -> DeepTutorUserBubble / DeepTutorAssistantBubble
  -> DeepTutorTracePanelView
  -> DeepTutorAssistantResponseView
  -> DeepTutorMarkdownRenderer
```

如果某个环节缺失，需要明确标记为：

```text
已对齐 / 部分对齐 / 未对齐 / 暂不实现
```

### 6.3 必查偏差清单

#### 6.3.1 Xcode 集成偏差

检查项：

1. DeepTutorChat 文件是否加入 Xcode project。
2. DeepTutorChat 是否属于正确 target。
3. 是否存在只在文件系统中、没有编译进 App 的情况。
4. 是否已经有 App 入口导航到 `DeepTutorConversationListPage`。
5. 是否有 feature flag 控制入口。
6. 是否有预览或调试入口。

验收：

```text
Clean build 通过
App 内可以进入 DeepTutorChat 会话列表
空态可以创建对话
创建后可以进入对话详情
```

#### 6.3.2 数据库流程偏差

检查项：

1. 是否使用已有 `ChatThreadEntity`。
2. 是否使用已有 `ChatMessageEntity`。
3. 是否使用已有 `ChatMessageBlockEntity`。
4. 是否按账号隔离 `ownerAccountID`。
5. 是否按场景隔离 `scenario = deeptutor`。
6. 是否支持软删除。
7. 是否支持消息分页。
8. 是否支持 block/envelope 存储。
9. 是否支持数据库变更通知刷新。

当前已观察到：

```text
DeepTutorLocalChatStore 使用 ChatDatabaseKernel 和已有 CoreData 实体。
这是正确方向，但需要补齐日志、失败处理和集成验收。
```

验收：

```text
创建对话后 ChatThreadEntity 有对应记录
发送消息后 ChatMessageEntity 有 user / assistant 两类记录
消息 block 能恢复为 UI 内容
切换账号后不会看到其他账号 DeepTutor 对话
删除后列表不显示软删除会话
```

#### 6.3.3 新建对话流程偏差

Web 中创建/进入会话是强状态链路，不是“写入后让用户自己找”。

iOS 当前偏差：

```text
创建成功后没有强制打开 created conversation。
创建失败被 try? 吞掉。
空态没有主按钮。
```

纠正要求：

```text
createConversation
  -> refreshConversations
  -> select/open created conversation
  -> show ready chat page
```

#### 6.3.4 消息列表刷新偏差

Web 由 `UnifiedChatContext` 驱动 `state.messages`，流式事件和持久化结果都进入同一条状态链。

iOS 需要保证：

1. 本地写库后，UI 不依赖手动刷新。
2. 数据库通知能触发列表和消息刷新。
3. 当前会话消息更新只刷新当前会话。
4. 非当前会话消息更新只刷新列表预览。
5. 高频更新需要 coalesce，避免 SwiftUI 抖动。
6. streaming 状态下滚动跟随底部。
7. 用户手动上滑后不要强制抢滚动。

需要重点检查：

```text
DeepTutorRefreshCoordinator.swift
DeepTutorChatNotifications.swift
DeepTutorChatViewModel.handleDatabaseChange
DeepTutorMessageListView.swift
```

#### 6.3.5 分支消息偏差

Web 关键逻辑：

```text
web/lib/message-branches.ts
buildVisiblePath
```

iOS 当前需要检查：

```text
DeepTutorBranchSelection.swift
DeepTutorChatViewModel.applyBranchSelection
```

风险点：

1. 当前实现可能只处理一层 parent-child。
2. Web 分支路径需要沿 selectedBranches 递归选择可见链路。
3. 用户编辑消息后，后续 assistant 分支也要跟随对应路径。
4. sibling branch 切换后，列表应稳定重算，不出现旧消息混入。

纠正要求：

```text
使用 parentMessageId 构建 childrenByParent
从 root messages 开始递归选择 child
selectedBranches[parentID] 优先
无选择时使用默认最新或稳定排序第一条
最终返回完整 visible path
```

验收：

```text
用户消息 A 有 A1/A2 两个编辑分支
选择 A2 后，后续 assistant 只显示 A2 对应回答
切回 A1 后，消息列完整切换
不会同时显示两个 sibling 分支
```

#### 6.3.6 trace / thinking / tool call 偏差

Web 对标：

```text
AssistantActivity
TracePanels.tsx
ModelThinkingCard
AssistantResponse
```

iOS 需要检查：

```text
DeepTutorTracePanelView.swift
DeepTutorThinkingCardView.swift
DeepTutorTraceFormatter.swift
DeepTutorMessageReducer.swift
```

纠正要求：

1. trace 区域必须在助手正文前。
2. thinking 必须可折叠。
3. tool call 必须有状态：pending / running / success / failed。
4. 工具名称、状态、耗时、摘要展示要清楚。
5. 工具输入输出默认不展开长文本。
6. 错误状态不能只靠颜色，要有文字和图标。
7. streaming 时 trace 可以先出现，正文随后增量更新。

验收：

```text
有 thinking 时显示思考卡片
有 tool call 时显示工具调用卡片
工具成功/失败状态可区分
trace 在正文上方
折叠状态稳定，不因刷新丢失
```

#### 6.3.7 ask_user / 问题回答偏差

Web 对标：

```text
AskUserOptions.tsx
AssistantMessage 内 hasInlineAskUser 分支
```

iOS 需要检查：

```text
DeepTutorAskUserCardView.swift
DeepTutorChatViewModel.submitAskUser
```

纠正要求：

1. 支持单选问题。
2. 支持多选问题。
3. 支持自由输入。
4. 支持“选项 + 自由输入”组合。
5. 已提交后卡片进入 resolved 状态。
6. 提交中禁用重复点击。
7. 提交失败可重试。
8. 发送后消息列表刷新。

验收：

```text
点击选项后状态变为提交中
成功后卡片展示已回答
失败后保留可重试状态
自由输入不会被日志记录正文
```

#### 6.3.8 特殊能力卡片偏差

Web `AssistantMessage` 按 capability 分支：

```text
research outline
math animator
visualization
quiz
ask_user
default markdown
```

iOS 现有卡片需要逐项确认：

```text
DeepTutorResearchOutlineCardView.swift
DeepTutorQuizCardView.swift
DeepTutorVisualizationPlaceholderView.swift
DeepTutorGeneratedFileCardView.swift
DeepTutorAskUserCardView.swift
```

本期本地版最低要求：

1. 不一定实现真实动画播放。
2. 不一定实现真实可视化运行。
3. 但必须保留相同的 UI 语义和占位卡片。
4. 不允许把特殊能力全部降级成普通 markdown。

验收：

```text
quiz 数据渲染为 quiz 卡片
research outline 数据渲染为 outline 卡片
visualization 数据渲染为可视化占位卡片
generated files 渲染为文件卡片
未知 capability 回退为普通助手消息
```

#### 6.3.9 UI 视觉偏差

需要继续对齐 DeepTutor Web：

用户消息：

```text
右对齐
最大宽度约屏幕 75%
圆角 16-18
背景使用 secondary surface
正文 14-15pt
支持 capability badge
支持附件/上下文树
支持编辑、删除、分支切换操作
```

助手消息：

```text
左对齐或自然文章流
先 trace 后正文
正文 markdown
thinking 卡片可折叠
工具调用卡片在正文前
特殊能力卡片优先于普通 markdown
支持复制、重新生成、删除
```

消息列表：

```text
最大内容宽度需要有 iPad 上限
底部 composer 固定
键盘弹起不遮挡最后一条消息
streaming 时自动滚底
用户上滑查看历史时暂停强制滚底
```

---

## 7. 本工单推荐实施顺序

### 第一阶段：打通新建对话

优先级最高，只处理主链路：

1. 去掉 UI 层 `try?`。
2. 增加创建中状态。
3. 增加创建失败提示。
4. 创建成功后自动打开新对话。
5. 空态增加新建按钮。
6. 增加创建流程日志。
7. 验证本地数据库写入和重启恢复。

交付结果：

```text
用户能从空态创建第一个 DeepTutor 本地对话，并直接进入聊天页。
```

### 第二阶段：补齐日志

覆盖关键链路：

1. list load / refresh。
2. create / open。
3. send / ask_user。
4. reducer。
5. store write。
6. database notification。
7. refresh coordinator。

交付结果：

```text
任何 DeepTutorChat 主流程失败，都能通过日志定位到 UI / ViewModel / UseCase / Store / Database 中的具体层级。
```

### 第三阶段：实现偏差审计与纠正

按清单逐项核对：

1. Xcode 集成。
2. 数据库模型。
3. 消息刷新。
4. 分支路径。
5. trace/thinking/tool。
6. ask_user。
7. 特殊能力卡片。
8. 气泡视觉。

交付结果：

```text
形成“Web 对标项 -> iOS 当前状态 -> 修复结果 -> 验收证据”的对照表。
```

---

## 8. 建议拆分子任务

### 子任务 A：修复新建对话入口

范围：

```text
DeepTutorChatPage.swift
DeepTutorChatViewModel.swift
DeepTutorLocalChatStore.swift
```

任务：

1. 新增创建中状态。
2. 新增创建失败状态。
3. 创建成功后自动打开新会话。
4. 空态增加新建按钮。
5. 去掉 `try?` 吞错。

验收：

```text
空态 -> 点击新建 -> 进入新聊天页 -> 输入框可用
```

### 子任务 B：接入 DeepTutorChat 日志

范围：

```text
DeepTutorChatViewModel.swift
DeepTutorLocalChatStore.swift
DeepTutorMessageReducer.swift
DeepTutorRefreshCoordinator.swift
SendLocalDeepTutorMessageUseCase.swift
```

任务：

1. 注入或复用项目已有 Logger。
2. 增加统一日志事件名。
3. 增加 operationID。
4. 增加耗时统计。
5. 失败路径必须记录 errorType。

验收：

```text
创建、打开、发送、刷新、ask_user 均可从日志串起来。
```

### 子任务 C：检查 Xcode 集成

范围：

```text
SparkClient.xcodeproj/project.pbxproj
App Root / Feature Registry / Navigation
DeepTutorChat directory
```

任务：

1. 确认 DeepTutorChat 文件是否进 target。
2. 确认 App 内是否有入口。
3. 确认 clean build。
4. 确认预览或 debug route。

验收：

```text
真机或模拟器能进入 DeepTutorChat 页面。
```

### 子任务 D：分支消息可见路径纠正

范围：

```text
DeepTutorBranchSelection.swift
DeepTutorChatViewModel.applyBranchSelection
```

任务：

1. 对齐 Web `buildVisiblePath`。
2. 支持多层 parent-child。
3. 支持 sibling branch 切换。
4. 增加单元测试。

验收：

```text
编辑分支切换时，消息列表只显示选中路径。
```

### 子任务 E：trace / tool / thinking 展示审计

范围：

```text
DeepTutorTracePanelView.swift
DeepTutorThinkingCardView.swift
DeepTutorTraceFormatter.swift
DeepTutorMessageReducer.swift
```

任务：

1. trace 显示在正文前。
2. thinking 可折叠。
3. tool call 有状态。
4. reducer 不识别事件要降级展示。
5. 日志不记录敏感正文。

验收：

```text
工具调用、思考、正文展示顺序与 Web 对齐。
```

---

## 9. 验收用例

### 9.1 新建对话

```text
Given 当前账号已登录
And DeepTutorChat 列表为空
When 用户点击“新建对话”
Then 创建本地 ChatThreadEntity
And 自动进入新对话页面
And composer 可输入
And 日志记录 create_success
```

### 9.2 新建对话失败

```text
Given 当前没有 activeAccountID
When 用户点击“新建对话”
Then 页面显示创建失败提示
And 不进入空白聊天页
And 日志记录 create_failure errorType=notAuthenticated
```

### 9.3 对话恢复

```text
Given 已创建一个 DeepTutor 本地对话
When 用户杀掉 App 并重启
Then DeepTutorChat 列表展示该对话
And 点击后能打开历史消息
```

### 9.4 消息发送

```text
Given 用户位于 DeepTutorChat 对话页
When 输入“解释一下血糖波动”并发送
Then user bubble 立即出现
And assistant bubble 本地生成或占位出现
And 数据库有 user / assistant message
And 日志记录 send_success
```

### 9.5 日志完整性

```text
Given 用户发送一条问题
When 查看日志
Then 日志包含完整用户问题正文
And 日志包含助手回答正文
And 如存在 thinking / tool call / ask_user，日志包含对应原文或 payload
And 同时包含 conversationID、messageID、phase、durationMs 等结构化字段
```

### 9.6 分支切换

```text
Given 某条用户消息有两个编辑分支
When 用户切换到第二个分支
Then 消息列表只展示第二个分支路径上的后续消息
And 不展示第一个分支的 sibling 消息
```

### 9.7 trace 展示

```text
Given assistant message 包含 thinking 和 tool call event
When 消息渲染
Then thinking 卡片展示在正文前
And tool call 卡片展示状态
And markdown 正文展示在 trace 后
```

---

## 10. 完成定义

本工单完成必须满足：

1. 新建对话可用。
2. 创建成功后自动进入新对话。
3. 创建失败不再被吞掉。
4. 空态有明确创建入口。
5. DeepTutorChat 主流程日志完整。
6. 本地调试日志能记录用户正文、thinking 原文、工具输入输出全文和 ask_user 原始回答。
7. 已检查 Xcode target 和 App 导航入口。
8. 已检查本地数据库写入与恢复。
9. 已检查消息 UI 与 Web 的主要偏差。
10. 已为未完成偏差创建后续子工单或 TODO。

---

## 11. 后续建议

建议修复顺序：

1. 先修 P0 新建对话不可用。
2. 同步补上创建流程日志，避免继续盲修。
3. 再做完整日志矩阵。
4. 最后做 Web/iOS 实现偏差逐项纠正。

推荐下一张工单：

```text
DEEPTUTORCHAT-000003 DeepTutorChat 分支消息 visible path 与 Web buildVisiblePath 对齐
```
