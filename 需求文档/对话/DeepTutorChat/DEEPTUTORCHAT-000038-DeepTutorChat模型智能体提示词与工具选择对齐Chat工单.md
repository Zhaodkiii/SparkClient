# DEEPTUTORCHAT-000038 DeepTutorChat 模型智能体提示词与工具选择对齐 Chat 工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000038 |
| 工单类型 | P1 DeepTutorChat 对齐 Chat 模型/智能体选择、Prompt 解析、工具白名单与发送链路 |
| 当前范围 | 只创建需求/技术方案工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标功能目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| 参考功能目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat` |
| 创建日期 | 2026-08-08 |
| 触发需求 | DeepTutorChat 当前对话里的“选择模型或智能体”需要对齐 Chat 模块。智能体确认、系统提示词、工具确认与处理逻辑应沿用 Chat 的 `AIScenarioRemoteModelRow` 语义 |
| 关联工单 | `DEEPTUTORCHAT-000022`、`DEEPTUTORCHAT-000024`、`DEEPTUTORCHAT-000030`、`DEEPTUTORCHAT-000037`、`CHAT-000007`、`CHAT-000008`、`CHAT-000009`、`CHAT-000010` |
| 核心约束 | DeepTutorChat 不做运行时“智能体识别算法”；用户选中的 `AIScenarioRemoteModelRow.identity == agent` 即视为智能体；Prompt、工具、基座模型调用、参数覆盖规则必须与 Chat 一致 |

## 1. 背景与问题

Chat 模块已经形成稳定规则：

```text
模型/智能体确认 = 输入栏选中哪条 AIScenarioRemoteModelRow
普通模型 = identity == model
智能体 = identity == agent
Prompt = 小任务 > 智能体 Prompt > 会话 Prompt > 默认 Prompt
工具 = Composer 开关 ∩ 模型/智能体 aiToolScenarios ∩ ToolHub/Capability 过滤
API 调用 = 智能体用 baseModelName，普通模型用自身 name
```

DeepTutorChat 当前已经有独立的 `DeepTutorCapability` 菜单、DeepTutor 工具 manifest、`DeepTutorPromptBuilder`、`DeepTutorToolPolicyResolver` 和 `DeepTutorRuntimeRequestBuilder`。但输入栏模型位目前只是展示 `conversation.currentModelName` 的 `modelChip`，没有像 Chat 的 Hanlin 输入栏一样提供模型/智能体横滑选择，也没有完整承接 `AIScenarioRemoteModelRow.identity/systemPrompt/baseModelName/aiToolScenarios/relatedTaskCodes` 的行为。

这会带来几个问题：

1. 用户在 DeepTutorChat 中无法像 Chat 一样明确选择智能体。
2. DeepTutorChat 的系统提示词来源可能继续依赖 DeepTutor 专用 Prompt，而不是选中智能体的 `systemProvision/systemPrompt`。
3. DeepTutorChat 的工具策略只看 DeepTutor capability 与可选工具，缺少模型/智能体 `aiToolScenarios` 白名单交集。
4. 会话里虽已有 `currentModelName` 字段，但缺少类似 `ChatDetailViewModel.updateThreadModel` 的 UI 选择与持久化闭环。
5. 重试、重新生成、AskUser 恢复、成员选择恢复等后续 turn 需要沿用原模型/智能体，否则同一会话可能前后 Prompt 与工具行为漂移。

本工单要求 DeepTutorChat 在“当前对话选择模型或智能体”上对齐 Chat，不再建立第二套语义。

## 2. 目标

### 2.1 产品目标

1. DeepTutorChat 输入栏能像 Chat Hanlin 专业版一样展示模型/智能体横滑选择行。
2. 用户选择普通模型或智能体后，本会话后续发送、重试、重新生成、追问恢复都使用同一选择。
3. 智能体在 DeepTutorChat 中表现为固定人设、固定生成参数、工具白名单可控，而不是普通模型加一个显示名称。
4. 工具是否可用对用户可解释：输入栏/能力开关、智能体配置、ToolHub 能力过滤共同决定。
5. DeepTutorChat 保留自身 DeepTutor capability 体验，但底层模型/智能体确认逻辑与 Chat 统一。

### 2.2 工程目标

1. 复用 `effectiveScenarioBundles().chat.models` 作为 DeepTutorChat 模型/智能体选择器数据源。
2. 复用 `AIModelIdentity.model/agent`、`AIScenarioRemoteModelRow`、`ChatSystemPromptResolver` 和 Chat 的工具白名单语义。
3. 在 DeepTutorChat 仓储层补齐 `currentModelName` 更新能力，保持本地会话字段与 UI 选择一致。
4. 在 `DeepTutorRuntimeRequestBuilder` 或相邻解析层引入“已解析模型行”，统一产出 systemPrompt、inference、preferredModelName、temperature/maxTokens。
5. 保持 DeepTutor 自身的 capability 工具策略，但最终工具集必须再与模型/智能体 `aiToolScenarios` 做交集。

## 3. 非目标

1. 不重构 Chat 主链路。
2. 不改变 AI 设置中创建智能体的字段设计。
3. 不把 DeepTutorChat 的 capability 菜单删除；本工单只让 capability 与模型/智能体选择共存。
4. 不新增服务端 API；第一期只使用现有 `AIConfigCenter`、本地 Core Data 会话字段和已有 ToolHub。
5. 不把 DeepTutorChat 全量改成 `ChatView` 组件；只对齐选择、Prompt、工具和发送解析规则。

## 4. Chat 侧基准规则

### 4.1 智能体确认

Chat 不做运行时用户意图识别，确认依据是模型配置行：

```swift
enum AIModelIdentity: String, Codable, CaseIterable, Sendable {
    case model
    case agent
}
```

选中行来源优先级：

```text
1. 输入栏草稿 runtimeFlags.selectedChatModelName
2. 当前会话 thread.currentModelName
3. 场景 bundle 默认模型
```

判定：

```text
resolvedRow.identity == "agent" -> 智能体
resolvedRow.identity == "model" -> 普通模型
```

DeepTutorChat 必须沿用这个判定，不允许通过用户输入文本、capability、标题、图标或 prompt 内容反推智能体。

### 4.2 Prompt 优先级

Chat 的系统提示词解析优先级为：

```text
小任务 > 智能体 Prompt > 会话 Prompt > 默认 Prompt
```

DeepTutorChat 对齐要求：

1. 如果选中普通模型，DeepTutorChat 可使用会话 Prompt 或 DeepTutor 默认 Prompt。
2. 如果选中智能体，必须优先使用模型行上的 `systemPrompt/systemProvision`。
3. 如果后续支持 DeepTutor 小任务，仍按“小任务 Prompt 最高优先级”处理。
4. 记忆检索追加逻辑应在基础 Prompt 解析后追加，不能覆盖智能体设定。

### 4.3 生成参数

Chat 规则：

| 类型 | temperature / maxTokens |
| --- | --- |
| 普通模型 | 会话可覆盖，不存在时使用模型行默认值 |
| 智能体 | 固定使用智能体配置，忽略会话覆盖 |

DeepTutorChat 对齐要求：

1. 选中 `identity == agent` 时，使用模型行的 temperature/maxTokens。
2. 选中 `identity == model` 时，可继续使用 `DeepTutorConversationGenerationSettings.temperature/maxMessages` 与模型默认值合并。
3. 当前 DeepTutorConversation 使用 `maxMessages`，但 API 调用还需明确 `maxTokens` 来源，不能继续只依赖 `resolvedConfig.maxTokens` 而忽略 agent 行配置。

### 4.4 API 调用模型名

智能体是包装层：

```text
DeepTutorChat 内部配置查找、Prompt、工具白名单：使用 agent name
实际厂商 API 调用：使用 agent.baseModelName
```

对齐要求：

1. `preferredModelName` 传入时保留智能体名称，用于 `AIConfigCenter.resolve`、Prompt、工具配置查找。
2. AIRuntimeService 对 `identity == agent` 的 `baseModelName` 替换逻辑必须继续生效。
3. DeepTutorChat 日志要同时能看出 selectedModelName、identity、baseModelName、apiModelName。

### 4.5 工具确认

工具可用性由三层交集决定：

```text
输入栏/能力开关
∩ 模型/智能体 aiToolScenarios 白名单
∩ ToolHub / DeepTutor capability / 领域意图过滤
```

Chat 语义：

```text
aiToolScenarios 为空数组 -> 不额外限制
包含 __spark_tools_none__ -> 明确禁用所有工具
包含具体 SparkToolName -> 只允许这些工具
```

DeepTutorChat 必须复用同一语义。DeepTutor capability 自动挂载的工具也必须被模型/智能体白名单约束。

## 5. DeepTutorChat 当前差距

| 维度 | Chat 当前行为 | DeepTutorChat 当前风险 | 对齐要求 |
| --- | --- | --- | --- |
| 输入栏选择器 | `ChatComposerModelPickerRow` 横滑选择模型/智能体 | `DeepTutorComposerToolbarView.modelChip` 仅展示，不可选 | 增加横滑选择或复用同组件 |
| 数据源 | `effectiveScenarioBundles().chat.models` | DeepTutorChat ViewModel 未维护模型列表 | 增加 `deepTutorScenarioModels` 或复用命名 |
| 选中持久化 | `updateThreadModel` 写 `thread.currentModelName` | 仓储协议无 update model 方法 | 补 `updateConversationModel` |
| 智能体判定 | `AIScenarioRemoteModelRow.identity` | DeepTutor capability 与智能体概念容易混淆 | 明确 capability 不是 agent identity |
| Prompt | `ChatSystemPromptResolver` | `DeepTutorPromptBuilder` 独立生成 | 引入 Chat 优先级并保留 DeepTutor 默认 Prompt 作为 fallback |
| 工具白名单 | Composer 开关 ∩ `aiToolScenarios` ∩ ToolHub | DeepTutor policy 只看 capability/intent/snapshot | 最终 `allowedToolNames` 再套模型行白名单 |
| 参数 | agent 固定行配置 | DeepTutor settings 可能覆盖 | agent 禁止会话覆盖 |
| 恢复链路 | 沿用线程模型 | AskUser/成员选择恢复可能使用默认 settings | 恢复时必须沿用原 user message snapshot 或会话模型 |

## 6. 需求方案

### 6.1 输入栏模型/智能体选择器

DeepTutorChat 输入栏底部新增模型/智能体横滑选择行，建议复用 `ChatComposerModelPickerRow`：

```text
DeepTutorComposerCardView
  -> DeepTutorComposerTextView
  -> DeepTutorComposerToolbarView
  -> ChatComposerModelPickerRow(models, selectedModelName)
```

行为要求：

1. 展示“默认”按钮和所有 `effectiveScenarioBundles().chat.models` 行。
2. 普通模型使用 `row.composerIconSystemName` 中的 cpu 语义。
3. 智能体使用 `person.crop.circle` 语义。
4. 选中“默认”时，解析到场景默认模型，并写入 resolved row 的 name，避免后续发送时空值漂移。
5. 键盘弹起时是否隐藏模型行，建议与 Hanlin 一致：隐藏横滑行，保留 toolbar 上的当前模型 chip。
6. `modelChip` 从纯展示改为显示当前 resolved row 的 `displayTitle` 和 identity 图标；可作为打开模型选择的辅助入口，但第一期不要求弹窗。

### 6.2 ViewModel 数据源与持久化

DeepTutorChatViewModel 新增：

```swift
@Published private(set) var chatScenarioModels: [AIScenarioRemoteModelRow] = []
```

新增方法：

```swift
func refreshChatModelPicker(for conversationID: UUID) async -> String?
func updateConversationModel(_ preferredModelName: String?, for conversationID: UUID) async
func validateCurrentModelSelection(for conversationID: UUID) async
```

数据源规则与 Chat 一致：

```text
aiConfigCenter.effectiveScenarioBundles().chat.models
```

持久化要求：

1. DeepTutorLocalChatRepository 增加 `updateConversationModel(conversationID:currentModelName:)` 或扩展为 `updateConversationGenerationConfig`。
2. 写入 Core Data `currentModelName`。
3. 更新 `conversation` 内存态和会话列表项。
4. 触发 `.deepTutorChatDatabaseDidChange`，但不能导致消息列表重复刷新或快照重入。
5. 如果远程配置删除了当前选中模型，回退到场景默认模型。

### 6.3 发送前模型行解析

DeepTutorChat 发送时必须先解析模型行：

```text
selectedName = composer selected model name
threadModel = conversation.currentModelName
preferredName = selectedName ?? threadModel
resolvedRow = bundles.resolveRow(for: .chat, preferredModelName: preferredName)
```

要求：

1. `resolvedRow` 为空时抛出 `AIConfigError.missingModelForScenario(.chat)`。
2. `resolvedRow.identity` 写入本轮请求快照，便于回放和调试。
3. `resolvedRow.name` 作为内部 selected model name。
4. `resolvedRow.baseModelName` 用于日志，不由 DeepTutorChat 手动替换 API model，继续交给 AIRuntimeService。
5. 重试、重新生成、AskUser 恢复、成员选择恢复优先使用原 user message 的 requestSnapshot.selectedModelName；没有 snapshot 时才用 conversation.currentModelName。

### 6.4 Prompt 对齐

新增 DeepTutorChat Prompt 解析规则：

```text
baseDeepTutorPrompt = DeepTutorPromptBuilder.build(...)
resolvedSystemPrompt = ChatSystemPromptResolver.resolve(
    sessionPrompt: conversation.rolePrompt 或 nil,
    agentPrompt: resolvedRow.identity == agent ? resolvedRow.systemPrompt : nil,
    smallTask: nil
)
finalPrompt = DeepTutorPromptMerger.merge(
    resolvedSystemPrompt,
    deepTutorCapabilityInstructions,
    healthPromptMode,
    weatherPromptMode,
    memoryAppendix
)
```

第一期建议：

1. 对普通模型，保留现有 `DeepTutorPromptBuilder` 的系统提示词作为默认 Prompt。
2. 对智能体，以智能体 Prompt 为主体，追加 DeepTutorChat 必需的消息块、工具卡片、AskUser、成员选择、引用保真等协议说明。
3. 不允许 DeepTutor capability Prompt 覆盖智能体人设；只能作为能力协议补充。
4. Prompt 日志需要输出：`promptSource=agent/session/default/deeptutorFallback`、`identity`、`capability`、`toolPromptMode`。

### 6.5 工具策略对齐

DeepTutorToolPolicyResolver 当前产出 `allowedToolNames`。本工单要求在进入 ChatOrchestrator 前增加模型/智能体工具白名单交集：

```text
deepTutorAllowed = DeepTutorToolPolicyResolver.resolve(...).allowedToolNames
modelAllowed = allowedToolNames(from: resolvedRow.aiToolScenarios)
finalAllowed =
  if modelAllowed == nil: deepTutorAllowed
  if modelAllowed == []: []
  else: deepTutorAllowed ∩ modelAllowed
```

`allowedToolNames(from:)` 语义必须与 Chat 保持一致：

```text
[] -> nil，不额外限制
["__spark_tools_none__"] -> 空集合，明确禁用全部工具
["query_member_profile", "ask_user_question"] -> 仅允许这些 SparkToolName
```

要求：

1. 如果 finalAllowed 为空，则 `useTools=false`，不向模型传 tools。
2. `useKnowledgeBag` 和 `useWebSearch` 仍受 Composer/能力开关影响，但也必须受白名单影响。
3. DeepTutor capability 的 owned tools 不能绕过模型/智能体白名单，除非工单另行定义系统保底工具。
4. 问报告、健康数据、体检计划智能体工具同样受 agent `aiToolScenarios` 约束。
5. 日志新增 `modelAllowedTools`、`deepTutorAllowedTools`、`finalAllowedTools`、`toolRestrictionReason`。

### 6.6 生成参数对齐

新增解析方法：

```swift
func generationParameters(
    row: AIScenarioRemoteModelRow,
    conversation: DeepTutorConversation
) -> (temperature: Double?, maxTokens: Int?, maxMessages: Int?)
```

规则：

| 条件 | temperature | maxTokens | maxMessages |
| --- | --- | --- | --- |
| row.identity == agent | row.temperature | row.maxTokens | conversation.maxMessages |
| row.identity == model | conversation.temperature ?? row.temperature | row.maxTokens 或 resolvedConfig.maxTokens | conversation.maxMessages |

注意：

1. DeepTutor 的 `maxMessages` 是历史消息数量，不等于 `maxTokens`。
2. 对 agent，不能让会话 temperature 覆盖 agent 配置。
3. 如果 `row.maxTokens` 缺失，才使用 `resolvedConfig.maxTokens`。

### 6.7 请求快照与回放

DeepTutorRequestSnapshot 建议增加：

```text
selectedModelName
selectedModelIdentity
selectedAgentBaseModelName
modelAllowedToolNames
finalAllowedToolNames
promptSource
resolvedTemperature
resolvedMaxTokens
```

用途：

1. 重试/重新生成时保持与原 turn 一致。
2. AskUser/成员选择恢复时继续同一智能体，不因用户中途切换选择器而改变。
3. Debug exporter 能复盘“为什么本轮用了这个 Prompt 和这些工具”。

兼容要求：

1. 新增字段必须全部为 optional，旧消息解码时不能失败。
2. `CodingKeys` 增加字段后，`decodeIfPresent` 失败或为空时按旧逻辑回退。
3. 老消息没有 `selectedModelName` 时，重试/恢复使用 `conversation.currentModelName`。
4. 新消息必须在用户消息落库前写入 snapshot，保证失败重试也有原始选择。

### 6.8 推荐新增的公共解析结构

建议新增一个 DeepTutorChat 专用解析结果，避免 `DeepTutorAIRuntimeAdapter`、`DeepTutorRuntimeRequestBuilder` 和 ViewModel 各自重复解析模型：

```swift
struct DeepTutorResolvedModelContext: Sendable, Equatable {
    let selectedModelName: String
    let identity: AIModelIdentity
    let displayTitle: String
    let baseModelName: String?
    let systemPrompt: String?
    let aiToolScenarios: [String]
    let supportsToolUse: Bool
    let supportsMultimodal: Bool
    let temperature: Double?
    let maxTokens: Int?
    let promptSource: DeepTutorPromptSource
    let modelAllowedToolNames: Set<String>?
}

enum DeepTutorPromptSource: String, Codable, Sendable {
    case smallTask
    case agent
    case session
    case deepTutorDefault
}
```

推荐解析入口：

```swift
enum DeepTutorModelContextResolver {
    static func resolve(
        bundles: AIScenarioRemoteBundlesCollection,
        conversation: DeepTutorConversation?,
        snapshot: DeepTutorRequestSnapshot?,
        composerSelectedModelName: String?
    ) throws -> DeepTutorResolvedModelContext
}
```

解析优先级：

```text
1. snapshot.selectedModelName
   - 仅用于 retry / regenerate / AskUser resume / memberSelection resume
   - 保证同一 turn 不被 UI 当前选择影响
2. composerSelectedModelName
   - 用于普通发送
3. conversation.currentModelName
4. bundles.resolveRow(for: .chat, preferredModelName: nil)
```

### 6.9 具体方法改造建议

#### 6.9.1 `DeepTutorChatViewModel`

新增属性：

```swift
@Published private(set) var chatScenarioModels: [AIScenarioRemoteModelRow] = []
@Published private(set) var selectedModelDisplayTitle: String?
@Published private(set) var selectedModelIdentity: AIModelIdentity?
```

新增职责：

```text
openConversation
  -> load conversation
  -> refreshChatModelPicker
  -> validateCurrentModelSelection
  -> 更新 selectedModelDisplayTitle / selectedModelIdentity

updateConversationModel
  -> resolve row
  -> repository.updateConversationModel
  -> reload conversation
  -> 更新 displayTitle / identity
```

发送时补充：

```text
sendMessage
  -> 将当前 selected model name 传入 request snapshot builder
  -> buildRequestSnapshot 时写入 selectedModelName/identity/tool whitelist
```

注意：

1. 切换模型不应清空 draft。
2. 切换模型不应触发消息列表 reload。
3. streaming 中禁止切换或允许切换但不影响当前正在执行的 turn；第一期建议禁用选择器。
4. 新建会话时如果没有保存模型，进入会话后自动解析默认模型并写入 `currentModelName`。

#### 6.9.2 `DeepTutorLocalChatRepository`

新增接口：

```swift
func updateConversationModel(
    conversationID: UUID,
    currentModelName: String?
) async throws -> DeepTutorConversation
```

`DeepTutorLocalChatStore` 写入要求：

```text
fetchThread(ownerAccountID, threadID)
  -> object.currentModelName = currentModelName
  -> object.updatedAt = now
  -> postChange(kind: .messagesUpdated 或新增 .conversationMetadataUpdated)
```

建议新增 change kind：

```text
conversationMetadataUpdated
```

原因：模型切换只影响会话元数据，不应让消息列表误以为消息内容变化。

#### 6.9.3 `DeepTutorRequestSnapshot`

当前已有字段：

```swift
references
capability
enabledTools
toolSnapshot
attachments
searchConfigRevision
```

建议补充：

```swift
var selectedModelName: String?
var selectedModelIdentity: String?
var selectedAgentBaseModelName: String?
var modelAllowedToolNames: [String]?
var finalAllowedToolNames: [String]?
var promptSource: String?
var resolvedTemperature: Double?
var resolvedMaxTokens: Int?
```

写入位置：

```text
DeepTutorToolPolicyResolver.makePerTurnSnapshot
或更上层的 DeepTutorRequestSnapshotBuilder
```

建议不要让 `DeepTutorToolPolicyResolver` 直接依赖 `AIScenarioRemoteModelRow`，可以让上层先生成基础 snapshot，再调用：

```swift
snapshot.appendingModelContext(resolvedModelContext, finalAllowedTools)
```

这样可以保持工具策略层不反向依赖 AI Settings 领域模型。

#### 6.9.4 `DeepTutorRuntimeRequestBuilder`

当前 `build` 里直接：

```text
DeepTutorToolPolicyResolver.resolve
DeepTutorPromptBuilder.build
ChatOrchestratorInferenceOptions(...)
```

改造后建议：

```text
build(
  ...,
  resolvedModelContext: DeepTutorResolvedModelContext,
  modelToolRestriction: DeepTutorModelToolRestriction
)
  -> 先算 DeepTutor toolPolicy
  -> 再与 modelToolRestriction 合并
  -> 用合并后的 finalPolicy 计算 healthPromptMode/weatherPromptMode
  -> 构建 prompt
  -> 返回 inference + finalToolPolicy + promptSource + parameters
```

不得在 Prompt 中声明实际不会传给模型的工具。也就是：

```text
finalAllowedTools 中没有 query_weather
  -> weatherPromptMode 必须是 disabled

finalAllowedTools 中没有健康资料工具
  -> healthPromptMode 必须是 disabled 或 readOnlyUnavailable
```

#### 6.9.5 `DeepTutorAIRuntimeAdapter`

改造顺序建议：

```text
1. effectiveScenarioBundles
2. resolve DeepTutorResolvedModelContext
3. resolve AIResolvedConfig
4. 计算 modelSupportsToolCalling
5. build DeepTutor runtime request
6. orchestrator.generateReply
```

关键点：

1. `modelSupportsToolCalling` 需要按 Chat 规则看 agent 自身和 base model。
2. `multimodalCapabilities` 也应按 selected row / base model 一致解析，避免 agent 包装后图片被错误禁用。
3. `preferredModelName` 传给 orchestrator 时应仍为 agent name，让 AIRuntimeService 完成 base model 替换。
4. 日志必须打印 `selectedModelName`，不要只打印 `resolvedConfig.model`，否则 agent 场景难排查。

### 6.10 工具白名单合并细则

建议新增：

```swift
struct DeepTutorModelToolRestriction: Equatable, Sendable {
    let allowedToolNames: Set<String>?
    let reason: String
}

enum DeepTutorModelToolRestrictionResolver {
    static func allowedToolNames(from storedToolNames: [String]) -> DeepTutorModelToolRestriction
}
```

合并规则：

| DeepTutor policy | model restriction | final |
| --- | --- | --- |
| `useTools=false` | 任意 | `useTools=false`，`allowed=[]` |
| `allowed={A,B}` | `nil` | `{A,B}` |
| `allowed={A,B}` | `{}` | `[]`，`useTools=false` |
| `allowed={A,B}` | `{B,C}` | `{B}` |
| `allowed={A,B}` | `{C}` | `[]`，`useTools=false` |

`useKnowledgeBag` / `useWebSearch` 二次修正：

```text
finalAllowedTools 不含 search_knowledge_bag / create_knowledge_document
  -> useKnowledgeBag=false

finalAllowedTools 不含 search_online / read_web_page / search_arxiv_papers
  -> useWebSearch=false
```

边界：

1. `ask_user_question`、`request_member_selection` 是否作为系统保底工具，需要产品明确。第一期按严格交集处理。
2. 如果严格交集导致不能追问，模型应以文本形式说明“当前智能体未开启追问工具”，不能伪造卡片。
3. 如果 agent 禁用工具，但用户上传附件，附件仍可作为普通 multimodal/file 输入；只是不能调用 ToolHub。

### 6.11 Prompt 合并细则

建议把 DeepTutor Prompt 拆成三段：

```text
personaPrompt
  - agent systemPrompt 或 sessionPrompt 或 DeepTutor 默认角色

capabilityProtocolPrompt
  - DeepTutor capability 的输出协议、卡片协议、AskUser/MemberSelection 约束

toolAvailabilityPrompt
  - 基于 finalAllowedTools 生成，且必须与实际 tools schema 一致
```

合并原则：

1. `personaPrompt` 决定“你是谁”。
2. `capabilityProtocolPrompt` 决定“在 DeepTutorChat 中如何输出”。
3. `toolAvailabilityPrompt` 决定“本轮能用哪些工具”。
4. 后两者不能反向修改智能体人设。
5. 如果 agent Prompt 与医疗安全边界冲突，医疗安全边界优先。

示例：

```text
选中“体检计划智能体”
  personaPrompt = 体检计划智能体 systemPrompt
  capabilityProtocolPrompt = DeepTutorChat 卡片/追问/引用协议
  toolAvailabilityPrompt = query_member_profile, ask_user_question, generate_task 等最终可用工具
```

### 6.12 UI 交互落地细节

模型行状态：

| 状态 | UI |
| --- | --- |
| `chatScenarioModels` 加载中 | 显示小号 ProgressView + “加载模型中” |
| 列表为空 | 显示“请先在 AI 设置配置 Chat 场景模型” |
| streaming | 模型行禁用，透明度 0.55 |
| 当前选择为 agent | chip 使用 `person.crop.circle`，显示智能体 displayTitle |
| 当前选择失效 | 自动回退默认模型，并显示默认模型 |

建议 `DeepTutorComposerCardView` 新增参数：

```swift
let modelRows: [AIScenarioRemoteModelRow]
@Binding var selectedModelName: String?
let selectedModelDisplayTitle: String?
let selectedModelIconName: String
let isModelPickerDisabled: Bool
let onPersistSelectedModel: (String?) -> Void
```

如果直接复用 `ChatComposerModelPickerRow`，需要注意：

1. 它依赖 `AIScenarioRemoteModelRow.displayTitle` 和 `composerIconSystemName`，DeepTutorChat 已可复用。
2. DeepTutor 的输入栏是卡片式，横滑行可放在 card 内底部或 card 外下方；第一期建议放在 card 内，减少 safeArea 抖动。
3. 键盘隐藏逻辑可以先复制 Hanlin 的通知监听，后续再抽公共 `KeyboardVisibilityObserver`。

### 6.13 日志与调试导出

新增日志建议：

```text
deeptutor.model_picker.loaded conversation=... count=... default=...
deeptutor.model_picker.selected conversation=... selected=... identity=... source=user/default/fallback
deeptutor.model_context.resolved conversation=... selected=... identity=... base=... supportsTools=...
deeptutor.prompt.resolved conversation=... source=agent capability=chat finalLength=...
deeptutor.tool_policy.model_restricted conversation=... deepTutor=... model=... final=... reason=...
deeptutor.generation.parameters conversation=... identity=agent temperature=... maxTokens=...
deeptutor.snapshot.model_mismatch conversation=... snapshot=... current=... source=askUserResume
```

Debug exporter 增加：

```text
- selectedModelName
- selectedModelIdentity
- selectedAgentBaseModelName
- promptSource
- modelAllowedToolNames
- finalAllowedToolNames
- resolvedTemperature / resolvedMaxTokens
```

### 6.14 分阶段实施顺序

建议拆成 4 个小 PR / 小工单执行：

| 阶段 | 范围 | 完成标准 |
| --- | --- | --- |
| Phase 1 | ViewModel 模型列表 + 仓储 currentModelName 更新 | DeepTutorChat 能加载模型列表，选择后重开会话仍恢复 |
| Phase 2 | 输入栏 UI 接入 `ChatComposerModelPickerRow` | UI 能选择默认/模型/智能体，streaming 禁用 |
| Phase 3 | Runtime 模型行解析 + Prompt/参数对齐 | agent Prompt 与参数生效，普通模型 fallback 正常 |
| Phase 4 | 工具白名单交集 + snapshot + 恢复链路 | `aiToolScenarios` 生效，AskUser/成员选择恢复沿用原 agent |

每个阶段都必须保持可编译，不能一次性大改后再补齐。

## 7. 端到端流程

```text
用户进入 DeepTutorChat 会话
  -> refreshChatModelPicker
  -> 展示默认/模型/智能体横滑行
  -> 用户选择模型或智能体
  -> updateConversationModel 写 currentModelName

用户发送消息
  -> 读取 selectedModelName / conversation.currentModelName
  -> effectiveScenarioBundles().chat.resolveRow
  -> 判断 identity model/agent
  -> 解析 Prompt：小任务 > agent Prompt > session Prompt > DeepTutor 默认 Prompt
  -> 解析 DeepTutor capability 工具策略
  -> 解析 row.aiToolScenarios 工具白名单
  -> final tools = DeepTutor policy ∩ model whitelist
  -> ChatOrchestrator.generateReply
  -> AIRuntimeService 对 agent 使用 baseModelName 调 API
  -> ToolHub 执行 tool_calls
  -> DeepTutor 消息块/卡片落库
```

## 8. UI 要求

### 8.1 DeepTutor 输入栏

目标结构：

```text
DeepTutorComposerCardView
  文本输入区
  工具栏：Capability / 当前模型 Chip / 附件 / 发送
  模型横滑行：默认 + 普通模型 + 智能体
```

展示规则：

1. 默认按钮文案沿用 Chat：`默认`。
2. 普通模型显示 `cpu`。
3. 智能体显示 `person.crop.circle`。
4. 当前模型 chip 显示 `row.displayTitle`，不是原始 `name`。
5. 如果模型列表为空，显示 loading 或“请先配置 Chat 场景模型”。
6. DeepTutor capability 菜单仍显示 Chat / Deep Research / Quiz / Visualize 等能力，不与模型/智能体选择混淆。

### 8.2 智能体 Prompt 设置展示

如果 DeepTutorChat 后续打开系统提示词设置：

1. 选中普通模型时，可编辑会话 Prompt。
2. 选中智能体时，展示智能体设定为只读。
3. UI 文案应说明：当前智能体设定来自 AI 设置，DeepTutorChat 只追加必要工具与消息协议。

## 9. 工程落点

### 9.1 需要新增/修改的 DeepTutorChat 文件

| 文件 | 改动 |
| --- | --- |
| `Presentation/DeepTutorChatPage.swift` | 向 Composer 传入模型列表、选中绑定、持久化回调 |
| `Presentation/DeepTutorComposerView.swift` | 增加模型选择器参数透传 |
| `Presentation/DeepTutorComposerCardView.swift` | 挂载 `ChatComposerModelPickerRow` 或 DeepTutor 包装组件 |
| `Presentation/DeepTutorComposerToolbarView.swift` | `modelChip` 使用 resolved row displayTitle 与 icon |
| `Application/DeepTutorChatViewModel.swift` | 增加 chatScenarioModels、刷新模型、更新会话模型、校验选择 |
| `Infrastructure/DeepTutorLocalChatRepository.swift` | 增加更新会话模型接口 |
| `Infrastructure/DeepTutorLocalChatStore.swift` | 写入 `currentModelName` 与更新时间 |
| `Application/DeepTutorRuntimeRequestBuilder.swift` | 接收 resolved row，构建 Prompt、工具、参数与 snapshot |
| `Application/DeepTutorAIRuntimeAdapter.swift` | 解析 row identity/baseModelName/tool whitelist，补日志 |
| `Domain/DeepTutorMessage.swift` / Snapshot 相关文件 | 按需增加 selected model 与工具快照字段 |

### 9.2 可复用 Chat 文件

| 文件 | 复用方式 |
| --- | --- |
| `ChatComposerModelPickerRow.swift` | 直接复用横滑选择 UI |
| `ChatSystemPromptResolver.swift` | 复用 Prompt 优先级 |
| `ChatCapabilityStrategy.swift` | 复用 allowedToolNames 语义或抽公共 helper |
| `SendChatMessageUseCase.allowedToolNames(from:)` | 建议抽到公共工具，DeepTutorChat 与 Chat 共用 |
| `AIRuntimeService.modelSupportsTools` | 保持 agent + base model supportsToolUse 判断 |

## 10. 验收标准

### 10.1 UI 验收

1. DeepTutorChat 输入栏底部出现模型/智能体横滑选择行。
2. 列表内容与 Chat Hanlin 输入栏一致，来自 `effectiveScenarioBundles().chat.models`。
3. 普通模型和智能体图标区分正确。
4. 切换模型/智能体后，关闭重开会话仍能恢复当前选择。
5. 键盘弹起时横滑行隐藏策略与 Chat 一致。

### 10.2 智能体确认验收

1. 选择 `identity == agent` 的行后，DeepTutorChat 本轮日志显示 `identity=agent`。
2. 选择普通模型后，日志显示 `identity=model`。
3. DeepTutorChat 不根据用户输入内容自动改写 identity。
4. 选择“默认”时解析到场景默认模型，并能稳定持久化。

### 10.3 Prompt 验收

1. 选中智能体时，最终 system prompt 包含智能体 `systemPrompt/systemProvision`。
2. 选中智能体时，会话自定义 Prompt 不覆盖智能体 Prompt。
3. 选中普通模型时，可使用会话 Prompt 或 DeepTutor 默认 Prompt。
4. DeepTutor 的卡片、AskUser、成员选择、工具协议说明以追加形式存在，不覆盖智能体人设。

### 10.4 工具验收

1. agent `aiToolScenarios` 为空时，DeepTutor capability 工具策略正常生效。
2. agent `aiToolScenarios` 为 `__spark_tools_none__` 时，本轮不传任何 tools。
3. agent 只勾选 `query_member_profile`、`ask_user_question` 时，即使 DeepTutor capability 命中更多工具，最终也只能传这两个。
4. 关闭 Knowledge/Web 开关时，对应工具不会因 agent 白名单存在而被重新放开。
5. 工具日志能同时看到 DeepTutor policy、agent whitelist、final tools。

### 10.5 恢复链路验收

1. 重试失败助手消息时，使用原用户消息所属模型/智能体。
2. 重新生成时，默认沿用原用户消息所属模型/智能体；如产品决定使用当前选择，必须在 UI 明确。
3. AskUser 提交后继续回答，不因用户切换选择器而换 agent。
4. 成员选择提交后继续回答，不因用户切换选择器而换工具白名单。

## 11. 测试建议

| 测试文件建议 | 覆盖点 |
| --- | --- |
| `Tests/DeepTutorChat/DeepTutorModelPickerTests.swift` | 模型列表刷新、默认选择、无效选择回退 |
| `Tests/DeepTutorChat/DeepTutorConversationModelPersistenceTests.swift` | `currentModelName` 写入与重开恢复 |
| `Tests/DeepTutorChat/DeepTutorAgentPromptResolutionTests.swift` | agent Prompt 优先级与普通模型 fallback |
| `Tests/DeepTutorChat/DeepTutorAgentToolWhitelistTests.swift` | `aiToolScenarios` 与 DeepTutor policy 交集 |
| `Tests/DeepTutorChat/DeepTutorAgentGenerationParameterTests.swift` | agent 固定参数、普通模型会话覆盖 |
| `Tests/DeepTutorChat/DeepTutorResumeModelSnapshotTests.swift` | 重试、AskUser、成员选择恢复沿用原模型 |

核心测试用例：

1. 场景模型列表包含一个普通模型和一个智能体，DeepTutorChat 选择器都展示。
2. 选中智能体发送，最终 prompt 来源为 agent，API 仍通过 baseModelName。
3. 智能体配置禁用所有工具，DeepTutor capability 为 deepResearch 时也不传工具。
4. 智能体只允许健康资料工具，体检计划智能体不能调用无关天气/地图工具。
5. 发送后用户切换模型，再提交 AskUser，恢复回答仍使用原 turn 的 agent。

## 12. 风险与取舍

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| DeepTutor capability 与 agent identity 概念混淆 | 用户以为 Chat/Deep Research 是智能体 | UI 文案和日志明确：capability 是能力模式，agent 是模型配置行 |
| Prompt 合并过长 | 影响回答稳定与 token 成本 | agent Prompt 为主体，DeepTutor 协议做精简追加 |
| 工具交集后为空 | 用户以为工具坏了 | 日志与 UI 提示“当前智能体未开启相关工具” |
| 复用 Chat UI 造成样式不协调 | DeepTutor 视觉不统一 | 第一版复用逻辑，可包一层 DeepTutor 样式适配 |
| 远程模型配置变化 | 已选模型失效 | 进入会话和发送前都做 validate fallback |

## 13. 结论

本工单建议 DeepTutorChat 对齐 Chat 的模型/智能体基础语义：

```text
模型/智能体确认：AIScenarioRemoteModelRow.identity
Prompt：小任务 > agent Prompt > 会话 Prompt > DeepTutor 默认 Prompt
工具：DeepTutor capability policy ∩ aiToolScenarios ∩ Composer/功能开关
API：agent 内部用 agent name，厂商调用用 baseModelName
UI：输入栏横滑选择模型/智能体，选择持久化到 currentModelName
```

完成后，DeepTutorChat 可以继续保留 DeepTutor 专属消息块、卡片、AskUser、成员选择和能力模式，同时不会在模型/智能体、Prompt 和工具策略上与 Chat 分叉。
