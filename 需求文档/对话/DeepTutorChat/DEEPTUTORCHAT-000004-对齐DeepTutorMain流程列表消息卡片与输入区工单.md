# DEEPTUTORCHAT-000004 对齐 DeepTutor-main 流程、对话列表、消息卡片与输入区工单

> 创建日期：2026-08-05  
> 所属模块：DeepTutorChat / iOS DeepTutor Web 对齐  
> 工单状态：待实现  
> 参考 Web 工程：`/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main`  
> iOS 工程：`/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient`  
> 处理边界：本工单只创建需求与修复方案，不直接修改 Swift 代码。

---

## 1. 工单目标

本工单聚焦 4 个当前必须修正的问题：

1. DeepTutorChat iOS 需要对齐 `DeepTutor-main` 的真实对话流程。
2. 创建新的对话之后，对话列表没有稳定展示新建会话。
3. 对话消息卡片需要完全对齐 `DeepTutor-main` 内的消息卡片，包含 UI 效果、层级、卡片、trace、thinking、tool call、ask_user、操作按钮。
4. 输入区域需要完全对齐 `DeepTutor-main` 的输入区，包含外层卡片、附件/引用区、能力/模型选择、发送/停止按钮、拖拽态、流式态。

一句话目标：

```text
iOS DeepTutorChat 不只是“能聊天”，而是从流程、列表刷新、消息卡片、工具活动、输入区交互上对齐 DeepTutor-main 的用户体验。
```

---

## 2. 参考端代码事实

### 2.1 DeepTutor-main 参考路径

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/app/(workspace)/home/[[...sessionId]]/page.tsx
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ChatMessages.tsx
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/TracePanels.tsx
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ChatComposer.tsx
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ComposerInput.tsx
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/common/AssistantResponse.tsx
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/common/MarkdownRenderer.tsx
```

### 2.2 Web 消息主链路

`ChatMessages.tsx` 中真实链路：

```text
ChatMessageList
  -> buildVisiblePath(messages, selectedBranches)
  -> deep_research 两轮合并
  -> UserMessage
  -> AssistantMessage
  -> AssistantActivity
  -> AskUserOptions / ResearchOutlineEditor / MathAnimatorViewer / VisualizationViewer / QuizViewer
  -> AssistantResponse
  -> MarkdownRenderer
```

关键代码事实：

```text
ChatMessages.tsx:404-415
AssistantActivity 固定在助手消息顶部，className="mb-3"

ChatMessages.tsx:416-515
AssistantMessage 按 outline / mathAnimator / visualize / quiz / inline ask_user / default markdown 分支渲染

ChatMessages.tsx:1034-1101
UserMessage 右对齐，max-w-[75%]，badge，rounded-2xl bg-secondary，data-turn-bubble

ChatMessages.tsx:1142-1208
ChatMessageList 入口，先 buildVisiblePath，再做 deep_research 两轮合并
```

### 2.3 Web 输入区主链路

`ChatComposer.tsx` 中真实输入区结构：

```text
外层吸底容器
  -> 渐变遮罩
  -> rounded-[26px] border bg-card shadow composer card
  -> 拖拽文件 overlay
  -> context reference tree 顶部引用带
  -> ComposerInput textarea
  -> attachments preview row
  -> bottom toolbar
       -> capability selectors
       -> knowledge/persona/model selectors
       -> context budget
       -> voice button
       -> send/stop one-button state machine
```

关键代码事实：

```text
ChatComposer.tsx:668
relative rounded-[26px] border bg-[var(--card)]
shadow-[0_1px_2px_rgba(0,0,0,0.025),0_10px_28px_-10px_rgba(0,0,0,0.08)]

ChatComposer.tsx:680
拖拽态 rounded-[26px] border-2 border-dashed border-primary/50 bg-primary/[0.04]

ChatComposer.tsx:708
引用区 rounded-t-[26px] border-b border-border/30 bg-muted/30 px-4 pb-2 pt-2.5

ChatComposer.tsx:721-752
ComposerInput，minHeight 有消息时 28，空态时 64

ChatComposer.tsx:1066-1073
ModelSelector 参与底部 toolbar

ChatComposer.tsx:1120-1151
发送按钮是同一个按钮，streaming 时 ArrowUp 与 Square 交叉淡入淡出，外圈 spinner
```

### 2.4 用户提供 DOM 片段事实

用户提供的 DOM 片段展示的是 DeepTutor Web 的活动/工具面板，核心视觉语义：

```text
活动 header：
  button aria-expanded
  flex w-full items-center gap-2.5
  text-[14px] font-semibold leading-none
  状态文本 “已完成”
  时长 “· 1m 17s”
  chevron-down

展开动画：
  grid transition-[grid-template-rows,opacity] duration-300 ease-out

活动内容：
  ml-[11px] border-l border-[var(--border)]/45 pl-[13px] pt-2

trace row：
  flex items-start gap-2.5 py-1.5 text-[14px] leading-[1.5]
  左侧 15px 手绘/线性 glyph
  muted foreground
  hover 时颜色增强

thinking 文本：
  italic leading-[1.6]
  md-renderer text-[11px] leading-[1.55]

工具行：
  role=button
  aria-expanded
  tool verb + chip
  chip 可 truncate / mono
  chevron hover opacity

工具详情：
  ml-[26px] mr-2 mt-0.5 max-h-[260px] overflow-y-auto
  pre bg-muted px-2 py-1 font-mono text-[10px]
  markdown result text-[11px]
```

这些视觉细节必须被 iOS 版本转译，而不是简化为普通 `DisclosureGroup` 或普通列表。

---

## 3. iOS 当前代码事实

### 3.1 当前 iOS DeepTutorChat 路径

```text
SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorChatPage.swift
SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorComposerView.swift
SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorMessageListView.swift
SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorMessageRowView.swift
SparkClient/Projects/Features/DeepTutorChat/Presentation/Bubbles/DeepTutorAssistantBubble.swift
SparkClient/Projects/Features/DeepTutorChat/Presentation/Bubbles/DeepTutorUserBubble.swift
SparkClient/Projects/Features/DeepTutorChat/Presentation/Cards/DeepTutorTracePanelView.swift
SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorChatViewModel.swift
SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorLocalChatStore.swift
```

### 3.2 当前对话列表实现

`DeepTutorConversationListPage` 当前结构：

```text
List
  -> if conversations.isEmpty: emptyState
  -> else ForEach(viewModel.conversations) NavigationLink
toolbar plus
navigationDestination(isPresented: selectedConversationID != nil)
task loadConversationsIfNeeded
refreshable refreshConversations
alert conversationCreationError
```

当前已有但仍需验收的点：

```text
createAndOpenConversation(source:)
selectedConversationID
emptyState 新建按钮
refreshConversations(source:)
```

用户反馈：

```text
创建新的对话之后，没有在对话列表展示出来。
```

因此不能把当前代码标为“已对齐”，只能标为：

```text
部分实现，未通过真实用户路径验收。
```

### 3.3 当前 iOS 输入区实现

`DeepTutorComposerView` 当前结构：

```text
VStack(spacing: 10)
  -> segmented Picker("Capability")
  -> HStack
       -> TextField("Message DeepTutor", axis: .vertical)
       -> stop.circle.fill / arrow.up.circle.fill
background(.bar)
```

当前差距：

```text
没有 rounded-[26px] 卡片。
没有 border bg-card shadow。
没有拖拽附件 overlay。
没有 context reference tree 顶部引用区。
没有 attachment preview row。
没有 bottom toolbar 的能力/模型/persona/context budget/voice/send 结构。
没有 Web 的同一发送按钮 arrow/square 交叉状态。
没有空态 minHeight 64 / 有消息 minHeight 28 的输入高度逻辑。
没有类似 Web 的视觉密度、阴影、边框和按钮动效。
```

### 3.4 当前 iOS 消息卡片实现

`DeepTutorUserBubble` 当前结构：

```text
VStack alignment trailing
  -> capability badge
  -> Text / TextEditor
  -> contextMenu Copy/Edit
  -> branch controls
  -> ContextReferenceTree
```

`DeepTutorAssistantBubble` 当前结构：

```text
VStack alignment leading
  -> ForEach blocks
  -> trace / askUser / researchOutline / quiz / visualization / generatedFile / thinking / markdown / error
  -> actions row Copy / Regenerate
```

当前差距：

```text
用户气泡未严格匹配 Web max-w 75%、rounded-2xl、px-4、py-2.5、shadow-sm、text 14px、badge 10px 追踪。
编辑态未匹配 Web 的 w[min(620px,75vw)]、border-primary/40、bg-secondary、按钮样式和快捷键提示。
助手 trace 视觉未匹配 Web 的活动 header、左侧竖线、15px glyph、11px markdown、工具详情折叠。
操作按钮只有文字 Copy/Regenerate，缺少 Web hover group、图标、删除、重生成、复制、turn anchor 效果。
特殊卡片已有占位，但未验证与 DeepTutor-main 的 ResearchOutlineEditor / QuizViewer / VisualizationViewer 卡片效果一致。
```

---

## 4. 问题一：对齐 DeepTutor-main 的流程

### 4.1 必须对齐的完整流程

iOS DeepTutorChat 应对齐以下流程：

```text
进入 DeepTutor
  -> 加载会话列表
  -> 空态 / 列表态
  -> 新建对话
  -> 新对话立刻出现在列表
  -> 自动进入新对话
  -> 输入区可输入
  -> 发送消息
  -> 用户气泡立即出现
  -> AssistantActivity 先出现
  -> thinking/tool/ask_user/正文按事件流增量渲染
  -> 完成后活动面板变为 “已完成 · duration”
  -> 助手正文 ready
  -> 返回列表看到最新 preview 和 updatedAt 排序
```

### 4.2 Web -> iOS 架构映射

| DeepTutor-main Web | iOS 目标 | 当前 iOS 状态 | 结论 |
| --- | --- | --- | --- |
| `page.tsx` 会话壳层 | `DeepTutorConversationListPage` + `DeepTutorChatPage` | 部分实现 | 需补列表刷新验收 |
| `ChatMessageList` | `DeepTutorMessageListView` | 部分实现 | 需对齐 visible path / deep research merge |
| `UserMessage` | `DeepTutorUserBubble` | 部分实现 | 需对齐气泡 UI |
| `AssistantMessage` | `DeepTutorAssistantBubble` | 部分实现 | 需对齐卡片分支 |
| `AssistantActivity` | `DeepTutorTracePanelView` | 部分实现 | 视觉和交互差距大 |
| `AssistantResponse` | `DeepTutorAssistantResponseView` | 部分实现 | 需对齐 markdown / streaming |
| `ChatComposer` | `DeepTutorComposerView` | 仅基础输入 | 需要重做 |

---

## 5. 问题二：创建新对话后列表没有展示

### 5.1 当前必须排查的链路

```text
点击新建
  -> DeepTutorChatViewModel.createAndOpenConversation
  -> createConversationUseCase
  -> DeepTutorLocalChatStore.createConversation
  -> ChatThreadEntity 写入
  -> postChange(.genericThreadsChanged)
  -> refreshConversations(source: "create")
  -> viewModel.conversations 更新
  -> SwiftUI List 重新渲染
  -> selectedConversationID navigationDestination
  -> 返回后列表仍可看到新会话
```

### 5.2 必查问题点

| 检查点 | 当前风险 | 修复要求 |
| --- | --- | --- |
| `ownerAccountID` | 当前账号为空时 Store 会抛 `notAuthenticated` | UI 必须显示错误，日志完整记录 |
| `scenario` | 列表只查 `DeepTutorScenarioConstants.scenario` | 创建和查询必须同一个 scenario |
| `isSoftDeleted` | 列表过滤 `isSoftDeleted == NO` | 创建必须明确 false |
| `updatedAt` 排序 | 新建后 preview 为空但应仍排第一 | 新建后列表必须显示，即使无消息 |
| `latestPreview` | 空 preview 可能导致 row 看起来空 | 空会话 row 显示 “新对话” / “暂无消息” |
| Notification | `writeWithoutNotification` 后自发通知 | 通知失败不应影响 create 后手动 refresh |
| SwiftUI navigation | `selectedConversationID` 进入详情后返回列表 | 返回时不应清空列表或未刷新 |
| Xcode target | DeepTutorChat 目录可能是未跟踪/未完整装配 | 文件必须加入 target 并由真实入口访问 |

### 5.3 修复要求

1. 新建成功后，先将 created conversation 乐观插入 `conversations` 顶部，再执行 repository refresh。
2. `refreshConversations(source: "create")` 必须记录 count、新会话 id 是否存在。
3. 如果 refresh 后找不到 created id，必须记录 `create_refresh_missing_created_conversation`。
4. 列表 row 对空 preview 使用占位文案，不允许显示空行。
5. 返回列表时必须触发一次轻量 refresh，确保最新 DB 状态。
6. 如果创建成功但列表为空，弹出错误或内联诊断，不允许静默。
7. 创建和查询的 `scenario` 必须写入日志。

### 5.4 验收标准

```text
Given DeepTutor 对话列表为空
When 用户点击新建对话
Then 立即创建本地会话
And 自动进入新对话详情
When 用户返回列表
Then 新对话出现在列表第一项
And row 显示标题 “DeepTutor Chat”
And preview 显示 “暂无消息” 或同等占位
And 日志显示 create id、refresh count、containsCreated=true
```

---

## 6. 问题三：消息卡片完全对齐 DeepTutor-main

### 6.1 用户气泡目标规格

Web 规格：

```text
外层：group flex justify-end
内容：flex max-w-[75%] flex-col items-end gap-1.5
badge：text-[10px] tracking-wide muted
气泡：rounded-2xl bg-secondary px-4 py-2.5 text-[14px] leading-relaxed shadow-sm
正文：whitespace-pre-wrap
编辑态：w[min(620px,75vw)] rounded-2xl border-primary/40 bg-secondary px-3 py-2.5
```

iOS 目标：

```text
右对齐。
最大宽度为容器 75%，iPad 有合理上限。
badge 位于右上方，10-11pt，muted，tracking 近似。
气泡圆角 16-18，背景 secondary surface，内边距 horizontal 16 / vertical 10。
文字 14-15pt，lineSpacing 近似 Web 1.5-1.6。
编辑态必须是同一卡片内 textarea 风格，不跳成系统大 TextEditor。
编辑按钮：Cancel / Send，尺寸和层级接近 Web。
ContextReferenceTree 在气泡下方右对齐。
```

### 6.2 助手卡片目标规格

Web 规格：

```text
AssistantActivity 始终在顶部，mb-3。
research 分支：AskUserOptions -> ResearchOutlineEditor -> AssistantResponse。
quiz 分支：preface AssistantResponse -> QuizViewer。
inline ask_user：text/card/text 按 stream 顺序穿插。
default：AssistantResponse。
```

iOS 目标：

```text
DeepTutorAssistantBubble 必须先渲染 DeepTutorActivityPanel。
block 顺序必须能表达：trace -> ask_user -> outline/quiz/viz/files -> thinking -> markdown。
inline ask_user 必须支持 text/card/text 顺序，不允许统一堆到顶部或底部。
quiz/research/visualize 不允许被普通 markdown 吃掉。
generated file card 必须与 Web 的 InlineFileCard/GeneratedFileCards 语义一致。
```

### 6.3 活动/工具面板目标规格

基于 `TracePanels.tsx` 和用户 DOM 片段，iOS 必须实现：

```text
Activity header：
  左侧 organic glyph / spark glyph
  状态文本：工作中 / 已完成 / 失败
  duration：· 1m 17s
  chevron
  可点击折叠

展开区域：
  左侧竖线
  row gap 10
  row vertical padding 6
  muted text
  hover 在 iOS 中对应 pressed/highlight

thinking row：
  italic
  小字号 markdown

tool row：
  verb + chip
  chip 可截断
  网页/搜索/命令/path 使用 mono 风格

tool detail：
  最大高度约 260px 对应 iOS 中 maxHeight + internal scroll
  参数 JSON 使用 monospace 小字号 code block
  结果使用 markdown 小字号
```

不得接受的实现：

```text
不允许只用普通 DisclosureGroup 默认样式。
不允许把所有工具调用拼成一段纯文本。
不允许隐藏 tool args/result。
不允许 thinking 和 tool trace 视觉混在正文里。
```

### 6.4 操作按钮目标规格

Web 语义：

```text
复制
重新生成
删除 turn
编辑用户消息
分支切换
turn anchor / flash
```

iOS 目标：

```text
助手 ready 后显示图标级轻量 actions，不只是 Text("Copy") / Text("Regenerate")。
用户气泡支持编辑、复制、删除、分支切换。
操作区默认弱化，长按或 hover-equivalent/上下文菜单可用。
删除 turn 需要确认。
重新生成要接真实 runtime。
```

---

## 7. 问题四：输入区域完全对齐 DeepTutor-main

### 7.1 外层卡片

Web 目标：

```text
rounded-[26px]
border border-border/55
bg-card
shadow subtle + large soft shadow
dragging 时 border-primary bg-primary/0.03
```

iOS 目标：

```text
外层使用 RoundedRectangle(cornerRadius: 26, style: .continuous)。
背景使用 card surface。
边框使用 border 55% 透明语义。
阴影两层：1px 轻阴影 + 10/28 大柔阴影。
拖拽态显示 dashed primary border 和淡 primary overlay。
```

### 7.2 顶部引用区

Web 目标：

```text
rounded-t-[26px]
border-b border-border/30
bg-muted/30
px-4 pb-2 pt-2.5
ContextReferenceTree direction="up"
max-w[min(560px,85%)]
```

iOS 目标：

```text
当附件/知识库/Book/历史/Persona/Memory 引用存在时，在输入卡顶部显示引用带。
引用带背景 muted 30%，底部分割线。
引用树宽度不铺满，长标题提前截断。
```

### 7.3 输入框

Web 目标：

```text
ComposerInput textarea
auto-sized
minHeight: 有消息 28 / 空态 64
max 200
Enter 发送，组合输入保护
支持 slash / @ 弹层
支持 paste / file
```

iOS 目标：

```text
使用自适应高度 TextEditor / UITextView bridge，而不是普通 TextField。
最小高度根据是否有消息变化。
最大高度后内部滚动。
支持 return 发送策略需要考虑中文输入法 composition。
支持粘贴图片/文件的扩展入口。
placeholder 视觉必须与 Web 接近。
```

### 7.4 底部工具栏

Web 目标：

```text
capability selectors
KnowledgeSelector
PersonaSelector
ModelSelector
ContextBudgetChip
voice record button
send/stop button
```

iOS 目标：

```text
不要使用顶部 segmented Picker 作为最终形态。
能力选择应进入输入卡底部 toolbar 的 chip/menu。
模型选择必须接入已有 .chat 模型配置。
语音按钮、附件按钮、引用按钮、发送按钮排列成统一 toolbar。
发送按钮固定 h/w 32，圆形。
streaming 时同一个按钮从 arrow 过渡为 square，并有外圈进度 spinner。
```

---

## 8. 实施拆分

### 阶段 A：列表创建后展示修复

目标文件：

```text
DeepTutorChatPage.swift
DeepTutorChatViewModel.swift
DeepTutorLocalChatStore.swift
DeepTutorChatNotifications.swift
```

任务：

1. 创建成功后乐观插入列表。
2. refresh 后校验 created id 是否存在。
3. 空 preview row 显示占位。
4. 返回列表触发 refresh。
5. 日志增加 create/list 关联字段。

验收：

```text
新建 -> 自动进入 -> 返回列表 -> 新会话第一项可见。
```

### 阶段 B：输入区重做为 DeepTutor-main composer card

目标文件：

```text
DeepTutorComposerView.swift
DeepTutorComposerCardView.swift
DeepTutorComposerToolbarView.swift
DeepTutorComposerTextView.swift
DeepTutorComposerReferenceBandView.swift
```

任务：

1. 外层 26 圆角 card。
2. shadow/border/bg 对齐。
3. 顶部引用区。
4. 自适应输入框。
5. 底部 toolbar。
6. 同一个 send/stop 按钮。
7. 拖拽/附件/粘贴状态预留。

验收：

```text
iOS 输入区截图与 DeepTutor-main composer DOM 对照，结构和视觉层级一致。
```

### 阶段 C：消息气泡视觉对齐

目标文件：

```text
DeepTutorUserBubble.swift
DeepTutorAssistantBubble.swift
DeepTutorMessageRowView.swift
DeepTutorMessageListView.swift
```

任务：

1. 用户气泡 max width / padding / font / badge / shadow 对齐。
2. 编辑态对齐 Web。
3. 助手 actions row 图标化。
4. 删除/重生成/复制/编辑/分支切换齐全。
5. 消息列最大宽度和 spacing 对齐。

验收：

```text
普通 user/assistant 回合截图与 Web 对照通过。
```

### 阶段 D：活动/工具面板对齐

目标文件：

```text
DeepTutorTracePanelView.swift
DeepTutorTraceFormatter.swift
DeepTutorThinkingCardView.swift
DeepTutorToolDetailView.swift
```

任务：

1. Activity header 对齐。
2. 左侧竖线和 trace rows。
3. thinking italic 小字号 markdown。
4. tool row verb + chip。
5. tool detail code block + markdown result。
6. expanded/collapsed 状态保存。

验收：

```text
使用用户提供 DOM 片段对应的工具链路，iOS 展示同等层级、时长、折叠、详情。
```

### 阶段 E：特殊卡片与 inline ask_user 对齐

目标文件：

```text
DeepTutorAskUserCardView.swift
DeepTutorResearchOutlineCardView.swift
DeepTutorQuizCardView.swift
DeepTutorVisualizationPlaceholderView.swift
DeepTutorGeneratedFileCardView.swift
DeepTutorMessageReducer.swift
```

任务：

1. inline ask_user 支持 text/card/text 顺序。
2. research Q&A summary -> outline -> final body 顺序。
3. quiz preface -> quiz card 顺序。
4. visualization/math animator 卡片不降级为普通文本。
5. generated file card 对齐 Web 文件卡。

验收：

```text
DeepTutor-main 每类 AssistantMessage 分支在 iOS 有对应卡片和顺序。
```

---

## 9. 验收用例

### 9.1 新建对话列表展示

```text
Given DeepTutor 对话列表为空
When 点击新建对话
Then 自动进入新对话
When 返回 DeepTutor 列表
Then 列表第一项展示新建对话
And preview 不为空白
And 日志 containsCreated=true
```

### 9.2 输入区视觉对齐

```text
Given 用户进入空对话
When 查看底部输入区
Then 输入区为 26 圆角 card
And 有 card 背景、边框、双层阴影
And 输入高度接近 Web 空态 64
And 底部 toolbar 内有能力、模型、附件、语音、发送按钮
```

### 9.3 用户气泡对齐

```text
Given 用户发送一条多行消息
When 消息展示
Then 气泡右对齐
And 最大宽度约 75%
And badge 在右上方
And padding、圆角、字号、背景与 Web 对齐
```

### 9.4 助手活动面板对齐

```text
Given 助手产生 thinking + web_search + fetch 工具事件
When 消息展示
Then 顶部显示活动 header
And 展开后有左侧竖线
And thinking 为 italic 小字号
And tool row 有 glyph、verb、chip、chevron
And 展开工具详情显示 JSON 参数和 markdown 结果
```

### 9.5 输入区发送/停止按钮

```text
Given 用户输入内容
When 未发送
Then send 按钮显示 arrow up
When 正在 streaming
Then 同一个按钮显示 square
And 外圈 spinner 动画
And 点击后停止生成
```

### 9.6 inline ask_user

```text
Given 模型先输出一段文字，再触发 ask_user，再继续输出文字
When iOS 展示该助手消息
Then 第一段文字在 ask_user 卡片上方
And ask_user 卡片在中间
And 继续输出文字在卡片下方
```

---

## 10. 完成定义

本工单完成必须满足：

1. iOS 新建对话后，列表能稳定展示新会话。
2. iOS DeepTutorChat 主流程与 DeepTutor-main 的页面链路一致。
3. 用户气泡视觉与 Web 对齐。
4. 助手消息卡片和特殊 capability 分支与 Web 对齐。
5. 活动/工具/思考面板与用户提供 DOM 片段对齐。
6. 输入区从系统基础 TextField 改为 DeepTutor-main 风格 composer card。
7. 发送/停止按钮使用同一按钮状态机。
8. 真实截图或录屏对照 DeepTutor-main 通过。
9. 所有未实现能力有明确降级 UI，不静默丢失。
10. 本工单执行过程中不得新增 DeepTutor 专属 AIScenario，继续使用通用 `.chat`。

---

## 11. 风险与待确认项

| 编号 | 风险/待确认项 | 影响 | 关闭条件 |
| --- | --- | --- | --- |
| R1 | 新建对话写库成功但列表刷新找不到 | 用户认为创建失败 | 日志证明 created id 在 refresh 后存在，列表可见 |
| R2 | SwiftUI List + navigationDestination 状态竞争 | 返回列表时空态仍显示 | 改为稳定 selection/path，返回触发 refresh |
| R3 | Web CSS 到 iOS 视觉单位换算 | UI “大概像”但不完全一致 | 建立截图对照表，逐项验收圆角、间距、字号、阴影 |
| R4 | 输入区当前 TextField 能力不足 | 无法实现 auto-size、placeholder、粘贴、composition | 使用 UITextView bridge 或等效自适应输入组件 |
| R5 | Tool trace 事件不足 | 活动面板无法完全还原 | 结合 000003 的真实 AIRuntime event mapper 补齐 |
| R6 | inline ask_user 顺序错误 | Web 对话语义被打乱 | reducer 支持 text/card/text segment 顺序 |
| R7 | 只做卡片外观但流程未对齐 | 验收时仍不像 DeepTutor-main | 必须按流程、状态、刷新、交互、视觉一起验收 |

