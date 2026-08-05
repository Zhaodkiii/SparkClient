# DEEPTUTORCHAT-000001 iOS 本地消息 UI 对齐 DeepTutor Web 需求文档

## 工单状态

待实现（2026-08-05）。

本工单只创建需求与技术边界文档，不修改 Swift、TypeScript、Python、配置或资源文件。

## 1. 背景

### Q：这次要解决什么问题？

A：在 SparkClient iOS 中新增 `DeepTutorChat` 会话体验，第一阶段只实现本地对话数据与本地 UI 渲染，但 UI、组件拆分、刷新方式和消息架构必须参考 DeepTutor Web 主对话。

目标路径：

- iOS 目标目录：[DeepTutorChat](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat)
- Web 参考工程：[DeepTutor web](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web)
- 文档目录：[DeepTutorChat 需求文档目录](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/需求文档/对话/DeepTutorChat)

当前代码事实：

| 模块 | 当前代码证据 | 接入证据 | 文档状态 | 下一步 |
| --- | --- | --- | --- | --- |
| DeepTutorChat 目标目录 | [DeepTutorChat](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat) 为空目录 | 未发现页面、ViewModel、Repository、路由装配 | 待实现 | 按本工单建立 Presentation/Application/Domain/Infrastructure |
| 既有 Chat 本地数据库 | [CoreDataChatStore.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Infrastructure/CoreDataChatStore.swift) | 被 Chat Repository / ViewModel / 列表刷新链路消费 | 已实现，可参考 | DeepTutorChat 第一阶段复用已有数据库思想，不新建网络同步 |
| 既有消息模型 | [ChatMessage.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Domain/ChatMessage/ChatMessage.swift) | 被 ChatView、CoreDataChatStore、AIRuntime 消费 | 已实现，可参考 | DeepTutorChat 可新增专用模型或扩展 block 语义，但字段需可落 CoreData |
| 既有刷新机制 | [ChatNotifications.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Infrastructure/ChatNotifications.swift)、[ConversationMessageListRepresentable.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ConversationList/ConversationMessageListRepresentable.swift) | NotificationCenter + diff plan + UIKit 列表桥接 | 已实现，可参考 | DeepTutorChat 采用本地写入后通知刷新、增量 diff、底部锚定 |

## 2. 一句话目标

### Q：一句话需求是什么？

A：在 iOS 新建 `DeepTutorChat` 本地会话模块，按照 DeepTutor Web 的“页面容器 -> 状态 -> 消息列表 -> 单条气泡 -> 内容渲染”链路，落地一套 SwiftUI/UIKit 原生消息 UI；第一阶段只读写本地数据库，不接入 DeepTutor WebSocket，不改现有 Chat 业务实现。

## 3. 范围边界

### Q：本次只做什么？

A：本次只要求后续实现以下内容：

1. DeepTutorChat 独立会话页入口。
2. 本地会话列表与本地消息存储。
3. 用户消息气泡、助手消息气泡、能力徽章、附件/引用树、trace 折叠卡片、ask_user 卡片、生成文件卡片的 iOS 组件规格。
4. 消息列表刷新、下拉刷新、加载更多、底部锚定、流式占位刷新策略。
5. 数据模型使用已有 CoreData 对话数据库流程，或在同一数据库内新增 DeepTutorChat 命名空间字段，保证账号隔离。

### Q：本次不做什么？

A：以下内容不在当前版本范围：

1. 不接入 DeepTutor WebSocket。
2. 不接入服务端会话持久化。
3. 不实现跨设备同步。
4. 不实现真实 deep_research、quiz、math_animator、visualize 业务执行。
5. 不修改现有 `Features/Chat` 的线上行为。
6. 不展开 HarmonyOS / Android 实现细节。

## 4. Web 参考链路

### Q：DeepTutor Web 的消息 UI 主链路是什么？

A：Web 主链路如下：

```text
home/[[...sessionId]]/page.tsx
  -> UnifiedChatContext.state.messages
  -> ChatMessageList
  -> UserMessage / AssistantMessage
  -> AssistantActivity / AskUserOptions / AssistantResponse
  -> MarkdownRenderer / 特殊能力 Viewer
```

关键参考代码：

| Web 文件 | 职责 | iOS 目标映射 |
| --- | --- | --- |
| [page.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/app/(workspace)/home/[[...sessionId]]/page.tsx) | 会话页壳层，组合消息列、TurnNavigator、Composer | `DeepTutorChatPage` |
| [UnifiedChatContext.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/context/UnifiedChatContext.tsx) | 会话状态、messages、streaming、branch | `DeepTutorChatStateStore` + `DeepTutorChatViewModel` |
| [ChatMessages.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ChatMessages.tsx) | 消息列表、用户气泡、助手气泡、能力分流 | `DeepTutorMessageListView` + `DeepTutorUserBubble` + `DeepTutorAssistantBubble` |
| [AssistantResponse.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/common/AssistantResponse.tsx) | 助手正文、thinking、Markdown | `DeepTutorAssistantResponseView` |
| [MarkdownRenderer.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/common/MarkdownRenderer.tsx) | Simple/Rich Markdown 路由 | `DeepTutorMarkdownRenderer` |
| [TracePanels.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/TracePanels.tsx) | 思考与工具 trace 折叠区 | `DeepTutorTracePanelView` |
| [AskUserOptions.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/AskUserOptions.tsx) | ask_user 交互卡片 | `DeepTutorAskUserCardView` |
| [ContextReferenceTree.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ContextReferenceTree.tsx) | 用户消息下方附件/引用树 | `DeepTutorContextReferenceTreeView` |
| [TurnNavigator.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/TurnNavigator.tsx) | 左侧 Turn 刻度尺 | iOS 第一阶段不做左侧刻度尺，先保留 turn anchor 数据 |

## 5. iOS 目标目录

### Q：DeepTutorChat 目标目录怎么拆？

A：使用与现有 `Features/Chat` 一致的四层结构。

```text
SparkClient/Projects/Features/DeepTutorChat/
├── Presentation/
│   ├── DeepTutorChatPage.swift
│   ├── DeepTutorMessageListView.swift
│   ├── DeepTutorComposerView.swift
│   ├── Bubbles/
│   │   ├── DeepTutorUserBubble.swift
│   │   └── DeepTutorAssistantBubble.swift
│   ├── Cards/
│   │   ├── DeepTutorTracePanelView.swift
│   │   ├── DeepTutorAskUserCardView.swift
│   │   ├── DeepTutorGeneratedFileCardView.swift
│   │   ├── DeepTutorResearchOutlineCardView.swift
│   │   ├── DeepTutorQuizCardView.swift
│   │   └── DeepTutorVisualizationPlaceholderView.swift
│   └── Rendering/
│       ├── DeepTutorAssistantResponseView.swift
│       ├── DeepTutorMarkdownRenderer.swift
│       └── DeepTutorThinkingCardView.swift
├── Application/
│   ├── DeepTutorChatViewModel.swift
│   ├── DeepTutorMessageReducer.swift
│   ├── LoadDeepTutorMessagesUseCase.swift
│   ├── SendLocalDeepTutorMessageUseCase.swift
│   └── DeepTutorRefreshCoordinator.swift
├── Domain/
│   ├── DeepTutorMessage.swift
│   ├── DeepTutorMessageBlock.swift
│   ├── DeepTutorStreamEvent.swift
│   ├── DeepTutorCapability.swift
│   ├── DeepTutorBranchSelection.swift
│   └── DeepTutorConversationState.swift
└── Infrastructure/
    ├── DeepTutorLocalChatRepository.swift
    ├── DeepTutorLocalChatStore.swift
    ├── DeepTutorMessageCodec.swift
    └── DeepTutorChatNotifications.swift
```

说明：以上为目标文件结构，不代表当前已实现。当前 `DeepTutorChat` 目录为空。

## 6. 页面与组件规格

### Q：页面 Plain text 草图是什么？

```text
DeepTutorChatPage
┌────────────────────────────────────┐
│ 顶部：会话标题 / 本地状态 / 更多       │
├────────────────────────────────────┤
│ DeepTutorMessageListView            │
│                                    │
│                    [用户能力标签]    │
│                 ┌──────────────┐   │
│                 │ 用户消息文本  │   │
│                 └──────────────┘   │
│                  附件/引用树         │
│                                    │
│  trace 折叠卡片                     │
│  助手正文 Markdown                  │
│  ask_user / quiz / outline 卡片      │
│  生成文件卡片                       │
│                                    │
├────────────────────────────────────┤
│ DeepTutorComposerView               │
│ 附件树 / 输入框 / 发送 / 停止         │
└────────────────────────────────────┘
```

### Q：哪些 Web UI 必须完全对齐？

A：完全对齐指信息架构、组件语义、状态和交互效果一致，不要求照搬 CSS 像素。

| Web 组件语义 | iOS 目标组件 | 必须对齐的行为 |
| --- | --- | --- |
| 用户消息右对齐、能力徽章 | `DeepTutorUserBubble` | 右对齐；显示 Chat/Deep Research/Quiz 等 capability label；支持复制、编辑占位、分支切换占位 |
| 助手消息无外框正文 | `DeepTutorAssistantBubble` | trace 在正文上方；正文 Markdown 流式增长；完成后显示操作按钮 |
| trace 折叠 | `DeepTutorTracePanelView` | streaming 时展开，完成后可折叠；工具调用按 call id 聚合 |
| ask_user 卡片 | `DeepTutorAskUserCardView` | 支持选项、自由输入、resolved 摘要；第一阶段可本地模拟提交 |
| 附件/引用树 | `DeepTutorContextReferenceTreeView` | 单个直接展示，多个折叠；可点击预览；右侧跟随用户气泡 |
| 生成文件卡片 | `DeepTutorGeneratedFileCardView` | 图片/视频内联预览，其他文件紧凑卡片；点击打开本地预览 |
| Markdown 渲染 | `DeepTutorMarkdownRenderer` | 普通文本、代码块、数学/Mermaid 占位策略、thinking 卡片 |

### Q：消息链路里每一层的职责边界是什么？

A：必须严格按下列职责拆分，避免把 DeepTutor 的 UI、状态、数据拼在一个大 ViewModel 里。

| 层级 | iOS 目标组件 | 唯一职责 | 明确禁止 |
| --- | --- | --- | --- |
| 页面壳层 | `DeepTutorChatPage` | 组合顶部栏、消息列表、Composer、全屏弹层；接收路由参数；持有页级 sheet 状态 | 不直接处理消息 block 分流 |
| 页面状态 | `DeepTutorChatViewModel` | 持有 `messages/isStreaming/selectedBranches/scrollAnchorState/activePreview` | 不直接写 UIKit cell；不直接拼 Markdown |
| 列表容器 | `DeepTutorMessageListView` | 负责 diff、滚动锚定、下拉刷新、加载更多、局部重载 | 不解析 tool 业务含义 |
| 单条用户消息 | `DeepTutorUserBubble` | 右对齐、徽章、编辑态、附件树、分支切换、hover/长按操作 | 不承载助手 trace 或 Markdown |
| 单条助手消息 | `DeepTutorAssistantBubble` | 组合 trace、正文、特殊能力卡片、底部操作区 | 不直接读取数据库 |
| 正文渲染 | `DeepTutorAssistantResponseView` | 分段正文、thinking 卡片、Markdown 路由 | 不负责按钮、文件卡片、error footer |
| 特殊卡片 | `DeepTutorTracePanelView` / `DeepTutorAskUserCardView` / `DeepTutorQuizCardView` 等 | 单一功能单一卡片 | 不依赖全局页面状态 |
| 存储层 | `DeepTutorLocalChatStore` | 本地会话/消息/事件的读写和通知 | 不做 UI 计算 |

### Q：页面壳层需要对齐哪些细节？

A：`DeepTutorChatPage` 需要对齐以下效果：

| 细节 | Web 参考 | iOS 落地要求 |
| --- | --- | --- |
| 消息列是页面中心主轴 | [page.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/app/(workspace)/home/[[...sessionId]]/page.tsx:2035) | iOS 中消息列表必须是视觉中心，顶部栏和 Composer 不可抢主层级 |
| 消息列最大宽度受控 | Web `max-w-[960px]` | iPhone 宽度下气泡最大宽度建议为容器宽度的 75%-78%；iPad 不允许无限拉宽 |
| Turn 导航是附属层 | `TurnNavigator` 为侧边叠层 | iOS 第一阶段不做左轨，但要预留 turn anchor 和当前轮次索引 |
| Composer 固定在底部 | `ChatComposer` 与列表分层 | iOS 底部输入区固定，不跟消息内容滚走；键盘弹起时保持输入区贴底 |
| 顶部/底部 fade mask | scroll root mask | iOS 可用 gradient mask 或 content inset 模拟，重点是最后一条消息不能被底部遮罩吃掉 |

### Q：用户气泡要对齐到什么程度？

A：`DeepTutorUserBubble` 需要把 Web 的信息密度和动作位置一起搬过来。

| 设计点 | Web 参考代码 | iOS 目标 |
| --- | --- | --- |
| 整体右对齐 | [ChatMessages.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ChatMessages.tsx:1034) | 整个用户 turn 右对齐，气泡尾部不需要卡通箭头 |
| 能力徽章在气泡上方 | [ChatMessages.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ChatMessages.tsx:1044) | 徽章是 10-11pt 轻量文字，不做大彩色 pill，不喧宾夺主 |
| 气泡底色轻、圆角大 | [ChatMessages.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ChatMessages.tsx:1096) | 建议 `secondary` 背景、连续圆角 18-20pt、正文 14-15pt、行高偏松 |
| 引用树挂在气泡下方右侧 | [ChatMessages.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ChatMessages.tsx:1103) | 附件树不是塞进气泡内部，而是独立一层挂在底部，与气泡右边对齐 |
| 操作区 hover 后出现 | [ChatMessages.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ChatMessages.tsx:1113) | iOS 改为长按菜单或轻量底部 action row，默认弱化显示 |
| 编辑态替换正文 | [ChatMessages.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ChatMessages.tsx:1049) | 进入编辑时同位置替换为多行输入框，不另外 push 新页 |

### Q：助手气泡需要对齐哪些视觉规则？

A：`DeepTutorAssistantBubble` 不是传统“左边一颗实心气泡”，而是“trace + 正文 + 卡片 + 操作条”的复合内容列。

| 设计点 | Web 参考代码 | iOS 目标 |
| --- | --- | --- |
| trace 固定在正文上方 | [ChatMessages.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ChatMessages.tsx:404) | 思考/工具活动区永远在正文前面，不允许落到底部 |
| 助手正文不强包在厚重卡片里 | `AssistantResponse` 直接渲染 | iOS 助手正文可用透明背景或极浅容器，不应比用户气泡更厚重 |
| 特殊能力分支替换正文中段 | [ChatMessages.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ChatMessages.tsx:416) | research/quiz/visualize/ask_user 以块级组件插入，不拆成独立消息列表项 |
| 错误状态单独显示 error card | [ChatMessages.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ChatMessages.tsx:1436) | turn terminal error 要在助手气泡后显示红色轻卡片和 Retry，不得只打日志 |
| 操作条在回答完成后出现 | [ChatMessages.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ChatMessages.tsx:1468) | streaming 时不展示 copy/regenerate/delete；完成后再出现 |

### Q：工具使用、工具调用、思考展示怎么对齐？

A：这三者必须拆清：

1. `思考`：模型产生但不直接属于最终正文的 reasoning 内容，展示为折叠 thinking card。
2. `工具使用`：给用户看的“正在搜索/读取文件/问你问题”等活动信息，属于 trace UI。
3. `工具调用结果`：真正形成消息内容、文件卡片、问题卡片、研究 outline、错误卡片的结果块。

对应 Web 依据：

| 类型 | Web 代码位置 | iOS 目标 |
| --- | --- | --- |
| thinking | [AssistantResponse.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/common/AssistantResponse.tsx:64) | `DeepTutorThinkingCardView`，默认折叠，可展开全文 |
| trace 活动行 | [TracePanels.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/TracePanels.tsx:179) | `DeepTutorTraceRowView`，显示图标、动词、chip、耗时、状态 |
| ask_user 结果 | [AskUserOptions.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/AskUserOptions.tsx:411) | `DeepTutorAskUserCardView`，支持 interactive/resolved 双态 |
| tool result 生成卡片 | `GeneratedFileCards` / capability viewers | `DeepTutorGeneratedFileCardView`、`DeepTutorResearchOutlineCardView` 等 |

## 6.1 用户消息 UI 详细规格

### Q：用户消息需要哪些具体 UI 字段？

| 字段 | 展示位置 | 展示规则 |
| --- | --- | --- |
| capability label | 气泡上方右侧 | 无值时默认 `Chat`；文案与 DeepTutor Web `getModeBadgeLabel` 对齐 |
| message text | 气泡正文 | 保留换行；不做 Markdown |
| attachments | 气泡下方 | 图片显示缩略图；文档显示图标 + 文件名 |
| requestSnapshot references | 同 attachments 树 | knowledge / book / notebook / persona / memory 统一走树形引用行 |
| branch nav | 操作条中 | 只有存在 sibling branches 时显示 `1 / N` 和左右切换 |
| edit action | 操作条 | streaming 期间禁用 |

### Q：用户消息编辑交互怎么做？

| 状态 | UI | 更新规则 |
| --- | --- | --- |
| normal | 普通气泡 | 可长按进入编辑 |
| editing | 原位多行输入框 | 输入框高度随内容长高，最大显示 6-8 行 |
| save pending | Send 按钮 loading | 本地先写入新 branch，再刷新 visible path |
| saved | 切回 normal | 列表滚动位置保持稳定，不要闪动整屏 |
| cancelled | 恢复 normal | 不写库 |

## 6.2 助手消息 UI 详细规格

### Q：助手消息的内部层次顺序是什么？

```text
AssistantBubble
  1. Activity Header / Trace Panel
  2. AskUser summary or interactive card（若 research 则先于 outline）
  3. Special capability card（outline / quiz / visualize / animation）
  4. AssistantResponse（正文 / thinking / markdown）
  5. Generated file cards
  6. Error / Retry card
  7. Actions row + cost footer
```

### Q：助手消息正文要注意哪些细节？

| 细节 | Web 依据 | iOS 要求 |
| --- | --- | --- |
| thinking 与正文分段 | [AssistantResponse.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/common/AssistantResponse.tsx:33) | 同一条消息中允许多个 segment：thinking / markdown / thinking / markdown |
| 空消息不渲染 | [AssistantResponse.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/common/AssistantResponse.tsx:50) | 没有可见内容的 segment 不占位，不制造空白卡片 |
| Markdown renderer 单向升级 | [MarkdownRenderer.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/common/MarkdownRenderer.tsx:26) | iOS 渲染器也要避免“简单文本 -> 富文本 -> 又退回简单文本”的闪烁 |
| 流式正文平滑增长 | `useSmoothStreamText` | iOS 应做节流增量刷新，避免每 token 全 cell 重算高度 |

## 6.3 Trace / 思考 / 工具调用详细规格

### Q：trace 面板需要哪些可见元素？

| 元素 | 是否必需 | 说明 |
| --- | --- | --- |
| 顶部状态标题 | 必需 | 例如“DeepTutor 正在探索… / 已回复” |
| 总耗时 | 必需 | streaming 时递增，完成后固定 |
| 折叠箭头 | 必需 | streaming 默认展开，完成默认折叠 |
| 工具活动行 | 必需 | 显示动作动词、对象 chip、进行中/完成态 |
| research 阶段卡片 | deep_research 必需 | understand / decompose / evidence / result 四段 |
| provider/tool 来源 | 建议 | MCP / CLI / built-in 来源应可见 |
| 失败工具行 | 必需 | 用错误色但不抢正文焦点 |

### Q：trace 行文案如何落到 iOS？

A：不要把 Web 端的渲染文案散落在多个 cell 里。iOS 要有一层 `DeepTutorTraceFormatter`：

1. 输入：`DeepTutorStreamEvent.metadata`
2. 输出：`icon + verb + chip + status + duration + groupingKey`
3. groupingKey 首选 `call_id`
4. 没有 `call_id` 时退化为 `step_id + trace_kind`

### Q：thinking card 需要什么行为？

| 行为 | 要求 |
| --- | --- |
| 默认折叠 | 是 |
| 记住展开状态 | 同一条消息生命周期内记住 |
| 正文超长渐变裁切 | 建议 |
| 不参与 copy assistant whole message | 是，整体复制时默认只复制用户可见正文，不把 thinking 混进去 |
| streaming 更新 | 若当前 thinking 仍在增长，只刷新 thinking card 本身 |

## 6.4 ask_user 卡片详细规格

### Q：ask_user 为什么要超级认真对齐？

A：因为 DeepTutor 的 ask_user 不是简单按钮集合，它决定“同一轮消息暂停 -> 用户补充 -> 继续当前轮”，这和普通新发一条用户消息不同。

### Q：ask_user 卡片字段要对齐什么？

| 字段 | 来源 | iOS 行为 |
| --- | --- | --- |
| `intro` | payload | 显示在卡片头部说明区 |
| `questions[]` | payload | 多问题时切 tab |
| `header` | payload | tab 标题，缺省时显示 Question N |
| `prompt` | payload | 问题正文 |
| `options[]` | payload | 选项按钮，支持 label + description |
| `allow_free_text` | payload | 控制输入框显示 |
| `placeholder` | payload | 输入框占位文案 |
| `resolved` | progress event | 已提交后切到摘要模式 |
| `answers[]` | progress event | resolved 态展示用户答案 |

### Q：iOS 第一阶段不接后端时怎么模拟这个机制？

A：本地版仍然要保留相同状态机：

```text
assistant emits ask_user tool_result
  -> messageSegments 插入 ask_user card
  -> user taps option / types answer
  -> local reducer 写 progress(ask_user_resolved=true)
  -> card 切 resolved summary
  -> 如需继续同轮，继续在同一 assistant message 后追加 text segment
```

重点：不要把 ask_user 的回答错误地做成一条新的普通用户消息。

## 6.5 Generated File / Preview 详细规格

### Q：生成文件卡片怎么对齐？

| 文件类型 | 展示方式 | 更新规则 |
| --- | --- | --- |
| image/* | 直接内联图像卡片 | 文件一到就局部插入，不重排前面正文 |
| video/* | 内联视频封面/播放器卡片 | 点击后可预览；默认不自动播放 |
| document / pdf / txt | 紧凑文件卡片 | 显示图标、标题、大小、Open |
| generated code/file artifact | 同 document | 来源标记为 assistant generated |

卡片位置必须在对应助手消息正文之后，而不是消息列表底部统一文件区。

## 6.6 Capability 级别展示详细规格

### Q：每个 capability 在 iOS 里分别怎么显示？

| capability | UI 结构 | 第一阶段落地策略 |
| --- | --- | --- |
| `chat` | trace + thinking + markdown + actions | 完整实现 |
| `deep_research` | trace + ask_user summary + outline card + final report | 先用本地 fixture 实现结构，保留 merged turn 模型 |
| `deep_question` | preface markdown + quiz cards | 先本地渲染题卡，不接判分网络 |
| `math_animator` | trace + animator result card | 先做 placeholder card，字段冻结 |
| `visualize` | trace + visualization card | 先做 placeholder snapshot，不内嵌 webview |
| `mastery_path` | trace + path summary card | 预留卡片类型，第一阶段可不开放入口 |

## 8.1 UI 更新与刷新详细策略

### Q：哪些更新必须局部刷新，哪些可以全量刷新？

| 更新类型 | 建议策略 | 原因 |
| --- | --- | --- |
| 同一条 assistant 文本增量 | 局部刷新最后一条消息 | 保持打字流畅，不触发全列表跳动 |
| tool trace 新增一行 | 局部刷新对应 assistant row | trace 与正文同属一条消息 |
| ask_user pending -> resolved | 局部刷新对应 card | 这是同一条消息内部状态变化 |
| generated file 新增 | 局部插入当前消息尾部 block | 不影响前面消息布局 |
| 用户编辑产生 branch | 重算 visible path，局部替换受影响区段 | 分支切换会改变路径 |
| 切换会话 | 全量重载该会话 | 数据源整体更换 |
| 下拉刷新本地库 | 强制 full list rediff 一次 | 对齐现有 `layoutNonce` 语义 |

### Q：滚动锚定规则怎么定？

| 场景 | 滚动策略 |
| --- | --- |
| 用户刚发送消息 | 自动到底部 |
| 助手正在 streaming 且用户停留底部附近 | 跟随到底部 |
| 助手正在 streaming 但用户已经上滑阅读历史 | 不自动抢到底部，只显示“回到底部”提示 |
| prepend 历史消息 | 保持当前首可见项视觉位置不跳 |
| 切换会话 | 恢复该会话上次滚动位置，若没有则到底部 |

### Q：UI 更新的最小实现链路是什么？

```text
DeepTutorLocalChatStore.write()
  -> DeepTutorChatDatabaseKernel.postChangeNotification(event)
  -> DeepTutorChatViewModel.handleDatabaseChange(event)
  -> loadMessages(threadID)
  -> DeepTutorConversationUpdateBuilder.plan(previous,current)
  -> UICollectionView / UITableView diff apply
  -> if needsBottomFollow then scrollToBottom()
```

## 8.2 状态机详细规格

### Q：页面级状态机要怎么定义？

| 状态 | 条件 | UI |
| --- | --- | --- |
| `idle` | 会话已打开但未加载 | 空白骨架或 loading |
| `loadingLocal` | 首次读取本地会话 | skeleton / spinner |
| `ready` | 本地数据可展示 | 正常页面 |
| `streaming` | 最后一条 assistant 正在增长 | 停止按钮可见，trace 展开 |
| `resolvingAskUser` | 用户刚提交 ask_user | 卡片按钮 disabled，等待本地 reducer 更新 |
| `error` | 本地写库失败或 message decode 失败 | 页级错误 banner 或行级错误卡片 |

### Q：消息级状态机要怎么定义？

| 状态 | 用途 | UI |
| --- | --- | --- |
| `draft` | 用户输入中，尚未发送 | 仅 Composer 内可见 |
| `pending` | 已入库待生成 | 用户消息显示；助手占位可空 |
| `streaming` | 助手内容增长中 | trace 展开、正文增量 |
| `ready` | 完成 | 展示 actions / cost / file cards |
| `failed` | 本地模拟失败或 future network 失败 | error card + retry |
| `deleted` | 软删除 | 列表不显示，但数据可恢复/审计 |

## 8.3 与现有 SparkClient Chat 刷新链路的关系

### Q：现有 iOS Chat 哪些代码是 DeepTutorChat 必须参考的关键位置？

| iOS 代码位置 | 当前职责 | DeepTutorChat 借鉴点 |
| --- | --- | --- |
| [ChatView.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatView.swift:55) | 选择当前可见消息与页面状态 | DeepTutorChatPage 的 page-level state 组织方式 |
| [ChatView.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatView.swift:805) | 消息列表容器与 refresh coordinator | 将异步刷新逻辑从 View 本体剥离 |
| [ConversationMessageListRepresentable.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ConversationList/ConversationMessageListRepresentable.swift:33) | SwiftUI -> UIKit 列表桥接 | DeepTutorChat 若继续用 UIKit 列表，应复用这套桥接思想 |
| [ConversationUpdateBuilder.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ConversationList/ConversationUpdateBuilder.swift:3) | 前后两帧消息 diff 计划 | DeepTutorChat 的 structural/minor/prepend/append 规则 |
| [ChatListViewModel.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatListViewModel.swift:58) | 监听 DB 变更并局部 patch list | DeepTutor 会话列表和消息列表都要走这一思路 |
| [ChatDatabaseKernel.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Infrastructure/ChatDatabaseKernel.swift:4) | 单写队列 + 写后通知 | DeepTutor 本地库必须保持单写入口 |
| [CoreDataChatStore.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Infrastructure/CoreDataChatStore.swift:483) | append/upsert/load message | DeepTutor 本地存储接口的实现参考 |
| [ChatMessageBubbleContentView.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatView/Components/ChatMessageBubbleContentView.swift:7) | 单条消息的 block timeline 渲染 | DeepTutorAssistantBubble 可借鉴 block timeline 投影，而不是把所有内容塞一个 Text |
| [MessageRunActor.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Application/MessageRunActor.swift:23) | 串行处理 partial/tool/rich block/finalize | DeepTutor 本地流式与 future 网络流也应有同类 actor |
| [ChatOrchestrator.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ChatOrchestrator.swift:61) | AI + tool loop 编排 | 未来接 DeepTutor 服务端时的能力编排参考，但本阶段不直接复用 |

## 8.4 DeepTutor Web 关键代码位置清单

### Q：Web 侧哪些文件是 iOS 实施时必须同时打开对照的？

| 优先级 | 文件 | 重点 |
| --- | --- | --- |
| P0 | [page.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/app/(workspace)/home/[[...sessionId]]/page.tsx:2039) | 页面壳层、消息列、Composer、TurnNavigator |
| P0 | [ChatMessages.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ChatMessages.tsx:1142) | 列表、用户气泡、助手气泡、deep_research 合并、actions |
| P0 | [AssistantResponse.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/common/AssistantResponse.tsx:28) | thinking + markdown 的最终落点 |
| P0 | [TracePanels.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/TracePanels.tsx:23) | trace metadata、tool descriptor、研究阶段显示 |
| P0 | [AskUserOptions.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/AskUserOptions.tsx:82) | ask_user payload、segment、resolved 机制 |
| P0 | [UnifiedChatContext.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/context/UnifiedChatContext.tsx:148) | MessageItem 字段与 streaming state |
| P1 | [MarkdownRenderer.tsx](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/common/MarkdownRenderer.tsx:26) | monotonic rich renderer 策略 |
| P1 | [message-branches.ts](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/lib/message-branches.ts:61) | edit branch visible path |
| P1 | [chat-outline.ts](/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/lib/chat-outline.ts:47) | turn anchor key |

## 9.1 工具调用、思考、UI 更新的事件模型

### Q：DeepTutorChat 的事件模型应该怎么落到 iOS？

A：建议先冻结一个比 Web 更适合本地落库的事件枚举：

```text
DeepTutorStreamEvent
  - contentDelta(text, callID?, round?)
  - reasoningDelta(text, callID?, round?)
  - toolCallStarted(callID, toolName, argsSummary)
  - toolProgress(callID, label, progress?)
  - toolResult(callID, payload)
  - askUser(payload, toolCallID)
  - askUserResolved(toolCallID, answers)
  - result(metadata)
  - error(message, turnTerminal)
```

关键原则：

1. `content` 只表示可见正文。
2. `reasoning` 只表示 thinking / trace 相关内容。
3. `toolResult` 不直接等于 UI，必须再走 `DeepTutorMessageReducer`。
4. reducer 输出的是 message blocks / card models，而不是直接刷新 View。

### Q：为什么要把“工具调用”和“消息 block”分成两层？

A：因为 Web 端就是这么做的：

1. `events` 是运行时事实。
2. `AssistantMessage` 根据 `events + capability + content` 决定显示什么。
3. `TracePanels` 展示过程。
4. `AssistantResponse` 展示正文。
5. `GeneratedFileCards` / `AskUserOptions` / `ResearchOutlineEditor` 展示副产物。

iOS 也必须保持这个顺序，不能直接把某个 tool result 写死成某种 cell。

## 10.1 本地模拟版的推荐实现步骤

### Q：如果明天开始做 iOS，本地版建议怎么拆实施？

| 阶段 | 目标 | 产物 |
| --- | --- | --- |
| P0 | 建基础目录、会话页入口、本地 store、消息列表壳层 | 空态、普通 user/assistant 文本消息 |
| P1 | 接 capability badge、thinking card、Markdown renderer、trace panel | chat 主路径可用 |
| P2 | 接 ask_user 卡片、generated file cards、error card、actions row | 工具交互主路径可用 |
| P3 | 接 deep_research / quiz / visualize placeholder cards、branch 数据模型 | 复杂 turn 结构可跑通 |
| P4 | 接会话列表、本地草稿恢复、滚动位置恢复、账号隔离回归 | 第一阶段可验收 |

### Q：哪些“关键技术”是实现成败点？

| 技术点 | 为什么关键 | iOS 落地要求 |
| --- | --- | --- |
| 单写队列 | 防止 streaming / rich card / ask_user resolution 乱序覆盖 | 复用 actor + CoreData 单入口 |
| 局部 diff | 否则流式消息会卡、跳、闪 | 保持 message id 稳定，区分 minor/structural |
| 稳定 block id | 否则 trace/card 会重复或错位 | 对 thinking/tool/file/quiz/research card 生成 deterministic ID |
| monotonic markdown upgrade | 否则 streaming 过程中正文会重建 | 一旦进入 rich renderer 就不回退 |
| 分层 reducer | 否则 ViewModel 会膨胀 | event -> card model / block model -> view |
| scroll anchor policy | 否则用户阅读体验会被 streaming 打断 | 底部跟随与阅读中暂停必须分开 |
| account scope | 否则本地 DeepTutor 会话会串账号 | 所有表和查询都带 ownerAccountID |

## 11. 验收标准

## 7. 数据模型与本地存储

### Q：消息模型应如何设计？

A：第一阶段建立 DeepTutor 专用领域模型，但落库要复用现有 Chat CoreData 流程和账号隔离思想。

| 字段 | 类型 | 来源 | 是否持久化 | 说明 |
| --- | --- | --- | --- | --- |
| `id` | `UUID` | iOS 本地生成 | 是 | 本地唯一消息 ID |
| `serverID` | `String?` | 后续服务端 | 预留 | 第一阶段为空 |
| `conversationID` | `UUID` | 本地会话 | 是 | 对应本地 DeepTutor 会话 |
| `role` | `user/assistant/system` | 本地构造 | 是 | system 不进入 UI 列表 |
| `content` | `String` | 用户输入或本地模拟助手 | 是 | 与 Web `MessageItem.content` 对齐 |
| `capability` | `chat/deep_research/deep_question/math_animator/visualize/mastery_path` | Composer 或本地测试数据 | 是 | 驱动徽章与助手分支 |
| `events` | `[DeepTutorStreamEvent]` | 本地模拟/后续 WebSocket | 是 | trace、ask_user、result、error 的来源 |
| `attachments` | `[DeepTutorAttachment]` | Composer/生成文件 | 是 | 用户附件与助手生成文件 |
| `requestSnapshot` | `DeepTutorRequestSnapshot?` | 发送时快照 | 是 | 支撑附件树、上下文引用和重生成 |
| `parentMessageID` | `UUID?` | 编辑分支 | 是 | 对齐 Web `parentMessageId` |
| `createdAt/updatedAt` | `Date` | 本地 store | 是 | 排序与刷新 |

### Q：为什么不是直接复用 Web `MessageItem`？

A：Web 的 `MessageItem` 是 React 状态与服务端字段混合结构；iOS 需要本地落库、账号隔离、Swift 类型安全和列表 diff。字段语义要对齐 Web，但模型必须是 Swift 原生领域模型。

### Q：数据库使用什么？

A：使用已有 CoreData 对话数据库流程作为实现基线：

1. `CoreDataChatStore` 已经通过 `ownerAccountID` 做账号隔离。
2. `ChatDatabaseKernel` 是聊天域单一数据库入口，写成功后广播 `.sparkChatDatabaseDidChange`。
3. `ChatMessageBlock` 已经支持文本、deepThought、tool、fileAttachments、assistantStatusCard 等 block 形态。
4. DeepTutorChat 第一阶段可以选择新增 DeepTutor 专用 entity，也可以复用现有 message/block entity 加 `source = deepTutor` 命名空间；实施前必须出数据库迁移小方案。

禁止事项：

1. 不用 `UserDefaults` 存消息正文。
2. 不用普通文件堆 JSON 作为正式对话库。
3. 不把跨账号消息混在同一无 owner scope 表里。
4. 不把后续 token、服务端 base URL、私密 header 写进消息表。

## 8. 刷新方式

### Q：刷新方式如何参考现有 iOS Chat？

A：DeepTutorChat 应复用“本地事实源 -> 通知 -> ViewModel 局部刷新 -> 列表 diff”的路径。

```text
SendLocalDeepTutorMessageUseCase
  -> DeepTutorLocalChatRepository 写入用户消息
  -> DeepTutorLocalChatRepository 写入/更新助手消息
  -> DeepTutorChatNotifications 广播本地变更
  -> DeepTutorChatViewModel 收到变更
  -> loadMessages(threadID)
  -> DeepTutorMessageListView diff apply
  -> 保持底部锚定或保留当前阅读位置
```

现有代码参考：

| 刷新点 | 现有代码事实 | DeepTutorChat 目标 |
| --- | --- | --- |
| 数据库写成功广播 | [ChatDatabaseKernel.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Infrastructure/ChatDatabaseKernel.swift) | 新增 `DeepTutorChatDatabaseDidChange` 或复用 chat change event 扩展 source |
| 列表 ViewModel 监听 | [ChatListViewModel.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatListViewModel.swift) | DeepTutorChatViewModel 监听本地变更并局部 patch |
| 下拉刷新 handler | [ConversationMessageListRepresentable.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ConversationList/ConversationMessageListRepresentable.swift) | 第一阶段下拉刷新只重新读本地；远端刷新按钮隐藏或 disabled |
| diff 计划 | [ConversationUpdateBuilder.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ConversationList/ConversationUpdateBuilder.swift) | 消息 ID 不变时 minor reload，新增消息 append，加载历史 prepend |
| 底部锚定 | [ConversationMessageListRepresentable.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ConversationList/ConversationMessageListRepresentable.swift) | streaming / 本地模拟助手回复时锁定底部，用户上滑阅读时不强制抢滚动 |

## 9. 消息渲染链路

### Q：iOS 消息列表应如何分层？

A：目标链路如下：

```text
DeepTutorChatPage
  -> DeepTutorChatStateStore.messages
  -> DeepTutorMessageListView
  -> DeepTutorUserBubble / DeepTutorAssistantBubble
  -> DeepTutorTracePanelView / DeepTutorAssistantResponseView / DeepTutorAskUserCardView
  -> DeepTutorMarkdownRenderer / DeepTutorThinkingCardView / DeepTutorGeneratedFileCardView
```

### Q：助手消息按 capability 怎么分流？

| capability / events | Web 参考 | iOS 第一阶段目标 |
| --- | --- | --- |
| `chat` | `AssistantResponse` | Markdown 正文 + thinking 卡片 + trace |
| `deep_research` | `ResearchOutlineEditor` + merged turn | 本地静态 outline 卡片与最终报告占位；预留二段合并字段 |
| `deep_question` | `QuizViewer` | Quiz 卡片组件占位，可用本地 fixture 渲染 |
| `math_animator` | `MathAnimatorViewer` | 动画占位卡片，不执行真实动画 |
| `visualize` | `VisualizationViewer` | 可视化占位卡片，不执行 JS/iframe |
| `ask_user` | `AskUserOptions` | 选项/自由输入卡片，提交后本地标 resolved |

## 10. 本地会话流程

### Q：第一阶段本地发送流程是什么？

```text
用户输入
  -> DeepTutorComposerView 校验非空
  -> SendLocalDeepTutorMessageUseCase
  -> 写入 user message，capability 和 requestSnapshot 同步落库
  -> 写入 assistant placeholder，状态 streaming/localGenerating
  -> 本地 reducer 按测试策略追加 assistant content/events
  -> 更新 assistant 为 ready 或 failed
  -> 通知列表刷新
```

### Q：本地助手回复从哪里来？

A：第一阶段不调用网络，可以提供三种本地来源，实施时任选其一或组合：

1. 固定欢迎语与回声回复。
2. 内置 fixture，用来测试 trace、ask_user、deep_research、quiz、generated file 卡片。
3. 复用本地 `AIRuntimeService` 的本地模型能力，但必须保持可关闭，且不是本工单验收必需项。

## 11. 验收标准

### Q：P0 本地 UI 版本怎么验收？

| 场景 | 验收标准 |
| --- | --- |
| 首次进入 | `DeepTutorChat` 可创建本地会话；空态可见；不访问网络 |
| 发送文本 | 用户气泡右对齐，显示 capability badge；消息立即落库 |
| 助手本地回复 | 助手消息在左侧/正文区域出现；Markdown 可渲染；完成后按钮区出现 |
| 本地刷新 | 下拉刷新只读本地库；不会触发服务端请求 |
| 列表更新 | 新消息 append 时底部锚定；用户上滑时不强制跳底 |
| 附件树 | 单附件直接显示，多附件折叠；点击打开本地预览 |
| trace 卡片 | streaming 状态展开，完成后可折叠 |
| ask_user 卡片 | 选项与自由输入可展示；提交后变 resolved 摘要 |
| 生成文件卡片 | 图片内联，其他文件卡片展示；点击预览 |
| 账号切换 | A 账号本地会话不出现在 B 账号；登出后不可读旧账号消息 |
| 离线状态 | 全流程可用，因为第一阶段只依赖本地数据 |
| 数据持久化 | kill app 后重新进入，历史会话和消息仍在 |
| 思考区 | thinking card 只出现在 assistant turn；展开收起不影响正文顺序 |
| 工具使用区 | trace 行能正确显示“开始中/完成/失败”；不会和正文重复 |
| UI 稳定性 | streaming 期间列表不整屏闪烁；不会频繁跳底；不会重复插入相同卡片 |
| 分支切换 | 切换 branch 后消息路径正确；不会把隐藏分支和当前分支混在一起 |
| research 合并 | 同一 deep_research 的 outline turn 和 followup turn 视觉上是一条 assistant bubble |
| 复杂卡片 | quiz / outline / ask_user / generated file 都在对应 assistant turn 内，不游离到别的地方 |

## 12. 风险与待确认项

| 编号 | 风险/待确认项 | 影响模块 | 证据 | 依赖方 | 关闭条件 |
| --- | --- | --- | --- | --- | --- |
| R1 | `DeepTutorChat` 当前为空目录，尚无路由入口 | Presentation / App 装配 | 目标目录为空 | iOS | 确认入口挂在现有 App 哪个 tab 或功能页 |
| R2 | 复用现有 Chat CoreData 还是新增 DeepTutor 专用 entity 未定 | Infrastructure | `CoreDataChatStore` 已服务现有 Chat | iOS / 数据库 | 出数据库迁移方案，确认不影响现有 Chat |
| R3 | Web deep_research 二段 turn 合并在 iOS 本地数据中如何表达需冻结 | Domain / Rendering | Web `ChatMessageList` 有 deepResearchMergeMap | 产品 / iOS | 明确 parent/followup 或 merged events 字段 |
| R4 | Markdown 数学、Mermaid 在 iOS 第一阶段是否完全支持需取舍 | Rendering | Web `MarkdownRenderer` 自动切 Rich | 产品 / iOS | 确认可占位还是必须原生渲染 |
| R5 | TurnNavigator 第一阶段不做完整左侧刻度尺 | Presentation | Web 有 `TurnNavigator` | 产品 | 确认 iOS 是否改为顶部/侧边轻量导航或后置 |
| R6 | 本地 fixture 的能力卡片不能伪装成真实 AI 结果 | QA / 产品 | 当前不接网络 | iOS / QA | fixture 显示开发态来源或仅测试包启用 |

## 13. 与既有工单关系

本工单依赖以下已完成或已有文档结论：

1. [CHAT-000008-P0-AI主干统一与Runtime协议收口需求工单.md](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/需求文档/对话/CHAT-000008-P0-AI主干统一与Runtime协议收口需求工单.md)：Runtime 主干与流式事件统一思路。
2. [CHAT-000009-P1-能力与工具分层与副作用外置需求工单.md](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/需求文档/对话/CHAT-000009-P1-能力与工具分层与副作用外置需求工单.md)：capability、tool、side effect 分层边界。
3. [CHAT-000010-P2-能力显式化与ToolHub瘦身需求工单.md](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/需求文档/对话/CHAT-000010-P2-能力显式化与ToolHub瘦身需求工单.md)：后续能力卡片与工具层收敛参考。

本工单不改变上述已有 Chat 主干，只为 `DeepTutorChat` 建立独立的本地 UI 与存储落地边界。
