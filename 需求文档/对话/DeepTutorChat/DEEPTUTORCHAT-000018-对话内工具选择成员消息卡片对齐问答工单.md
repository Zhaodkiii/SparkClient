# DEEPTUTORCHAT-000018 对话内工具选择成员消息卡片对齐问答工单

## 1. 工单背景

DeepTutorChat 当前已经接入项目通用 AI Runtime，并通过 `DeepTutorPromptBuilder -> DeepTutorRuntimeRequestBuilder -> DeepTutorToolPolicyResolver -> ChatOrchestrator -> ToolHub -> runtimeService.generateTextStream(toolChoice=.auto)` 使用项目内已有工具体系。

现在需要补齐一个关键体验：

当 DeepTutorChat 对话内的工具调用需要确认“使用哪个家庭成员/就诊人档案”时，不能让 AI 直接裸露工具过程，也不能只依赖问答侧已有的统一 sheet。DeepTutorChat 应该复用项目中同一个成员选择工具 `request_member_selection`，但在 DeepTutorChat 的消息流里，以消息卡片形式展示“选择成员”，并在用户选择后继续当前同一轮 AI 工具调用。

目标是对齐：

- DeepTutor Web 的消息内交互卡片思路：工具需要用户补充信息时，在会话消息流中出现卡片，用户提交后继续当前 turn。
- SparkClient 现有问答 Chat 的成员选择能力：继续复用 `ToolHub`、`request_member_selection`、成员上下文、成员绑定和工具返回语义。
- DeepTutorChat 当前消息架构：`页面容器 -> 状态 -> 消息列表 -> 单条气泡 -> 内容 block 渲染`，不要临时绕过消息模型。

本工单只描述需求、差距、关键代码位置、实现方案和验收标准，不直接改动代码。

## 2. 当前问题

### 2.1 DeepTutorChat 缺少消息内“选择成员”卡片

当前 DeepTutorChat 已经有 AskUser 提问卡片：

- `DeepTutorAskUserCardView`
- `DeepTutorMessageBlockKind.askUser`
- `DeepTutorMessageReducer`
- `DeepTutorAIRuntimeEventMapper`
- `DeepTutorAskUserResumeBuilder`
- `DeepTutorChatViewModel.submitAskUser`

但成员选择工具是另一类业务交互，当前 DeepTutorChat 没有对应的：

- `DeepTutorMemberSelectionCardView`
- `DeepTutorMessageBlockKind.memberSelection`
- `DeepTutorMemberSelectionBlockPayload`
- `DeepTutorMemberSelectionResumeBuilder`
- `DeepTutorChatViewModel.submitMemberSelection`
- 会话级 `memberID` 绑定与持久化
- 工具调用等待期间的消息 block 创建、更新、恢复

结果是：工具需要成员时，DeepTutorChat 不能像 DeepTutor Web 一样在消息内自然展示“选择成员”卡片。

### 2.2 问答 Chat 已有工具，但展示方式偏 sheet，不适合 DeepTutorChat

问答 Chat 已经具备通用工具：

```text
request_member_selection
```

这个工具应该继续复用，不能在 DeepTutorChat 里另起一套“假工具”或把成员选择改成普通 ask_user。

但问答 Chat 目前的主交互是：

```text
ToolHubRequestMemberSelection
-> ToolInteractionCoordinator.requestMemberSelection(...)
-> activePresentation
-> ToolInteractionPresentationSheet / 成员选择 sheet
-> complete
-> ToolExecutionResult
```

DeepTutorChat 需要的主交互是：

```text
ToolHubRequestMemberSelection
-> DeepTutorChat 工具交互适配层
-> 当前 assistant message 插入 member_selection block
-> DeepTutorMemberSelectionCardView 展示成员列表
-> 用户在消息卡片里选择成员
-> 更新卡片状态并绑定会话 memberID
-> complete pending continuation
-> ToolExecutionResult 返回给 ToolHub
-> AI 继续同一轮回答
```

也就是说，工具仍然是同一个工具，差异只发生在 DeepTutorChat 的 presentation adapter 和消息 block 映射层。

### 2.3 DeepTutorChat 工具上下文未携带成员状态

当前 DeepTutorChat 构建运行时请求时，已经有工具挂载上下文：

```text
DeepTutorToolMountContext.default(...)
DeepTutorToolPolicyResolver.resolve(...)
ChatOrchestratorInferenceOptions(useTools: ..., allowedToolNames: ...)
```

但 DeepTutorChat 里成员状态还没有完整贯穿：

- 会话是否已绑定 `memberID`
- 当前工具执行上下文是否已有 `memberID`
- `DeepTutorToolMountContext.hasSelectedMember` 是否真实反映状态
- `ToolExecutionContext.memberID` 是否传给 ToolHub
- 成员选择完成后是否写回本地数据库
- 后续 health/member 工具是否能直接使用已选择成员

如果这些缺失，AI 会反复触发成员选择，或者工具明明已经选择成员但下一步仍然拿不到 `memberID`。

### 2.4 如果只弹 sheet，会破坏 DeepTutorChat 消息流一致性

DeepTutorChat 已经在努力对齐 DeepTutor Web 的工具思考、AskUser、QuickCheck 和消息卡片。

成员选择如果只弹 sheet，会带来几个偏差：

- 工具交互不在消息时间线里，用户回看时不知道当时选择了谁。
- 刷新/重载后无法从消息中恢复选择状态。
- 多轮工具调用时，sheet 和消息列表状态容易分离。
- 调试日志里只有工具结果，没有可见的消息 block 生命周期。
- 与 DeepTutor Web 的“工具需要用户补充信息 -> 消息内卡片 -> 提交后继续”不一致。

## 3. 目标

### 3.1 功能目标

DeepTutorChat 在对话内使用需要成员的工具时，应支持：

1. 复用项目已有 `request_member_selection` 工具。
2. 参考问答 Chat 的成员选择能力和成员绑定逻辑。
3. 在 DeepTutorChat 的助手消息气泡内展示“选择成员”消息卡片。
4. 用户选择成员后，卡片状态更新为已完成。
5. 选择结果写入会话本地数据库，后续本会话默认使用该成员。
6. 选择结果回传 ToolHub，当前 AI turn 继续执行，不需要用户重新发送问题。
7. 刷新/重载后已完成卡片仍可展示选择结果。
8. 如果会话已绑定成员，则工具应直接返回 `already_resolved`，不重复弹卡片。
9. 如果没有成员档案，卡片展示空状态，并给出可恢复路径。
10. 所有关键阶段有日志，便于定位工具选择、UI 刷新、恢复失败和重复弹出问题。

### 3.2 体验目标

对齐 DeepTutor Web 的消息卡片体验：

- 卡片出现在助手消息中，而不是脱离对话上下文。
- 卡片位置跟随工具调用 trace，不跳屏、不重复。
- 工具思考区只展示整理后的工具阶段，不把模型内部裸推理直接作为正式正文输出。
- 用户选择成员后，卡片就地变为完成态。
- AI 继续生成正式回答时，思考/工具调用区可自动收起。
- 选择成员动作不打开键盘。
- 不出现重复卡片、重复恢复、重复回答。

## 4. 范围

### 4.1 本工单包含

- DeepTutorChat 复用问答 Chat 的 `request_member_selection` 工具。
- DeepTutorChat 新增消息内选择成员卡片的需求设计。
- DeepTutorChat 成员选择 block 数据模型设计。
- DeepTutorChat 工具等待/恢复/完成状态机设计。
- DeepTutorChat 会话成员绑定本地存储设计。
- DeepTutorChat 与 ToolHub / ToolInteractionCoordinator 的适配方案。
- DeepTutorChat 日志设计。
- DeepTutorChat 和 DeepTutor Web / 问答 Chat 的差距清单。
- 实现步骤与验收标准。

### 4.2 本工单不包含

- 不新增独立 AI 厂商。
- 不新增 `.deepTutor` AI 场景，继续使用通用 `.chat` 场景。
- 不重写 ToolHub。
- 不把成员选择改成普通 `ask_user_question`。
- 不直接实现代码。
- 不改变已有问答 Chat 的成员选择行为，除非需要抽取公共适配接口。

## 5. 参考端业务语义

### 5.1 DeepTutor Web 的对齐语义

DeepTutor Web 对工具交互的核心语义是：

```text
AI 决定本轮是否需要工具
-> 工具调用进入 trace
-> 如果工具需要用户补充信息，生成消息内交互卡片
-> 用户提交卡片
-> 当前 turn 恢复
-> 工具继续执行
-> 正式回答输出
```

DeepTutorChat 的成员选择要遵守同样语义。

成员选择不是一个普通聊天问题，而是工具执行期间的缺参恢复节点。它必须能够回到当前 AI turn，而不是开启一条全新的用户消息。

### 5.2 问答 Chat 的对齐语义

问答 Chat 已经定义了“工具需要成员”的标准语义：

```text
ToolHub.resolveTargetMemberID(...)
-> 如果 invocation.arguments["member_id"] 有值，直接使用
-> 如果 ToolExecutionContext.memberID 有值，直接使用
-> 如果 thread 已绑定 memberID，直接使用
-> 否则 requestMemberSelection(...)
```

选择完成后的工具结果语义：

```json
{
  "selection_completed": true,
  "member_id": 123,
  "instruction": "continue_conversation"
}
```

DeepTutorChat 应复用这个工具返回语义，不能另造不兼容字段。

## 6. 当前关键代码位置

### 6.1 通用 ToolHub 成员选择工具

| 文件 | 作用 |
|---|---|
| `SparkClient/Projects/Core/AIRuntime/ToolHub/Models/ToolingModels.swift` | 定义 `SparkToolName.requestMemberSelection = "request_member_selection"` 与 `ToolMemberSelectionPrompt` |
| `SparkClient/Projects/Core/AIRuntime/ToolHub/ToolHub+Schema.swift` | 定义 `request_member_selection` 的工具 schema |
| `SparkClient/Projects/Core/AIRuntime/ToolHub/Executors/ToolHubRequestMemberSelection.swift` | `request_member_selection` 执行入口 |
| `SparkClient/Projects/Core/AIRuntime/ToolHub/ToolHub+Shared.swift` | `resolveTargetMemberID`、`awaitMemberSelection`、`memberSelectionCompletedResult`、`memberSelectionTimeoutResult` |
| `SparkClient/Projects/Core/AIRuntime/ChatOrchestrator.swift` | 构造工具执行上下文，含 `memberID` |

### 6.2 问答 Chat 已有成员卡片

| 文件 | 作用 |
|---|---|
| `SparkClient/Projects/Features/Chat/Domain/ChatMessage/BlockPayloads/PendingMemberToolCard.swift` | 问答 Chat 的待选择成员工具卡片数据模型 |
| `SparkClient/Projects/Features/Chat/Presentation/ChatView/MessageCards/ChatPendingMemberToolCardView.swift` | 问答 Chat 的成员选择消息卡片 UI |
| `SparkClient/Projects/Features/Chat/Presentation/ChatView/Components/ChatMessageBlock+Render.swift` | 将 `.pendingMemberToolCards` 渲染成 `ChatPendingMemberToolCardView` |
| `SparkClient/Projects/Features/Chat/Presentation/ChatView/Components/ChatRenderContext.swift` | 透传 `onPendingMemberToolSelect` |
| `SparkClient/Projects/Features/Chat/Presentation/ChatDetailViewModel.swift` | `setPendingMemberToolSelection`、`updateThreadMemberBinding` |
| `SparkClient/Projects/Features/Chat/Presentation/ChatView.swift` | 注入 `memberContextStore`、成员绑定、工具 sheet |

### 6.3 DeepTutorChat 当前消息与工具链路

| 文件 | 作用 |
|---|---|
| `SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorPromptBuilder.swift` | 构建 DeepTutorChat system prompt |
| `SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorRuntimeRequestBuilder.swift` | 构造通用 AI Runtime 请求和工具策略 |
| `SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorToolPolicyResolver.swift` | DeepTutorChat 本轮允许工具集合策略 |
| `SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorAIRuntimeAdapter.swift` | 接入通用 `.chat` AI 场景与 runtime stream |
| `SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorAIRuntimeEventMapper.swift` | 将 AI Runtime 事件映射到 DeepTutorStreamEvent |
| `SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorMessageReducer.swift` | 将消息、事件、能力归约成 UI blocks |
| `SparkClient/Projects/Features/DeepTutorChat/Domain/DeepTutorMessageBlock.swift` | DeepTutorChat 消息 block 定义 |
| `SparkClient/Projects/Features/DeepTutorChat/Presentation/Bubbles/DeepTutorAssistantBubble.swift` | 助手气泡内 block 渲染入口 |
| `SparkClient/Projects/Features/DeepTutorChat/Presentation/Cards/DeepTutorAskUserCardView.swift` | 已有 AskUser 消息卡片，可作为视觉结构参考 |
| `SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorChatViewModel.swift` | 发送消息、提交 AskUser、状态刷新与落库 |
| `SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorLocalChatStore.swift` | DeepTutorChat 本地消息与 block 持久化 |
| `SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorChatLogging.swift` | DeepTutorChat 日志 |

## 7. 现状链路

### 7.1 目前工具链路

```text
DeepTutorChatViewModel.sendMessage
-> SendDeepTutorAIMessageUseCase.send
-> DeepTutorAIRuntimeAdapter.streamReply
-> DeepTutorRuntimeRequestBuilder.build
-> DeepTutorToolPolicyResolver.resolve
-> ChatOrchestratorInferenceOptions(useTools=true, allowedToolNames=...)
-> ChatOrchestrator
-> ToolHub.filteredToolDefinitions
-> ToolHub.run
-> ToolHubRequestMemberSelection.runRequestMemberSelection
-> awaitMemberSelection
-> ToolInteractionCoordinator.requestMemberSelection
```

问题点在最后一步：

```text
ToolInteractionCoordinator.requestMemberSelection
```

目前它更接近问答 Chat 的 sheet 交互模型，DeepTutorChat 需要在这里接入“消息内卡片”承载。

### 7.2 目前 DeepTutorChat AskUser 链路

```text
AI 调用 ask_user_question
-> DeepTutorAIRuntimeEventMapper 映射 askUser event
-> DeepTutorMessageReducer 生成 askUser block
-> DeepTutorAssistantBubble 渲染 DeepTutorAskUserCardView
-> 用户提交
-> DeepTutorChatViewModel.submitAskUser
-> SendDeepTutorAIMessageUseCase.resumeAfterAskUser
-> DeepTutorAIRuntimeAdapter.resumeAfterAskUser
```

成员选择应借鉴 AskUser 的 UI block 和恢复思路，但不能把成员选择伪装成 AskUser。原因：

- `request_member_selection` 是通用 ToolHub 已有工具。
- 成员选择结果会影响 `ToolExecutionContext.memberID`。
- 问答 Chat 里已有 `memberSelectionCompletedResult` 和 `resolvedMemberID`。
- 后续 health/member 工具依赖成员绑定，不只是文本答案。

## 8. 目标链路

### 8.1 无成员绑定时

```text
用户：帮我看一下最近的健康报告
-> DeepTutorToolPolicyResolver 允许 health/member 相关工具
-> AI 选择调用 request_member_selection
-> ToolHubRequestMemberSelection 未解析到 memberID
-> DeepTutor 工具交互适配器捕获成员选择请求
-> 当前 assistant message 插入 member_selection block
-> UI 展示 DeepTutorMemberSelectionCardView
-> 用户选择成员
-> DeepTutorChatViewModel.submitMemberSelection
-> 更新 member_selection block 为 completed
-> 会话绑定 memberID 并落库
-> complete ToolInteractionCoordinator continuation
-> ToolHub 返回 memberSelectionCompletedResult
-> AI Runtime 继续本轮工具调用
-> AI 输出正式回答
```

### 8.2 已绑定成员时

```text
用户：继续看他的最近报告
-> DeepTutorRuntimeRequestBuilder 携带 memberID
-> ToolExecutionContext.memberID 有值
-> ToolHub.resolveTargetMemberID 直接返回 memberID
-> request_member_selection 返回 already_resolved
-> 不展示选择成员卡片
-> 后续工具直接使用 memberID
```

### 8.3 用户未选择或超时

```text
request_member_selection 等待用户选择
-> 超时/取消
-> memberSelectionTimeoutResult
-> member_selection block 更新为 timeout/cancelled
-> AI 根据 instruction 决定继续询问或说明需要选择成员
```

## 9. 关键技术方案

### 9.1 继续使用同一个工具

工具名称保持：

```swift
SparkToolName.requestMemberSelection.rawValue
// request_member_selection
```

DeepTutorChat 不新增：

```text
deep_tutor_select_member
select_deeptutor_member
ask_user_member
```

原因：

- 统一 ToolHub 是项目内工具协议的单一事实源。
- AI 工具 schema 不应因页面不同而分裂。
- 问答 Chat、DeepTutorChat、未来其他对话面都应复用同一工具名。
- 成员选择完成后的结果字段应保持一致。

### 9.2 新增 DeepTutorChat 成员选择 block

建议新增 block kind：

```swift
case memberSelection = "member_selection"
```

建议新增 payload：

```swift
struct DeepTutorMemberSelectionBlockPayload: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case pending
        case running
        case completed
        case timeout
        case cancelled
    }

    var id: UUID
    var toolName: String
    var toolCallID: String?
    var reason: String
    var arguments: [String: String]
    var selectedMemberID: Int?
    var status: Status
    var resultText: String?
    var createdAt: Date
    var updatedAt: Date
}
```

说明：

- `toolName` 固定为 `request_member_selection`，也允许兼容未来 member 工具。
- `toolCallID` 用于和 stream/tool event 匹配。
- `reason` 来自工具参数，用于展示“为什么需要选择成员”。
- `arguments` 保留原始工具参数，便于调试和恢复。
- `selectedMemberID` 完成后写入。
- `status` 驱动 UI 状态。
- `resultText` 显示完成、超时、取消文案。

是否复用问答 Chat 的 `PendingMemberToolCard`：

- 可以复用字段语义。
- 不建议 DeepTutorChat 直接依赖 Chat Feature 的消息模型类型。
- 更推荐在 DeepTutorChat 内定义自己的 payload，并在必要时从 `ToolMemberSelectionPrompt` 映射。

### 9.3 新增 DeepTutorMemberSelectionCardView

建议新增文件：

```text
SparkClient/Projects/Features/DeepTutorChat/Presentation/Cards/DeepTutorMemberSelectionCardView.swift
```

UI 应参考：

- DeepTutor Web AskUser 卡片。
- DeepTutorChat 当前 `DeepTutorAskUserCardView` 的圆角、边框、阴影、间距。
- 问答 Chat 当前 `ChatPendingMemberToolCardView` 的成员选择菜单和完成态。

不建议直接照搬问答 Chat 的小尺寸卡片，因为 DeepTutorChat 的视觉已经在对齐 Web，对话内卡片应更接近 DeepTutor Web 的卡片密度。

## 10. UI 设计细节

### 10.1 卡片位置

成员选择卡片应位于当前助手消息气泡内：

```text
DeepTutorAssistantBubble
├── trace / thinking / tool activity
├── assistant text blocks
├── member_selection card
└── message action bar
```

卡片不应：

- 插入成新的 user 消息。
- 插入到 composer 上方的独立 overlay。
- 只通过 sheet 出现。
- 出现在底部 TabBar 或输入区下面。

### 10.2 卡片视觉结构

建议结构：

```text
┌────────────────────────────────────────────┐
│ ? / person icon   请选择成员                 │
│                 这个工具需要确认查询哪位成员  │
│                                            │
│ 为了继续查询健康数据，请选择一个家庭成员。     │
│                                            │
│ ┌──────────────────────────────────────┐   │
│ │ 头像/首字  张三      本人/父亲/母亲    │   │
│ │          42岁 男    已选择 check       │   │
│ └──────────────────────────────────────┘   │
│ ┌──────────────────────────────────────┐   │
│ │ 头像/首字  李四      家属              │   │
│ └──────────────────────────────────────┘   │
│                                            │
│ 未选择成员将无法继续使用该工具。             │
└────────────────────────────────────────────┘
```

### 10.3 尺寸

建议与 DeepTutor AskUser 卡片保持一致：

- 外层圆角：`24-26pt`
- 边框：`1pt`，浅灰
- 背景：白色或当前 DeepTutor card 背景色
- 阴影：轻阴影，不要厚重
- 内边距：`16-20pt`
- 选项高度：`56-68pt`
- 选项圆角：`14-18pt`
- 选项间距：`10-12pt`
- 卡片最大宽度跟随助手消息内容宽度

### 10.4 标题区

标题区建议包含：

- 圆形 icon：`person.crop.circle.badge.questionmark` 或 DeepTutor 自定义问号 icon。
- 标题：`请选择成员`。
- 副标题：`该工具需要确认要查询哪位家庭成员。`

如果工具参数传入了 `reason`：

```text
为了查询健康报告，请先选择成员。
```

如果 `reason` 为空：

```text
继续前，请选择本次要使用的成员档案。
```

### 10.5 成员选项行

每个成员选项建议展示：

- 成员姓名。
- 关系标签，例如“本人”“父亲”“母亲”“家属”。
- 可选补充信息：年龄、性别。
- 右侧选中标记。

选中态：

- 边框使用 DeepTutor 主蓝色。
- 背景使用主蓝色 `8%-12%` 透明度。
- 左侧头像/首字背景变成淡蓝。
- 右侧显示 check。

未选态：

- 白底。
- 浅灰边框。
- 轻微阴影或无阴影。

禁用态：

- 若工具已完成，不允许再次切换，除非本期明确支持“修改选择并重新生成”。

### 10.6 完成态

用户选择后卡片应变为完成态：

```text
已选择：张三
```

完成态表现：

- 标题可保持“已选择成员”。
- icon 变为 check 或保留成员 icon 加绿色状态点。
- 选中的成员行高亮。
- 其他成员可以隐藏或弱化。
- 底部显示 `AI 将继续使用该成员完成本次查询。`

### 10.7 空状态

如果本地没有成员档案：

```text
暂无可选择的成员档案
请先创建家庭成员后，再继续使用健康数据工具。
```

本期建议：

- 卡片展示空状态。
- 工具返回 timeout/cancelled 或 no_member_available 的结构化结果。
- 不强行跳转创建成员页，避免打断 DeepTutorChat。

后续可扩展：

- 卡片按钮 `去创建成员`。
- 创建完成后回到同一会话并恢复工具。

### 10.8 和 sheet 的关系

DeepTutorChat 主路径：

```text
消息卡片
```

不是：

```text
sheet
```

但可以保留 sheet 作为底层通用协调器的 fallback：

- 如果 DeepTutorChat 成员卡片适配器不可用，才允许走 sheet。
- 正常 DeepTutorChat 页面内不能同时出现卡片和 sheet。
- 日志必须记录本轮使用的是 `presentation=message_card` 还是 `presentation=sheet_fallback`。

## 11. 数据模型与持久化

### 11.1 会话需要成员绑定

DeepTutorChat 会话模型应增加或读取：

```swift
memberID: Int?
```

如果 DeepTutorChat 底层复用 ChatThread / Thread CoreData entity，则优先复用已有字段。

目标能力：

- 新会话默认 `memberID = nil`。
- 选择成员后写入本地数据库。
- 会话列表/会话详情加载时能读出 `memberID`。
- 后续发送消息时能把 `memberID` 传给 AI Runtime。

### 11.2 本地数据库更新

建议在 DeepTutor 本地仓储协议增加：

```swift
func updateConversationMemberBinding(conversationID: UUID, memberID: Int?) async
```

如果已有通用 ChatRepository 可复用，则在 DeepTutorLocalChatRepository 里封装调用，不要让 View 直接操作 CoreData。

### 11.3 消息 block 持久化

`member_selection` block 必须作为 DeepTutorMessageBlock 持久化。

持久化要求：

- pending 状态要能落库。
- completed 状态要能落库。
- selectedMemberID 要能落库。
- toolCallID 要能落库。
- arguments 要能落库。
- resultText 要能落库。
- 老版本未知 block 不能导致整条消息解码失败。

需要同步更新：

- `DeepTutorMessageBlockKind`
- `DeepTutorMessageBlockPayload`
- `DeepTutorMessageCodec`
- `DeepTutorMessageCodec+Compatibility`
- `DeepTutorLocalChatStore`
- `DeepTutorChatDebugExporter`

## 12. 工具交互适配方案

### 12.1 推荐方案：DeepTutor 专属 ToolInteraction Adapter

新增一个 DeepTutorChat 工具交互适配层，承接 `ToolInteractionCoordinator.requestMemberSelection`，但把 presentation 映射成消息 block。

建议命名：

```text
DeepTutorToolInteractionBridge
DeepTutorMemberSelectionCoordinator
DeepTutorMessageCardToolInteractionAdapter
```

推荐职责：

1. 接收 `ToolMemberSelectionPrompt`。
2. 获取当前 conversationID、assistantMessageID、toolCallID。
3. 在当前 assistant message 中插入 `member_selection` block。
4. 保存 pending continuation。
5. 等待 `DeepTutorChatViewModel.submitMemberSelection` 完成。
6. 返回 `InteractionResult.completed(memberID)` 给 ToolHub。
7. 超时或取消时返回 `.cancelled` 或 `.timeout`。

### 12.2 为什么不把成员选择改成 AskUser

不推荐：

```text
request_member_selection -> ask_user_question
```

原因：

- AskUser 是通用提问，返回文本答案。
- 成员选择是工具上下文绑定，返回 `memberID`。
- ToolHub 已有 `resolvedMemberID` 机制。
- 后续健康数据工具需要真实 `memberID`，不是成员名字文本。
- 如果成员重名，文本答案会歧义。

### 12.3 为什么不直接用问答 Chat 的 PendingMemberToolCard

可以借鉴，不建议直接耦合。

问答 Chat 的 `PendingMemberToolCard` 属于：

```text
Features/Chat/Domain/ChatMessage
```

DeepTutorChat 应保持自己的消息模型：

```text
Features/DeepTutorChat/Domain/DeepTutorMessageBlock
```

推荐做法：

```text
ToolMemberSelectionPrompt
-> DeepTutorMemberSelectionBlockPayload
-> DeepTutorMemberSelectionCardView
```

字段语义与问答 Chat 对齐，但类型归属 DeepTutorChat。

## 13. 状态机

### 13.1 状态定义

```text
idle
-> tool_requested
-> card_created
-> waiting_user_selection
-> member_selected
-> conversation_binding_saved
-> tool_continuation_resumed
-> tool_result_emitted
-> ai_continues
-> completed
```

异常状态：

```text
waiting_user_selection
-> timeout
-> tool_timeout_result_emitted

waiting_user_selection
-> cancelled
-> tool_cancelled_result_emitted

waiting_user_selection
-> app_reloaded
-> pending_card_recovered_as_expired
```

### 13.2 pending

触发：

```text
ToolHubRequestMemberSelection 无法解析 memberID
```

动作：

- 创建 `member_selection` block。
- 卡片显示成员候选。
- 工具调用保持等待。
- 输入框可禁用或保持可输入，需要产品确认；建议本期禁用发送，避免同一会话并发 turn。

### 13.3 completed

触发：

```text
用户点击某个成员
```

动作：

- 更新 block `selectedMemberID`。
- 更新 block `status = completed`。
- 写入 conversation `memberID`。
- 调用 ToolInteraction continuation。
- ToolHub 产生 `memberSelectionCompletedResult`。
- AI 继续。

### 13.4 timeout/cancelled

触发：

- 用户长时间未选。
- 页面离开。
- 会话被删除。
- 工具任务取消。

动作：

- block 状态更新为 `timeout` 或 `cancelled`。
- ToolHub 返回 timeout result。
- AI 可提示需要选择成员后继续。

### 13.5 reload recovery

如果 App 重启或会话重载时发现 pending card：

建议本期不恢复内存 continuation，因为原始 async 工具调用已经不存在。

处理方式：

- 将 pending 卡片标记为 `cancelled` 或 `expired`。
- 文案：`本次成员选择已中断，请重新发送问题。`
- 不自动再次弹出同一个问题。
- 不自动恢复 AI 回答，避免重复回答和错乱刷新。

## 14. DeepTutorToolPolicy 对齐

### 14.1 工具组合策略

DeepTutorChat 已有本轮工具策略：

```text
DeepTutorToolPolicyResolver.resolve(...)
```

成员选择工具应只在相关能力/意图下进入 allowed tools：

- 用户问题涉及健康报告。
- 用户问题涉及成员档案。
- 用户问题涉及任务、用药、体检、病例等成员维度数据。
- 当前会话未绑定成员，且下游工具需要成员。

不应在普通闲聊、解释知识、Quiz 等场景无条件暴露全部成员工具。

### 14.2 已绑定成员后的策略

如果 `hasSelectedMember = true`：

- 可以允许 health/member 查询工具直接使用 memberID。
- `request_member_selection` 可保留，但模型不应优先调用。
- prompt 应提示：`当前会话已绑定成员，除非用户明确要求切换成员，否则不要再次请求选择成员。`

### 14.3 未绑定成员后的策略

如果 `hasSelectedMember = false` 且用户问题需要成员数据：

- 允许 `request_member_selection`。
- 允许后续 health/member 工具，但模型应先选择成员再查。
- prompt 应提示：`需要成员上下文的工具必须先确认 memberID。`

## 15. Prompt 约束

DeepTutorPromptBuilder 需要补充工具使用约束：

```text
当用户请求查询个人/家庭成员相关健康数据，但当前上下文没有 memberID 时：
1. 先调用 request_member_selection。
2. 不要让用户手动输入成员ID。
3. 不要把工具参数格式说明暴露给用户。
4. 成员选择完成后继续使用返回的 member_id 调用后续工具。
5. 如果当前会话已有绑定成员，除非用户要求切换，不要重复询问成员。
```

需要避免当前类似问题：

```text
AI 把工具内部格式、required 字段、parameters JSON 解释给用户
```

DeepTutorChat 正式回答里不应出现：

- `工具名称正确`
- `parameters 中 required 是 []`
- `askuserquestion`
- `querylocation`
- `queryweather`
- 任何工具 schema 检查过程

这些内容只能作为内部 trace/调试信息，不能作为正式回答。

## 16. UI 更新与刷新机制

### 16.1 插入卡片时

收到成员选择请求后：

1. 更新当前 streaming assistant message 的 `events`。
2. 通过 reducer 生成或直接追加 `member_selection` block。
3. 只更新当前 message，不重载整个 conversation。
4. Diffable/SwiftUI cell 更新必须走主线程队列，避免之前工单中出现的快照重入。
5. 滚动策略：如果用户接近底部，自动滚到卡片；如果用户正在查看历史，不强制抢滚。

### 16.2 选择成员时

用户点击成员：

1. 先将卡片本地状态更新为 `running` 或直接 `completed`。
2. 禁用重复点击。
3. 写入会话绑定。
4. 完成 ToolHub continuation。
5. AI 继续输出时，思考区自动收起。
6. 正式回答追加到同一 assistant message 或后续 assistant message，需与现有 DeepTutor AskUser 恢复链路统一。

### 16.3 防重复

必须建立去重 key：

```text
conversationID + assistantMessageID + toolCallID + toolName
```

如果没有 toolCallID：

```text
conversationID + assistantMessageID + normalized(reason) + createdTurnIndex
```

同一个 key 的 member selection 只能创建一个 block。

### 16.4 和 AskUser 并存

同一轮内理论上可能出现：

- ask_user_question
- request_member_selection

处理原则：

- 每个工具卡片独立 block。
- 用 toolCallID 匹配提交。
- 不使用全局 “当前唯一问题” 状态覆盖。
- UI 排列按 tool event 顺序。

## 17. 日志设计

日志不需要脱敏。为了排查 DeepTutorChat 工具链路，建议新增以下日志。

### 17.1 工具请求

```text
deeptutor.member_selection.tool_requested
conversation=<short>
assistant=<short>
toolCall=<short>
reason=<raw>
hasBoundMember=<true|false>
boundMemberID=<id|->
allowedToolCount=<n>
```

### 17.2 成员解析

```text
deeptutor.member_selection.resolve
conversation=<short>
source=<argument|context|thread|none>
memberID=<id|->
```

### 17.3 卡片创建

```text
deeptutor.member_selection.card_created
conversation=<short>
assistant=<short>
block=<short>
toolCall=<short>
memberCount=<n>
status=pending
```

### 17.4 卡片渲染

```text
deeptutor.member_selection.card_rendered
conversation=<short>
assistant=<short>
block=<short>
status=<pending|completed|timeout|cancelled>
selectedMemberID=<id|->
```

### 17.5 用户选择

```text
deeptutor.member_selection.member_selected
conversation=<short>
assistant=<short>
block=<short>
memberID=<id>
memberName=<name>
```

### 17.6 会话绑定

```text
deeptutor.member_selection.conversation_bound
conversation=<short>
oldMemberID=<id|->
newMemberID=<id>
persisted=<true|false>
```

### 17.7 continuation 恢复

```text
deeptutor.member_selection.continuation_resumed
conversation=<short>
assistant=<short>
toolCall=<short>
memberID=<id>
durationMs=<ms>
```

### 17.8 工具结果

```text
deeptutor.member_selection.tool_result_emitted
conversation=<short>
toolCall=<short>
selectionCompleted=<true|false>
memberID=<id|->
instruction=<continue_conversation|continue_without_member_or_ask_again>
```

### 17.9 重载恢复

```text
deeptutor.member_selection.reload_recovered_pending
conversation=<short>
assistant=<short>
block=<short>
action=<expired|cancelled|kept_readonly>
```

### 17.10 防重复

```text
deeptutor.member_selection.duplicate_suppressed
conversation=<short>
assistant=<short>
toolCall=<short>
existingBlock=<short>
```

## 18. 与问答 Chat 的差距清单

| 能力 | 问答 Chat 当前 | DeepTutorChat 当前 | DeepTutorChat 目标 |
|---|---|---|---|
| 成员工具 | 已有 `request_member_selection` | 可通过 ToolHub 暴露，但交互未对齐 | 复用同一工具 |
| 成员选择 UI | `ChatPendingMemberToolCardView` / sheet | 无 DeepTutor 专属消息卡片 | `DeepTutorMemberSelectionCardView` |
| 消息模型 | `.pendingMemberToolCards` | 无 `.memberSelection` | 新增 DeepTutor block |
| 成员绑定 | `updateThreadMemberBinding` | 不完整/未贯穿 | 会话级 `memberID` 本地持久化 |
| 工具恢复 | ToolInteractionCoordinator continuation | AskUser 有恢复，成员选择缺失 | 成员选择完成后恢复同一 tool call |
| 重载恢复 | Chat block 可持久化 | DeepTutor 无成员卡片持久化 | completed 可恢复，pending 可过期 |
| 日志 | Chat 有部分日志 | DeepTutor 缺少全链路 | 补齐 member_selection 全流程 |

## 19. 与 DeepTutor Web 的差距清单

| DeepTutor Web 语义 | DeepTutorChat 当前偏差 | 修正要求 |
|---|---|---|
| 工具需要补充信息时出现消息内卡片 | 成员选择缺消息卡片 | 新增 member_selection block |
| 用户提交后当前 turn 继续 | 成员选择可能只更新 UI 或 sheet，不恢复工具 | 完成 continuation 并返回 ToolHub |
| 工具 trace 与卡片在同一消息中 | 成员选择与 trace 分离 | 按 tool event 顺序插入 |
| 卡片状态可回放 | 无可持久化成员选择 block | block 落库 |
| 正式回答不暴露工具 schema | AI 可能输出工具参数检查过程 | prompt + event mapper + trace formatter 隔离 |
| 已有上下文不重复问 | memberID 未贯穿会重复 | mount context + ToolExecutionContext 携带 memberID |

## 20. 实现拆解

### 20.1 第一阶段：模型与持久化

需要改动：

- `DeepTutorMessageBlockKind`
- `DeepTutorMessageBlockPayload`
- `DeepTutorMemberSelectionBlockPayload`
- `DeepTutorMessageCodec`
- `DeepTutorMessageCodec+Compatibility`
- `DeepTutorLocalChatStore`
- `DeepTutorChatDebugExporter`

交付：

- 能编码/解码 `member_selection` block。
- 能落库 pending/completed 状态。
- 老数据不崩溃。

### 20.2 第二阶段：会话成员绑定

需要改动：

- `DeepTutorConversation`
- `DeepTutorLocalChatRepository`
- `DeepTutorLocalChatStore`
- `DeepTutorChatViewModel`

交付：

- 会话可以保存 `memberID`。
- 会话加载后可恢复 `memberID`。
- 发送消息时能携带 `memberID`。

### 20.3 第三阶段：运行时上下文贯通

需要改动：

- `DeepTutorAIRuntimeAdapter`
- `DeepTutorRuntimeRequestBuilder`
- `DeepTutorToolMountContext`
- `DeepTutorToolPolicyResolver`
- `ChatOrchestrator` 调用参数

交付：

- `hasSelectedMember` 真实可用。
- `ToolExecutionContext.memberID` 真实可用。
- 已绑定成员时不重复弹卡片。

### 20.4 第四阶段：工具交互适配

需要新增或改动：

- `DeepTutorMemberSelectionCoordinator`
- `DeepTutorToolInteractionBridge`
- `ToolInteractionCoordinator` 扩展 presentation style
- `SendDeepTutorAIMessageUseCase`

交付：

- ToolHub 请求成员选择时，DeepTutorChat 创建消息卡片。
- 用户选择后恢复工具调用。
- 超时/取消可控。

### 20.5 第五阶段：UI 卡片

需要新增：

- `DeepTutorMemberSelectionCardView`

需要改动：

- `DeepTutorAssistantBubble`
- `DeepTutorMessageRowModel`
- `DeepTutorMessageListRepresentable` 或对应消息列表桥接层

交付：

- 卡片按 DeepTutor 风格展示。
- 选择态、完成态、空状态可见。
- 点击不会重复提交。

### 20.6 第六阶段：日志与调试面板

需要改动：

- `DeepTutorChatLogging`
- `DeepTutorChatDebugExporter`

交付：

- 支持导出成员选择卡片状态。
- 日志能覆盖工具请求、卡片创建、选择、绑定、恢复、结果、失败。

## 21. 验收用例

### 21.1 无绑定成员时查询健康数据

```text
Given 当前 DeepTutorChat 会话没有 memberID
And 本地存在 2 个家庭成员
When 用户发送“帮我看一下最近的体检报告”
Then AI Runtime 允许成员/健康数据相关工具
And 模型调用 request_member_selection
And DeepTutorChat 在助手消息内展示选择成员卡片
And 不弹出独立 sheet 作为主交互
```

### 21.2 选择成员后继续回答

```text
Given 选择成员卡片处于 pending
When 用户点击成员“张三”
Then 卡片变为 completed
And 会话 memberID 写入本地数据库
And ToolHub 收到 memberSelectionCompletedResult
And 当前 AI turn 继续执行
And AI 输出正式回答
```

### 21.3 已绑定成员不重复询问

```text
Given 当前会话已绑定 memberID=123
When 用户发送“继续看他的报告”
Then request_member_selection 如果被调用，应返回 already_resolved
And 不展示新的选择成员卡片
And 不弹 sheet
And 后续工具使用 memberID=123
```

### 21.4 刷新后保留已完成卡片

```text
Given 用户已选择成员
And 卡片状态为 completed
When 退出并重新进入 DeepTutorChat 会话
Then 消息列表能加载该成员选择卡片
And 卡片展示“已选择：张三”
And 不重新触发工具 continuation
```

### 21.5 pending 卡片重载不重复恢复

```text
Given request_member_selection 正在等待用户选择
When App 被杀掉后重新打开
Then pending 卡片被标记为 expired/cancelled 或只读中断态
And 不自动恢复旧 continuation
And 不重复弹出成员选择
And 不重复生成 AI 回答
```

### 21.6 无成员档案

```text
Given 本地没有家庭成员
When 工具请求选择成员
Then DeepTutorChat 展示空状态卡片
And 日志记录 memberCount=0
And 工具返回可解释的失败/取消结果
And AI 说明需要先创建成员档案
```

### 21.7 工具 schema 不暴露

```text
Given 工具需要选择成员
When AI 正式回答
Then 正式回答不出现 request_member_selection 参数格式
And 不出现 required、parameters、tool name 检查过程
And 工具内部过程只出现在 trace 或调试日志中
```

## 22. 风险

### 22.1 continuation 生命周期风险

成员选择卡片是持久化 UI，但 ToolHub continuation 是内存态。

风险：

- App 重启后 continuation 消失。
- 用户点击旧 pending 卡片无法恢复工具。

要求：

- pending 卡片重载后必须转为 expired/cancelled 或只读。
- 不允许假装可以继续旧工具调用。

### 22.2 sheet 与消息卡片双触发风险

如果 DeepTutorChat 仍保留 `ToolInteractionCoordinator.activePresentation` sheet，同时新增消息卡片，可能出现：

- sheet 弹出一次。
- 消息内卡片也出现一次。
- 用户选择两次。
- continuation 被 complete 两次。

要求：

- DeepTutorChat 成员选择必须有唯一 presentation owner。
- 正常路径 `presentation=message_card`。
- sheet 只允许 fallback 且日志可见。

### 22.3 线程/会话 ID 复用风险

ToolHub 使用 `threadID`，DeepTutorChat 使用 `conversationID`。

要求：

- 明确 DeepTutorChat 的 `conversationID` 是否等价于 Chat `threadID`。
- 如果底层复用 `Thread` entity，必须保证 UUID 一致。
- 如果不是同一实体，需要在 DeepTutor adapter 中映射清楚。

### 22.4 重复工具卡片风险

流式事件可能多次 partial，或者工具调用 event 多次更新。

要求：

- 用 `conversationID + assistantMessageID + toolCallID + toolName` 去重。
- `DeepTutorMessageReducer` 不能每次刷新都 append 新卡片。

### 22.5 成员绑定污染风险

用户本轮选择成员后，会话默认绑定该成员。

风险：

- 用户下轮问“另一个人呢”时仍然使用旧成员。

要求：

- Prompt 中明确：用户表达切换成员时应重新调用 `request_member_selection` 或 `switchMember`。
- UI 后续可增加会话顶部/输入区成员绑定提示，本工单不强制。

## 23. 开发优先级

### P0

- 复用 `request_member_selection`。
- DeepTutorChat 消息内展示选择成员卡片。
- 选择后恢复当前工具调用。
- 会话 memberID 落库。
- 已绑定成员不重复询问。

### P1

- pending 重载恢复策略。
- 日志全链路。
- 调试导出包含 member selection block。
- 空状态。

### P2

- 顶部/输入区展示当前绑定成员。
- 支持切换成员。
- 支持创建成员后回到原工具链路。

## 24. 建议任务清单

1. 梳理问答 Chat `PendingMemberToolCard` 的完整生命周期。
2. 给 DeepTutorChat 增加 `member_selection` block 和 payload。
3. 给 DeepTutorLocalChatStore 增加新 block 编解码兼容。
4. 给 DeepTutorConversation 增加或读取 `memberID`。
5. 给 DeepTutorLocalChatRepository 增加成员绑定更新方法。
6. DeepTutorRuntimeRequestBuilder 传入已绑定 `memberID`。
7. DeepTutorToolMountContext 根据真实 memberID 设置 `hasSelectedMember`。
8. DeepTutorAIRuntimeAdapter 将 memberID 传入 ChatOrchestrator / ToolExecutionContext。
9. 增加 DeepTutor 成员选择工具交互 adapter。
10. 工具请求成员时插入 message card 并等待用户选择。
11. 新增 DeepTutorMemberSelectionCardView。
12. DeepTutorAssistantBubble 渲染 member_selection block。
13. DeepTutorChatViewModel 增加 submitMemberSelection。
14. 用户选择后写回 block、会话绑定、MemberContextStore。
15. complete ToolInteraction continuation 并继续 AI turn。
16. 增加防重复 key。
17. 增加 pending 重载过期处理。
18. 增加全链路日志。
19. 增加调试导出字段。
20. 做无成员、单成员、多成员、已绑定、重载、重复事件测试。

## 25. Definition of Done

完成本工单后，应满足：

- DeepTutorChat 使用项目已有 `request_member_selection` 工具。
- DeepTutorChat 不新增不兼容成员选择工具。
- 成员选择主体验是消息卡片。
- 成员选择卡片 UI 与 DeepTutorChat / DeepTutor Web 消息卡片体系一致。
- 用户选择成员后，当前 AI turn 能继续回答。
- 会话绑定成员可持久化。
- 已绑定成员不会重复弹选择卡片。
- 刷新后 completed 卡片可恢复展示。
- pending 重载不会重复恢复或重复回答。
- 工具 schema 不裸露在正式回答中。
- 日志能完整定位：工具请求、卡片创建、渲染、选择、绑定、恢复、结果、失败。

