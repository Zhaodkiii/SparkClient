# CHAT-000011 SwiftUI 会话架构与 DeepTutor 刷新体验对齐工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | CHAT-000011 |
| 工单类型 | P1 UI 架构切换 / SwiftUI 消息列表 / 会话刷新体验 / 设置配置 |
| 当前范围 | 创建需求工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标模块 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat` |
| 目标设置模块 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/AISettings` |
| 可参考本地实现 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| 可参考 Web 项目 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main` |
| 创建日期 | 2026-08-10 |
| 触发问题 | 当前 Chat 会话主体仍以 UIKit `UICollectionView` 消息列表为主，样式扩展、局部刷新、状态表达和 DeepTutor 风格体验对齐成本较高；用户希望新增一套 SwiftUI 会话 UI，并可在设置内切换 UIKit / SwiftUI 两套架构 |
| 核心目标 | 在 Chat 内新增完全独立的 SwiftUI 会话渲染架构，参考 DeepTutorChat 和 DeepTutor-main 的视觉与刷新体验，但不复用 DeepTutorChat 类型、View、Palette、Reducer 或 Web 代码；设置内可切换 UIKit / SwiftUI 会话 UI |

## 1. 背景

当前 Chat 会话 UI 主链路位于：

```text
SparkClient/Projects/Features/Chat/Presentation/ChatView.swift
SparkClient/Projects/Features/Chat/Presentation/ConversationList/ConversationMessageListViewController.swift
SparkClient/Projects/Features/Chat/Presentation/ConversationList/ConversationMessageListRepresentable.swift
SparkClient/Projects/Features/Chat/Presentation/ConversationList/ChatConversationMessageRow.swift
SparkClient/Projects/Features/Chat/Presentation/ChatView/Components/ChatMessageBubbleContentView.swift
```

现状特征：

1. 消息列表由 UIKit `UICollectionView` 承载，SwiftUI 行视图通过 `UIHostingConfiguration` 嵌入。
2. 这套架构在长列表、Diffable 快照和已有滚动控制上比较稳定，但样式切换、消息级局部刷新和 SwiftUI 原生交互扩展不够直接。
3. DeepTutorChat 已有一套更接近 Web 的 SwiftUI 消息体验，包括 trace / 正文分层、刷新协调器、状态收口、会话加载反馈等，可以作为产品体验参考。
4. DeepTutor-main Web 侧的 `ChatMessages.tsx`、`TracePanels.tsx`、`SessionLoadingView.tsx`、`SessionViewerPanel.tsx` 体现了“会话加载明确反馈、工具过程聚合、正文优先、可取消/可恢复”的交互方向。

本工单要求在 Chat 内新增一套 SwiftUI 会话 UI，并允许用户在设置内切换：

```text
Chat 会话 UI 架构
  - UIKit 经典架构
  - SwiftUI 新架构
```

## 2. 强边界

本工单最重要的约束是：Chat 与 DeepTutorChat 两套完全独立。

### 2.1 禁止复用 DeepTutorChat 实现

Chat SwiftUI 新架构禁止依赖以下 DeepTutorChat 类型或文件：

```text
DeepTutorMessage
DeepTutorMessageBlock
DeepTutorMessageRowModel
DeepTutorMessageListView
DeepTutorMessageRowView
DeepTutorAssistantBubble
DeepTutorUserBubble
DeepTutorTracePanelView
DeepTutorPalette
DeepTutorMarkdownRenderer
DeepTutorRefreshCoordinator
DeepTutorConversationUpdateBuilder
DeepTutorMessageReducer
DeepTutorTraceFormatter
DeepTutorToolInteractionCoordinator
```

允许参考的只有：

1. 视觉层级：正文优先、工具过程上置、轻量卡片、柔和分隔线。
2. 交互语义：加载中明确反馈、刷新期间不闪屏、流式时保持底部锁定、最终回答后工具过程可折叠。
3. 命名灵感：可以学习“RefreshCoordinator / UpdateBuilder / RowModel”的分层，但必须使用 `ChatSwiftUI...` 前缀另起类型。

### 2.2 禁止把 DeepTutor-main Web 代码迁入 iOS

DeepTutor-main 仅作为体验参考，不作为代码依赖：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ChatMessages.tsx
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/TracePanels.tsx
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/SessionLoadingView.tsx
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/SessionViewerPanel.tsx
```

不得引入 Web 文件、Tailwind class、React 状态结构或 TypeScript 类型。

## 3. 目标

### 3.1 产品目标

1. Chat 会话支持两套 UI 架构：UIKit 经典架构、SwiftUI 新架构。
2. 用户可在设置内切换架构，切换后重新进入 Chat 会话即可生效。
3. SwiftUI 新架构提供一套新的消息卡片设计样式，可参考 DeepTutorChat 的正文优先视觉，但必须属于 Chat 自己。
4. 会话打开、下拉刷新、加载历史、流式回复、重试、删除、复制、语音、翻译、保存知识卡片等核心能力保持可用。
5. SwiftUI 新架构需要学习 DeepTutor 的刷新体验：加载有反馈、刷新不闪屏、底部锁定可靠、用户滚动时不抢滚动位置。

### 3.2 技术目标

1. 在 Chat 目录下创建独立 SwiftUI 会话渲染子目录。
2. 新增 Chat 专属 SwiftUI 消息列表、消息行、气泡、刷新协调器和滚动锚点策略。
3. 复用 Chat 现有 Domain / Application / ViewModel / StateStore，不新增第二套业务数据源。
4. UIKit 与 SwiftUI 两套 UI 只在 `ChatView` 或更上层的架构选择点分流。
5. 设置偏好进入 `AISettingsSnapshot.PreferencesPayload`，不能只放临时 `@State`。

## 4. 建议目录

建议新增：

```text
SparkClient/Projects/Features/Chat/Presentation/SwiftUIConversation/
  ChatSwiftUIConversationView.swift
  ChatSwiftUIMessageListView.swift
  ChatSwiftUIMessageRowView.swift
  ChatSwiftUIAssistantBubble.swift
  ChatSwiftUIUserBubble.swift
  ChatSwiftUIMessageBubbleContentView.swift
  ChatSwiftUIToolTracePanelView.swift
  ChatSwiftUIRefreshCoordinator.swift
  ChatSwiftUIConversationUpdateBuilder.swift
  ChatSwiftUIScrollAnchorPolicy.swift
  ChatSwiftUIStreamEventBuffer.swift
  ChatSwiftUIStreamReducer.swift
  ChatSwiftUIFrameScheduler.swift
  ChatSwiftUIPalette.swift
  ChatSwiftUIRenderContext.swift
```

命名要求：

1. 新类型统一使用 `ChatSwiftUI` 前缀。
2. 不使用 `DeepTutor` 前缀。
3. 不把 UIKit 旧实现重命名为通用实现。
4. UIKit 旧链路保留在 `ConversationList/`，SwiftUI 新链路放入 `SwiftUIConversation/`。

## 5. 设置项设计

### 5.1 新增设置模型

建议在 `AISettingsDomainModels.swift` 新增：

```swift
nonisolated enum ChatConversationUIArchitecture: String, Codable, CaseIterable, Sendable {
    case uiKit
    case swiftUI
}

nonisolated struct ChatConversationUIPreferences: Codable, Equatable, Sendable {
    var architecture: ChatConversationUIArchitecture
    var swiftUIRefreshBehavior: ChatSwiftUIRefreshBehavior
}
```

如果当前工程已存在 `chatConversationAppearance`，本工单不得覆盖它；应新增更明确的架构字段，例如：

```text
chatConversationUIPreferences
```

或在既有 Chat 外观偏好中追加 `uiArchitecture`，但必须保持向后兼容默认值。

### 5.2 设置页入口

在 `AISettingsView` 内增加 Chat 会话 UI 架构配置：

```text
Chat 会话 UI
  架构：UIKit / SwiftUI
  SwiftUI 刷新策略：稳定优先 / 跟随底部 / 手动优先

Chat 对话外观
  对话卡片样式：标准 / 正文优先
  工具调用展示：默认展开 / 完成后折叠 / 始终折叠
  流式过程也折叠：开 / 关
```

默认值：

| 字段 | 默认值 | 说明 |
| --- | --- | --- |
| 架构 | UIKit | 保持线上体验稳定 |
| SwiftUI 刷新策略 | 稳定优先 | 用户滚动时不抢位置 |
| 对话卡片样式 | 标准 | UIKit 与 SwiftUI 共用，避免同一视觉项出现两处配置 |

### 5.3 切换生效策略

1. 设置修改立即持久化。
2. 已打开的 Chat 页面可以提示“重新进入会话后生效”，也可以由 `ChatView` 根据 `AISettingsViewModel.snapshot` 动态切换。
3. 如果选择动态切换，必须清理滚动状态、输入焦点和临时菜单状态，避免两个列表同时持有滚动控制。

## 6. SwiftUI 会话架构要求

### 6.1 架构分流

`ChatView` 中增加单一分流点：

```text
if aiSettingsViewModel.snapshot.chatConversationUIPreferences.architecture == .swiftUI {
    ChatSwiftUIConversationView(...)
} else {
    ChatConversationMessageListContainer(...)
}
```

要求：

1. UIKit 旧链路不删除。
2. SwiftUI 新链路不绕过 `ChatDetailViewModel`。
3. 两套链路共享同一份 `visibleMessages`、`ChatStateStore`、`ChatMessageUIStateStore`、`ChatSpeechHelper`、`MemberContextStore`。
4. 业务 action 仍从 Chat 现有 ViewModel / UseCase 发出，不在 SwiftUI Row 内直接访问数据库或 Runtime。

### 6.2 SwiftUI 消息列表

推荐使用：

```text
ScrollViewReader
ScrollView
LazyVStack
```

核心能力：

1. 首次进入会话时滚到底部。
2. 流式回复时，如果用户仍在底部附近，持续保持底部锁定。
3. 用户向上滚动后，不再抢滚动。
4. 加载历史消息时，保留顶部锚点，不让视口跳动。
5. 消息删除、重试、翻译、保存等状态更新时，只刷新对应行。
6. 键盘弹出 / 收起时，底部锚点策略与 UIKit 旧实现保持一致。

### 6.3 刷新体验学习 DeepTutor

参考 DeepTutorChat 本地文件：

```text
SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorRefreshCoordinator.swift
SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorMessageListView.swift
SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorConversationUpdateBuilder.swift
```

参考 DeepTutor-main Web 文件：

```text
web/components/chat/home/SessionLoadingView.tsx
web/components/chat/home/ChatMessages.tsx
web/components/chat/home/TracePanels.tsx
```

Chat SwiftUI 新架构应实现自己的：

```text
ChatSwiftUIRefreshCoordinator
ChatSwiftUIConversationUpdateBuilder
ChatSwiftUIScrollAnchorPolicy
```

刷新行为要求：

1. 会话加载阶段显示明确 loading，而不是空白或欢迎页闪现。
2. 加载超过 8 秒显示“仍在加载”类提示，参考 DeepTutor-main 的慢加载提示语义。
3. 下拉刷新期间保留当前视口，刷新完成后只在必要时更新行。
4. 进入流式回复时，如果用户在底部，自动跟随最新 token。
5. 如果用户主动滚动到历史位置，流式更新不抢回底部。
6. 重试或重新生成消息时，应将相关消息定位到可见区，不触发全列表跳动。

### 6.4 DeepTutor-main 字节流 / 流式事件 UI 刷新架构学习

DeepTutor-main 的对话流式体验不是让 UI 直接消费“裸字节”，而是把网络字节解码为可排序、可重放、可恢复的流式事件，再由前端 reducer 合成消息与 trace UI。

关键参考文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/core/stream.py
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/api/routers/unified_ws.py
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/services/session/turn_runtime.py
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/lib/unified-ws.ts
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/lib/stream.ts
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/context/UnifiedChatContext.tsx
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/hooks/useChatAutoScroll.ts
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/lib/turn-reconcile.ts
```

#### 6.4.1 DeepTutor-main 的事件协议事实

后端 `StreamEvent` 的核心字段：

```text
type
source
stage
content
metadata
session_id
turn_id
seq
timestamp
```

WebSocket 客户端支持的事件类型包括：

```text
stage_start
stage_end
thinking
observation
content
tool_call
tool_result
progress
sources
result
error
session
session_meta
done
```

对 Chat SwiftUI 新架构的要求：

1. 不能只把服务端 token 当成一串字符串追加到 Text。
2. 必须有 Chat 专属的流式事件缓冲层，至少保存 `turnID`、`seq`、`type`、`content`、`metadata`、本地接收时间。
3. UI 刷新不能直接由网络回调逐字节触发；网络层先进入 buffer / reducer，再由 SwiftUI 主线程节流发布可见状态。
4. 同一个 `turnID + seq` 的事件必须去重，避免重连续流后重复追加正文。

#### 6.4.2 DeepTutor-main 的续流与重连模型

Web 侧 `UnifiedWSClient` 有以下稳定机制：

1. 心跳：30 秒发送 ping，45 秒未收到消息判定连接失活。
2. 自动重连：指数退避，最多 5 次。
3. 续流：保存 `activeTurnId` 与 `lastSeq`，重连后发送：

```text
resume_from(turn_id, seq)
```

4. 后端支持：

```text
subscribe_turn(turn_id, after_seq)
subscribe_session(session_id, after_seq)
resume_from(turn_id, seq)
```

对 Chat SwiftUI 新架构的要求：

1. 如果当前 Chat Runtime 已有等价 `turnID / seq / event` 语义，SwiftUI 层必须直接消费该语义，不再发明 UI-only token 序号。
2. 如果当前 Chat Runtime 只有 block 增量，没有显式 seq，则 SwiftUI 层需要在 `ChatSwiftUIStreamEventBuffer` 内生成本地单调序号，用于 UI 去重、合批和滚动判断。
3. 网络断开或 App 前后台切换后，SwiftUI UI 层不应清空正在显示的 assistant 气泡；应保持最后已收到的正文和工具 trace，并显示轻量连接状态。
4. 重连后收到历史事件，要按 `seq` 合并，不能把同一段 content 再追加一次。

#### 6.4.3 DeepTutor-main 的 reducer 合成模型

Web `UnifiedChatContext` 的核心策略：

1. 发送后先创建乐观 user 行和空 assistant 行。
2. 每个 `STREAM_EVENT` 到达时：
   - 找到当前 session。
   - 如果最后一条不是 assistant，则补一个 assistant 占位行。
   - 对 `turn_id + seq` 去重。
   - 将事件 append 到 assistant 的 `events`。
   - 对可作为最终回答的 `content` 事件追加到 assistant `content`。
3. 遇到 narration marker 时，重新从 events 计算回答正文，把“工具调用前导语 / 旁白”从最终正文移回 trace。
4. 遇到 `done` 时：
   - 停止 streaming。
   - 用 `done.metadata.user_message_id / assistant_message_id` 将乐观 id 替换成持久化 id。
   - 不重新拉取整段会话，避免长对话 O(n) 刷新卡顿。

对 Chat SwiftUI 新架构的要求：

1. 新增 `ChatSwiftUIStreamReducer`，输入 Chat 现有流式 block / runtime event，输出 `ChatSwiftUIMessageRowState`。
2. reducer 必须支持乐观 assistant 占位：发送后立即显示空助手气泡或“正在思考”态。
3. reducer 必须区分：
   - 用户最终可读正文。
   - 工具调用前导语 / narration。
   - thinking / reasoning。
   - tool call。
   - tool result。
   - terminal error。
   - done。
4. 如果 Chat 现有 `MessageRunActor` 已经把流式内容落成 `ChatMessageBlock`，SwiftUI reducer 仍需要在 UI 层生成“可见行状态”，避免每个 block 微小变化导致整条列表重算。
5. `done` 后不得强制全量 reload 会话；应优先做 targeted reconciliation。只有缺少必要持久化 id 或本地状态不可信时才触发整会话 reload。

#### 6.4.4 narration / finish marker 的 UI 语义

DeepTutor-main 的 `web/lib/stream.ts` 明确区分：

```text
llm_final_response / agent_loop_round -> 可进入回答正文
call_role = narration                -> 前导语，归入 trace，不留在最终正文
call_role = finish                   -> Chat 单循环进入最终回答阶段
```

`TracePanels.tsx` 依赖 finish marker 判断最终回答阶段，用于自动折叠 trace：

```text
streaming + 未 finish -> trace 可展开 / 活跃
streaming + finish    -> 进入最终回答阶段
done                  -> 最终状态
```

对 Chat SwiftUI 新架构的要求：

1. 工具调用过程中的说明性文字不能和最终回答正文混在一起。
2. 如果 Chat 现有事件没有 `call_role`，需要在 `ChatSwiftUIStreamReducer` 内按现有 `ChatMessageBlockNodeRole`、`ChatMessageBlockKind.deepThought`、`.tool`、`.text` 建立等价归类。
3. `ChatSwiftUIToolTracePanelView` 应在“工具执行 / 推理中”展开，在进入最终回答阶段或 turn done 后按设置折叠。
4. 用户手动展开 / 折叠后，该选择要 pin 在当前消息上，不被后续 token 刷新覆盖。

#### 6.4.5 UI 发布节奏：字节流不能逐字刷新 SwiftUI

DeepTutor-main Web 侧为避免流式卡顿，做了两层控制：

1. 文本层：`AssistantResponse` / markdown streaming 会平滑消费内容，避免上游 token 抖动直接变成 UI 抖动。
2. 滚动层：`useChatAutoScroll` 只在自动跟随状态下写 `scrollTop`，并用 layout effect / MutationObserver / 短窗口跟随处理动态内容高度变化。

对 SwiftUI 的要求：

1. 新增 `ChatSwiftUIFrameScheduler` 或等价合批器。
2. 网络事件可以高频进入 buffer，但发布给 SwiftUI View 的 `@Published` / `@State` 更新需要按帧合批。
3. 建议策略：

```text
正文 token 合批：最多 30-60 fps 发布
工具事件：按事件立即入 buffer，但 UI 可同帧合并
done / error / ask_user：立即发布
滚动 pin：只由一个策略对象写入，不允许多个 onChange 同时 scrollTo
```

4. SwiftUI 新架构不能对每个 token 执行全量 `visibleMessages.map`、全量 Markdown 重新分段、全量滚动定位。
5. 动态高度内容（图片、文件卡片、Markdown 代码块、结构化健康卡片）完成布局后，如果用户仍在底部锁定状态，需要短窗口继续跟随到底部。

#### 6.4.6 Auto-scroll 的 DeepTutor-main 经验

`useChatAutoScroll.ts` 的关键经验：

1. 自动跟随只在用户位于底部附近时开启。
2. 用户一旦上滑超过阈值，释放自动跟随。
3. 流式中只保留一个 scroll writer，避免 throttle、rAF、smooth scroll、系统 scroll anchoring 互相打架。
4. 流式结束后保留短窗口，继续跟随 late-mount 的动态组件高度变化。

对 Chat SwiftUI 新架构的要求：

1. `ChatSwiftUIScrollAnchorPolicy` 是唯一允许触发 `scrollToBottom` 的策略对象。
2. 任何消息行内部 view 不得私自滚动列表。
3. 用户离底部超过阈值后释放底部锁定。
4. 用户回到底部附近后重新启用底部锁定。
5. turn done 后保留约 3-4 秒 post-stream follow window，用于图片、附件、结构化卡片延迟完成布局后的底部跟随。

#### 6.4.7 对 Chat 当前 SwiftUI 工单的新增组件要求

新增建议文件：

```text
ChatSwiftUIStreamEventBuffer.swift
ChatSwiftUIStreamReducer.swift
ChatSwiftUIFrameScheduler.swift
ChatSwiftUIStreamingMessageState.swift
ChatSwiftUIStreamingEvent.swift
```

职责建议：

| 类型 | 职责 |
| --- | --- |
| `ChatSwiftUIStreamingEvent` | Chat UI 层事件，抹平 block 增量、tool event、done/error |
| `ChatSwiftUIStreamEventBuffer` | 按 `turnID + seq/localSeq` 去重、排序、保存最近活动 turn |
| `ChatSwiftUIStreamReducer` | 把事件合成为 assistant row 可见状态、trace 状态、正文状态 |
| `ChatSwiftUIFrameScheduler` | 合批高频 token，控制 SwiftUI 发布频率 |
| `ChatSwiftUIStreamingMessageState` | 单条 assistant 消息的流式 UI 状态，避免全列表重算 |

## 7. Chat 统一卡片样式要求

### 7.1 视觉方向

Chat 卡片样式由 `ChatConversationAppearancePreferences.cardStyle` 统一控制，UIKit 与 SwiftUI 两套会话架构都读取同一个字段，禁止再新增 SwiftUI 专属卡片样式开关。

```text
标准卡片
  - 保留当前 Chat 的助手 / 用户气泡层级
  - 更适合稳态使用

正文优先
  - 助手正文弱化外框
  - 工具过程在正文上方独立折叠
  - Markdown 正文宽松排版
  - 卡片和结构化结果使用轻边框
```

可参考 DeepTutorChat 的视觉事实：

```text
DeepTutorPalette.bubbleCornerRadius = 18
DeepTutorPalette.cardCornerRadius = 16
DeepTutorPalette.bodyFontSize = 14
DeepTutorPalette.traceBodyFontSize = 11
```

但 Chat 必须在 `ChatSwiftUIPalette` 内重新定义自己的常量，不能直接读 `DeepTutorPalette`。

### 7.2 工具过程与正文关系

SwiftUI 新架构应继续尊重 Chat 的 block / timeline 语义：

```text
ChatMessageBlock
ChatMessageBlockNodeRole.tool
ChatMessageBlockNodeRole.toolPresentation
ChatMessageBlockKind.deepThought
ChatMessageBlockKind.text
```

推荐结构：

```text
ChatSwiftUIToolTracePanelView
  - deepThought
  - tool
  - toolPresentation

正文区
  - text
  - translatedText
  - disclaimer

结构化卡片区
  - taskCards
  - knowledgeCards
  - healthCards
  - captureCard
  - nutritionCards
  - healthResourceReference
```

工具区与正文区可以同属一条 assistant 消息，但视觉上要分层。

## 8. 功能保持清单

SwiftUI 新架构必须覆盖现有 Chat 常用能力：

| 能力 | 要求 |
| --- | --- |
| 发送消息 | 保持当前 composer 与 send use case |
| 流式回复 | token 更新不闪屏、不全列表重绘 |
| 下拉加载历史 | 保留视口锚点 |
| 重试失败消息 | 沿用 `retryLatestConversationFailure` / `retryFailedMessage` |
| 复制 | 与 UIKit 旧链路一致 |
| 删除 | 与 `uiStateStore.markDeleted` 一致 |
| 文本选择 | 继续支持选择正文 |
| 语音朗读 | 继续使用 `ChatSpeechHelper` |
| 翻译 | 继续使用当前翻译状态 |
| 保存到知识库 | 继续使用当前保存状态 |
| 工具详情预览 | 继续使用 `ToolInteractionCoordinator` / `ToolInteractionPresentationSheet` |
| 问报告健康资料引用 | 不丢失 health resource 入口 |
| 图片/文件附件 | 用户消息和助手生成附件均可见 |
| 键盘收起 | 拖动列表可收键盘 |

## 9. 不做的事

1. 不删除 UIKit 经典会话架构。
2. 不把 DeepTutorChat 的 SwiftUI View 抽成 Chat 共用组件。
3. 不把 DeepTutor-main Web 代码迁入 iOS。
4. 不重写 Chat 业务层、数据库层、Runtime 层。
5. 不改变 ChatMessage / ChatThread 的持久化 schema，除非确认为 UI 架构切换必须。
6. 不把 SwiftUI 新架构设为默认，默认仍为 UIKit，直到验收通过后另开工单切默认。

## 10. 建议实施步骤

### 阶段一：设置与分流

1. 新增 `ChatConversationUIArchitecture` 与 `ChatConversationUIPreferences`。
2. 接入 `AISettingsSnapshot` 与 `PreferencesPayload`。
3. `AISettingsView` 增加 UIKit / SwiftUI 切换入口。
4. `ChatView` 增加架构分流点。

### 阶段二：SwiftUI 列表骨架

1. 新建 `Presentation/SwiftUIConversation/`。
2. 实现 `ChatSwiftUIConversationView`。
3. 实现 `ChatSwiftUIMessageListView`，先支持消息展示、滚到底部、加载中态。
4. 复用现有 `ChatMessageBubbleContentView` 的行为语义，逐步迁到 SwiftUI 专属渲染组件。

### 阶段三：流式事件缓冲与字节流刷新模型

1. 实现 `ChatSwiftUIStreamingEvent`，把 Chat 现有 block 增量、tool event、done/error 映射为 UI 层事件。
2. 实现 `ChatSwiftUIStreamEventBuffer`，按 `turnID + seq/localSeq` 去重、排序、保存最近活跃 turn。
3. 实现 `ChatSwiftUIStreamReducer`，把事件合成为单条 assistant row 状态。
4. 实现 `ChatSwiftUIFrameScheduler`，高频 token 按帧合批发布给 SwiftUI。
5. 实现 done 后 targeted reconciliation，避免为了拿持久化状态全量 reload 会话。
6. 增加断线 / 前后台切换后保持已接收内容的 UI 状态。

### 阶段四：统一卡片样式

1. 实现 `ChatSwiftUIPalette`。
2. 实现 `ChatSwiftUIAssistantBubble` / `ChatSwiftUIUserBubble`。
3. 实现 `ChatSwiftUIToolTracePanelView`。
4. SwiftUI 读取 `ChatConversationAppearancePreferences.cardStyle`，与 UIKit 共用标准、正文优先两种样式。

### 阶段五：刷新与滚动体验

1. 实现 `ChatSwiftUIRefreshCoordinator`。
2. 实现顶部锚点保留。
3. 实现底部锁定策略。
4. 实现慢加载提示。
5. 对齐键盘弹出 / 收起时的列表位置。
6. 实现 post-stream 3-4 秒短窗口跟随动态高度变化。
7. 确保只有 `ChatSwiftUIScrollAnchorPolicy` 触发滚动。

### 阶段六：能力补齐与验收

1. 补齐复制、删除、选择文本、语音、翻译、保存知识库、工具详情预览。
2. 补齐附件、健康资料引用、结构化卡片展示。
3. 添加架构选择与滚动策略测试。
4. 通过 `xcodebuild`。

## 11. 验收标准

### 11.1 设置验收

1. 设置内可以看到 `Chat 会话 UI` 配置。
2. 可以在 UIKit / SwiftUI 之间切换。
3. 配置重启 App 后仍保持。
4. 默认仍为 UIKit。

### 11.2 架构边界验收

1. `SparkClient/Projects/Features/Chat` 内新增 `SwiftUIConversation` 目录。
2. `SwiftUIConversation` 内所有新类型以 `ChatSwiftUI` 开头。
3. `SparkClient/Projects/Features/Chat` 内不得引用 `DeepTutorMessage`、`DeepTutorTracePanelView`、`DeepTutorPalette`、`DeepTutorMarkdownRenderer`。
4. `SparkClient/Projects/Features/DeepTutorChat` 不需要为本工单改动。

建议增加脚本或测试：

```bash
rg "DeepTutor(Message|TracePanelView|Palette|MarkdownRenderer)" SparkClient/Projects/Features/Chat
```

结果应为空。

### 11.3 UI 行为验收

1. UIKit 模式下现有 Chat 行为不回退。
2. SwiftUI 模式下可正常打开会话、发送消息、接收流式回复。
3. 会话打开时不出现欢迎页闪现。
4. 慢加载超过 8 秒出现持续加载提示。
5. 用户在底部时流式回复自动跟随。
6. 用户上滑查看历史时流式回复不抢滚动。
7. 下拉加载历史后当前视口不跳。
8. 工具过程与正文分层清楚。
9. 新卡片样式在深色 / 浅色模式均可读。

### 11.4 流式刷新验收

1. 高频 token 流式输出时，SwiftUI 消息列表不出现肉眼可见卡顿、跳帧、反复整行闪烁。
2. 同一 `turnID + seq/localSeq` 的事件重复到达时，正文不会重复追加。
3. 工具调用前导语 / narration 不残留在最终正文中，应归入工具 / trace 区。
4. 进入最终回答阶段后，工具 trace 可按设置自动折叠；用户手动展开状态不会被后续 token 覆盖。
5. `done` 后不强制全量 reload 当前会话；优先原地 reconcile 当前 turn 的持久化状态。
6. 断线或 App 切到后台后，已显示的流式正文和工具 trace 不消失。
7. 如果恢复连接后收到历史事件，按序合并，不重复、不乱序。
8. terminal error 事件显示为可重试错误卡片，不把错误文本拼进最终正文。

### 11.5 构建验收

1. `xcodebuild -project SparkClient.xcodeproj -scheme SparkClient -configuration Debug -destination 'generic/platform=iOS Simulator' build` 通过。
2. 不新增 Swift 并发隔离 error。
3. 不新增 DeepTutorChat 与 Chat 的交叉依赖。

## 12. 风险与注意事项

| 风险 | 说明 | 规避 |
| --- | --- | --- |
| SwiftUI 长列表性能 | `LazyVStack` 在复杂消息卡片中可能有测量抖动 | 首期保留 UIKit 默认；SwiftUI 模式先灰度 |
| 滚动锚点不稳定 | 历史加载和流式更新同时发生容易跳动 | 独立实现 `ChatSwiftUIScrollAnchorPolicy` |
| 状态重复持有 | UIKit 和 SwiftUI 同时持有菜单/滚动状态会冲突 | `ChatView` 单点分流，只挂载一套列表 |
| DeepTutor 代码被误复用 | 两套业务语义不同 | grep / 测试阻断 DeepTutor 类型引用 |
| 设置迁移 | 新字段缺默认值会导致旧偏好解码失败 | `decodeIfPresent ?? .default` |
| 高频 token 刷新卡顿 | 网络事件直接驱动 SwiftUI 会导致频繁重算 | `ChatSwiftUIFrameScheduler` 合批发布 |
| 续流重复追加 | 重连后历史事件回放可能重复 | `ChatSwiftUIStreamEventBuffer` 按 `turnID + seq/localSeq` 去重 |
| done 后全量刷新冻结 | 长会话重新拉取会造成 O(n) 重绘 | 学习 DeepTutor-main，优先 targeted reconciliation |
| trace 与正文归属错误 | 工具旁白混入最终正文 | reducer 明确区分 narration / final content / tool result |

## 13. 交付文件清单

预期新增：

```text
SparkClient/Projects/Features/Chat/Presentation/SwiftUIConversation/ChatSwiftUIConversationView.swift
SparkClient/Projects/Features/Chat/Presentation/SwiftUIConversation/ChatSwiftUIMessageListView.swift
SparkClient/Projects/Features/Chat/Presentation/SwiftUIConversation/ChatSwiftUIMessageRowView.swift
SparkClient/Projects/Features/Chat/Presentation/SwiftUIConversation/ChatSwiftUIAssistantBubble.swift
SparkClient/Projects/Features/Chat/Presentation/SwiftUIConversation/ChatSwiftUIUserBubble.swift
SparkClient/Projects/Features/Chat/Presentation/SwiftUIConversation/ChatSwiftUIToolTracePanelView.swift
SparkClient/Projects/Features/Chat/Presentation/SwiftUIConversation/ChatSwiftUIRefreshCoordinator.swift
SparkClient/Projects/Features/Chat/Presentation/SwiftUIConversation/ChatSwiftUIScrollAnchorPolicy.swift
SparkClient/Projects/Features/Chat/Presentation/SwiftUIConversation/ChatSwiftUIStreamingEvent.swift
SparkClient/Projects/Features/Chat/Presentation/SwiftUIConversation/ChatSwiftUIStreamEventBuffer.swift
SparkClient/Projects/Features/Chat/Presentation/SwiftUIConversation/ChatSwiftUIStreamReducer.swift
SparkClient/Projects/Features/Chat/Presentation/SwiftUIConversation/ChatSwiftUIFrameScheduler.swift
SparkClient/Projects/Features/Chat/Presentation/SwiftUIConversation/ChatSwiftUIStreamingMessageState.swift
SparkClient/Projects/Features/Chat/Presentation/SwiftUIConversation/ChatSwiftUIPalette.swift
```

预期修改：

```text
SparkClient/Projects/Features/AISettings/Domain/AISettingsDomainModels.swift
SparkClient/Projects/Features/AISettings/Domain/AISettingsSnapshot.swift
SparkClient/Projects/Features/AISettings/Presentation/Root/AISettingsView.swift
SparkClient/Projects/Features/Chat/Presentation/ChatView.swift
```

## 14. 备注

本工单是 Chat 会话 UI 架构升级工单，不是 DeepTutorChat 迁移工单。

DeepTutorChat 和 DeepTutor-main 只提供“体验答案”：

```text
加载要明确
刷新要稳定
工具过程要聚合
正文要优先
用户滚动时不要抢位置
```

Chat 的实现必须使用 Chat 自己的数据模型、渲染上下文、设置字段和 SwiftUI 类型独立完成。

## 15. 落地详细设计

本节给出开发可直接拆任务的实现细节。目标是在不改写 Chat 业务流的前提下，新增一套 SwiftUI 会话 UI 架构。

### 15.1 当前 Chat 真实链路

当前 Chat 流式与列表刷新链路：

```text
SendChatMessageUseCase / ChatOrchestrator
  -> MessageRunActor
  -> ChatRepository.upsertMessageBlock / updateMessageDeliveryState
  -> Core Data notification: .sparkChatDatabaseDidChange
  -> ChatDetailViewModel.loadMessagesIfNeeded / load changed messages
  -> ChatStateStore.messagesByThread
  -> ChatView.visibleMessages
  -> ConversationMessageListRepresentable
  -> ConversationMessageListViewController.apply(...)
  -> ConversationUpdateBuilder.plan(...)
  -> Diffable reloadItems / prepend / append
```

`MessageRunActor` 已经有关键稳定机制：

1. `assistantPartial` 进入 `pendingPartials`。
2. 文本 partial 默认约 50ms flush 一次。
3. 工具、reasoning、结构化卡片按稳定 block id upsert。
4. `finalizeAssistantBlocks` 后统一把 assistant delivery state 从 `.sending` 转到 `.pending`。

因此 SwiftUI 新架构不应重写发送、Runtime、数据库或同步逻辑，而应新增 UI 层投影：

```text
ChatMessage[] -> ChatSwiftUIConversationFrame -> ChatSwiftUIMessageRowState[]
```

### 15.2 分流点落地

在 `ChatView.messageList` 或 `ChatConversationMessageListContainer` 上方做单点分流。

建议最终结构：

```swift
@ViewBuilder
private var messageList: some View {
    switch aiSettingsViewModel.snapshot.chatConversationUIPreferences.architecture {
    case .uiKit:
        ChatConversationMessageListContainer(
            threadID: threadID,
            stateStore: stateStore,
            detailViewModel: detailViewModel,
            uiStateStore: uiStateStore,
            speechHelper: speechHelper,
            memberContextStore: homeViewModel.memberContextStoreForBinding,
            taskManager: taskManager,
            logger: logger,
            actionStateHandle: actionStateHandle,
            conversationAppearance: aiSettingsViewModel.snapshot.chatConversationAppearance,
            visibleMessages: visibleMessages,
            hasMoreMessages: hasMoreMessages,
            isLoadingMoreMessages: isLoadingMoreMessages,
            lockBottomViewport: stateStore.isBottomViewportLocked(for: threadID),
            scrollToBottomRequestGeneration: stateStore.scrollToBottomRequestGeneration(for: threadID),
            showCaptureFileImporter: $showCaptureFileImporter
        )
    case .swiftUI:
        ChatSwiftUIConversationView(
            threadID: threadID,
            visibleMessages: visibleMessages,
            hasMoreMessages: hasMoreMessages,
            isLoadingMoreMessages: isLoadingMoreMessages,
            lockBottomViewport: stateStore.isBottomViewportLocked(for: threadID),
            scrollToBottomRequestGeneration: stateStore.scrollToBottomRequestGeneration(for: threadID),
            preferences: aiSettingsViewModel.snapshot.chatConversationUIPreferences,
            conversationAppearance: aiSettingsViewModel.snapshot.chatConversationAppearance,
            dependencies: ChatSwiftUIConversationDependencies(...)
        )
    }
}
```

要求：

1. 同一时间只挂载一套列表。
2. `composerChrome` 不复制，继续由 `ChatView` 统一管理。
3. `ToolInteractionPresentationSheet`、参数面板、附件 file importer 等仍由 `ChatView` 统一挂载。
4. SwiftUI 新列表只负责消息区域，不接管全屏导航和输入栏。

### 15.3 设置模型落地

建议新增独立字段，避免污染已有 `chatConversationAppearance`：

```swift
nonisolated enum ChatConversationUIArchitecture: String, Codable, CaseIterable, Sendable {
    case uiKit
    case swiftUI

    var displayName: String {
        switch self {
        case .uiKit: return "UIKit 经典"
        case .swiftUI: return "SwiftUI 新架构"
        }
    }
}

nonisolated enum ChatSwiftUIRefreshBehavior: String, Codable, CaseIterable, Sendable {
    case stable
    case followBottom
    case manualFirst
}

nonisolated struct ChatConversationUIPreferences: Codable, Equatable, Sendable {
    var architecture: ChatConversationUIArchitecture
    var swiftUIRefreshBehavior: ChatSwiftUIRefreshBehavior

    static let `default` = ChatConversationUIPreferences(
        architecture: .uiKit,
        swiftUIRefreshBehavior: .stable
    )
}
```

持久化要求：

1. `AISettingsSnapshot` 顶层新增 `chatConversationUIPreferences`。
2. `PreferencesPayload` 新增同名字段。
3. decode 使用：

```swift
chatConversationUIPreferences = try container.decodeIfPresent(
    ChatConversationUIPreferences.self,
    forKey: .key("chatConversationUIPreferences")
) ?? .default
```

4. 设置页新增 Picker，默认 UIKit。

### 15.4 SwiftUIConversation 目录最小可交付版本

第一版建议只放这些文件，不一口气铺太大：

```text
ChatSwiftUIConversationView.swift
ChatSwiftUIConversationDependencies.swift
ChatSwiftUIConversationFrame.swift
ChatSwiftUIConversationFrameBuilder.swift
ChatSwiftUIMessageListView.swift
ChatSwiftUIMessageRowView.swift
ChatSwiftUIAssistantBubble.swift
ChatSwiftUIUserBubble.swift
ChatSwiftUIRenderContext.swift
ChatSwiftUIStreamEventBuffer.swift
ChatSwiftUIStreamReducer.swift
ChatSwiftUIFrameScheduler.swift
ChatSwiftUIScrollAnchorPolicy.swift
ChatSwiftUIPalette.swift
```

第一版可暂时复用现有 block render 逻辑：

```text
ChatSwiftUIAssistantBubble
  -> ChatSwiftUIMessageBubbleContentView
      -> ChatMessageBlock.render(context: ChatRenderContext)
```

但 SwiftUI 新架构自己的 trace / card chrome / row state 必须独立，不能直接套 UIKit 行。

### 15.5 依赖注入结构

避免 `ChatSwiftUIMessageRowView` 参数爆炸，新增依赖容器：

```swift
@MainActor
struct ChatSwiftUIConversationDependencies {
    let stateStore: ChatStateStore
    let detailViewModel: ChatDetailViewModel
    let uiStateStore: ChatMessageUIStateStore
    let speechHelper: ChatSpeechHelper
    let memberContextStore: MemberContextStore
    let taskManager: TaskManager
    let logger: Logger
    let actionStateHandle: ChatMessageActionStateHandle
    let fileTransferService: FileTransferService
    let medicalQueryAPI: SparkMedicalQueryAPI
    let cachedMemberCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    let onCaptureOpenFiles: () -> Void
    let onHeightChangingUpdate: (@escaping () -> Void) -> Void
}
```

注意：

1. 依赖容器只在 Chat SwiftUI 目录内部使用。
2. 不放 DeepTutorChat 依赖。
3. 不把业务 use case 注入 Row，Row 只触发 ViewModel 已有方法。

### 15.6 ConversationFrame 设计

新增一层 frame，隔离 `ChatMessage` 变化与 SwiftUI List 渲染：

```swift
struct ChatSwiftUIConversationFrame: Equatable, Sendable {
    var threadID: UUID
    var rows: [ChatSwiftUIMessageRowState]
    var hasMoreMessages: Bool
    var isLoadingMoreMessages: Bool
    var lockBottomViewport: Bool
    var scrollToBottomRequestGeneration: UInt64
    var generation: UInt64
}

struct ChatSwiftUIMessageRowState: Identifiable, Equatable, Sendable {
    var id: UUID
    var message: ChatMessage
    var role: ChatMessageRole
    var renderSignature: ChatSwiftUIMessageRenderSignature
    var isStreaming: Bool
    var isLastAssistant: Bool
}

struct ChatSwiftUIMessageRenderSignature: Equatable, Sendable {
    var messageRevision: Int
    var blockCount: Int
    var blockRevisionSum: Int64
    var deliveryState: ChatDeliveryState
    var uiFlagsHash: Int
}
```

`ChatSwiftUIConversationFrameBuilder` 职责：

1. 接收 `visibleMessages`。
2. 过滤已删除消息。
3. 标记最后一条 assistant。
4. 为每条消息生成 render signature。
5. 只在 signature 改变时触发行刷新。

### 15.7 流式事件投影落地

当前 Chat 没有 DeepTutor-main 那套 `StreamEvent seq` 暴露给 UI，真实流式已被 `MessageRunActor` 持久化为 block 更新。因此 SwiftUI 新架构第一版应使用“block revision 事件化”：

```swift
struct ChatSwiftUIStreamingEvent: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case textDelta
        case reasoning
        case toolCall
        case toolPresentation
        case richBlock
        case terminalError
        case done
    }

    var id: String
    var threadID: UUID
    var messageID: UUID
    var localSeq: UInt64
    var kind: Kind
    var blockID: UUID?
    var blockRevision: Int64
    var content: String
    var receivedAt: Date
}
```

`id` 建议：

```text
messageID:blockID:blockRevision:kind
```

如果 block 没有 revision，则使用 frame builder 的本地自增 `localSeq`。

### 15.8 StreamEventBuffer 落地

```swift
@MainActor
final class ChatSwiftUIStreamEventBuffer: ObservableObject {
    private var seenEventIDs: Set<String> = []
    private var eventsByMessageID: [UUID: [ChatSwiftUIStreamingEvent]] = [:]
    private var nextLocalSeq: UInt64 = 1

    func ingest(messages: [ChatMessage]) -> [UUID] {
        // 返回发生变化的 message ids
    }

    func events(for messageID: UUID) -> [ChatSwiftUIStreamingEvent] {
        eventsByMessageID[messageID] ?? []
    }

    func reset(threadID: UUID) {
        seenEventIDs.removeAll()
        eventsByMessageID.removeAll()
        nextLocalSeq = 1
    }
}
```

`ingest(messages:)` 细则：

1. 遍历 visibleMessages。
2. 遍历 message.blocks。
3. 按 `block.kind / block.nodeRole / block.status / block.revision` 映射 `ChatSwiftUIStreamingEvent.Kind`。
4. 生成 event id。
5. 去重后加入 buffer。
6. 返回 changed message ids，供 frame scheduler 决定发布哪些 row。

### 15.9 StreamReducer 落地

```swift
struct ChatSwiftUIStreamingMessageState: Equatable, Sendable {
    var messageID: UUID
    var answerText: String
    var reasoningText: String
    var toolTraceItems: [ChatSwiftUIToolTraceItem]
    var richBlocks: [ChatMessageBlock]
    var terminalErrorText: String?
    var isStreaming: Bool
    var isFinalAnswerPhase: Bool
}

enum ChatSwiftUIStreamReducer {
    static func reduce(
        message: ChatMessage,
        events: [ChatSwiftUIStreamingEvent]
    ) -> ChatSwiftUIStreamingMessageState
}
```

归类规则：

| Chat block 事实 | SwiftUI UI 状态 |
| --- | --- |
| `kind == .text` | `answerText` |
| `kind == .deepThought` | `reasoningText` / trace |
| `nodeRole == .tool` | `toolTraceItems` |
| `nodeRole == .toolPresentation` | 对应 tool trace 子结果或 rich block |
| `deliveryState == .failed` | `terminalErrorText` |
| `deliveryState == .sending` | `isStreaming = true` |
| `text` 已出现或 delivery 非 sending | `isFinalAnswerPhase = true` |

第一版不要重新解释所有业务卡片；先保持 ChatMessageBlock 原渲染，并把“工具/思考/正文/错误”的主结构分清。

### 15.10 FrameScheduler 落地

SwiftUI 发布策略：

```swift
@MainActor
final class ChatSwiftUIFrameScheduler: ObservableObject {
    @Published private(set) var frame: ChatSwiftUIConversationFrame

    private var pendingFrame: ChatSwiftUIConversationFrame?
    private var scheduled = false

    func submit(_ frame: ChatSwiftUIConversationFrame, priority: ChatSwiftUIFramePriority) {
        switch priority {
        case .immediate:
            self.frame = frame
            pendingFrame = nil
            scheduled = false
        case .nextFrame:
            pendingFrame = frame
            scheduleIfNeeded()
        }
    }
}

enum ChatSwiftUIFramePriority {
    case immediate   // done, error, thread switch, user send
    case nextFrame   // token/block revision update
}
```

调度细则：

1. thread 切换、done、terminal error、用户发送：立即发布。
2. `.sending` 中 `.text` 或 `.deepThought` 高频变化：同帧合批。
3. 建议使用 `Task { @MainActor in try? await Task.sleep(nanoseconds: 16_000_000) }` 或 `CADisplayLink` 包装。
4. 不允许每个 block revision 都触发 ScrollView 全量重新定位。

### 15.11 SwiftUI 列表落地

推荐结构：

```swift
struct ChatSwiftUIMessageListView: View {
    let frame: ChatSwiftUIConversationFrame
    let dependencies: ChatSwiftUIConversationDependencies
    @StateObject private var scrollPolicy = ChatSwiftUIScrollAnchorPolicy()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: ChatSwiftUIPalette.rowSpacing) {
                    if frame.hasMoreMessages {
                        ChatSwiftUILoadMoreRow(...)
                    }
                    ForEach(frame.rows) { row in
                        ChatSwiftUIMessageRowView(...)
                            .id(row.id)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(ChatSwiftUIScrollAnchorPolicy.bottomAnchorID)
                }
            }
            .coordinateSpace(name: ChatSwiftUIScrollAnchorPolicy.coordinateSpaceName)
            .onChange(of: frame.generation) { _, _ in
                scrollPolicy.handleFrame(frame, proxy: proxy)
            }
        }
    }
}
```

限制：

1. 不使用 SwiftUI `List`，避免默认 inset、cell reuse 行为和滚动控制不可预期。
2. 使用 `ScrollView + LazyVStack`。
3. 每行 id 使用 `message.clientMessageID`，不要使用数组 index。
4. 顶部加载更多行使用固定 UUID 或固定 anchor id。

### 15.12 ScrollAnchorPolicy 落地

状态：

```swift
@MainActor
final class ChatSwiftUIScrollAnchorPolicy: ObservableObject {
    static let bottomAnchorID = "chat-swiftui-bottom-anchor"
    static let coordinateSpaceName = "chat-swiftui-scroll"

    private var userPinnedToBottom = true
    private var postStreamFollowUntil: Date?
    private var lastScrollToBottomGeneration: UInt64 = 0
    private var activeTopAnchor: ChatSwiftUITopAnchor?
}
```

行为：

1. 首次进入会话：滚到底。
2. `scrollToBottomRequestGeneration` 增加：强制滚到底。
3. `lockBottomViewport == true` 且用户未上滑：保持底部。
4. 用户上滑超过阈值：释放底部锁定。
5. 加载历史 prepend：捕获顶部 anchor，插入后恢复。
6. turn done 后：开启 `postStreamFollowUntil = now + 4s`。
7. post-stream 期间如果仍 pinned，则动态高度变化后继续滚到底。

SwiftUI 难点：

1. `ScrollViewReader.scrollTo` 不能精确恢复 offset；顶部 prepend 第一版可先恢复到原 top item，第二版再用 PreferenceKey 记录 offset 差值。
2. 如果精确锚点做不到，必须在工单实施记录里标为已知限制，不能假装等价 UIKit。

### 15.13 Row 操作落地

`ChatSwiftUIMessageRowView` 需要覆盖现有 `ChatConversationMessageRow` 的操作：

| 操作 | 现有来源 | SwiftUI 新架构做法 |
| --- | --- | --- |
| 复制 | `UIPasteboard.general.string` | Row 内调用同样 plain text 生成逻辑 |
| 删除 | `uiStateStore.markDeleted` | 通过 dependencies 调用 |
| 重试 | `detailViewModel.retryLatestConversationFailure` / `retryFailedMessage` | 封装到 `ChatSwiftUIRowActions` |
| 语音 | `ChatSpeechHelper.toggle` | 通过 dependencies 调用 |
| 翻译 | Row 当前 toggleTranslate 逻辑 | 抽成 Chat 专属 helper，避免复制大段 |
| 保存知识库 | Row 当前 saveMessageToKnowledge 逻辑 | 可先复用私有 helper 下沉到 shared Chat helper |
| 工具预览 | `detailViewModel.presentToolDetailPreview` | 使用 ChatSwiftUIRenderContext 转 ChatRenderContext 或补等价入口 |
| 高度变化 | `onHeightChangingUpdate` | SwiftUI 首版改由 scroll policy post-layout 跟随 |

如果现有 `ChatConversationMessageRow` 中 helper 是 private，落地时建议先提取到 Chat 专属 service/helper，例如：

```text
ChatMessagePlainTextBuilder
ChatMessageRowActionFactory
ChatMessageTranslationController
ChatMessageKnowledgeSaveController
```

不要为了 SwiftUI 新架构直接复制 300 行 Row 逻辑。

### 15.14 工具 trace 与正文分层落地

`ChatSwiftUIAssistantBubble` 建议结构：

```swift
VStack(alignment: .leading, spacing: style.blockSpacing) {
    if state.toolTraceItems.isEmpty == false || state.reasoningText.isEmpty == false {
        ChatSwiftUIToolTracePanelView(
            state: state,
            style: conversationAppearance.cardStyle,
            displayMode: conversationAppearance.toolTraceDisplayMode,
            collapseToolsWhileStreaming: conversationAppearance.collapseToolsWhileStreaming
        )
    }

    ChatSwiftUIAnswerBodyView(
        message: row.message,
        streamingState: state,
        renderContext: renderContext
    )

    ChatSwiftUIRichBlockStack(...)
}
```

第一版分层规则：

1. `.deepThought` 和 `.tool` 进入 trace。
2. `.text` 和 `.translatedText` 进入正文。
3. `nodeRole == .toolPresentation` 优先跟随对应 tool；如果无法关联，作为正文后的结构化卡片显示。
4. `medicalDisclaimerCard` 放正文后。
5. `healthResourceReference` 保持现有分组语义，不丢入口。

### 15.15 加载态落地

新增：

```text
ChatSwiftUISessionLoadingView
```

行为：

1. `stateStore.isLoading == true && visibleMessages.isEmpty` 显示加载态。
2. 8 秒后显示“仍在加载…”。
3. 有取消能力时可给取消按钮；如果当前 Chat 没有取消 load API，第一版只显示提示，不做假按钮。
4. 不允许在会话加载中显示空欢迎页。

### 15.16 测试落地

建议新增测试：

```text
Tests/Chat/ChatSwiftUIConversationFrameBuilderTests.swift
Tests/Chat/ChatSwiftUIStreamEventBufferTests.swift
Tests/Chat/ChatSwiftUIStreamReducerTests.swift
Tests/Chat/ChatSwiftUIScrollAnchorPolicyTests.swift
Tests/Chat/ChatConversationUIArchitectureSettingsTests.swift
```

测试用例：

1. 默认设置 decode 为空时 architecture 为 UIKit。
2. 切换 SwiftUI 后 PreferencesPayload encode/decode 保持。
3. 同一 block revision 重复进入 buffer 不重复生成 event。
4. `.text` streaming block 多次 revision 后最终 answerText 等于最新文本，不重复拼接。
5. `.deepThought` 和 `.tool` 不进入最终正文。
6. deliveryState `.failed` 生成 terminal error 状态。
7. prepend 历史消息时 frame 标记 `hasPrependedItems` 或等价 anchor intent。
8. done/error priority 为 immediate，text delta priority 为 nextFrame。

### 15.17 首版验收降级策略

为了降低风险，第一版允许以下降级：

1. SwiftUI 架构默认关闭，只能在设置中手动开启。
2. SwiftUI 顶部 prepend 锚点第一版恢复到 top item，不强求像 UIKit 一样精确到像素。
3. `ChatSwiftUIToolTracePanelView` 第一版只做 message 级折叠，不做每个 tool 二级展开。
4. 复杂结构化卡片可继续调用现有 `ChatMessageBlock.render(context:)`。

不允许降级：

1. 不允许复用 DeepTutorChat View / Palette / Domain。
2. 不允许 SwiftUI 模式丢失发送、流式正文、重试、复制、删除、工具预览。
3. 不允许 UIKit 模式行为回退。
4. 不允许把 SwiftUI 设为默认。

## 16. 代码落地记录

### 16.1 已实现代码位置

设置与持久化：

```text
SparkClient/Projects/Features/AISettings/Domain/AISettingsDomainModels.swift
SparkClient/Projects/Features/AISettings/Domain/AISettingsSnapshot.swift
SparkClient/Projects/Features/AISettings/Presentation/Root/AISettingsView.swift
```

Chat SwiftUI 会话架构：

```text
SparkClient/Projects/Features/Chat/Presentation/SwiftUIConversation/ChatSwiftUIConversationModels.swift
SparkClient/Projects/Features/Chat/Presentation/SwiftUIConversation/ChatSwiftUIStreamSupport.swift
SparkClient/Projects/Features/Chat/Presentation/SwiftUIConversation/ChatSwiftUIScrollAnchorPolicy.swift
SparkClient/Projects/Features/Chat/Presentation/SwiftUIConversation/ChatSwiftUIConversationView.swift
```

Chat 入口切换：

```text
SparkClient/Projects/Features/Chat/Presentation/ChatView.swift
```

### 16.2 已落地能力

1. 设置内新增 `Chat 会话 UI 架构`，支持 `UIKit 经典` / `SwiftUI 新架构` 切换。
2. 默认值保持 `UIKit 经典`，避免影响现有 Chat 线上行为。
3. SwiftUI 模式独立使用 `ChatConversationUIPreferences`，不复用 DeepTutorChat 的 View、Palette、Domain、Preference。
4. SwiftUI 模式复用 `Chat 对话外观 / 对话卡片样式`，不再提供重复的 SwiftUI 专属卡片样式配置。
5. SwiftUI 模式支持 `SwiftUI 刷新策略`：稳定刷新、跟随底部、手动优先。
6. SwiftUI 会话列表使用 `ScrollViewReader + ScrollView + LazyVStack + refreshable`。
7. SwiftUI 会话列表保留 Chat 自身消息行能力：复制、删除、重试、朗读、翻译、工具预览、附件导入、健康资源跳转。
8. SwiftUI 帧模型基于 `ChatMessage.clientMessageID` 建立稳定 row id。
9. SwiftUI 流式刷新通过 `ChatSwiftUIStreamEventBuffer` 识别文本长度、工具块数量、block revision 变化。
10. SwiftUI 帧调度通过 `ChatSwiftUIFrameScheduler` 将流式 delta 合并到下一帧，结构变化立即刷新。
11. SwiftUI 滚动通过 `ChatSwiftUIScrollAnchorPolicy` 区分强制到底部、底部锁定、用户手动滚动后的不抢焦点。
12. SwiftUI 支持下拉刷新，复用 Chat 的 `ConversationMessageListRefreshCoordinator`。
13. SwiftUI 支持加载更早消息，调用 Chat 自己的 `ChatDetailViewModel.loadMoreMessages`。
14. SwiftUI 支持文件导入，复用 Chat 的 `ChatComposerAttachmentImporter`。

### 16.3 编译验收

已执行：

```bash
xcodebuild -project SparkClient.xcodeproj -scheme SparkClient -configuration Debug -destination 'generic/platform=iOS Simulator' build
```

结果：构建通过。当前输出仍包含工程既有 warning，本工单新增代码无阻断编译错误。
