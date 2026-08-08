# DEEPTUTORCHAT-000043 DeepTutorChat 独立工具架构对齐 DeepTutor-main 工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000043 |
| 工单类型 | P0 架构重构 / 工具运行时独立 / DeepTutor-main 对齐 |
| 当前范围 | 创建全新需求工单，不直接修改 Swift 业务代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标功能目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| 参考实现 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main` |
| 对齐模块 | `deeptutor/core/tool_protocol.py`、`deeptutor/runtime/registry/tool_registry.py`、`deeptutor/core/agentic/tool_dispatch.py`、`deeptutor/agents/chat/agentic_pipeline.py`、`deeptutor/agents/chat/agent_loop.py`、`deeptutor/agents/_shared/tool_composition.py`、`deeptutor/tools/ask_user.py`、`deeptutor/tools/builtin/__init__.py` |
| 关联 Spark 模块 | `Projects/Features/DeepTutorChat`、`Projects/Features/Chat`、`Projects/Core/AIRuntime/ToolHub`、`Projects/Features/Chat/Presentation/ToolInteraction` |
| 创建日期 | 2026-08-08 |
| 需求来源 | DeepTutorChat 需要独立工具架构，完全对齐 DeepTutor-main 的工具使用流程；不再复用 Chat 的 `ToolHub + ToolInteraction` |
| 第一阶段范围 | 只接入 `选择成员`、`问答 ask_user`、`记忆 read_memory/write_memory` |

## 1. 结论先行

本工单确认一个新的架构方向：

```text
DeepTutorChat 不再复用 Chat 的 ToolHub + ToolInteraction。
DeepTutorChat 建立自己的 Tool Protocol / Registry / Composition / Dispatch / Pause Resume / Tool UI。
DeepTutorChat 的工具循环对齐 DeepTutor-main 的 agentic loop。
Chat 的 ToolHub + ToolInteraction 回归 Chat 专属能力，移除为 DeepTutorChat 做的兼容分支。
```

这和历史工单 `DEEPTUTORCHAT-000040` 的方向不同。`000040` 仍假设底层工具运行时共享，只隔离交互 UI；本工单按新的产品和架构决策，将 DeepTutorChat 工具运行时整体独立。

第一阶段不追求一次性迁移所有 Spark 工具，只做最小闭环：

```text
1. request_member_selection / select_member
2. ask_user
3. read_memory
4. write_memory
```

其中 `ask_user` 和 `memory` 必须严格对齐 DeepTutor-main；`选择成员` 是 SparkClient 健康家庭成员业务的领域工具，DeepTutor-main 没有同名工具，但必须复用 DeepTutor-main 的 `pause_for_user` 机制和同 turn 恢复语义。

## 2. 为什么必须新建独立工具架构

### 2.1 当前共享架构的问题

当前 SparkClient 的 DeepTutorChat 仍通过 Chat 工具链运行：

```text
DeepTutorChatViewModel
  -> SendDeepTutorAIMessageUseCase
  -> DeepTutorAIRuntimeAdapter
  -> ChatOrchestrator
  -> ToolHub
  -> ToolInteractionCoordinator
```

现有代码事实：

```text
Projects/App/Sources/App/AppContainer.swift
  -> DeepTutorChatViewModel 注入 chat.chatOrchestrator
  -> DeepTutorChatViewModel 注入 chat.toolInteractionCoordinator

Projects/Features/DeepTutorChat/Application/DeepTutorAIRuntimeAdapter.swift
  -> let orchestrator: ChatOrchestrator
  -> orchestrator.generateReply(...)
  -> preferInlineAskUser: true
  -> preferInlineMemberSelection: true

Projects/Features/DeepTutorChat/Application/SendDeepTutorAIMessageUseCase.swift
  -> let toolInteractionCoordinator: ToolInteractionCoordinator
  -> submitAskUser / submitMemberSelection 仍有 shared coordinator 兼容路径

Projects/Features/DeepTutorChat/Application/DeepTutorToolPolicyResolver.swift
  -> 将 DeepTutor canonical tool 映射到 SparkToolName
  -> 最终还是收窄 ChatOrchestratorInferenceOptions.allowedToolNames
```

这导致 DeepTutorChat 的工具体验被 Chat 的运行时结构约束：

1. DeepTutorChat 的工具定义必须进入 `SparkToolName` 和 `ToolHub+Schema`。
2. DeepTutorChat 的工具执行必须经过 `ToolHub` 的 execute dispatcher。
3. DeepTutorChat 的人机交互需要绕过或兼容 `ToolInteractionCoordinator`。
4. DeepTutorChat 的 inline 卡片依赖 `preferInlineAskUser`、`preferInlineMemberSelection` 这类特殊开关。
5. DeepTutorChat 的工具 trace、pause、resume、side effect 都被迫适配 Chat 的消息模型。
6. 健康资料、成员选择、授权、问答、记忆等能力容易出现 Chat Sheet 和 DeepTutorChat 卡片混杂。

本工单要求从根上切开：

```text
Chat 继续拥有 ToolHub + ToolInteraction。
DeepTutorChat 新建 DeepTutorToolRuntime。
两个 Feature 可以复用底层 AI provider、配置中心、存储服务和领域 Repository，但不共享工具编排器。
```

### 2.2 为什么要对齐 DeepTutor-main

DeepTutor-main 的工具体系不是简单的 function calling 包装，而是一套清晰的 agentic runtime：

```text
Tool Protocol
  -> Tool Definition
  -> Tool Registry
  -> Tool Composition
  -> OpenAI Schema Builder
  -> Agent Loop
  -> Tool Dispatch
  -> pause_for_user
  -> resume same turn
  -> StreamBus event
```

这个模型正适合 DeepTutorChat：

1. 每轮对话有明确的工具挂载策略。
2. 工具 schema 由 registry 统一输出。
3. LLM 一轮可并行调用多个工具。
4. 工具结果以 role=tool 回灌给同一轮 agent loop。
5. 需要用户输入时不结束任务，而是暂停、展示卡片、等待用户提交、再继续完成原始请求。
6. UI 不需要依赖 Chat Sheet，而是消费 DeepTutorChat 自己的 stream event 和 message block。

## 3. DeepTutor-main 工具流程事实

### 3.1 Tool Protocol

参考文件：

```text
DeepTutor-main/deeptutor/core/tool_protocol.py
```

核心模型：

```text
ToolParameter
ToolDefinition
ToolAlias
ToolPromptHints
ToolResult
ToolEventSink
ToolLookup
BaseTool
```

关键字段：

```text
ToolDefinition.name
ToolDefinition.description
ToolDefinition.parameters
ToolDefinition.raw_parameters
ToolDefinition.to_openai_schema()

ToolResult.content
ToolResult.sources
ToolResult.metadata
ToolResult.success
ToolResult.terminate_turn
ToolResult.pause_for_user
```

其中 `pause_for_user` 是 DeepTutorChat 第一阶段必须完整复刻的关键字段。

Swift 对齐模型建议：

```swift
struct DeepTutorToolParameter: Equatable, Sendable, Codable
struct DeepTutorToolDefinition: Equatable, Sendable, Codable
struct DeepTutorToolPromptHints: Equatable, Sendable, Codable
struct DeepTutorToolResult: Equatable, Sendable, Codable
protocol DeepTutorTool: Sendable
protocol DeepTutorToolLookup: Sendable
```

`DeepTutorToolResult` 必须至少包含：

```swift
let content: String
let sources: [DeepTutorToolSource]
let metadata: [String: JSONValue]
let success: Bool
let terminateTurn: Bool
let pauseForUser: DeepTutorToolPauseRequest?
```

### 3.2 Tool Registry

参考文件：

```text
DeepTutor-main/deeptutor/runtime/registry/tool_registry.py
```

DeepTutor-main 的 registry 能力：

```text
register
unregister
deferred_tools
load_builtins
get
list_tools
get_enabled
get_definitions
get_prompt_hints
build_prompt_text
build_openai_schemas
execute
```

Swift 对齐目标：

```text
DeepTutorToolRegistry
  -> register(_ tool: DeepTutorTool)
  -> unregister(name:)
  -> get(name:)
  -> listTools()
  -> getEnabled(names:)
  -> definitions(names:)
  -> promptHints(names:)
  -> buildToolManifest(names:locale:)
  -> buildOpenAISchemas(names:)
  -> execute(name:arguments:context:)
```

注意：DeepTutorChat 第一阶段不使用 `ToolHub` 作为 registry。可以复用领域 repository，例如成员数据仓库、记忆仓库，但工具注册、schema 输出、执行分发必须属于 `DeepTutorChat`。

### 3.3 Tool Composition

参考文件：

```text
DeepTutor-main/deeptutor/agents/_shared/tool_composition.py
```

DeepTutor-main 的组合逻辑：

```text
1. 用户开关工具
2. optional whitelist 收窄
3. mount flags 自动挂载
4. capability-owned tools 强制挂载
5. ask_user / write_memory 等 always-on 工具兜底
6. exclusive capability 只保留 capability-owned + ask_user 等必要工具
```

DeepTutorChat 第一阶段的工具挂载规则：

| 工具 | 挂载条件 | 是否用户可关 | 说明 |
| --- | --- | --- | --- |
| `ask_user` | 默认 always-on | 否 | 只有在真正卡住时调用，不能问“是否继续” |
| `request_member_selection` | 有成员体系，且当前任务需要成员上下文但未绑定成员 | 否 | SparkClient 领域工具，按 `pause_for_user` 实现 |
| `read_memory` | 当前账号存在可读记忆，且本轮需要个性化 | 可配置，默认开 | 对齐 DeepTutor-main 的 `hasMemory` gate |
| `write_memory` | 默认 always-on | 可配置，默认开 | 仅保存用户明确表达的偏好，不推测 |

第一阶段不挂载：

```text
web_search
rag
kb_files
health resource
weather
exec
code_execution
notebook
skill
cron
Chat 专用医疗工具
```

### 3.4 Agent Loop

参考文件：

```text
DeepTutor-main/deeptutor/agents/chat/agent_loop.py
DeepTutor-main/deeptutor/agents/chat/agentic_pipeline.py
```

DeepTutor-main 的一轮对话不是“一次模型请求结束”，而是：

```text
messages = history + current user

while round < max_rounds:
  call LLM
  if no tool_calls:
    stream final text
    finish

  append assistant_message_with_tool_calls
  dispatch tool calls
  append role=tool messages

  if dispatch.pause:
    await user reply
    replace matching tool message content
    continue same loop

  continue next round
```

DeepTutorChat 必须实现同样语义：

```text
用户问：帮我制定体检计划
  -> agent 发现需要成员
  -> call request_member_selection
  -> DeepTutorChat 暂停并展示成员选择卡
  -> 用户选择成员
  -> 同一个 assistant message 恢复
  -> role=tool 内容被替换为“用户选择了成员...”
  -> agent 继续 read_memory / ask_user / 最终回答
  -> 原始任务完成
```

不能出现：

```text
选择成员后只回复“好的”
选择成员后新开一条孤立 assistant 消息
选择成员 pending 时后台继续调用成员资料工具
awaiting_user_input 之后仍合并过期 tool events
```

### 3.5 Tool Dispatch

参考文件：

```text
DeepTutor-main/deeptutor/core/agentic/tool_dispatch.py
```

DeepTutor-main 调度特征：

```text
MAX_PARALLEL_TOOL_CALLS = 8
并行执行 tool calls
按 tool_call_id 返回 role=tool message
去重 ask_user，同一批只允许一个 ask_user 主调用
每个工具调用发送 stream.tool_call 事件
收集 sources / metadata / terminate / pause
pause 时记录 pause_payload 和 pause_tool_call_id
```

DeepTutorChat 第一阶段建议：

```text
maxParallelToolCalls = 4
ask_user 和 request_member_selection 互斥暂停
同一批工具调用中只允许一个 pause 工具生效
如果模型同批同时请求 ask_user 和 request_member_selection：
  -> 优先 request_member_selection
  -> ask_user 返回工具消息提示“成员选择完成后再追问”
```

原因：

```text
成员上下文是健康场景的前置身份边界。
没有成员时，ask_user 的问题也可能无法个性化。
```

### 3.6 ask_user

参考文件：

```text
DeepTutor-main/deeptutor/tools/ask_user.py
DeepTutor-main/deeptutor/tools/builtin/__init__.py
DeepTutor-main/tests/tools/test_ask_user.py
DeepTutor-main/web/lib/ask-user-state.ts
```

DeepTutor-main 约束：

```text
MAX_QUESTIONS = 4
MAX_OPTIONS = 8
MAX_OPTION_CHARS = 120
MAX_OPTION_DESC_CHARS = 200
MAX_HEADER_CHARS = 16
MAX_QUESTION_CHARS = 800
MAX_INTRO_CHARS = 400
MAX_PLACEHOLDER_CHARS = 120
```

schema 要点：

```text
questions: 1-4 个问题
prompt: 完整问题
header: 很短的标签
options: 选项对象数组
multi_select: 是否多选
id: 稳定问题 ID
allow_free_text: 是否允许自由输入
placeholder: 输入提示
intro: 顶部引导语
```

执行语义：

```text
返回 ToolResult(
  content="[awaiting user reply to: ...]",
  metadata={"ask_user": payload},
  pause_for_user=payload
)
```

恢复语义：

```text
用户回答后：
  -> 找到 matching tool_call_id
  -> 将 role=tool content 替换为用户回答摘要
  -> 附加 directive：
     [ask_user 已解决。请使用这些回答继续处理用户的原始请求。不要只回复确认。]
  -> agent loop 继续下一轮
```

DeepTutorChat 必须保留现有体验资产：

```text
DeepTutorAskUserCardView
DeepTutorAskUserNormalizer
DeepTutorAskUserResumeBuilder
DeepTutorAskUserToolCallIDMatcher
```

但这些资产的数据来源需要从 `ToolHub` 结果切到新的 `DeepTutorAskUserTool` 结果。

### 3.7 Memory

参考文件：

```text
DeepTutor-main/deeptutor/tools/builtin/__init__.py
DeepTutor-main/deeptutor/services/memory
```

DeepTutor-main 内置工具：

```text
read_memory
  -> 读取用户 L3 记忆
  -> recent / profile / scope / preferences
  -> metadata.char_count

write_memory
  -> 只保存用户明确表达的偏好
  -> op = add / edit
  -> text <= 240 chars
  -> target_id 可选，edit 时需要
  -> reason 可选
  -> 去重时返回 preference already saved
```

DeepTutorChat 第一阶段记忆边界：

```text
读取：
  1. 优先读取 SparkClient 已有记忆系统中与当前用户相关的长期偏好。
  2. 如果当前项目只有 Chat 记忆工具，则通过 DeepTutorMemoryStoreAdapter 调用底层 repository，不走 ToolHub。
  3. 输出拼接文本和 char_count。

写入：
  1. 只允许保存用户明确说出的偏好、语言、格式、深度、沟通方式。
  2. 不保存医疗诊断推测、模型推断的疾病风险、未经确认的家庭成员隐私。
  3. 医疗档案类事实不进入 `write_memory`，应进入医疗档案维护工具，第一阶段不做。
```

## 4. 新架构设计

### 4.1 总体架构

```text
DeepTutorChatPage
  -> DeepTutorChatViewModel
  -> SendDeepTutorAIMessageUseCase
  -> DeepTutorAIRuntimeAdapter
  -> DeepTutorAgenticRuntime
       -> DeepTutorToolRegistry
       -> DeepTutorToolComposition
       -> DeepTutorToolSchemaBuilder
       -> DeepTutorAgentLoop
       -> DeepTutorToolDispatcher
       -> DeepTutorPauseResumeCoordinator
       -> DeepTutorToolEventMapper
  -> DeepTutorMessageReducer
  -> DeepTutorAskUserCardView / DeepTutorMemberSelectionCardView
```

AI Provider 可以继续复用：

```text
AIConfigCenter
AIRuntimeService
AIResolvedConfig
AIScenarioRemoteModelRow
```

但工具运行时不再复用：

```text
ChatOrchestrator.generateReply 的 tool loop
ToolHub.toolDefinitions()
ToolHub.execute()
ToolInteractionCoordinator
ToolInteractionPresentationSheet
SparkToolName
ChatOrchestratorInferenceOptions.allowedToolNames
```

### 4.2 目录规划

在 `Projects/Features/DeepTutorChat` 下新增独立工具目录：

```text
Projects/Features/DeepTutorChat/
├── Domain/
│   └── Tools/
│       ├── DeepTutorToolName.swift
│       ├── DeepTutorToolParameter.swift
│       ├── DeepTutorToolDefinition.swift
│       ├── DeepTutorToolPromptHints.swift
│       ├── DeepTutorToolResult.swift
│       ├── DeepTutorToolCall.swift
│       ├── DeepTutorToolMessage.swift
│       ├── DeepTutorToolSource.swift
│       ├── DeepTutorToolPauseRequest.swift
│       ├── DeepTutorToolMountFlags.swift
│       ├── DeepTutorToolCompositionResult.swift
│       └── DeepTutorToolError.swift
│
├── Application/
│   └── Tools/
│       ├── DeepTutorTool.swift
│       ├── DeepTutorToolLookup.swift
│       ├── DeepTutorToolRegistry.swift
│       ├── DeepTutorToolRegistryFactory.swift
│       ├── DeepTutorToolComposition.swift
│       ├── DeepTutorToolSchemaBuilder.swift
│       ├── DeepTutorToolPromptManifestBuilder.swift
│       ├── DeepTutorToolDispatcher.swift
│       ├── DeepTutorToolArgumentDecoder.swift
│       ├── DeepTutorToolTraceReducer.swift
│       ├── DeepTutorPauseResumeCoordinator.swift
│       ├── DeepTutorAgentLoop.swift
│       ├── DeepTutorAgenticRuntime.swift
│       └── Builtins/
│           ├── DeepTutorAskUserTool.swift
│           ├── DeepTutorMemberSelectionTool.swift
│           ├── DeepTutorReadMemoryTool.swift
│           └── DeepTutorWriteMemoryTool.swift
│
├── Infrastructure/
│   └── Tools/
│       ├── DeepTutorMemberToolDataSource.swift
│       ├── DeepTutorMemoryStore.swift
│       ├── DeepTutorMemoryStoreAdapter.swift
│       └── DeepTutorToolAuditStore.swift
│
└── Presentation/
    └── Cards/
        ├── DeepTutorAskUserCardView.swift
        └── DeepTutorMemberSelectionCardView.swift
```

已有文件处理：

```text
保留并迁移：
  DeepTutorAskUserCardView.swift
  DeepTutorMemberSelectionCardView.swift
  DeepTutorAskUserNormalizer.swift
  DeepTutorAskUserResumeBuilder.swift
  DeepTutorMemberSelectionNormalizer.swift
  DeepTutorMemberSelectionResumeBuilder.swift

逐步废弃：
  DeepTutorToolPolicyResolver.swift 中映射 SparkToolName 的逻辑
  DeepTutorToolAliasMap.swift 中面向 SparkToolName 的 alias
  DeepTutorDomainToolExtensionResolver.swift 中依赖 ToolHub 的 domain extension
  DeepTutorAIRuntimeAdapter.swift 中 orchestrator.generateReply 工具循环路径
```

## 5. 第一阶段工具设计

### 5.1 `ask_user`

工具名：

```text
ask_user
```

用途：

```text
当模型无法根据用户请求、历史上下文、记忆、已选成员和合理默认值继续完成任务时，暂停同一轮对话，向用户一次性提出 1-4 个澄清问题。
```

禁止场景：

```text
不能问“是否继续”
不能确认用户已经明确说过的信息
不能把模型自己可以决定的常规选择丢给用户
不能连续调用多个 ask_user
```

输出：

```text
DeepTutorToolResult(
  content: "[awaiting user reply to: ...]",
  metadata: ["ask_user": payload],
  pauseForUser: .askUser(payload)
)
```

UI：

```text
DeepTutorMessageBlock.askUser
  -> DeepTutorAskUserCardView
  -> viewModel.submitAskUser(...)
  -> DeepTutorPauseResumeCoordinator.resolve(...)
```

验收：

```text
1. ask_user 卡片展示问题、选项、自由输入。
2. 用户提交后，同一条 assistant message 继续流式回答。
3. 最终回答必须完成原始请求，不只回复“收到”。
4. reload 后 pending ask_user 仍能恢复。
5. 同一批 tool calls 中多个 ask_user 只保留第一个主调用。
```

### 5.2 `request_member_selection`

工具名建议：

```text
request_member_selection
```

备选别名：

```text
select_member
choose_member
```

用途：

```text
当 DeepTutorChat 需要明确家庭成员上下文，但当前 conversation 没有 boundMemberID 时，暂停同一轮对话，请用户选择成员。
```

注意：

```text
DeepTutor-main 没有这个工具。
该工具是 SparkClient 领域扩展，但必须按 DeepTutor-main pause_for_user 机制实现。
```

schema 建议：

```json
{
  "name": "request_member_selection",
  "description": "Pause the turn and ask the user to choose the family member this answer should use.",
  "parameters": {
    "type": "object",
    "properties": {
      "reason": {
        "type": "string",
        "description": "Why a member is needed for this request."
      },
      "required_context": {
        "type": "string",
        "description": "The kind of member-specific context required, e.g. health_profile, exam_plan, medication, report."
      },
      "allow_skip": {
        "type": "boolean",
        "description": "Whether the user may continue without selecting a member."
      }
    },
    "required": ["reason"]
  }
}
```

执行原则：

```text
1. 工具结果不把完整成员列表暴露给 LLM。
2. 成员列表由 App 本地数据源提供给 UI。
3. LLM 只知道“需要用户选择成员”的结构化原因。
4. 用户选择后，resume 内容可包含 memberID、昵称、关系、年龄段等最小必要上下文。
5. 如果用户跳过，则 resume 内容明确说明未绑定成员，后续回答只能给通用建议。
```

输出：

```text
DeepTutorToolResult(
  content: "[awaiting member selection]",
  metadata: ["member_selection": payload],
  pauseForUser: .memberSelection(payload)
)
```

UI：

```text
DeepTutorMessageBlock.memberSelection
  -> DeepTutorMemberSelectionCardView
  -> viewModel.submitMemberSelection(...)
  -> DeepTutorPauseResumeCoordinator.resolve(...)
```

硬暂停规则：

```text
request_member_selection 返回 pause 后，本轮不得继续执行 query/profile/report/health 类工具。
必须等待用户选择后，通过同一个 assistant message resume。
```

验收：

```text
1. 未绑定成员时，健康相关请求先展示成员选择卡。
2. 选择成员后，同一条 assistant message 继续回答。
3. trace 中 request_member_selection 从 running 正确变为 awaiting/resolved。
4. pending 状态 reload 后可继续提交。
5. 不再触发 Chat 的 MemberSelectionToolSheet。
```

### 5.3 `read_memory`

工具名：

```text
read_memory
```

用途：

```text
读取当前用户长期记忆，用于个性化语气、深度、格式、偏好和上下文延续。
```

schema：

```text
无参数
```

执行：

```text
DeepTutorReadMemoryTool
  -> DeepTutorMemoryStore.readL3Concat()
  -> DeepTutorToolResult(content: text, metadata: ["char_count": text.count])
```

记忆内容结构建议：

```text
recent: 近期对话和学习摘要
profile: 用户 profile 摘要
scope: 用户知识范围和熟悉程度
preferences: 明确偏好
```

隐私边界：

```text
1. 不读取未授权家庭成员医疗档案。
2. 不把医疗档案事实混入普通 memory。
3. 如果未来要读成员健康档案，应使用独立医疗档案工具，不由 read_memory 承担。
```

验收：

```text
1. 有记忆时 schema 会挂载 read_memory。
2. 无记忆时不挂载，或执行返回空内容和 char_count=0。
3. read_memory 结果进入 role=tool message，不直接展示给用户。
4. 调试快照能看到本轮是否 hasMemory。
```

### 5.4 `write_memory`

工具名：

```text
write_memory
```

用途：

```text
保存用户明确表达的长期偏好。
```

schema：

```json
{
  "name": "write_memory",
  "parameters": {
    "type": "object",
    "properties": {
      "op": {
        "type": "string",
        "enum": ["add", "edit"]
      },
      "text": {
        "type": "string",
        "description": "The preference, in the user's own words where possible. <= 240 chars."
      },
      "target_id": {
        "type": "string"
      },
      "reason": {
        "type": "string"
      }
    },
    "required": ["op", "text"]
  }
}
```

执行规则：

```text
1. op 只能是 add 或 edit。
2. text 不能为空，长度建议 <= 240。
3. edit 时 target_id 必须指向已有条目。
4. 重复内容要去重，返回 already saved。
5. 保存失败要返回 success=false 和明确原因。
```

安全规则：

```text
允许保存：
  - “以后请用中文回答”
  - “我喜欢先给结论再展开”
  - “体检计划请用表格”
  - “解释医学指标时尽量简单”

禁止保存：
  - 模型推断出来的疾病
  - 未确认的家族病史
  - 体检报告异常值
  - 家庭成员隐私信息
  - 用户一次性任务临时输入
```

验收：

```text
1. 用户明确表达偏好时模型可调用 write_memory。
2. 保存后 tool result 返回 entry_id 或 deduplicated。
3. 下一轮 read_memory 能读取到该偏好。
4. 医疗档案信息不会被写入普通 memory。
```

## 6. 工具运行流程设计

### 6.1 Live Send 流程

```text
用户发送消息
  -> DeepTutorTurnCoordinator 创建 turn session
  -> DeepTutorModelContextResolver 解析模型/智能体
  -> AIConfigCenter 解析 provider/base model
  -> DeepTutorToolMountContext 计算 mount flags
  -> DeepTutorToolComposition 产出 enabled tool names
  -> DeepTutorToolRegistry 输出 tool schemas
  -> DeepTutorPromptBuilder 注入 tool manifest / prompt hints
  -> DeepTutorAgenticRuntime.start
  -> DeepTutorAgentLoop round 1
  -> AIRuntimeService stream completion
  -> 如果无 tool_calls：完成回答
  -> 如果有 tool_calls：DeepTutorToolDispatcher 执行
  -> role=tool messages 回灌
  -> 如果 pause：落 pending card，等待用户
  -> 如果无 pause：进入下一 round
```

### 6.2 Pause 流程

```text
ToolResult.pauseForUser != nil
  -> DeepTutorToolDispatcher 返回 pause outcome
  -> DeepTutorAgentLoop 暂停
  -> DeepTutorPauseResumeCoordinator 记录：
       conversationID
       assistantMessageID
       turnID
       toolCallID
       toolName
       pausePayload
       pendingMessages
       enabledToolsSnapshot
       modelContextSnapshot
  -> DeepTutorMessageReducer 生成 pending card block
  -> assistant message status = awaitingUserInput
```

### 6.3 Resume 流程

```text
用户提交卡片
  -> viewModel.submitAskUser / submitMemberSelection
  -> DeepTutorPauseResumeCoordinator.resolve
  -> 找到 matching pending turn
  -> 生成 user reply body
  -> 替换 matching role=tool content
  -> append continue directive
  -> DeepTutorAgentLoop 从 pause 点继续
  -> 后续工具 / 最终回答继续写入同一 assistant message
```

### 6.4 Stop / Cancel 流程

```text
用户点击停止
  -> cancellation token cancel
  -> 如果当前有 pending pause：
       mark cancelled
       assistant message status = cancelled 或 ready_with_pending_cancelled
  -> 不再调用 LLM
  -> 不再触发 Chat ToolInteraction
```

## 7. 和 Chat 共享工具链的拆除范围

### 7.1 DeepTutorChat 需要移除的共享依赖

目标移除：

```text
DeepTutorChatViewModel.init(chatOrchestrator:)
DeepTutorChatViewModel.init(toolInteractionCoordinator:)
DeepTutorAIRuntimeAdapter.let orchestrator: ChatOrchestrator
DeepTutorAIRuntimeAdapter.orchestrator.generateReply(...)
SendDeepTutorAIMessageUseCase.let toolInteractionCoordinator
DeepTutorToolPolicyResolver -> SparkToolName 映射
DeepTutorToolAliasMap -> SparkToolName 映射
DeepTutorDomainToolExtensionResolver -> ToolHub domain extension
```

替换为：

```text
DeepTutorChatViewModel.init(agenticRuntime:)
DeepTutorAIRuntimeAdapter.let agenticRuntime: DeepTutorAgenticRuntime
SendDeepTutorAIMessageUseCase.let pauseResumeCoordinator
DeepTutorToolComposition -> DeepTutorToolName
DeepTutorToolRegistry -> DeepTutorTool
```

### 7.2 Chat 侧需要回收的 DeepTutor 兼容代码

在 DeepTutorChat 新 runtime 完成后，清理 Chat/Core 中只为 DeepTutorChat 加的兼容逻辑：

```text
ChatOrchestrator.generateReply(preferInlineAskUser:)
ChatOrchestrator.generateReply(preferInlineMemberSelection:)
ToolHubAskUserQuestion 中 DeepTutor inline 特判
ToolHubRequestMemberSelection 中 DeepTutor inline 特判
ToolInteractionCoordinator 中 DeepTutorChat fallback 完成路径
ChatOrchestratorOutput 中仅为 DeepTutor inline 卡片增加的字段
```

保留原则：

```text
如果某段逻辑 Chat 自身仍使用，则保留在 Chat。
如果某段逻辑仅用于 DeepTutorChat 兼容，则迁移到 DeepTutorChat/Tools 后删除。
```

### 7.3 不能拆的共享基础设施

以下仍可复用：

```text
AIConfigCenter
AIScenarioRemoteModelRow
AIRuntimeService
AIResolvedConfig
模型/智能体选择配置
本地数据库 repository
成员 repository
记忆 repository
日志系统 Logger
```

复用边界：

```text
复用服务，不复用工具壳。
复用数据，不复用 ToolHub executor。
复用 AI provider，不复用 ChatOrchestrator tool loop。
```

## 8. Prompt 与工具提示词设计

### 8.1 System Prompt 中的工具 manifest

DeepTutor-main 会通过 registry 生成 prompt hints / manifest。DeepTutorChat 应新增：

```text
DeepTutorToolPromptManifestBuilder
```

输出结构：

```text
Available tools:
- ask_user: ...
- request_member_selection: ...
- read_memory: ...
- write_memory: ...

Tool rules:
- Prefer sensible defaults.
- Ask the user only when blocked.
- If member context is required and no member is selected, call request_member_selection first.
- After ask_user/member selection is resolved, continue the original request.
- Do not use write_memory for medical facts.
```

### 8.2 ask_user 中文恢复指令

恢复后 role=tool 内容末尾必须加：

```text
[ask_user 已解决。请使用这些回答继续处理用户的原始请求。不要只回复确认。]
```

成员选择恢复指令建议：

```text
[成员选择已解决。请使用该成员上下文继续处理用户的原始请求。不要只回复确认。]
```

### 8.3 体检计划智能体的成员优先规则

当 DeepTutorChat 运行体检计划类智能体时：

```text
1. 如果没有 boundMemberID，先调用 request_member_selection。
2. 成员选择未完成前，不调用健康档案/报告/风险类工具。
3. 第一阶段没有接入健康档案工具时，使用 ask_user 补齐缺失信息。
4. 最终回答要明确哪些信息来自用户输入，哪些是通用建议。
```

## 9. 状态机与消息块

### 9.1 Turn 状态

新增或明确 DeepTutor turn 状态：

```text
idle
streaming
dispatchingTools
awaitingUserInput
resuming
completed
cancelled
failed
```

状态转换：

```text
streaming -> dispatchingTools
dispatchingTools -> streaming
dispatchingTools -> awaitingUserInput
awaitingUserInput -> resuming
resuming -> streaming
streaming -> completed
any -> cancelled
any -> failed
```

### 9.2 MessageBlock

第一阶段必须支持：

```text
DeepTutorMessageBlock.askUser
DeepTutorMessageBlock.memberSelection
DeepTutorMessageBlock.trace
DeepTutorMessageBlock.text
```

建议增加：

```text
DeepTutorMessageBlock.toolPause
DeepTutorMessageBlock.toolResultSummary
```

但第一阶段可以先用现有 askUser/memberSelection/trace。

### 9.3 pending 持久化

pending block 必须可落库：

```text
assistantMessageID
turnID
toolCallID
toolName
payload
createdAt
status: pending/resolved/cancelled
resumeDirective
```

reload 后：

```text
pending -> 卡片可继续提交
resolved -> 卡片显示已选择/已回答，不可重复提交
cancelled -> 卡片显示已取消
```

## 10. 日志与调试

新增日志事件建议：

```text
deeptutor.tool.registry.loaded
deeptutor.tool.composition.resolved
deeptutor.tool.schema.outbound
deeptutor.agent_loop.round_started
deeptutor.tool.dispatch.started
deeptutor.tool.dispatch.completed
deeptutor.tool.pause.started
deeptutor.tool.pause.resolved
deeptutor.tool.pause.cancelled
deeptutor.memory.read
deeptutor.memory.write.accepted
deeptutor.memory.write.rejected
```

调试快照新增字段：

```text
toolRuntime = deepTutorNative
enabledDeepTutorTools
outboundToolSchemas
toolMountFlags
agentLoopRoundCount
toolStepCount
pauseState
pauseToolCallID
pendingToolName
memoryCharCount
memberSelectionState
```

验收日志示例：

```text
deeptutor.tool.composition.resolved tools=ask_user,request_member_selection,write_memory reason=phase1_default;needs_member
deeptutor.tool.pause.started tool=request_member_selection toolCallID=call_xxx message=...
deeptutor.tool.pause.resolved tool=request_member_selection memberID=12
deeptutor.agent_loop.round_started round=2 resume=true
deeptutor.agent_loop.completed finishReason=stop toolSteps=1
```

## 11. 迁移实施计划

### Phase 0: 架构冻结与基线测试

目标：

```text
确认 DeepTutorChat 独立工具 runtime 的边界。
冻结当前 Chat ToolHub 行为，避免迁移时破坏 Chat。
```

任务：

```text
1. 给 Chat ToolHub 增加现有行为回归测试。
2. 给 DeepTutorChat 记录当前 ask_user/member_selection 的端到端快照。
3. 标记所有 DeepTutorChat -> ToolHub/ToolInteractionCoordinator 依赖点。
4. 建立迁移 feature flag：DeepTutorNativeToolsEnabled。
```

验收：

```text
feature flag off 时行为不变。
feature flag on 时只影响 DeepTutorChat。
Chat 页面不受影响。
```

### Phase 1: 建立 DeepTutor Tool Protocol / Registry

任务：

```text
1. 新增 Domain/Tools 基础模型。
2. 新增 Application/Tools/DeepTutorTool 协议。
3. 新增 DeepTutorToolRegistry。
4. 新增 DeepTutorToolSchemaBuilder。
5. 注册四个第一阶段工具的空实现或最小实现。
```

验收：

```text
DeepTutorToolRegistryTests 通过。
buildOpenAISchemas 输出 OpenAI-compatible schema。
不依赖 ToolHub.toolDefinitions。
```

### Phase 2: 建立 DeepTutor Tool Composition

任务：

```text
1. 新增 DeepTutorToolComposition。
2. 对齐 DeepTutor-main mount flags。
3. 第一阶段只输出 ask_user / request_member_selection / read_memory / write_memory。
4. 接入 DeepTutorRuntimeRequestBuilder 或新的 AgenticRuntime request builder。
```

验收：

```text
无成员时健康类请求挂载 request_member_selection。
有记忆时挂载 read_memory。
write_memory 和 ask_user 默认可见。
不产生 SparkToolName。
```

### Phase 3: 建立 DeepTutor Agent Loop

任务：

```text
1. 新增 DeepTutorAgenticRuntime。
2. 新增 DeepTutorAgentLoop。
3. 将 AIRuntimeService 包装为 round-level LLM caller。
4. 支持 assistant tool_calls、role=tool messages、max rounds。
5. 支持 tool pause 后停止 loop。
```

验收：

```text
无工具请求时可正常流式回答。
有普通工具时可进入下一 round。
有 pause 工具时停在 awaitingUserInput。
```

### Phase 4: 接入 ask_user

任务：

```text
1. 按 DeepTutor-main 常量实现 AskUser payload normalizer。
2. 将 DeepTutorAskUserCardView 数据源切到 native pause payload。
3. submitAskUser 改走 DeepTutorPauseResumeCoordinator。
4. 恢复后替换 matching role=tool content。
```

验收：

```text
ask_user 卡片可展示、提交、恢复、继续完成原始任务。
reload 后 pending ask_user 可提交。
不会触发 ToolInteractionCoordinator.requestQuestionAnswer。
```

### Phase 5: 接入成员选择

任务：

```text
1. 新增 DeepTutorMemberSelectionTool。
2. 新增 DeepTutorMemberToolDataSource。
3. submitMemberSelection 改走 DeepTutorPauseResumeCoordinator。
4. 成员选择结果写入 conversation bound member 或本轮 member context。
5. 硬暂停边界：pending 前不得继续跑后续成员依赖工具。
```

验收：

```text
未绑定成员时触发成员选择卡。
选择后同一 assistant message 继续回答。
不会触发 Chat 的 MemberSelectionToolSheet。
```

### Phase 6: 接入记忆

任务：

```text
1. 新增 DeepTutorMemoryStore 协议。
2. 新增 DeepTutorMemoryStoreAdapter，复用底层记忆 repository。
3. 实现 read_memory。
4. 实现 write_memory。
5. 加入医疗隐私写入拦截规则。
```

验收：

```text
read_memory 返回 char_count。
write_memory 支持 add/edit/deduplicate/rejected。
医疗事实不会写入普通 memory。
```

### Phase 7: 切断 DeepTutorChat 对 ToolHub + ToolInteraction 的依赖

任务：

```text
1. DeepTutorChatViewModel 初始化参数移除 ChatOrchestrator。
2. DeepTutorChatViewModel 初始化参数移除 ToolInteractionCoordinator。
3. SendDeepTutorAIMessageUseCase 移除 ToolInteractionCoordinator fallback。
4. DeepTutorAIRuntimeAdapter 改用 DeepTutorAgenticRuntime。
5. DeepTutorChatDebugExporter 改读 DeepTutor native tool runtime 快照。
```

验收：

```text
rg \"ToolInteractionCoordinator\" Projects/Features/DeepTutorChat 只剩文档或测试兼容说明。
rg \"ChatOrchestrator\" Projects/Features/DeepTutorChat 只剩迁移注释或已删除。
rg \"SparkToolName\" Projects/Features/DeepTutorChat 不再参与 native tool policy。
```

### Phase 8: 回收 Chat/Core 的 DeepTutor 兼容分支

任务：

```text
1. 删除 ChatOrchestrator 中 DeepTutor inline ask_user/member selection 开关。
2. 删除 ToolHub 中 DeepTutor inline 兼容路径。
3. 删除 ToolInteractionCoordinator 中 DeepTutorChat 完成 fallback。
4. 保留 Chat 自身工具交互完整行为。
```

验收：

```text
Chat 工具测试通过。
DeepTutorChat native tools 测试通过。
Chat 和 DeepTutorChat 不再共享 ToolInteraction 状态。
```

## 12. 测试计划

### 12.1 单元测试

新增测试建议：

```text
Tests/DeepTutorChat/DeepTutorToolRegistryTests.swift
Tests/DeepTutorChat/DeepTutorToolSchemaBuilderTests.swift
Tests/DeepTutorChat/DeepTutorToolCompositionTests.swift
Tests/DeepTutorChat/DeepTutorAskUserPayloadTests.swift
Tests/DeepTutorChat/DeepTutorMemberSelectionToolTests.swift
Tests/DeepTutorChat/DeepTutorMemoryToolTests.swift
Tests/DeepTutorChat/DeepTutorToolDispatcherTests.swift
Tests/DeepTutorChat/DeepTutorPauseResumeCoordinatorTests.swift
Tests/DeepTutorChat/DeepTutorAgentLoopPauseResumeTests.swift
```

### 12.2 ask_user 测试矩阵

```text
legacy question/options 被兼容或明确拒绝
questions 为空时报错
questions 超过 4 截断
options 超过 8 截断
重复 option 去重
重复 question id 自动消歧
header 超长截断
prompt 超长截断
free text 时不重复追加 Other
object option description 正常保留
```

### 12.3 成员选择测试矩阵

```text
无成员数据 -> 工具返回不可用错误
有成员未绑定 -> 返回 pauseForUser.memberSelection
已有 boundMemberID -> composition 不挂载 request_member_selection，或工具直接返回已绑定
用户选择成员 -> resume 同 turn
用户取消 -> turn cancelled 或返回通用回答
reload pending -> 可继续提交
重复提交 -> 第二次被拒绝
```

### 12.4 记忆测试矩阵

```text
无记忆 -> read_memory char_count=0
有记忆 -> read_memory 返回拼接文本
write_memory add 成功
write_memory edit 缺 target_id 失败
write_memory duplicate 返回 deduplicated=true
write_memory 医疗事实被拒绝
下一轮 read_memory 可读到明确偏好
```

### 12.5 端到端测试

场景 1：成员选择闭环

```text
用户：帮我制定体检计划
AI：调用 request_member_selection
UI：展示成员选择卡
用户：选择“爸爸”
AI：继续完成体检计划，不只回复确认
```

场景 2：ask_user 闭环

```text
用户：帮我做一个适合我的体检计划
AI：如没有必要信息，调用 ask_user 一次性问年龄段/症状/预算等
用户：提交答案
AI：继续输出计划
```

场景 3：记忆闭环

```text
用户：以后给我体检计划都用表格
AI：调用 write_memory
下一轮用户：再帮我整理一下
AI：调用 read_memory 后使用表格
```

场景 4：Chat 隔离

```text
Chat 页面 ask_user 仍走 ToolInteraction Sheet。
DeepTutorChat 页面 ask_user 只走 DeepTutorAskUserCardView。
两个页面的 pending 状态互不影响。
```

## 13. 验收标准

### 13.1 架构验收

```text
DeepTutorChat 有独立 Tools 目录。
DeepTutorChat 有独立 ToolRegistry。
DeepTutorChat 有独立 ToolDispatcher。
DeepTutorChat 有独立 AgentLoop。
DeepTutorChat 有独立 PauseResumeCoordinator。
DeepTutorChat 不再依赖 ToolHub 执行工具。
DeepTutorChat 不再依赖 ToolInteractionCoordinator 完成人机交互。
```

### 13.2 功能验收

```text
ask_user 可暂停、展示、提交、恢复、继续原始任务。
request_member_selection 可暂停、展示、提交、恢复、继续原始任务。
read_memory 可读取用户长期记忆。
write_memory 可保存明确偏好并防止医疗事实误写。
```

### 13.3 流程验收

```text
awaitingUserInput 是硬暂停边界。
pause 之后不得继续合并过期工具事件。
resume 必须回到同一 assistant message。
最终回答必须完成用户原始请求。
```

### 13.4 隔离验收

```text
DeepTutorChat 不弹 Chat ToolInteractionPresentationSheet。
DeepTutorChat 不调用 ToolHub.execute。
DeepTutorChat 不通过 SparkToolName 决定工具白名单。
Chat 的工具链不受 DeepTutorChat native tools 影响。
```

### 13.5 可观测性验收

```text
每轮能看到 enabledDeepTutorTools。
每轮能看到 outboundToolSchemas。
每个工具调用有 stable toolCallID。
pause/resume 有完整日志。
debug exporter 能输出 native tool runtime snapshot。
```

## 14. 风险与处理

| 风险 | 影响 | 处理 |
| --- | --- | --- |
| 一次性替换 ChatOrchestrator 风险大 | DeepTutorChat 发送链路可能回归 | 使用 feature flag 分阶段切换 |
| DeepTutorAgentLoop 与 AIRuntimeService 对接复杂 | 流式、tool_calls、停止逻辑可能不稳定 | 先只支持第一阶段四个工具，max round 限制保守 |
| 记忆 repository 边界不清 | 可能误写医疗隐私 | 新增 DeepTutorMemoryStoreAdapter 和医疗事实拦截测试 |
| 成员选择不是 DeepTutor-main 原生工具 | 对齐时容易混入 Spark 旧逻辑 | 只复用 pause/resume 模式，不复用 ToolHub executor |
| 清理共享兼容分支可能影响 Chat | Chat 工具交互回归 | Phase 8 必须在 DeepTutor native tools 完成后执行，并跑 Chat 回归测试 |

## 15. 本工单和既有工单关系

```text
DEEPTUTORCHAT-000037
  -> 体检报告制定计划智能体需求。
  -> 本工单提供该智能体第一阶段所需的成员选择、问答、记忆工具运行时。

DEEPTUTORCHAT-000038
  -> DeepTutorChat 模型/智能体选择、提示词、工具选择对齐 Chat。
  -> 本工单不推翻模型/智能体配置选择；只推翻工具运行时共享方式。

DEEPTUTORCHAT-000040
  -> 曾提出底层 ToolHub 共享、交互隔离。
  -> 本工单按新决策升级为工具运行时整体独立。

DEEPTUTORCHAT-000041
  -> 分析工具调用与 Quiz 卡片流程对齐问题。
  -> 本工单复用其“agent loop + stream event + card block”方向，但第一阶段不处理 Quiz。

DEEPTUTORCHAT-000042
  -> 处理健康体检计划在成员选择处意外停止的问题。
  -> 本工单从架构上规定 awaitingUserInput 硬暂停和同 turn resume，作为根治方案。
```

## 16. 最终交付物

第一阶段完成后应交付：

```text
1. DeepTutorChat 独立工具目录。
2. DeepTutorToolProtocol / Registry / Composition / Dispatcher / AgentLoop。
3. ask_user native tool。
4. request_member_selection native tool。
5. read_memory native tool。
6. write_memory native tool。
7. DeepTutorPauseResumeCoordinator。
8. DeepTutorChat 不再使用 ToolHub + ToolInteraction 的迁移 PR。
9. Chat 侧 DeepTutor 兼容分支清理 PR。
10. 单元测试与端到端测试。
```

## 17. Done Definition

本工单完成的唯一标准：

```text
DeepTutorChat 在不依赖 ToolHub + ToolInteraction 的情况下，
可以使用 DeepTutor-main 风格的工具循环完成：

用户发送请求
  -> 工具挂载
  -> 模型 tool_calls
  -> 工具执行
  -> 成员选择/ask_user 暂停
  -> 用户提交
  -> 同 turn 恢复
  -> 读取/写入记忆
  -> 完成原始回答

并且 Chat 原有工具链不回归。
```

