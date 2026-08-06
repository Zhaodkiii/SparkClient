# DEEPTUTORCHAT-000003 接入项目 AIConfigCenter 真实大模型系统工单

> 创建日期：2026-08-05  
> 所属模块：DeepTutorChat / iOS 真实 AI 模型接入  
> 工单状态：待实现  
> 关联文档：`DEEPTUTORCHAT-000001-iOS本地消息UI对齐DeepTutor-Web需求文档.md`、`DEEPTUTORCHAT-000002-新建对话日志与实现偏差修正工单.md`  
> 处理边界：本工单只创建需求与技术工单，不直接修改 Swift 代码。

---

## 1. 工单目标

当前 DeepTutorChat 的消息发送链路仍然使用本地模拟器：

```text
DeepTutorChatViewModel
  -> SendLocalDeepTutorMessageUseCase
  -> DeepTutorLocalReplySimulator
  -> 本地生成 fixture / echo / ask_user / quiz / research placeholder
```

本工单要求将 DeepTutorChat 接入项目已有的大模型系统：

```text
AIConfigCenter
  -> ScenarioPolicyResolver
  -> AIRuntimeService
  -> OpenAICompatibleTextGateway / LocalGGUFTextGateway
  -> AIRuntimeStreamEvent
```

最终目标：

1. DeepTutorChat 不再使用本地模拟回复作为主路径。
2. 消息发送真实消费项目已有 AI 模型配置。
3. 模型选择、厂商、API Key、endpoint、temperature、topP、maxTokens 全部走项目已有 `AIConfigCenter`。
4. 流式 UI 使用真实 `AIRuntimeStreamEvent` 驱动。
5. thinking、tool call、工具结果、ask_user、正文增量都要转换成 DeepTutorChat 自己的消息事件与 UI blocks。
6. 未对齐 DeepTutor Web 的消息渲染、工具调用、思考过程、刷新方式必须纳入接入验收。

---

## 2. 当前代码事实

### 2.1 DeepTutorChat 当前发送链路

关键文件：

```text
SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorChatViewModel.swift
SparkClient/Projects/Features/DeepTutorChat/Application/SendLocalDeepTutorMessageUseCase.swift
SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorMessageReducer.swift
SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorLocalChatStore.swift
```

当前 ViewModel 持有：

```swift
private let sendMessageUseCase: SendLocalDeepTutorMessageUseCase
```

当前发送用例核心逻辑：

```swift
let simulation = DeepTutorLocalReplySimulator.simulate(
    userText: trimmed,
    capability: capability,
    assistantMessageID: assistant.id,
    conversationID: conversationID
)

for step in simulation.steps {
    try await Task.sleep(nanoseconds: step.delayNanoseconds)
    assistant = step.apply(assistant)
    assistant = DeepTutorMessageReducer.applyBlocks(to: assistant)
    _ = try await repository.upsertMessage(assistant)
}
```

结论：

```text
当前 DeepTutorChat 不消费真实模型。
当前没有调用 AIConfigCenter。
当前没有调用 AIRuntimeService。
当前没有调用 OpenAICompatibleTextGateway。
当前没有 token / API 消费。
当前 tool / thinking / ask_user 主要来自本地 fixture。
```

### 2.2 项目已有 AI 模型系统

用户指定的模型配置入口：

```text
SparkClient/Projects/Core/AI/AIConfigCenter.swift
```

关键能力：

```swift
func resolve(for scenario: AIScenario, preferredModelName: String? = nil) async throws -> AIResolvedConfig
func effectiveScenarioBundles() async throws -> AIScenarioRemoteBundlesCollection
func currentSnapshot(ownerAccountID: Int64? = nil) async -> AISettingsSnapshot
func reloadLocalSnapshot(ownerAccountID: Int64? = nil) async -> AISettingsSnapshot
func updateScenarioDefaultModel(_ modelName: String, for scenario: AIScenario) async
func setRuntimeOverride(_ config: AIScenarioConfig, for scenario: AIScenario) async
func clearRuntimeOverride(for scenario: AIScenario) async
```

AI Runtime 主入口：

```text
SparkClient/Projects/Core/AIRuntime/AIRuntimeService.swift
```

核心接口：

```swift
protocol AIRuntimeServing: Sendable {
    func generateTextStream(
        request: AIRuntimeTextRequest
    ) async throws -> AsyncThrowingStream<AIRuntimeStreamEvent, Error>
}
```

`AIRuntimeService` 内部行为：

```text
1. 通过 AIConfigCenter.resolve 解析当前场景配置。
2. 从 effectiveScenarioBundles 判断模型能力。
3. 如选择本地模型，走 LocalGGUFTextGateway。
4. 如选择云端模型，走 AIClientFactory + OpenAICompatibleTextGateway。
5. 自动传递 endpoint、model、apiKey、temperature、topP、maxTokens。
6. 统一输出 AIRuntimeStreamEvent。
```

OpenAI-compatible 网关：

```text
SparkClient/Projects/Core/AIRuntime/OpenAICompatibleTextGateway.swift
```

关键行为：

```text
POST endpoint
Authorization: Bearer apiKey
stream: true
messages
tools
toolChoice
reasoning extras
```

### 2.3 当前 AIScenario 状态

当前已有场景：

```swift
enum AIScenario: String, Codable, CaseIterable, Sendable {
    case chat
    case embedding
    case voice
    case medicalStructuredExtraction = "medical_structured_extraction"
    case medicalDocumentTypeRecognition = "medical_document_type_recognition"
    case medicalCaseExtraction = "medical_case_extraction"
    case healthExamExtraction = "health_exam_extraction"
    case medicalReportExtraction = "medical_report_extraction"
    case prescriptionExtraction = "prescription_extraction"
    case medicationExtraction = "medication_extraction"
    case medicineBoxExtraction = "medicine_box_extraction"
    case optimizationText = "optimization_text"
    case optimizationVisual = "optimization_visual"
    case contextFolding = "context_folding"
    case router
    case modelConfig = "model_config"
    case reportInterpretation = "report_interpretation"
    case nutritionIntakeExtraction = "nutrition_intake_extraction"
    case medicalExamPlanGeneration = "medical_exam_plan_generation"
}
```

当前场景策略：

```text
只使用 AIScenario.chat。
不需要新增 DeepTutor 专属 AIScenario。
DeepTutorChat 的业务能力通过 capability 和 prompt 区分。
```

因此本工单明确最终产品/架构决策：

```text
DeepTutorChat 固定复用通用 AIScenario.chat。
不要新增 AIScenario.deepTutor / AIScenario.deepTutorChat。
不要为 DeepTutorChat 新增独立场景 bundle、远程配置字段、设置页场景或本地化场景文案。
```

本工单结论：

```text
DeepTutorChat 的模型消费统一归入通用 chat 场景。
DeepTutor 的差异通过 PromptBuilder、capability、tools、message reducer 和 UI blocks 表达。
模型选择、厂商、endpoint、API Key、temperature、topP、maxTokens 均沿用 chat 场景配置。
```

---

## 3. 必须修复的问题

### 3.1 问题一：DeepTutorChat 当前仍是本地模拟

当前问题：

```text
用户以为在使用 AI 对话，但实际只是本地 simulator。
无法验证真实模型能力。
无法验证厂商 tool call / reasoning / stream delta 差异。
无法验证 token、模型配置、API Key、endpoint 是否正确消费。
无法对齐 DeepTutor Web 真实流式体验。
```

修复要求：

```text
SendLocalDeepTutorMessageUseCase 不再作为主发送链路。
新增真实模型发送用例，例如 SendDeepTutorAIMessageUseCase。
本地 simulator 只能保留为 debug fixture / offline fallback，默认关闭。
```

### 3.2 问题二：未接入 AIConfigCenter

当前问题：

```text
DeepTutorChat 不读取 AISettingsSnapshot。
DeepTutorChat 不解析 AIScenario。
DeepTutorChat 不消费用户选择模型。
DeepTutorChat 不支持运行时 override。
DeepTutorChat 不知道最终 provider / model / endpoint。
```

修复要求：

```text
DeepTutorChatViewModel 或 UseCase 必须注入 AIConfigCenter / AIRuntimeServing。
发送前必须通过 AIConfigCenter.resolve 或 AIRuntimeService 间接解析真实模型。
模型选择优先使用 composer/runtime flags 或 conversation.currentModelName。
固定使用 AIScenario.chat，不新增 DeepTutor 专属 AIScenario。
```

### 3.3 问题三：未对齐 DeepTutor Web 的真实事件语义

DeepTutor Web 的助手消息链路：

```text
AssistantActivity
  -> trace / tool calls / thinking
AssistantResponse
  -> MarkdownRenderer
AssistantMessage capability branch
  -> research / quiz / animation / visualization / ask_user / default markdown
```

iOS 当前有 UI blocks，但真实事件来源不足：

```text
DeepTutorMessageReducer
  -> 从 DeepTutorStreamEvent 生成 blocks
DeepTutorTraceFormatter
  -> trace rows
DeepTutorThinkingCardView
  -> thinking
DeepTutorAskUserCardView
  -> ask_user
```

缺口：

```text
AIRuntimeStreamEvent.textDelta 尚未映射到 DeepTutorStreamEvent.contentDelta。
AIRuntimeStreamEvent.reasoningDelta 尚未映射到 DeepTutorStreamEvent.reasoningDelta。
AIRuntimeStreamEvent.toolCallDelta 尚未稳定组装为 toolCallStarted/toolResult/trace。
AIRuntimeStreamEvent.completed 尚未写入模型名、token、finishReason、最终内容。
厂商工具调用与 DeepTutor Web 工具 trace 语义未对齐。
```

---

## 4. 目标架构

### 4.1 推荐调用链

```text
DeepTutorComposerView
  -> DeepTutorChatViewModel.sendMessage()
  -> SendDeepTutorAIMessageUseCase
  -> DeepTutorAIRuntimeAdapter
  -> AIRuntimeService.generateTextStream()
  -> AIConfigCenter.resolve(for: .chat)
  -> OpenAICompatibleTextGateway / LocalGGUFTextGateway
  -> AIRuntimeStreamEvent
  -> DeepTutorAIRuntimeEventMapper
  -> DeepTutorMessageReducer.applyBlocks
  -> DeepTutorLocalChatRepository.upsertMessage
  -> DeepTutorChatNotifications
  -> DeepTutorMessageListView refresh
```

### 4.2 新增职责建议

建议新增或重命名的职责：

```text
Application/
├── SendDeepTutorAIMessageUseCase.swift
├── DeepTutorAIRuntimeAdapter.swift
├── DeepTutorAIRuntimeEventMapper.swift
├── DeepTutorPromptBuilder.swift
├── DeepTutorRuntimeRequestBuilder.swift
└── DeepTutorGenerationSession.swift
```

说明：

```text
SendDeepTutorAIMessageUseCase
  负责发送主流程、写入 user/assistant message、消费 runtime stream、落库刷新。

DeepTutorAIRuntimeAdapter
  负责隔离 DeepTutorChat 与 AIRuntimeService 的接口差异。

DeepTutorAIRuntimeEventMapper
  负责把 AIRuntimeStreamEvent 转成 DeepTutorStreamEvent。

DeepTutorPromptBuilder
  负责构造 DeepTutor system prompt、capability prompt、上下文引用说明。

DeepTutorRuntimeRequestBuilder
  负责把历史消息、附件、上下文、模型偏好转换成 AIRuntimeTextRequest。

DeepTutorGenerationSession
  负责 cancellationToken、assistantMessageID、operationID、stream 状态。
```

### 4.3 现有组件复用边界

必须复用：

```text
AIConfigCenter
ScenarioPolicyResolver
AIRuntimeService
AIRuntimeTextRequest
AIRuntimeStreamEvent
AIRuntimeCancellationToken
OpenAICompatibleTextGateway
AIClientFactory
DeepTutorLocalChatRepository
DeepTutorLocalChatStore
DeepTutorMessageReducer
DeepTutorMessageCodec
DeepTutorChatNotifications
```

不得重复实现：

```text
不得为 DeepTutorChat 新建一套 AI Provider 配置。
不得在 DeepTutorChat 内直接拼 OpenAI endpoint / apiKey。
不得绕过 AIConfigCenter 直接读 API Key。
不得复制 OpenAICompatibleTextGateway。
不得让页面层直接消费 URLSession stream。
```

---

## 5. 模型消费规则

### 5.1 场景选择

P0 推荐：

```swift
scenario = .chat
```

原因与约束：

```text
现有 AI 设置页和模型绑定已经围绕 .chat 成熟。
用户已明确 DeepTutorChat 继续使用通用 .chat 场景。
DeepTutorChat 不新增 .deepTutor 或 .deepTutorChat。
P0 目标是替换本地 simulator，并通过 chat 场景完成真实模型连通。
DeepTutorChat 的能力差异不通过 AIScenario 区分，而通过 capability prompt、tool schema、event mapper、UI blocks 区分。
```

禁止改造项：

1. 不新增 `AIScenario.deepTutor`。
2. 不新增 `AIScenario.deepTutorChat`。
3. 不扩展 `AIScenarioRemoteBundlesCollection` 的 DeepTutor 专属字段。
4. 不新增 AI 设置页中的 DeepTutor 专属场景。
5. 不为 DeepTutorChat 建立独立 Provider/API Key/endpoint 配置。

### 5.2 模型优先级

DeepTutorChat 发送时模型选择优先级：

```text
1. 当前对话显式 currentModelName / preferredModelName
2. Composer runtime flags 选择的 chat model
3. AIConfigCenter 中场景默认模型
4. runtime override
5. bundle 默认模型
```

注意：

```text
ScenarioPolicyResolver 当前优先级是：
显式 preferredModelName > runtime override > bundle 默认解析链
```

DeepTutorChat 必须遵守这个已有顺序，不要自定义另一套选择逻辑。

### 5.3 参数消费

请求参数必须从已有设置体系进入：

```text
model
endpoint
apiKey
temperature
topP
maxTokens
providerCompanyUppercased
reasoning options
tools / toolChoice
```

DeepTutorChat 本地对话表可保存线程级覆盖：

```text
currentModelName
temperature
topP
maxMessages
```

当前 `DeepTutorLocalChatStore.createConversation` 只写入：

```text
maxMessages = 20
topP = 1.0
rolePrompt = ""
```

需要补充检查：

```text
是否应写 currentModelName
是否应写 temperature
是否应允许用户在 DeepTutorChat 内切换模型
是否复用普通 Chat 的 runtime flags
```

---

## 6. AIRuntime 事件映射

### 6.1 当前 AIRuntime 事件

```swift
enum AIRuntimeStreamEvent {
    case textDelta(String)
    case reasoningDelta(String)
    case toolCallDelta(AIRuntimeToolCallDelta)
    case completed(AIRuntimeTextResponse)
}
```

### 6.2 目标 DeepTutor 事件映射

| AIRuntimeStreamEvent | DeepTutorStreamEvent | UI 结果 | 持久化要求 |
| --- | --- | --- | --- |
| `textDelta(String)` | `contentDelta(text:callID:round:)` | 助手正文流式追加 | 更新 assistant.content 与 events |
| `reasoningDelta(String)` | `reasoningDelta(text:callID:round:)` | thinking 卡片增量 | 写入 events，完成后保留 |
| `toolCallDelta` 新 tool id/name | `toolCallStarted(callID:toolName:argsSummary:)` | trace 工具调用 running | 需要累积 tool call buffer |
| `toolCallDelta` arguments 增量 | `toolCallStarted` 更新或 trace args | trace 展示参数增量 | 不丢失 argumentsDelta |
| `completed.response.text` | `result(metadata:)` + final content | 助手 ready | 写 final text/model/tokens |
| `completed.response.reasoningText` | `reasoningDelta` final reconcile | thinking 完整化 | 避免重复拼接 |
| `completed.response.toolCalls` | tool call finalize | trace/tool cards | 若模型返回 tool calls，进入工具执行或降级展示 |
| runtime error | `error(message:code:)` | assistant failed | 保留失败消息，可重试 |

### 6.3 tool call 策略

P0 最小连通：

```text
支持模型返回 toolCallDelta，但不执行真实 DeepTutor Web 工具。
将 tool call 作为 trace 卡片展示。
如果工具不可执行，给出明确 “工具暂未接入 iOS” 的 tool result/error。
不得静默吞掉 tool call。
```

P1 对齐：

```text
复用项目已有 ToolHub / ChatOrchestrator 工具体系。
或建立 DeepTutor 专属 ToolRegistry。
ask_user 必须映射为 DeepTutorAskUserCardView。
```

### 6.4 thinking 策略

要求：

```text
AIRuntimeStreamEvent.reasoningDelta 必须进入 DeepTutorThinkingCardView。
completed.reasoningText 必须与流式 reasoningDelta 去重合并。
thinking 卡片显示在助手正文前。
刷新后 thinking 不丢失。
```

---

## 7. Prompt 与上下文构造

### 7.1 DeepTutor system prompt

需要新增 `DeepTutorPromptBuilder`：

```text
输入：
  capability
  language
  conversation title
  selected member/context refs
  attachments summary
  existing messages

输出：
  AIRuntimeMessage(role: .system, content: ...)
```

能力模式：

```text
chat
deepResearch
deepQuestion
mathAnimator
visualize
```

每种 capability 必须有不同 prompt 约束：

```text
chat：普通解释与问答
deepResearch：先给研究计划/outline，再逐步回答
deepQuestion：生成 quiz/question card 语义
mathAnimator：输出可用于动画/步骤演示的结构
visualize：输出可视化说明或结构化 spec
```

### 7.2 历史消息构造

从本地数据库读取：

```text
DeepTutorLocalChatRepository.loadMessages
```

转换规则：

```text
DeepTutorMessage.role.user -> AIRuntimeMessage(role: .user)
DeepTutorMessage.role.assistant -> AIRuntimeMessage(role: .assistant)
system prompt -> AIRuntimeMessage(role: .system)
```

限制：

```text
只发送可见分支路径 messages。
遵守 maxMessages。
过滤 tombstone / deleted。
附件和上下文引用用文本摘要或 contentParts 表达。
不要把 envelope block 当成模型消息。
```

### 7.3 分支路径要求

真实模型接入后，分支更重要：

```text
用户编辑消息 -> 新分支
再次发送 -> 只能带当前 visible path 上下文
不能把 sibling branch 一起发送给模型
```

因此 `DEEPTUTORCHAT-000002` 中提到的 visible path 偏差需要在本工单一并验收。

---

## 8. UI 刷新与状态机

### 8.1 发送状态

目标状态流：

```text
ready
  -> streaming
  -> ready
```

失败：

```text
ready
  -> streaming
  -> error / assistant failed
  -> ready after retry
```

取消：

```text
streaming
  -> cancelling
  -> ready 或 interrupted
```

当前 `stopStreaming()` 只是本地改状态：

```text
state.isStreaming = false
state.phase = .ready
```

真实模型接入后必须：

```text
保存 AIRuntimeCancellationToken。
stopStreaming 调用 cancellationToken.cancel()。
AsyncThrowingStream termination 时正确关闭。
assistant message 标记 interrupted / ready with partial / failed。
```

### 8.2 刷新方式

要求：

```text
每个 text delta 可以节流 upsert，避免每 token 写库。
UI 层可以先内存增量刷新，再按批次持久化。
最终 completed 必须落库。
数据库通知只刷新当前会话消息。
非当前会话只刷新列表 preview。
```

建议节流：

```text
文本增量：50-120ms 批量刷新一次 UI。
数据库写入：200-500ms 批量持久化一次，completed 强制 flush。
reasoning/tool call：事件级刷新，但可 coalesce。
```

### 8.3 消息气泡对齐

真实模型接入后，以下 UI 必须用真实事件验证：

```text
助手 trace 在正文前。
thinking 卡片在正文前且可折叠。
正文 markdown 流式增长。
tool call 卡片显示 running / success / failed。
ask_user 出现后 composer 或卡片状态正确。
quiz/research/visualization capability 不被降级为普通文本。
```

---

## 9. 实施拆分

### 阶段 A：替换本地 simulator 主链路

目标文件：

```text
DeepTutorChatViewModel.swift
SendLocalDeepTutorMessageUseCase.swift
SendDeepTutorAIMessageUseCase.swift
DeepTutorAIRuntimeAdapter.swift
```

任务：

1. 新增真实 AI 发送用例。
2. ViewModel 注入 `AIRuntimeServing`。
3. 主发送按钮改走真实 AI 用例。
4. 本地 simulator 降级为 debug fixture，默认不使用。
5. 保留本地数据库写入 user / assistant message 的既有流程。

验收：

```text
发送后能看到真实模型返回内容。
AIConfigCenter 日志中出现 scenario/model/source。
OpenAICompatibleTextGateway 或 LocalGGUFTextGateway 被调用。
本地 simulator 日志不再出现在主路径。
```

### 阶段 B：接入 AIConfigCenter 模型选择

目标文件：

```text
AIConfigCenter.swift
AIScenario.swift
DeepTutorRuntimeRequestBuilder.swift
DeepTutorLocalChatStore.swift
DeepTutorConversationState.swift
```

任务：

1. P0 使用 `.chat` 场景。
2. 支持 preferredModelName。
3. 支持 temperature / topP / maxTokens。
4. 发送前记录 resolved model/provider/source。
5. 无模型配置时展示可读错误，引导去 AI 设置。

验收：

```text
切换 AI 设置中的 chat 默认模型后，DeepTutorChat 使用新模型。
如果指定 preferredModelName，优先使用指定模型。
如果模型不存在，显示 missingModelForScenario 错误。
```

### 阶段 C：事件映射与流式 UI

目标文件：

```text
DeepTutorAIRuntimeEventMapper.swift
DeepTutorMessageReducer.swift
DeepTutorTraceFormatter.swift
DeepTutorAssistantBubble.swift
DeepTutorAssistantResponseView.swift
DeepTutorThinkingCardView.swift
```

任务：

1. `textDelta` 映射为正文增量。
2. `reasoningDelta` 映射为 thinking。
3. `toolCallDelta` 组装为 trace/tool call。
4. `completed` 写入 final metadata。
5. error 映射为 failed block。

验收：

```text
真实流式文本逐步出现在助手气泡。
真实 reasoning 出现在 thinking 卡片。
真实 tool call 出现在 trace 区。
模型完成后状态变为 ready。
网络失败后状态变为 failed 且可重试。
```

### 阶段 D：DeepTutor capability 对齐

目标文件：

```text
DeepTutorPromptBuilder.swift
DeepTutorCapability.swift
DeepTutorResearchOutlineCardView.swift
DeepTutorQuizCardView.swift
DeepTutorVisualizationPlaceholderView.swift
DeepTutorGeneratedFileCardView.swift
DeepTutorAskUserCardView.swift
```

任务：

1. 按 capability 构造不同 prompt。
2. deepResearch 要能产出 outline/card 语义。
3. deepQuestion 要能产出 quiz/card 语义。
4. visualize/mathAnimator 至少保留结构化 spec 或占位卡片。
5. ask_user 工具调用要能显示交互卡片。

验收：

```text
不同 capability 不再只是同一段普通回答。
DeepTutor Web 中的特殊卡片语义在 iOS 有对应 UI。
未支持的工具必须显式降级，不静默吞掉。
```

### 阶段 E：取消、重试、重新生成

目标文件：

```text
DeepTutorChatViewModel.swift
SendDeepTutorAIMessageUseCase.swift
DeepTutorGenerationSession.swift
DeepTutorLocalChatStore.swift
```

任务：

1. stopStreaming 真实取消上游 runtime。
2. 重试失败 assistant。
3. regenerate 最新 assistant。
4. 取消后保留 partial 内容或 interrupted 状态。
5. 避免重复发送与并发覆盖。

验收：

```text
点击停止后上游请求停止。
重试不会生成重复 user message。
重新生成会创建正确分支或替换策略明确。
```

---

## 10. 日志要求

本工单沿用 `DEEPTUTORCHAT-000002` 的要求：本地调试阶段日志不做对话内容脱敏，便于复现问题。

必须新增日志点：

```text
deeptutor_ai_send_start
deeptutor_ai_config_resolve_start
deeptutor_ai_config_resolve_success scenario model provider source endpoint
deeptutor_ai_config_resolve_failure error
deeptutor_ai_runtime_request_built messages tools reasoning preferredModelName
deeptutor_ai_stream_start
deeptutor_ai_stream_text_delta text
deeptutor_ai_stream_reasoning_delta text
deeptutor_ai_stream_tool_delta id name argumentsDelta
deeptutor_ai_stream_completed model promptTokens completionTokens finishReason text reasoningText
deeptutor_ai_stream_failed error
deeptutor_ai_stream_cancelled
deeptutor_ai_message_flush persistenceMode blockCount contentLength
```

必须能回答：

```text
本次到底消费了哪个 provider？
本次到底消费了哪个 model？
本次 endpoint 来自哪里？
本次 apiKey 是否存在？
本次走云端还是本地 GGUF？
本次是否启用了 reasoning？
本次 tool call 是否被模型返回？
本次 UI 是否收到 text delta？
本次是否成功 completed？
```

---

## 11. 验收用例

### 11.1 真实模型最小连通

```text
Given AI 设置中 chat 场景已配置可用模型
And DeepTutorChat 存在一个本地对话
When 用户发送 “请用三句话解释血糖波动”
Then DeepTutorChat 调用 AIRuntimeService.generateTextStream
And AIConfigCenter.resolve(for: .chat) 成功
And UI 看到真实模型流式回答
And 本地数据库保存 user / assistant message
And 日志记录实际 provider/model/source
```

### 11.2 禁止本地 simulator 主路径

```text
Given 当前不是 debug fixture 模式
When 用户发送任意消息
Then 不调用 DeepTutorLocalReplySimulator.simulate
And 不出现 local-fixture result
And assistant 内容来自 AIRuntimeStreamEvent
```

### 11.3 模型切换生效

```text
Given AI 设置页把 chat 默认模型从 modelA 切换到 modelB
When DeepTutorChat 发送新消息
Then AIConfigCenter.resolve 返回 modelB
And OpenAICompatibleTextGateway 请求体 model 为 modelB 或 agent 的 baseModelName
```

### 11.4 thinking 展示

```text
Given 厂商返回 reasoningDelta
When DeepTutorChat 消费流式事件
Then thinking 卡片出现在助手正文前
And completed 后刷新仍保留 thinking
```

### 11.5 tool call 展示

```text
Given 厂商返回 toolCallDelta
When DeepTutorChat 消费流式事件
Then trace 区显示工具调用 running
And 如果工具未接入，显示明确降级结果
And 不静默丢弃工具调用
```

### 11.6 取消生成

```text
Given 模型正在流式输出
When 用户点击停止
Then AIRuntimeCancellationToken.cancel 被调用
And 上游 stream 终止
And assistant message 保存 partial 或 interrupted 状态
And UI 回到可输入状态
```

### 11.7 配置缺失

```text
Given AI 设置没有 chat 可用模型
When DeepTutorChat 发送消息
Then 不创建假回复
And 页面显示“请先配置 AI 模型”
And 日志记录 missingModelForScenario
```

---

## 12. 当前不做的事

本工单不要求：

```text
不直接实现 Swift 代码。
不新增另一个 AI Provider 设置页面。
不绕过项目已有 AIConfigCenter。
不重新实现 OpenAI-compatible 网关。
不立即完成所有 DeepTutor Web 后端协议迁移。
不把本地 simulator 删除，只是从主路径移除。
```

---

## 13. 风险与待确认项

| 编号 | 风险/待确认项 | 影响 | 关闭条件 |
| --- | --- | --- | --- |
| R1 | DeepTutorChat 固定复用 `.chat` 后，DeepTutor 差异必须在业务层表达 | 影响 research/quiz/visualize 输出质量 | 建立 `DeepTutorPromptBuilder`、tool schema 与 capability mapper，不新增 AIScenario |
| R2 | DeepTutor capability 输出结构化协议待冻结 | 影响卡片解析、quiz、research outline、visualize 占位 | 明确每个 capability 的模型输出格式、解析规则和降级策略 |
| R3 | 项目 ToolHub 是否可直接复用 | 影响 tool call 执行而不只是展示 | 审计 `ChatOrchestrator` / `ToolHub` 后决定 |
| R4 | ask_user 是否由模型 tool call 触发 | 影响交互卡片真实可用性 | 定义 ask_user tool schema 与 mapper |
| R5 | 流式事件高频写库性能 | 影响 UI 卡顿与 CoreData 压力 | 增加节流、批量 flush、completed 强制落库 |
| R6 | 本地 GGUF 与云端 provider 事件差异 | 影响 reasoning/tool 支持 | 使用 AIRuntimeService 的统一事件做兼容矩阵 |
| R7 | 日志完整记录对话内容 | 影响开发态日志体积和隐私边界 | 本地调试允许完整记录；生产开关另设工单 |
| R8 | DeepTutor Web 特殊工具未接入 iOS | 影响“完全一致”目标 | 未支持工具必须显式降级并建子工单 |

---

## 14. 完成定义

本工单完成必须满足：

1. DeepTutorChat 主发送链路不再走 `DeepTutorLocalReplySimulator`。
2. DeepTutorChat 使用项目已有 `AIConfigCenter` 解析模型。
3. DeepTutorChat 使用 `AIRuntimeService.generateTextStream` 消费真实模型。
4. 能在日志中看到实际 provider、model、source、endpoint、reasoning、tool 信息。
5. `AIRuntimeStreamEvent.textDelta` 驱动助手正文流式更新。
6. `AIRuntimeStreamEvent.reasoningDelta` 驱动 thinking 卡片。
7. `AIRuntimeStreamEvent.toolCallDelta` 至少能显示 trace，不能静默丢弃。
8. `completed` 后 assistant message 正确保存为 ready。
9. 失败时 assistant message 正确保存为 failed，并可重试。
10. 停止生成能取消上游 runtime。
11. 本地数据库仍保存完整对话历史。
12. 当前未对齐 DeepTutor Web 的 capability / tool / ask_user / trace 项已列出后续子工单。

---

## 15. 建议后续子工单

```text
DEEPTUTORCHAT-000004 DeepTutorChat AIRuntimeStreamEvent 到 DeepTutorStreamEvent 映射实现工单
DEEPTUTORCHAT-000005 DeepTutorChat PromptBuilder 与 capability 输出协议对齐工单
DEEPTUTORCHAT-000006 DeepTutorChat ToolHub / ask_user 真实工具调用接入工单
DEEPTUTORCHAT-000007 DeepTutorChat 取消、重试、重新生成与分支消息对齐工单
```
