# DEEPTUTORCHAT-000008 AskUser 提问卡片缺失、日志分析与 DeepTutor Web 对齐工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000008 |
| 工单类型 | P0 缺陷分析 + DeepTutor Web ask_user 交互对齐 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| iOS 功能目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| iOS 运行时依赖 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime` |
| Web 参考工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main` |
| 日志附件 | `/Users/hua/.codex/attachments/71e90354-39d6-4e26-8a11-16de61e60ba5/pasted-text.txt` |
| 创建日期 | 2026-08-05 |
| 模型场景约束 | 继续使用项目已有通用 `.chat` 场景，不新增 `.deepTutor` |
| 关联工单 | `DEEPTUTORCHAT-000001`、`DEEPTUTORCHAT-000007` |

## 1. 本工单目标

本工单聚焦当前日志暴露出的 AskUser 提问交互未展示问题，并明确后续实现必须同时处理两层对齐：

```text
1. P0：先接入项目已有统一 ToolInteraction sheet，保证 ask_user_question 工具触发后能弹出“选择/提问 sheet”。
2. P1：再对齐 DeepTutor Web 的消息内 ask_user 卡片展示语义，保证最终消息流体验一致。
```

需要解决的问题：

```text
1. 分析当前日志中暴露的关键问题。
2. 梳理 iOS 当前没有对齐 DeepTutor Web 的 ask_user 部分。
3. 排查为什么模型已经调用 ask_user_question，但消息内提问卡片没有展示。
4. 在 DeepTutorChat 功能目录内明确后续修复方案、关键代码位置、日志要求与验收标准。
5. 补充 DeepTutorChat 未挂载项目统一 sheet，导致工具触发后没有弹出选择/提问 sheet 的问题。
6. 补充 DeepTutorChat 右上角“打印调试信息”入口需求，对齐普通 Chat 对话。
7. 本工单只写需求与技术方案，不直接改动 Swift 代码。
```

## 2. 日志结论摘要

本次日志里，用户输入：

```text
今天的天气怎么样
```

当前策略已经识别为天气位置类问题：

```text
deeptutor.tool_policy.resolved conversation=D2E9455A message=3534270E capability=chat inputLength=8 policyReason=weather_location useTools=true useKnowledgeBag=false useWebSearch=false allowedToolCount=4 allowedTools=ask_user_question,get_route,query_weather,search_nearby_locations ...
deeptutor.tool_schema.outbound conversation=D2E9455A message=3534270E toolChoice=auto schemaCount=4 schemaNames=ask_user_question,get_route,query_weather,search_nearby_locations reason=weather_location
```

说明：

```text
DEEPTUTORCHAT-000007 所要求的“本轮工具策略层”已经开始出现日志，且本轮不是 SparkToolName.all 全量出站。
```

但 ask_user 卡片仍未出现。关键日志如下：

```text
deeptutor.ask_user.map_failed phase=tool_started tool=ask_user_question call=call_j5allmjgyyfbez2tjrlhnfak argumentKeys=- rawLength=0 raw=-
deeptutor.ask_user.map_failed phase=tool_completed tool=ask_user_question call=call_j5allmjgyyfbez2tjrlhnfak argumentKeys=- rawLength=0 raw=-
deeptutor.stream.partial.mapped ... events=toolStart(...),toolResult(ask_user#...) forceFlush=true blocks=envelope=1,text=1,trace=1
deeptutor.trace.state_changed message=3534270E rows=1 askUserBlocks=0 blocks=envelope|trace|text
```

最关键结论：

```text
1. 模型确实返回了 ask_user_question tool_call。
2. iOS mapper 没有拿到 tool_call 原始 arguments，因此 ask_user payload 解析失败。
3. ToolHub 执行 ask_user_question 时也拿到空参数或不兼容参数，返回“参数无效”。
4. MessageReducer 最终没有生成 askUser block，日志一直是 askUserBlocks=0。
5. UI 没有 askUser block/askUser event 可消费，所以消息内提问卡片无法展示。
```

## 3. 当前日志中发现的问题

### 3.1 ask_user_question 原始参数在 AI 请求回灌里存在，但 mapper 阶段丢失

日志中后续回灌给模型的 tool call 明确包含原始 arguments：

```json
{
  "id": "call_j5allmjgyyfbez2tjrlhnfak",
  "function": {
    "name": "ask_user_question",
    "arguments": "{\"question\":\"你想查询哪个城市的天气呢？\",\"options\":[],\"selection_mode\":\"single\",\"allows_other\":true}"
  },
  "type": "function"
}
```

但 DeepTutor mapper 阶段日志显示：

```text
argumentKeys=-
rawLength=0
raw=-
```

说明：

```text
ChatOrchestrator / AIRuntime stream collector 虽然最终保存了 tool_calls，但传给 DeepTutorAIRuntimeEventMapper 的 ChatAssistantPartialDelta 缺少 toolArguments / toolInvocationArguments。
```

影响：

```text
DeepTutorAskUserNormalizer 无法从 partial 中恢复 question、options、allows_other，自然无法 emit .askUser event。
```

### 3.2 ToolHub 参数协议与 DeepTutor Web 自由输入追问不一致

当前 ToolHub ask_user_question 解析位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ToolHub/Executors/ToolHubAskUserQuestion.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ToolHub/ToolHub+Shared.swift
```

当前 `makeQuestionItem` 要求：

```swift
guard question.isEmpty == false, (2...5).contains(rawOptions.count) else { return nil }
```

本次模型返回：

```json
{
  "question": "你想查询哪个城市的天气呢？",
  "options": [],
  "selection_mode": "single",
  "allows_other": true
}
```

这在 DeepTutor Web 的语义里是合理的自由输入追问：没有选项，但允许用户直接输入城市。

但 iOS 当前 ToolHub 判定为无效：

```text
【系统】ask_user_question 参数无效：需提供 1-5 个问题，每个问题的 options 必须包含 2-5 个选项。
```

影响：

```text
1. 工具结果没有进入 awaitingUserInput。
2. 没有等待用户输入。
3. 没有创建消息内提问卡片。
4. 模型进入下一轮时收到“参数无效”，而不是用户回答。
```

### 3.3 events 有 toolResult，但没有 askUser event

日志：

```text
events=toolStart(ask_user_question#...),toolResult(ask_user#...)
blocks=envelope=1,text=1,trace=1
askUserBlocks=0
```

说明：

```text
DeepTutorMessageReducer 只拿到了工具 trace / toolResult 摘要，没有拿到可渲染的 askUser payload。
```

应对齐 DeepTutor Web：

```text
DeepTutor Web 不是只根据“工具名是 ask_user”展示卡片，而是从 msg.events 中提取 ask_user payload，再通过 AskUserOptions 渲染。
```

### 3.4 正文里出现模型内部“思考：...”文本

日志中 AI 输出 preview：

```text
（思考：用户问“今天的天气怎么样”，需要先获取用户的位置信息才能查询天气。...）
```

问题：

```text
模型把工具决策解释作为正文 content 输出，而不是标准 reasoning 字段或 trace。
```

这会导致：

```text
1. UI 正文污染，用户看到不该出现在正式回答里的内部判断。
2. hasFinalContent=true 过早出现，trace 进入 final_phase。
3. 后续 ask_user 失败时，消息里留下“思考”文本而不是提问卡片。
```

后续需要确认：

```text
1. Prompt 是否诱导模型输出“（思考：...）”到 content。
2. AIRuntime 对 Doubao thinking 字段的解析是否稳定。
3. DeepTutorMessageReducer 是否需要识别并转移/过滤这类括号思考片段。
```

### 3.5 日志存在重复 partial 刷屏

日志中同一 tool call 多次重复：

```text
deeptutor.stream.partial.mapped ... tool=ask_user_question ... events=none forceFlush=true blocks=envelope=1,text=1,trace=1
```

问题：

```text
工具 partial 已经没有新事件，但仍多次 forceFlush=true，导致日志刷屏和 UI 潜在重复刷新。
```

要求：

```text
forceFlush 必须只在 tool start、tool args update、askUser event、tool result、状态变化时触发。
events=none 且 blockSummary 未变化时，不应重复强刷。
```

### 3.6 工具策略天气场景缺少 query_location / get_current_location

模型在日志中推理：

```text
系统中有 query_weather 工具，但需要经纬度坐标。可能需要调用 get_current_location 工具获取用户当前位置，但查看可用工具列表发现没有这个工具。那么只能让用户提供位置信息，或者使用 query_location 工具？但可用工具里也没有 query_location。
```

当前出站工具：

```text
ask_user_question,get_route,query_weather,search_nearby_locations
```

问题：

```text
weather_location 策略挂了 get_route/search_nearby_locations，却没有挂 query_location/get_current_location。
```

如果产品策略是“天气必须先问城市”，可以只挂 ask_user_question + query_weather。

如果产品策略是“允许自动定位/地理编码”，则需要挂：

```text
ask_user_question
query_location
get_current_location
query_weather
```

当前混入 `get_route` 和 `search_nearby_locations` 反而增加模型困惑。

### 3.7 DeepTutorChat 没有挂载项目统一 ToolInteraction sheet

普通 Chat 的工具交互不是每个消息卡片自己弹，而是页面壳层统一挂载：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatView.swift
```

关键实现位置：

```text
ChatView.swift:360 左右
.sheet(
  item: Binding(
    get: { detailViewModel.toolInteractionCoordinator.activePresentation },
    set: { newValue in
      guard newValue == nil else { return }
      detailViewModel.clearToolPreviewRenderContext()
      detailViewModel.toolInteractionCoordinator.dismissActivePresentationByUser()
    }
  )
) { active in
  ToolInteractionPresentationSheet(...)
}
```

统一 sheet 内部对 `.question` 的路由：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ToolInteraction/ToolInteractionPresentationSheet.swift

active.snapshot == .question(prompt)
  -> ToolQuestionSheet(...)
  -> coordinator.completeQuestion(...)
```

DeepTutorChat 当前已经在容器层注入了同一套工具交互协调器：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/App/Sources/App/AppContainer.swift

DeepTutorChatViewModel(
  ...
  toolInteractionCoordinator: chat.toolInteractionCoordinator,
  ...
)
```

但 DeepTutorChat 页面没有对应的 `.sheet(item:)` 宿主：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorChatPage.swift

当前只有：
VStack(...)
  .navigationTitle(...)
  .navigationBarTitleDisplayMode(.inline)
  .task(id: conversationID) { ... }

缺少：
.sheet(item: viewModel.toolInteractionCoordinator.activePresentation)
```

因此当前存在双重阻断：

```text
阻断 A：ask_user_question arguments 在 DeepTutor mapper 阶段丢失或被解析失败，导致消息内 askUser block 不生成。
阻断 B：即使 ToolHub 走项目统一 sheet 并设置 activePresentation，DeepTutorChatPage 没有挂载 sheet，用户也看不到提问/选择面板。
```

这解释了“工具触发之后没有弹出选择提问 sheet”的问题：不是 `ToolQuestionSheet` 本身不存在，而是 DeepTutorChat 的页面壳层没有把统一 sheet 接到当前功能内。

### 3.8 DeepTutorChat 缺少右上角打印调试信息入口

普通 Chat 已有右上角调试入口：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatView.swift:274-279

Button {
  logDebugInfo()
} label: {
  Label(L10n.text("chat.management.print_debug_info"), systemImage: "doc.text.magnifyingglass")
}
```

DeepTutorChat 当前页面：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorChatPage.swift
```

现状：

```text
1. DeepTutorChatPage 没有右上角调试菜单。
2. DeepTutorConversationListPage 右上角只有新建对话按钮。
3. 遇到 ask_user 不展示、会话加载转码失败、toolArguments 丢失、sheet 不弹时，只能依赖散落日志，无法一键打印当前页面状态快照。
```

影响：

```text
1. 排查成本高，无法快速确认当前 conversationID、messageID、phase、isStreaming、activePresentation。
2. 无法快速导出当前消息 blocks/events，定位 askUserBlocks 为什么为 0。
3. 无法确认 tool policy、allowedTools、tool schema、active sheet 状态是否和 UI 表现一致。
```

## 4. DeepTutor Web 对齐要求

### 4.1 Web 的 ask_user 渲染位置

参考文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ChatMessages.tsx
```

Web 关键链路：

```text
AssistantMessage
  -> extractAskUserPayload(msg.events)
  -> extractMessageSegments(msg.events)
  -> hasInlineAskUser
  -> <AskUserOptions data={seg.data} onSubmit={onSubmitUserReply} />
```

对齐点：

```text
1. ask_user 是消息事件流的一部分，不是全局弹窗附属物。
2. 默认 chat 分支必须把正文和 ask_user 卡片按事件顺序交错渲染。
3. research 分支把 ask_user Q&A 放在 outline 上方。
4. 非默认分支有 fallback，把 ask_user 卡片放到正文下方。
```

### 4.2 Web 的 ask_user 是暂停并恢复同一 turn

Web 语义：

```text
ask_user pauses the turn and resumes with the user's reply.
```

iOS 对齐要求：

```text
1. ask_user_question 调用成功后，assistant 消息状态应进入 awaitingUserInput 或等价状态。
2. UI 卡片提交后，不应新开无关会话或普通消息分支。
3. 用户 reply 应回到同一 toolCallID / same assistant message。
4. 后续模型回答应继续追加到同一助手消息或按 DeepTutor Web 对齐规则合并。
```

### 4.3 Web 支持自由输入式追问

本次例子是：

```text
问题：你想查询哪个城市的天气呢？
选项：[]
允许其他输入：true
```

DeepTutor Web 的 ask_user 卡片应允许这种自由输入追问，不要求必须有 2-5 个选项。

iOS 需要对齐：

```text
1. options 为空且 allows_other=true 时，渲染输入框和提交按钮。
2. options 为空且 allows_other=false 时，视为协议错误，展示错误 trace，不展示空卡片。
3. options 非空时渲染选项 chip，selection_mode 控制单选/多选。
```

## 5. 当前 iOS 关键代码位置

| 职责 | 文件 |
| --- | --- |
| AI Runtime partial 到 DeepTutor events 映射 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorAIRuntimeEventMapper.swift` |
| ask_user payload 归一化 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorAskUserNormalizer.swift` |
| 消息 events 到 blocks reducer | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorMessageReducer.swift` |
| ViewModel trace / blocks 状态日志 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorChatViewModel.swift` |
| AI Runtime 接入与 partial flush | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorAIRuntimeAdapter.swift` |
| 发送消息与流式落库 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/SendDeepTutorAIMessageUseCase.swift` |
| ask_user 卡片 UI | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Cards/DeepTutorAskUserCardView.swift` |
| DeepTutor 会话页面壳层 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorChatPage.swift` |
| 普通 Chat 右上角调试入口参考 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatView.swift:274` |
| 普通 Chat 统一工具 sheet 挂载参考 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatView.swift:360` |
| 统一工具 sheet 路由 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ToolInteraction/ToolInteractionPresentationSheet.swift` |
| 统一提问 sheet UI | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ToolInteraction/Sheets/ToolQuestionSheet.swift` |
| DeepTutorChat ViewModel 装配位置 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/App/Sources/App/AppContainer.swift` |
| ToolHub ask_user 执行 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ToolHub/Executors/ToolHubAskUserQuestion.swift` |
| ToolHub question 参数解析 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ToolHub/ToolHub+Shared.swift` |
| Tool call stream 收集 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ChatOrchestrator.swift` |

## 6. 根因假设与排查顺序

### 6.1 P0 根因一：partial 缺少 toolArguments

证据：

```text
deeptutor.ask_user.map_failed ... argumentKeys=- rawLength=0
```

但 AI 请求回灌中又有：

```text
"arguments":"{\"question\":\"你想查询哪个城市的天气呢？\",\"options\":[],\"selection_mode\":\"single\",\"allows_other\":true}"
```

排查方向：

```text
1. ChatOrchestrator.collectRuntimeResponse 是否在 tool_call delta 阶段累积了 arguments。
2. onPartial(ChatAssistantPartialDelta) 是否在 tool call started / completed 时带出 toolArguments。
3. ToolInvocation.arguments 是否被传入 partial.toolInvocationArguments。
4. DeepTutorAIRuntimeEventMapper 是否只消费 partial，而 completionEvents 没有补偿解析 output.toolContent。
```

验收标准：

```text
模型返回 ask_user_question arguments 后，日志必须出现：
deeptutor.ask_user.mapped phase=tool_started/tool_completed questionCount=1
且 rawLength > 0 或 argumentKeys 包含 question/options/allows_other。
```

### 6.2 P0 根因二：ToolHub 不接受自由输入追问

证据：

```text
【系统】ask_user_question 参数无效：需提供 1-5 个问题，每个问题的 options 必须包含 2-5 个选项。
```

当前实现要求：

```text
question 非空 且 options 数量必须在 2...5。
```

但 DeepTutor Web 对齐要求：

```text
options 为空 + allows_other=true 是合法自由输入卡片。
```

验收标准：

```text
ask_user_question({ question, options: [], allows_other: true }) 必须生成可输入的消息内卡片，而不是参数无效。
```

### 6.3 P0 根因三：ToolHub sheet 模式与 DeepTutor 消息内卡片模式冲突

当前 ToolHub 逻辑：

```text
toolInteractionCoordinator.requestQuestionAnswer(...)
```

这更像通用 Chat 的 sheet 交互。

DeepTutor Web 对齐要求：

```text
ask_user 在助手消息内渲染卡片，由卡片 submit_user_reply 恢复本轮。
```

后续需要决策：

```text
1. 当前阶段先不要绕过通用 sheet，必须先把项目已有统一 sheet 接入 DeepTutorChat，恢复工具提问的基础可用性。
2. DeepTutor Web 完全对齐阶段，再决定是否把 ask_user 从 sheet 迁移为消息内 block，或采用 sheet + 消息摘要双渲染。
3. ToolHub 是否返回 awaitingUserInput=true，等待 DeepTutorAskUserCardView 提交，需要在 P1 阶段单独设计。
4. ToolInteractionCoordinator 是否需要支持 inline presentation mode，需要与项目统一工具交互架构一起评估，不能在 DeepTutorChat 内私有 fork 一套。
```

### 6.4 P1 根因四：天气工具策略不完整

当前 weather_location 允许工具：

```text
ask_user_question,get_route,query_weather,search_nearby_locations
```

问题：

```text
1. 缺少 query_location/get_current_location。
2. 多了 get_route/search_nearby_locations，天气查询不需要路线和附近地点。
3. 模型因此在工具选择阶段产生困惑。
```

建议：

```text
天气策略分成两个版本：

无定位权限/无城市：
  ask_user_question, query_weather

有定位权限或允许自动定位：
  ask_user_question, get_current_location, query_location, query_weather
```

### 6.5 P0 根因五：DeepTutorChatPage 缺少 activePresentation sheet 宿主

普通 Chat 流程：

```text
ToolHub ask_user_question
  -> ToolInteractionCoordinator.requestQuestionAnswer(...)
  -> activePresentation = .question(prompt)
  -> ChatView .sheet(item: activePresentation)
  -> ToolInteractionPresentationSheet
  -> ToolQuestionSheet
  -> coordinator.completeQuestion(...)
  -> ToolHub 继续返回工具结果
```

DeepTutorChat 当前流程：

```text
ToolHub ask_user_question
  -> ToolInteractionCoordinator.requestQuestionAnswer(...)
  -> activePresentation = .question(prompt)
  -> DeepTutorChatPage 没有 .sheet(item:)
  -> 用户看不到选择/提问 sheet
  -> 工具等待、取消、超时或返回异常
  -> 消息内也没有 askUser block
```

验收标准：

```text
当 toolInteractionCoordinator.activePresentation 变为 .question 时：
1. DeepTutorChat 页面必须弹出与普通 Chat 一致的 ToolQuestionSheet。
2. 日志必须打印 deeptutor.tool_sheet.presented snapshot=question。
3. 用户提交后必须打印 deeptutor.tool_sheet.completed snapshot=question answerCount=...。
4. 用户关闭后必须打印 deeptutor.tool_sheet.dismissed snapshot=question reason=user。
```

### 6.6 P1 根因六：缺少页面级调试快照

当前问题横跨：

```text
1. 本地数据库加载。
2. message decoding。
3. AI Runtime partial。
4. tool_call arguments。
5. ToolHub 执行。
6. ToolInteractionCoordinator activePresentation。
7. MessageReducer blocks。
8. UIKit message list reload。
```

如果没有页面级“一键打印调试信息”，每次排查都要从大量流式日志里拼状态。

DeepTutorChat 需要对齐普通 Chat 的 `logDebugInfo()` 能力，并专门增加 DeepTutor 字段。

## 7. 后续实现要求

### 7.1 必须保证 ask_user event 先于 ToolHub 失败被 UI 消费

即使 ToolHub 后续执行返回参数错误，只要模型原始 tool_call arguments 能构成 DeepTutorAskUserPayload，就应该先生成 `.askUser` event，让 UI 展示卡片。

目标：

```text
模型 ask_user_question arguments
  -> DeepTutorAIRuntimeEventMapper
  -> .askUser(payload, toolCallID)
  -> DeepTutorMessageReducer
  -> askUser block
  -> DeepTutorAskUserCardView
```

### 7.2 ToolHub ask_user_question 需要支持自由输入

规则：

| 参数 | 是否合法 | UI |
| --- | --- | --- |
| `question` 非空，`options=[]`，`allows_other=true` | 合法 | 自由输入卡片 |
| `question` 非空，`options=nil`，`allows_other=true` | 合法 | 自由输入卡片 |
| `question` 非空，`options=2...5` | 合法 | 选项卡片 |
| `questions` 数组 1...5，每题 options 空且 allows_other=true | 合法 | 多问题自由输入 |
| `question` 空 | 非法 | 错误 trace |
| options 空且 allows_other=false | 非法 | 错误 trace |

### 7.3 DeepTutorChat 必须使用消息内卡片，不优先使用 sheet

本节是 DeepTutor Web 完全对齐阶段目标，不应阻塞 P0 的统一 sheet 接入。

P0 当前必须先做到：

```text
ToolHub ask_user_question
  -> 项目统一 ToolInteractionPresentationSheet
  -> ToolQuestionSheet 弹出
  -> 用户提交
  -> 工具链路继续
```

P1 最终目标体验：

```text
Assistant trace
Assistant text before ask_user
AskUser card inline
User submits answer
Assistant continues final answer
```

不符合对齐的体验：

```text
1. 只弹 sheet，消息内没有卡片。
2. sheet 消失后消息里只有工具失败文本。
3. 用户回答被当成新普通消息，不能恢复同一 ask_user turn。
```

阶段约束：

```text
1. P0 允许先使用统一 sheet，确保“工具提问可见、可提交、可继续”。
2. P1 如要求完全对齐 DeepTutor Web，则必须把提问交互沉淀回消息内卡片，或在消息内展示已提问/已回答摘要。
3. 不允许 DeepTutorChat 私自做一套视觉不同、数据结构不同、刷新机制不同的问答弹窗。
```

### 7.4 answerLen/reasoningLen 与思考文本需要分流

要求：

```text
1. 正文 content 不应展示“（思考：...）”这类模型内部工具决策文本。
2. 若供应商把思考放进 content，需要在 DeepTutor 层进行迁移或过滤。
3. trace 展示思考，AssistantResponse 展示正式正文。
```

### 7.5 partial forceFlush 需要去重

日志中 `events=none forceFlush=true` 重复很多次。后续需要：

```text
1. toolName 存在但 callID 已开始且无新 arguments / 无新 result 时，不强制 UI flush。
2. 只有 askUser event、toolStart 首次、toolResult 首次、blockSummary 变化时 forceFlush。
3. 日志增加 skipped reason，例如 deeptutor.stream.partial.skipped_duplicate_tool_state。
```

### 7.6 DeepTutorChat 必须接入项目统一 ToolInteraction sheet

实现要求：

```text
1. DeepTutorChatPage 需要像普通 ChatView 一样挂载 .sheet(item:)。
2. sheet 的数据源必须来自 viewModel.toolInteractionCoordinator.activePresentation。
3. .question 必须复用项目已有 ToolQuestionSheet，不重新设计一套临时 UI。
4. 用户手动关闭 sheet 时，需要调用 dismissActivePresentationByUser()，避免 coordinator 悬挂。
5. 提交答案时，需要通过 coordinator.completeQuestion(...) 回写，不能把答案当普通用户消息直接发送。
```

推荐落地方式：

```text
优先方案：
  DeepTutorChatPage 直接复用 ToolInteractionPresentationSheet。

如果完整 ToolInteractionPresentationSheet 依赖 ChatStateStore、MemberContextStore、AISettingsViewModel 等普通 Chat 上下文，DeepTutorChat 暂时无法完整提供：
  1. 在 DeepTutorChat 内新增 DeepTutorToolInteractionSheetHost。
  2. Host 仍消费同一个 ToolInteractionCoordinator.ActivePresentation。
  3. .question 分支直接复用 ToolQuestionSheet。
  4. 其他 snapshot 分支先显示“当前 DeepTutorChat 暂不支持此工具交互”的统一提示，或延后接入完整依赖。
  5. 不允许复制 ToolQuestionSheet 视觉与逻辑后分叉维护。
```

刷新要求：

```text
1. activePresentation 从 nil -> .question 时，页面必须立即弹 sheet。
2. activePresentation 从 .question -> nil 时，sheet 必须关闭。
3. 关闭 sheet 不应触发消息列表整屏重载。
4. 用户提交答案后，消息列表应保持当前位置，后续 AI 正式回答流式追加。
5. 如果页面被 pop 或 conversationID 切换，必须清理当前 DeepTutorChat 相关 activePresentation，避免串到其他对话。
```

日志要求：

```text
deeptutor.tool_sheet.state_changed conversation=... active=true snapshot=question presentationID=...
deeptutor.tool_sheet.presented conversation=... snapshot=question questionCount=...
deeptutor.tool_sheet.submit conversation=... snapshot=question answerCount=... answerLengths=...
deeptutor.tool_sheet.dismissed conversation=... snapshot=question reason=user|completed|conversation_changed
deeptutor.tool_sheet.unsupported_snapshot conversation=... snapshot=...
```

### 7.7 DeepTutorChat 右上角增加打印调试信息

参考普通 Chat：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatView.swift:274-279
Button { logDebugInfo() } label {
  Label(L10n.text("chat.management.print_debug_info"), systemImage: "doc.text.magnifyingglass")
}
```

DeepTutorChat 要求：

```text
1. DeepTutorChatPage 右上角增加菜单或按钮，位置对齐普通 Chat 的 navigationBarTrailing。
2. 按钮文案优先复用 L10n.text("chat.management.print_debug_info")。
3. 图标优先复用 systemImage: "doc.text.magnifyingglass"。
4. 点击后调用 DeepTutorChatViewModel.logDebugInfo() 或同等页面级方法。
5. 打印到项目统一 logger，不使用 print。
```

调试信息至少包含：

```text
conversationID
conversationTitle
selectedConversationID
currentModelName
activeCapability
phase
isStreaming
draftLength
messageCount
assistantMessageCount
userMessageCount
latestMessageID
latestAssistantMessageID
latestMessageStatus
blockCount
blockKinds
askUserBlockCount
traceBlockCount
textBlockCount
eventCount
eventTypes
latestToolPolicyReason
latestAllowedTools
latestToolSchemaNames
activePresentationID
activePresentationSnapshot
toolQuestionCount
lastError
localDBConversationLoaded
localDBMessageLoadedCount
decodeFailureCount
refreshCoordinatorState
keyboardFocusState
```

JSON 导出要求：

```text
1. 输出当前会话 messages JSON。
2. 每条消息包含 id、role、status、contentLength、contentPreview、createdAt、updatedAt。
3. 每条消息包含 blocks summary：blockID、kind、toolCallID、isStreaming、payloadLength。
4. 每条消息包含 events summary：eventID、type、toolName、toolCallID、rawArgumentLength、createdAt。
5. ask_user payload 可以完整打印，不需要脱敏。
6. 正文 content 可以完整打印，不需要脱敏。
```

注意：

```text
本项目 DeepTutorChat 日志按用户要求不做脱敏。调试信息可以打印完整问题、完整回答、完整 tool arguments，用于本地排查。
```

## 8. 日志需求

### 8.1 ask_user 原始参数日志

新增或补齐：

```text
deeptutor.ask_user.raw_arguments
```

字段：

```text
conversation
message
toolCallID
phase
rawLength
raw
argumentKeys
```

目标：

```text
排查 tool_call arguments 是供应商没吐、runtime 没累积、partial 没传，还是 mapper 没解析。
```

### 8.2 ask_user payload 归一化日志

成功：

```text
deeptutor.ask_user.mapped phase=tool_started tool=ask_user_question call=... questionCount=1 optionCounts=0 allowsOther=true mode=free_text
```

失败：

```text
deeptutor.ask_user.map_failed phase=tool_started tool=ask_user_question call=... reason=missing_arguments/raw_invalid/question_empty/options_invalid
```

### 8.3 reducer 日志

```text
deeptutor.message_reducer.ask_user_block_created
deeptutor.message_reducer.ask_user_block_skipped
```

字段：

```text
message
toolCallID
questionCount
blockID
reason
```

### 8.4 UI 渲染日志

```text
deeptutor.ask_user.card_visible
deeptutor.ask_user.card_submit
deeptutor.ask_user.card_resolved
```

字段：

```text
conversation
message
blockID
toolCallID
questionCount
answerLength
```

### 8.5 统一 sheet 日志

新增：

```text
deeptutor.tool_sheet.state_changed
deeptutor.tool_sheet.presented
deeptutor.tool_sheet.submit
deeptutor.tool_sheet.completed
deeptutor.tool_sheet.dismissed
deeptutor.tool_sheet.unsupported_snapshot
```

字段：

```text
conversation
message
toolCallID
presentationID
snapshot
questionCount
answerCount
answerLengths
reason
```

用途：

```text
确认 ToolHub 是否真的触发 coordinator，DeepTutorChatPage 是否真的弹出 sheet，以及用户提交是否回到同一工具调用。
```

### 8.6 右上角调试信息日志

新增：

```text
deeptutor.debug.snapshot
deeptutor.debug.messages_json
deeptutor.debug.active_tool_presentation
```

字段：

```text
conversation
phase
isStreaming
messageCount
blockKinds
askUserBlockCount
eventTypes
activePresentationSnapshot
allowedTools
schemaNames
decodeFailureCount
```

要求：

```text
1. 点击右上角“打印调试信息”必须同步输出 summary 和 JSON 两段日志。
2. 日志不脱敏，完整保留 content、tool arguments、ask_user payload。
3. JSON 编码失败时，也必须打印 fallback summary，不能静默失败。
```

## 9. 验收用例

### 9.1 天气先问城市

输入：

```text
今天的天气怎么样
```

期望：

```text
1. allowedTools 不包含 SparkToolName.all。
2. 模型调用 ask_user_question。
3. ask_user arguments 被 mapper 捕获。
4. askUserBlocks 从 0 变成 1。
5. P0 阶段：弹出项目统一 ToolQuestionSheet，展示“你想查询哪个城市的天气呢？”自由输入。
6. P1 阶段：消息内展示“你想查询哪个城市的天气呢？”自由输入卡片，并与 Web 事件顺序对齐。
7. 用户输入城市后，sheet 关闭或卡片变为已回答状态。
8. 后续继续查询天气或要求补充经纬度，不显示“参数无效”。
```

### 9.2 选项式追问

输入：

```text
帮我制定学习计划，先问我学习目标。
```

模型可能返回：

```json
{
  "question": "你的主要学习目标是什么？",
  "options": ["考试提分", "系统入门", "项目实践"],
  "selection_mode": "single",
  "allows_other": true
}
```

期望：

```text
展示单选 chip + 其他输入入口。
```

### 9.3 多问题追问

模型可能返回：

```json
{
  "questions": [
    { "question": "你想学习哪门课？", "options": [], "allows_other": true },
    { "question": "你每天能学习多久？", "options": ["30分钟", "1小时", "2小时"], "allows_other": true }
  ]
}
```

期望：

```text
展示多问题卡片，并能一次提交结构化答案。
```

### 9.4 参数错误可见但不污染正文

如果 question 为空或 payload 非 JSON：

```text
1. trace 中显示 ask_user 参数错误。
2. 正文不展示系统内部错误大段文本。
3. 不生成空卡片。
4. 日志明确 reason。
```

### 9.5 DeepTutor Web UI 对齐

对齐点：

```text
1. P0 阶段必须先让项目统一 ToolQuestionSheet 可见、可提交、可恢复工具链路。
2. P1 阶段 AskUser 卡片位于助手消息内部。
3. P1 阶段卡片与正文按事件顺序交错。
4. 用户提交后 sheet 关闭，或卡片进入 resolved/summary 状态。
5. trace 在顶部，ask_user 卡片在正文分支中；如短期使用 sheet，消息内必须至少留下提问/已回答摘要，避免消息流断裂。
```

### 9.6 统一 sheet 弹出验收

输入：

```text
今天的天气怎么样
```

期望：

```text
1. ToolHub 触发 toolInteractionCoordinator.activePresentation = .question。
2. DeepTutorChatPage 监听到 activePresentation。
3. 页面弹出与普通 Chat 一致的 ToolQuestionSheet。
4. sheet 文案、输入框、提交按钮、取消按钮样式复用项目统一组件。
5. 用户提交城市后，coordinator.completeQuestion 被调用。
6. 日志出现 deeptutor.tool_sheet.presented 和 deeptutor.tool_sheet.completed。
7. 不出现 activePresentation 已设置但 UI 无弹窗的状态。
```

### 9.7 右上角打印调试信息验收

操作：

```text
进入 DeepTutorChat 对话页，点击右上角调试菜单中的“打印调试信息”。
```

期望：

```text
1. 菜单入口位置、文案、图标对齐普通 Chat。
2. 日志输出 deeptutor.debug.snapshot。
3. 日志输出当前会话 messages JSON。
4. JSON 中能看到 ask_user tool_call arguments、events、blocks、activePresentation。
5. 日志不脱敏，完整保留问题正文和工具参数。
```

## 10. 实施拆分

### P0：修复 ask_user payload 从 tool_call arguments 到 DeepTutor event 的链路

要求：

```text
1. ChatAssistantPartialDelta 必须携带原始 toolArguments。
2. DeepTutorAIRuntimeEventMapper 在 tool_started 或 tool_completed 阶段能解析到 payload。
3. completionEvents 需要兜底处理 finish=tool_calls 但 partial 未带 args 的情况。
```

### P0：支持 options 为空 + allows_other=true

要求：

```text
1. DeepTutorAskUserNormalizer 已支持 options 为空，需要确保 ToolHub 同步支持。
2. ToolHub parseQuestionItems 不再把自由输入追问判为无效。
3. DeepTutorAskUserCardView 必须展示自由输入框。
```

### P0：接入项目统一 ToolInteraction sheet

要求：

```text
1. DeepTutorChatPage 挂载 toolInteractionCoordinator.activePresentation。
2. .question 分支复用 ToolQuestionSheet。
3. 用户提交后通过 coordinator.completeQuestion 回到 ToolHub。
4. 用户取消后通过 coordinator.completeQuestionCancelled 或 dismissActivePresentationByUser 收束。
5. 页面切换/会话切换时清理当前 DeepTutorChat 相关 presentation。
6. 增加 sheet presented/submit/completed/dismissed 全链路日志。
```

### P0：右上角增加打印调试信息入口

要求：

```text
1. DeepTutorChatPage 右上角增加与普通 Chat 一致的调试菜单/按钮。
2. 复用 chat.management.print_debug_info 文案和 doc.text.magnifyingglass 图标。
3. 输出 DeepTutor 专用 summary。
4. 输出 messages/events/blocks/tool presentation JSON。
5. 日志不脱敏。
```

### P1：DeepTutor Web inline ask_user 与项目统一 sheet 的长期对齐

要求：

```text
1. 短期 P0 使用统一 sheet 保证功能可用。
2. 长期 P1 对齐 DeepTutor Web 的消息内卡片：AssistantMessage 内按事件顺序渲染 AskUser。
3. 两条链路共用 ToolQuestionItem / ToolQuestionAnswer 数据结构。
4. 如果保留 sheet，也必须在消息流中留下 ask_user 提问和回答摘要，不能让对话上下文断层。
5. 最终形态由产品确认：纯 inline、纯 sheet + 消息摘要、或 inline + sheet 辅助输入。
```

### P1：天气工具策略纠偏

要求：

```text
1. weather_location 策略不要挂 get_route/search_nearby_locations。
2. 明确 query_location/get_current_location 的策略。
3. 如果没有定位工具，就优先 ask_user_question 问城市。
```

### P2：日志降噪与思考正文分流

要求：

```text
1. 去掉重复 events=none forceFlush=true。
2. “（思考：...）”类内容不进入正式正文。
3. trace.final_phase 只在状态变化时打印。
```

## 11. 风险与注意事项

### 11.1 不要只修 UI

当前不是卡片 View 不漂亮或没有被插入列表这么简单。核心是：

```text
events 里没有 ask_user payload，MessageReducer 没有 askUser block。
```

如果只改 `DeepTutorAskUserCardView`，不会解决问题。

### 11.2 不要只改 prompt

要求模型“必须提供 2-5 个 options”可以减少参数错误，但不对齐 DeepTutor Web。DeepTutor Web 支持自由输入追问，iOS 也应该支持。

### 11.3 不要让 ToolHub 参数错误吞掉可渲染卡片

只要原始 tool_call arguments 可以归一化为 AskUser payload，就应该进入消息内卡片。ToolHub 执行层的错误不能优先把交互卡片短路掉。

### 11.4 不要把 ask_user 回复当成普通用户消息

用户对卡片的回答是对某个 `toolCallID` 的结构化回复，不是普通新问题。必须保留：

```text
conversationID
assistantMessageID
toolCallID
questionID
answers
```

## 12. 最终验收标准

实现完成后必须满足：

```text
1. 日志不再出现 ask_user.map_failed rawLength=0，除非供应商确实没有返回 arguments。
2. ask_user_question({question, options: [], allows_other: true}) 能展示自由输入提问卡片。
3. askUserBlocks 至少从 0 变为 1，并能在 UI 中看到卡片。
4. ToolHub 不再对自由输入追问返回“options 必须包含 2-5 个选项”。
5. 消息内卡片布局对齐 DeepTutor Web：trace 在上，正文与 ask_user 卡片按事件顺序展示。
6. 用户提交卡片答案后，卡片进入已回答状态，并能继续同一会话生成。
7. 天气问题不会暴露路线/附近地点等无关工具。
8. 重复 partial 日志显著减少。
9. 正文不再显示“（思考：...）”这类内部工具决策文本。
10. 通用 Chat 现有 sheet ask_user 能力不被破坏。
11. DeepTutorChat 触发 ask_user_question 后，项目统一 ToolQuestionSheet 能弹出。
12. DeepTutorChat 右上角存在“打印调试信息”入口，并能输出完整未脱敏调试快照。
13. activePresentation 不会因为缺少页面 sheet 宿主而悬挂。
14. 文档明确区分 P0 统一 sheet 可用性与 P1 DeepTutor Web inline 卡片完全对齐，不再混淆两条链路。
```

本工单只完成分析与需求创建，未修改 Swift 业务实现代码。
