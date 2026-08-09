# DEEPTUTORCHAT-000049 消息卡片样式与工具调用折叠配置工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000049 |
| 工单类型 | P1 UI 配置 / 消息卡片样式 / 工具调用折叠 / DeepTutor-main 对齐 |
| 当前范围 | 创建需求工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标渲染入口 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatView/Components/ChatMessageBlock+Render.swift` |
| 目标设置模块 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/AISettings` |
| 对标项目 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main` |
| 创建日期 | 2026-08-09 |
| 触发问题 | 当前 Chat 消息卡片样式和工具调用展示方式较固定；用户希望新增可配置的对话卡片样式，并支持工具调用部分按配置折叠或展开，参考 Web 仅突出正文的阅读体验 |
| 核心目标 | 在设置内提供“对话卡片样式”配置，新增一套正文优先的消息卡片样式；开启折叠后，工具调用过程默认折叠，正文继续独立展示，用户可手动展开查看工具明细 |

## 1. 背景与目标

当前 `ChatMessageBlock+Render.swift` 按 block 类型逐个渲染：

```text
.tool -> ChatToolBlockStreamedPresentationView
.text -> Markdown(text)
其它卡片 -> 对应结构化 View
```

这套结构已经具备“工具块”和“正文块”分离的基础，但展示策略仍偏固定：

1. 工具调用块直接进入消息流，容易挤占正文阅读空间。
2. 工具结果可通过 `ChatToolContentBlockView` 和详情 Sheet 查看，但没有“默认折叠 / 默认展开”的用户配置。
3. 设置内还没有“对话卡片样式”配置入口，用户不能在紧凑、标准、正文优先等风格之间切换。
4. DeepTutor-main Web 的体验更接近“上方过程可折叠，下方正文 article 独立呈现”，用户明确希望参考这种方式。

本工单目标是新增一个可配置的消息卡片呈现能力：

```text
设置 > AI 设置 / 对话外观
  - 对话卡片样式：标准 / 正文优先
  - 工具调用展示：默认折叠 / 默认展开

消息流
  - 工具/思考/调用过程聚合成可折叠区域
  - 正文 Markdown 单独展示
  - 用户可在单条消息内展开工具详情
```

## 2. 当前代码事实

### 2.1 Chat block 渲染入口

真实文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatView/Components/ChatMessageBlock+Render.swift
```

当前关键事实：

1. `.tool` 块统一进入 `ChatToolBlockStreamedPresentationView`。
2. `.text` 块在非数学模式下使用 `Markdown(text).markdownTheme(.chatBubble(...))`。
3. `shouldShowToolResultContent(context:tool:)` 决定流式过程中工具块何时从执行态切到结果态。
4. `ChatPendingPresentationBlockView` 已有轻量的 pending 状态展示，可作为折叠区 loading 行的参考。

### 2.2 工具块展示控制

真实文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatView/Components/ChatToolBlockStreamedPresentationView.swift
```

当前关键事实：

1. 工具执行态最少展示 2 秒，避免一闪而过。
2. 结果态使用 `ChatToolContentBlockView`。
3. 点击工具结果会通过 `context.message.makeToolPreviewPrompt(forToolBlock:)` 打开工具详情。
4. 该组件现在只处理“执行态 / 结果态”，不处理“折叠态 / 展开态”。

### 2.3 消息时间线投影

真实文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatView/Components/ChatMessageBubbleContentView.swift
```

当前关键事实：

1. `ChatMessageBubbleContentView.body` 遍历 `effectiveTimeline`。
2. `ChatMessageTimelineProjector.project(blocks:messageRole:)` 已经负责从 blocks 投影为 timeline node。
3. 单条消息的渲染上下文由 `ChatRenderContext` 汇总传递。

因此折叠策略建议落在“消息级工具区聚合 / timeline node 投影 / render context 配置”一层，而不是每个 `.tool` block 自己孤立决定布局。

### 2.4 AI 设置持久化位置

真实文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/AISettings/Domain/AISettingsSnapshot.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Root/AISettingsView.swift
```

当前关键事实：

1. `AISettingsSnapshot` 已包含本地偏好字段，例如搜索工具、天气工具、场景模型来源、试用模型等。
2. `PreferencesPayload` 负责轻量偏好持久化。
3. `AISettingsView` 已按“模型 / 工具 / 个性化”分组。
4. 新增对话卡片样式更适合放入 AISettings 的偏好载荷，而不是只存在于 Chat View 的临时 `@State`。

### 2.5 DeepTutorChat 已实现的对话卡片样式

真实文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Bubbles/DeepTutorAssistantBubble.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Bubbles/DeepTutorUserBubble.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorPalette.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Rendering/DeepTutorMarkdownRenderer.swift
```

当前 DeepTutorChat 内已经实现了一套独立于通用 Chat 的卡片体系，只能作为“产品形态与交互事实参考”，不能作为 Chat 侧的可复用实现：

1. `DeepTutorAssistantBubble` 按 `DeepTutorMessageBlock` 顺序渲染，不依赖 `ChatMessageBlock+Render.swift`。
2. 助手消息已经区分 `trace`、`thinking`、`text`、`askUser`、`memberSelection`、`captureCard`、`memberProfile`、`researchOutline`、`quiz`、`generatedFile`、`error` 等 block。
3. `DeepTutorMarkdownRenderer` 已统一正文 Markdown 渲染，并使用 `.markdownTheme(.chatBubble(foreground: .primary))`。
4. `DeepTutorPalette` 已定义 Web 到 iOS 的视觉换算常量：
   - `bubbleCornerRadius = 18`
   - `cardCornerRadius = 16`
   - `bodyFontSize = 14`
   - `captionFontSize = 11`
   - `traceBodyFontSize = 11`
   - `traceDetailFontSize = 11.5`
   - `bubbleHorizontalPadding = 16`
   - `bubbleVerticalPadding = 10`
5. `DeepTutorPalette` 已有 `deepTutorBubbleShadow()`、`deepTutorAskUserCardShadow()`，可作为“正文优先”样式的阴影与层级参考。

因此，本工单必须把两套对话系统完全隔离：

```text
DeepTutorChat 已有实现
  -> 只作为 DeepTutorChat 自己的实现事实和体验参考
  -> 不抽象成 Chat / DeepTutorChat 共用组件
  -> 不把 DeepTutorTracePanelView、DeepTutorTraceBlockPayload、DeepTutorPalette 迁移给 Chat 使用

Chat 侧目标实现
  -> 在 Chat 自己目录下另起 Chat 专属类型与 View
  -> 使用 ChatMessageBlock / ChatRenderContext / ToolPreviewPrompt
  -> 不 import DeepTutorChat Presentation / Domain 类型
```

### 2.6 DeepTutorChat 已实现的工具过程折叠与思考时间

真实文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Cards/DeepTutorTracePanelView.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorTraceFormatter.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Domain/DeepTutorMessageBlock.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorMessageReducer.swift
```

当前 DeepTutorChat 的 trace 已经具备本工单所需的大部分交互语义：

1. `DeepTutorTraceBlockPayload` 已包含：
   - `title`
   - `rows`
   - `isExpanded`
   - `isStreaming`
   - `isFinalAnswerPhase`
   - `elapsedSeconds`
2. `DeepTutorTracePanelView.effectiveExpanded` 当前规则是：

```text
userPinnedExpansion ?? !payload.isFinalAnswerPhase
```

即：用户未手动固定时，最终回答阶段前默认展开，进入最终回答阶段后自动折叠。

3. `DeepTutorTracePanelView` 已实现：
   - 顶部状态按钮
   - 流式时使用 `DeepTutorReasoningGlyph`
   - 完成后使用 `DeepTutorRespondedGlyph`
   - `chevron.down` 旋转表示展开 / 折叠
   - 每个工具行可二级展开
   - 点击工具名打开 `DeepTutorToolPreviewPrompt`
4. `DeepTutorTraceFormatter.formatDuration(_:)` 已把 `elapsedSeconds` 格式化为：

```text
· 12s
· 1m 08s
```

5. `DeepTutorTraceFormatter.tracePayload(...)` 已按事件计算标题：

```text
streaming + running tool/askUser -> 调用工具中…
streaming + no running tool      -> DeepTutor 推理中…
finished + has failure           -> 失败
finished                         -> 已完成
```

6. `DeepTutorMessageReducer.blocks(for:)` 已保证 assistant 消息中 trace block 在正文 block 之前生成：

```text
trace block
inline text / thinking / askUser / memberSelection...
capability-specific cards
```

这与 Web “过程区在正文上方，正文独立展示”的结构一致。

### 2.7 当前缺口：已有实现还没有变成可配置能力

DeepTutorChat 现状更像“固定的正文优先样式”，但还缺少设置驱动：

| 能力 | DeepTutorChat 当前状态 | 本工单目标 |
| --- | --- | --- |
| 正文优先布局 | 已具备：trace 在正文前，正文独立 Markdown | DeepTutorChat 内部接入可配置样式；Chat 另起一套 |
| 工具过程折叠 | 已具备：最终回答阶段自动折叠 | 接入设置项：展开 / 完成后折叠 / 始终折叠 |
| 思考时间展示 | 已具备：`elapsedSeconds` + `formatDuration` | 明确计算口径，避免只是事件数估算 |
| 工具二级展开 | 已具备：`expandedToolIDs` | Chat 侧独立实现同等交互，不复用 DeepTutorChat 类型 |
| 单条消息手动展开状态 | 已具备：`userPinnedExpansion` | 保持消息级临时状态，不入库 |
| 全局用户偏好 | 未接入 | DeepTutorChat 与 Chat 使用各自独立偏好字段，禁止共用状态键 |

## 3. Web 对齐基准

### 3.1 用户提供的 Web 片段结论

用户提供的 HTML 片段表现为：

```text
助手活动状态行：已完成 · 12s
  - 工具/思考/命令等过程行位于可折叠区域
  - 单个工具行支持二级展开
  - 正文 article 单独渲染，显示 Markdown 表格和段落
  - 底部操作区显示复制、朗读、重新生成、删除、token/调用次数
```

对 iOS 的可参考语义不是 CSS，而是信息架构：

1. 工具调用过程不应抢正文主视觉。
2. 完成后默认可折叠，只展示状态摘要。
3. 正文作为主内容独立展示。
4. 用户需要时可展开过程明细。
5. 工具调用次数、耗时、状态可作为折叠标题摘要。

### 3.2 DeepTutor-main 真实代码证据

Web 参考文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/TracePanels.tsx
```

关键事实：

1. `TraceFlow` 渲染 inline trace rows。
2. `AssistantActivity` 负责外层状态头部和折叠：
   - 流式过程中默认展开。
   - 进入最终回答阶段后自动折叠。
   - 用户点击后可手动固定展开或折叠。
3. 折叠动画使用行高和透明度过渡。
4. 注释明确：trace rows 没有外层 trace card，而是嵌在 status header 下方。

Web 参考文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ChatMessages.tsx
```

关键事实：

1. Web 消息渲染先展示 trace/activity，再展示 message body。
2. 工具结果、agent loop 中间过程不会混进最终正文。
3. 正文按 Markdown / article 方式独立渲染。

## 4. 产品需求

### 4.1 新增设置项

在设置内新增“对话卡片样式”配置入口，但必须拆成 Chat 与 DeepTutorChat 两套独立配置。页面可以同在 AI 设置内展示，底层字段、存储 key、ViewModel 输入必须完全分开。

```text
设置
└── AI 设置
    ├── Chat 对话外观
    │   ├── 对话卡片样式
    │   │   ├── 标准
    │   │   └── 正文优先
    │   └── 工具调用展示
    │       ├── 默认折叠
    │       └── 默认展开
    └── DeepTutorChat 对话外观
        ├── 对话卡片样式
        │   ├── 标准
        │   └── 正文优先
        └── 工具调用展示
            ├── 默认折叠
            └── 默认展开
```

字段建议：

| 字段 | 所属 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- | --- |
| `chatConversationAppearance.cardStyle` | Chat | enum | `standard` | Chat 专属对话卡片样式 |
| `chatConversationAppearance.toolTraceDisplayMode` | Chat | enum | `collapsedAfterCompletion` | Chat 专属工具调用区域展示方式 |
| `chatConversationAppearance.collapseToolsWhileStreaming` | Chat | Bool | `false` | Chat 流式过程中是否也折叠工具过程 |
| `deepTutorConversationAppearance.cardStyle` | DeepTutorChat | enum | `bodyFocused` | DeepTutorChat 专属对话卡片样式，默认保持现有正文优先体验 |
| `deepTutorConversationAppearance.toolTraceDisplayMode` | DeepTutorChat | enum | `collapsedAfterCompletion` | DeepTutorChat 专属工具调用区域展示方式 |
| `deepTutorConversationAppearance.collapseToolsWhileStreaming` | DeepTutorChat | Bool | `false` | DeepTutorChat 流式过程中是否也折叠工具过程 |

禁止字段：

```text
conversationCardStyle                         # 禁止：无归属，会导致两套对话共用
toolTraceDisplayMode                          # 禁止：无归属，会导致两套对话共用
collapseToolsWhileStreaming                   # 禁止：无归属，会导致两套对话共用
```

枚举建议：

```text
ChatConversationCardStyle
  - standard：沿用当前消息气泡布局
  - bodyFocused：正文优先；工具/过程区弱化并可折叠

ChatToolTraceDisplayMode
  - expanded：默认展开
  - collapsedAfterCompletion：流式展开，完成后折叠
  - collapsedAlways：默认折叠，流式过程也只显示摘要

DeepTutorConversationCardStyle
  - standard：沿用当前 DeepTutorChat 消息布局
  - bodyFocused：正文优先；工具/过程区弱化并可折叠

DeepTutorToolTraceDisplayMode
  - expanded：默认展开
  - collapsedAfterCompletion：流式展开，完成后折叠
  - collapsedAlways：默认折叠，流式过程也只显示摘要
```

### 4.2 新卡片样式：正文优先

正文优先样式目标：

1. 助手正文保持最高层级。
2. 工具调用、思考、命令、检索等过程统一进入“过程区”。
3. 过程区在正文上方，标题显示状态摘要：

```text
已完成 · 12s · 3 次调用
正在查询资料 · 2 次调用
已折叠工具过程 · 点击展开
```

4. 正文仍由 `.text` block 负责，不把工具 JSON 或中间日志拼到正文里。
5. 工具详情仍可点开 `ToolPreviewSheet`，保留现有详情能力。

### 4.3 工具调用折叠规则

| 场景 | `expanded` | `collapsedAfterCompletion` | `collapsedAlways` |
| --- | --- | --- | --- |
| 正在流式调用工具 | 展开工具过程 | 展开工具过程 | 只显示摘要 |
| 工具完成但正文未开始 | 展开工具过程 | 可保持展开，直到正文出现 | 只显示摘要 |
| 正文已出现 / turn 完成 | 展开工具过程 | 自动折叠 | 只显示摘要 |
| 用户手动展开 | 展开并记住当前消息状态 | 展开并记住当前消息状态 | 展开并记住当前消息状态 |
| 新消息进入下一轮 | 按全局配置重新计算 | 按全局配置重新计算 | 按全局配置重新计算 |

用户手动展开/折叠是消息级临时状态，不需要入库。全局配置需要按账号持久化。

### 4.4 不改变内容事实源

本工单不要求改变后端协议、工具执行协议或消息落库结构。

必须保持：

1. `ChatMessage.blocks` 仍是内容事实源。
2. `.tool` block 仍保留 tool name、content、invocationArguments、toolCallID。
3. `.text` block 仍是最终正文事实源。
4. 工具详情 Sheet 继续通过 `makeToolPreviewPrompt(forToolBlock:)` 构造。
5. 折叠只是 Presentation 策略，不得删除或吞掉工具数据。

## 5. 推荐实现拆分

### 5.1 设置域

建议新增或修改：

```text
SparkClient/Projects/Features/AISettings/Domain/AISettingsDomainModels.swift
SparkClient/Projects/Features/AISettings/Domain/AISettingsSnapshot.swift
SparkClient/Projects/Features/AISettings/Infrastructure/DefaultAISettingsRepository.swift
SparkClient/Projects/Features/AISettings/Presentation/Root/AISettingsView.swift
SparkClient/Projects/Features/AISettings/Presentation/Preferences/ChatConversationAppearanceSettingsView.swift
SparkClient/Projects/Features/AISettings/Presentation/Preferences/DeepTutorConversationAppearanceSettingsView.swift
```

建议新增模型：

```swift
enum ChatConversationCardStyle: String, Codable, CaseIterable, Sendable {
    case standard
    case bodyFocused
}

enum ChatToolTraceDisplayMode: String, Codable, CaseIterable, Sendable {
    case expanded
    case collapsedAfterCompletion
    case collapsedAlways
}

struct ChatConversationAppearancePreferences: Codable, Equatable, Sendable {
    var cardStyle: ChatConversationCardStyle
    var toolTraceDisplayMode: ChatToolTraceDisplayMode
    var collapseToolsWhileStreaming: Bool
}

enum DeepTutorConversationCardStyle: String, Codable, CaseIterable, Sendable {
    case standard
    case bodyFocused
}

enum DeepTutorToolTraceDisplayMode: String, Codable, CaseIterable, Sendable {
    case expanded
    case collapsedAfterCompletion
    case collapsedAlways
}

struct DeepTutorConversationAppearancePreferences: Codable, Equatable, Sendable {
    var cardStyle: DeepTutorConversationCardStyle
    var toolTraceDisplayMode: DeepTutorToolTraceDisplayMode
    var collapseToolsWhileStreaming: Bool
}
```

注意：以上为字段设计建议，不是本工单已实现代码。禁止用一个 `AIConversationAppearancePreferences` 同时承载 Chat 与 DeepTutorChat；也禁止共用同一组 `ConversationCardStyle` / `ToolTraceDisplayMode` enum。

### 5.2 Chat 渲染上下文

建议修改：

```text
SparkClient/Projects/Features/Chat/Presentation/ChatView/Components/ChatRenderContext.swift
SparkClient/Projects/Features/Chat/Presentation/ChatView/Components/ChatMessageBubbleContentView.swift
```

将 Chat 专属设置态从页面上层注入到 `ChatRenderContext`，避免子 View 自行访问全局单例。

建议字段：

```text
chatConversationCardStyle
chatToolTraceDisplayMode
chatCollapseToolsWhileStreaming
```

### 5.3 Timeline 聚合与折叠区

建议新增：

```text
SparkClient/Projects/Features/Chat/Presentation/ChatView/Components/ChatToolTraceDisclosureView.swift
SparkClient/Projects/Features/Chat/Presentation/ChatView/Components/ChatMessageToolTraceProjector.swift
```

职责：

1. 从单条消息 blocks 中收集 `.tool`、`.deepThought`、可归类为过程的 pending block。
2. 计算摘要：状态、耗时、工具调用次数、最后一个工具名。
3. 根据配置和消息 deliveryState 决定默认展开状态。
4. 展开时使用 Chat 侧自己的 `ChatMessageBlock` 渲染链，可调用 Chat 目录内现有 `toolBlock.render(context:)` 或 `ChatToolBlockStreamedPresentationView`；禁止引用 DeepTutorChat 的 trace/card 组件。
5. 折叠时只显示一行摘要，不渲染大段 tool content。

### 5.4 保持正文 block 独立

`ChatMessageBlock+Render.swift` 中 `.text` 分支不应被工具折叠逻辑污染。

正文优先样式应在更高一层改变 block 组合方式：

```text
消息级布局
  1. 工具/思考过程折叠区
  2. 正文 Markdown
  3. 结构化业务卡片
  4. 操作按钮
```

不要在 `.text` 分支内判断工具折叠，也不要把工具结果拼接进 Markdown。

### 5.5 DeepTutorChat 侧落地方式

DeepTutorChat 已有固定的正文优先实现，因此落地时应做“配置接入”，不是重写 UI。

建议修改：

```text
SparkClient/Projects/Features/DeepTutorChat/Presentation/Bubbles/DeepTutorAssistantBubble.swift
SparkClient/Projects/Features/DeepTutorChat/Presentation/Cards/DeepTutorTracePanelView.swift
SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorTraceFormatter.swift
SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorMessageReducer.swift
SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorChatPage.swift
```

建议新增 DeepTutorChat 专属轻量配置模型，放在 DeepTutorChat 的 Presentation 或 Domain 内；禁止为了 Chat 共用而上提到共享 UI 层：

```swift
struct DeepTutorConversationCardAppearance: Equatable, Sendable {
    var cardStyle: DeepTutorConversationCardStyle
    var toolTraceDisplayMode: DeepTutorToolTraceDisplayMode
    var collapseToolsWhileStreaming: Bool
}
```

DeepTutorChat 接入建议：

1. `DeepTutorChatPage` 从 AISettings / 本地设置读取 `DeepTutorConversationCardAppearance`。
2. `DeepTutorMessageRowView` 或 `DeepTutorAssistantBubble` 透传配置。
3. `DeepTutorTracePanelView` 增加 `displayMode` / `collapseToolsWhileStreaming` 入参。
4. 保留现有 `userPinnedExpansion`，用户手动操作优先级最高。
5. `DeepTutorTraceFormatter` 继续负责生成 `title`、`rows`、`elapsedSeconds`、`isFinalAnswerPhase`。
6. `DeepTutorTracePanelView` 只负责把配置转换为默认展开状态。

默认展开策略建议从当前：

```text
userPinnedExpansion ?? !payload.isFinalAnswerPhase
```

升级为：

```text
if userPinnedExpansion != nil:
  return userPinnedExpansion

switch displayMode:
  expanded:
    return true
  collapsedAlways:
    return false
  collapsedAfterCompletion:
    if payload.isStreaming && collapseToolsWhileStreaming == false:
      return true
    return !payload.isFinalAnswerPhase
```

注意：`payload.isExpanded` 当前在 payload 里存在，但 `DeepTutorTracePanelView` 实际使用 `userPinnedExpansion ?? !payload.isFinalAnswerPhase`。本工单落地时要二选一收口：

1. 要么让 View 完全以配置 + `isFinalAnswerPhase` 计算，不依赖 payload 的 `isExpanded`。
2. 要么让 reducer 计算后的 `payload.isExpanded` 成为默认态，View 只叠加用户手动固定。

建议选择方案 1，减少持久化字段和临时 UI 状态之间的冲突。

### 5.6 思考时间与工具耗时落地细节

当前 `DeepTutorTraceFormatter` 的 `elapsedSeconds` 来源是：

```text
previous?.elapsedSeconds ?? estimatedDuration(from: events)
```

其中 `estimatedDuration(from:)` 只是按事件数量估算：

```text
max(1, Double(events.count) * 0.4)
```

这能先显示一个近似时长，但不应作为最终口径。正式落地需要把“思考时间”和“工具耗时”拆开：

| 指标 | 展示位置 | 推荐来源 | 说明 |
| --- | --- | --- | --- |
| 本轮总耗时 | trace header：`已完成 · 12s` | turn 开始时间到 ready / failed 时间 | 代表用户感知等待时间 |
| 当前流式耗时 | trace header：`推理中… · 8s` | turn 开始时间到当前 Date | 流式过程中每秒或随事件刷新 |
| 工具单次耗时 | 工具详情 / 二级展开 | `toolCallStarted` 到 `toolResult` | 可选，首期可不在行内展示 |
| 思考文本耗时 | thinking 行 / 详情 | reasoningDelta 第一条到 final answer phase | 不等于模型真实思考，只是客户端接收推理片段时长 |

建议补齐字段：

```text
DeepTutorTraceBlockPayload
  - elapsedSeconds: Double?             # 本轮总耗时或当前耗时
  - startedAt: Date?                    # 可选，若要运行时精确刷新
  - completedAt: Date?                  # 可选，ready/failed 后冻结

DeepTutorTraceRowModel
  - durationSeconds: Double?            # 已存在字段，建议正式写入工具耗时
```

事件侧推荐在生成 `DeepTutorStreamEvent` 时记录时间戳，或在 adapter/reducer 中维护 `toolCallID -> startedAt`：

```text
turnStartedAt = first event received time / send action time
toolStartedAt[toolCallID] = toolCallStarted time
toolDuration = toolResult time - toolStartedAt[toolCallID]
turnElapsed = now - turnStartedAt
```

如果事件模型暂时没有时间戳，首期可采用降级方案：

1. 流式中使用 ViewModel 记录的本地 turn start time。
2. ready / failed 时冻结 `elapsedSeconds`。
3. 历史消息缺少耗时时，继续用 `estimatedDuration(from:)` 兜底，但标题不应伪装为精确值；可只显示“已完成”，不显示秒数。

### 5.7 标题与状态文案规则

建议统一标题格式：

| 状态 | 标题 | 时长 | 调用次数 |
| --- | --- | --- | --- |
| 无工具，仅推理 | `DeepTutor 推理中…` | 可显示 | 不显示 |
| 工具运行中 | `调用工具中…` | 可显示 | `· 2 次调用` |
| 等待用户输入 | `等待你的回复` | 可显示 | 可显示 |
| 最终回答阶段 | `已完成` | 显示冻结耗时 | 可显示 |
| 失败 | `失败` | 显示冻结耗时 | 可显示 |

折叠 header 建议组合：

```text
已完成 · 12s · 3 次调用
调用工具中… · 8s · 2 次调用
等待你的回复 · 6s
失败 · 4s · 1 次调用
```

调用次数计算：

```text
payload.rows.filter { row.kind == .tool || row.kind == .askUser }.count
```

不要把纯 thinking 行计入工具调用次数。

### 5.8 Chat 与 DeepTutorChat 完全堵路

本工单必须明确：Chat 与 DeepTutorChat 是两套实现，互相不能复用类型、View、状态模型、设置键和渲染组件。DeepTutorChat 可以作为产品交互参考，但 Chat 侧必须在自己的模块内独立实现。

禁止关系：

```text
Chat 不允许 import DeepTutorChat
DeepTutorChat 不允许 import Chat 的消息渲染组件
Chat 不允许使用 DeepTutorTraceBlockPayload / DeepTutorTraceRowModel
Chat 不允许使用 DeepTutorTracePanelView / DeepTutorThinkingCardView
Chat 不允许使用 DeepTutorPalette 作为运行时依赖
Chat 与 DeepTutorChat 不共用 UserDefaults key / AISettings 偏好字段
```

允许关系：

```text
需求文档可引用 DeepTutorChat 的现有体验作为参考
设计值可人工对齐，例如字号、间距、折叠策略
两套实现可以有同名概念，但类型名、文件路径、状态存储必须分开
```

两套实现边界：

| 领域 | DeepTutorChat | Chat |
| --- | --- |
| 消息模型 | `DeepTutorMessageBlock` | `ChatMessageBlock` |
| trace payload | `DeepTutorTraceBlockPayload` | `ChatToolTracePresentationModel`，Chat 专属新增 |
| trace row | `DeepTutorTraceRowModel` | `ChatToolTraceRowModel`，Chat 专属新增 |
| formatter | `DeepTutorTraceFormatter` | `ChatToolTraceFormatter`，Chat 专属新增 |
| 折叠 View | `DeepTutorTracePanelView` | `ChatToolTraceDisclosureView`，Chat 专属新增 |
| 工具详情 | `DeepTutorToolPreviewPrompt` | `ToolPreviewPrompt` |
| 正文渲染 | `DeepTutorMarkdownRenderer` | `Markdown(...).markdownTheme(.chatBubble)` |
| 设置字段 | `deepTutorConversationAppearance` | `chatConversationAppearance` |
| 存储键 | `deeptutor.*` | `chat.*` |

Chat 侧首期独立支持：

1. `.tool` block 聚合为 row。
2. `ChatToolRuntimeAttachmentBuilder.localizedDisplayName(for:)` 作为工具名。
3. `ChatToolRuntimeAttachmentBuilder.makeOperationalMeta(...)` 作为运行态摘要。
4. 已完成工具点击后继续打开现有 `ToolPreviewSheet`。
5. `.text` 正文继续独立渲染。
6. 所有新增文件放在 `SparkClient/Projects/Features/Chat/Presentation/ChatView/Components/` 或 Chat 自己的 Domain/Application 目录，不放入 DeepTutorChat。

## 6. 页面 Plain Text 草图

### 6.1 设置页

```text
AI 设置

模型
  API Keys                         >
  模型管理                         >
  默认模型配置                     >

工具
  小任务                           >
  搜索工具                         >
  天气查询                         >

对话外观
  对话卡片样式                     正文优先 >
  工具调用展示                     完成后折叠 >
  流式过程也折叠                   [ off ]

个性化
  提示词库                         >
  记忆归档                         >
```

### 6.2 正文优先消息卡片：完成后折叠

```text
┌──────────────────────────────────────────┐
│ 已完成 · 12s · 3 次调用                 v │
│                                          │
│ 上海今日天气                             │
│                                          │
│ | 项目 | 数据 |                          │
│ | 天气 | 晴朗 |                          │
│ | 温度 | 34°C |                          │
│                                          │
│ 今天上海天气晴好，建议注意防晒、多补水。 │
│                                          │
│ [复制] [朗读] [重新生成]          tokens │
└──────────────────────────────────────────┘
```

### 6.3 用户展开工具过程后

```text
┌──────────────────────────────────────────┐
│ 已完成 · 12s · 3 次调用                 ^ │
│ │ 我将询问用户所在城市。                  │
│ │ 向你提问                               >│
│ │ 已选定上海，将查询当地天气。            │
│ │ 运行命令 curl ...                      >│
│ │ 上海今日天气数据已获取。                │
│                                          │
│ 上海今日天气                             │
│ ...                                      │
└──────────────────────────────────────────┘
```

## 7. 验收标准

### 7.1 设置验收

1. 设置内出现“对话外观”入口或分组。
2. 可选择“标准 / 正文优先”。
3. 可选择“默认展开 / 完成后折叠 / 始终折叠”。
4. 设置保存后重启 App 仍生效。
5. 按账号隔离，不串到其他账号。

### 7.2 消息渲染验收

1. 标准样式下，现有消息渲染不回退。
2. 正文优先样式下，工具调用区域位于正文上方并可折叠。
3. `collapsedAfterCompletion` 下，流式过程默认展开，最终正文出现后工具区自动折叠。
4. `collapsedAlways` 下，工具区默认只显示摘要，用户点击后可展开。
5. 展开工具区后，原有工具详情入口仍可打开。
6. `.text` Markdown 表格、标题、段落仍正常渲染。
7. 结构化业务卡片不被错误折叠到工具区，例如成员选择卡、健康资料引用卡、任务卡等仍按业务卡片展示。

### 7.3 DeepTutorChat 对齐验收

1. DeepTutorChat 默认视觉不回退，`DeepTutorAssistantBubble` 中 `trace -> text -> 业务卡片 -> actionsRow` 的顺序保持稳定。
2. `DeepTutorTracePanelView` 在 `collapsedAfterCompletion` 下继续保持：流式中展开，最终回答阶段自动折叠。
3. 用户手动展开 / 折叠优先于全局配置，切换消息或新消息时不串状态。
4. `DeepTutorThinkingCardView` 的思考文本仍保持小字号、斜体、弱化展示，不抢正文层级。
5. `DeepTutorTraceFormatter.formatDuration` 仍只在有有效耗时时显示；历史消息没有可靠耗时时不强行显示伪精确秒数。
6. trace header 能显示“已完成 / 调用工具中 / 失败 / 等待你的回复”等状态，并能附加耗时和工具调用次数。
7. 单个工具行二级展开仍可查看参数和结果，点击工具名仍打开 `DeepTutorToolPreviewPrompt` 详情。

### 7.4 回归验收

1. 发送普通纯文本对话，没有工具调用时不出现空折叠区。
2. 工具调用失败时，折叠标题能显示失败状态，展开后能看到错误或详情入口。
3. 多个工具连续调用时摘要计数正确。
4. 流式中工具 pending 至少展示策略不被破坏。
5. 长工具结果默认折叠时不造成消息 cell 高度异常跳动。
6. VoiceOver 能读出折叠按钮状态，例如“工具调用，已折叠，3 次调用”。
7. DeepTutorChat 与 Chat 两套消息模型不互相污染：DeepTutor 继续使用 `DeepTutorMessageBlock`，Chat 继续使用 `ChatMessageBlock`。
8. 代码检索验收：Chat 新增文件不得出现 `DeepTutorTracePanelView`、`DeepTutorTraceBlockPayload`、`DeepTutorTraceRowModel`、`DeepTutorPalette`、`DeepTutorMarkdownRenderer` 等 DeepTutorChat 类型引用。
9. 代码检索验收：DeepTutorChat 新增文件不得引用 Chat 侧新增的 `ChatToolTraceDisclosureView`、`ChatToolTracePresentationModel`、`ChatToolTraceFormatter` 等 Chat 专属类型。

## 8. 非目标

1. 不重构 `ChatMessage` / `ChatMessageBlock` 数据模型。
2. 不改变工具调用协议和 AI Runtime。
3. 不在本工单内重做 DeepTutorChat 专属消息卡片。
4. 不把 Web 的 CSS、DOM、Tailwind class 原样迁移到 SwiftUI。
5. 不把工具过程永久隐藏；用户必须能展开查看。

## 9. 风险与待确认项

| 风险 / 待确认项 | 说明 | 建议 |
| --- | --- | --- |
| 设置入口归属 | Chat 与 DeepTutorChat 都可能需要“对话卡片样式”，但不能共用字段 | 可以同在 AI 设置页面展示，但必须拆成 `Chat 对话外观` 与 `DeepTutorChat 对话外观` 两个独立配置组 |
| Chat 与 DeepTutorChat 是否共用 | 用户已明确要求完全堵路，两套实现 | 禁止共用类型、View、Formatter、Palette、UserDefaults key、AISettings payload 字段；文档中的 DeepTutorChat 只作为参考证据 |
| Timeline 投影复杂度 | 如果直接在每个 block render 内折叠，会难以形成消息级摘要 | 推荐在消息级 projector 聚合工具过程 |
| 自动折叠时机 | “正文出现后折叠”需要判断最终回答阶段 | 可先用 `message.deliveryState != .sending` 和存在 `.text` block 作为近似，后续再细化 |
| 业务卡误折叠 | 一些工具副作用会产出健康资料卡、成员选择卡 | 只折叠 `.tool` 和明确 trace/pending 类型，不折叠业务卡 |
| 无障碍 | 折叠按钮如果只有图标会难以理解 | 必须提供 `accessibilityLabel`、`accessibilityValue` 和足够点击区域 |

## 10. 建议实施顺序

1. 先确认本次实现目标端：只做 Chat，或只做 DeepTutorChat；不得一个 PR 同时抽公共层。
2. 如果做 Chat：新增 `chatConversationAppearance` 独立偏好字段和持久化 key。
3. 如果做 Chat：在 `AISettingsView` 增加 `Chat 对话外观` 设置入口。
4. 如果做 Chat：将 Chat 偏好注入 Chat 页面和 `ChatRenderContext`。
5. 如果做 Chat：新增 `ChatToolTraceDisclosureView`、`ChatToolTracePresentationModel`、`ChatToolTraceFormatter`，先仅承接 `.tool` block。
6. 如果做 Chat：在 `ChatMessageBubbleContentView` 或 Chat timeline projector 中按配置聚合工具块。
7. 如果做 DeepTutorChat：新增 `deepTutorConversationAppearance` 独立偏好字段和持久化 key。
8. 如果做 DeepTutorChat：只修改 DeepTutorChat 自己的 `DeepTutorTracePanelView` / `DeepTutorAssistantBubble` 配置接入，不触碰 Chat 组件。
9. 验证标准样式完全不变。
10. 开启正文优先样式，验证工具区折叠、正文展示、详情 Sheet、流式状态。
11. 补充单元测试或快照测试：偏好持久化、折叠策略、无工具消息不出现空区、两套类型互不引用。
