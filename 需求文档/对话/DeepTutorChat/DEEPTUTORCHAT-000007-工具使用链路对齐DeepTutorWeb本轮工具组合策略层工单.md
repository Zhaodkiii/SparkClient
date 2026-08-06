# DEEPTUTORCHAT-000007 工具使用链路对齐 DeepTutor Web 本轮工具组合策略层工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000007 |
| 工单类型 | P0 架构偏差修正 + DeepTutor Web 工具策略对齐 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| iOS 功能目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| iOS 运行时依赖 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime` |
| Web 参考工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main` |
| 创建日期 | 2026-08-05 |
| 模型场景约束 | 继续使用项目已有通用 `.chat` 场景，不新增 `.deepTutor` |
| 实施约束 | 后续实现时必须先补策略层、日志和测试，再调整 UI 验收；本工单不直接实现 |

## 1. 背景与问题结论

当前 DeepTutorChat iOS 版本接入了项目已有 `AIConfigCenter` 与 `ChatOrchestrator`，并使用通用 `.chat` 场景消费真实大模型。但工具使用链路与 DeepTutor Web 存在关键架构偏差：

```text
当前 iOS 链路：

DeepTutorPromptBuilder
  -> ChatOrchestratorInferenceOptions(useTools=true, allowedToolNames=nil)
  -> ChatOrchestrator.filteredToolDefinitions()
  -> ToolHub.toolDefinitions()
  -> SparkToolName.all
  -> runtimeService.generateTextStream(toolChoice=.auto)
```

这个链路的问题是：`.chat` 模式下 `allowedToolNames=nil` 被解释为“不限制工具”，最终 `ToolHub.toolDefinitions()` 会把 `SparkToolName.all` 中所有工具 schema 暴露给模型。模型虽然仍使用 `toolChoice=.auto`，但 `auto` 只能在“已经暴露的工具集合”中决定是否调用，不能替代“本轮应该暴露哪些工具”的策略层。

DeepTutor Web 的实际设计不是“全部工具给 AI”。它有一层“本轮工具组合策略层”，先根据用户开关、上下文、权限、capability、资源挂载状态生成本轮可见工具集，再交给模型 `tool_choice=auto` 自主决定是否调用。

本工单目标：在 iOS DeepTutorChat 中补齐 DeepTutor Web 同类的“本轮工具组合策略层”，避免普通寒暄、闲聊、纯文本问答时暴露健康、位置、成员、知识库、系统卡片等全部工具。

## 2. 当前 iOS 代码事实

### 2.1 DeepTutorPromptBuilder 当前把 `.chat` 工具白名单设置为 nil

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorPromptBuilder.swift
```

当前事实：

```swift
case .chat:
    capabilityPrompt = """
    Mode: general tutoring chat.
    Explain clearly, cite reasoning steps, and ask clarifying questions when needed.
    You may call `ask_user_question` when you need structured user input.
    """
    allowedTools = nil
```

问题：

```text
allowedTools = nil 当前不是“默认最小工具集”，而是“工具不做白名单限制”。
```

### 2.2 ChatOrchestratorInferenceOptions 当前以 allowedToolNames 表达白名单

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ChatOrchestratorInferenceOptions.swift
```

当前事实：

```swift
struct ChatOrchestratorInferenceOptions: Equatable, Sendable {
    var useTools: Bool
    var useKnowledgeBag: Bool
    var useWebSearch: Bool
    var reasoningEnabled: Bool
    var reasoningEffortTier: Int
    var allowedToolNames: Set<String>? = nil
}
```

问题：

```text
allowedToolNames 是正确的策略入口，但 DeepTutorChat 当前没有在进入 ChatOrchestrator 前生成本轮白名单。
```

### 2.3 ChatOrchestrator 当前会从 ToolHub 读取全部工具定义

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ChatOrchestrator.swift
```

当前事实：

```swift
private func filteredToolDefinitions(inference: ChatOrchestratorInferenceOptions) -> [AIRuntimeToolDefinition] {
    guard inference.useTools else { return [] }
    var definitions = toolHub.toolDefinitions()
    ...
    if let allowed = inference.allowedToolNames {
        let normalizedAllowed = Set(allowed.map(Self.normalizeToolName))
        definitions.removeAll { normalizedAllowed.contains(Self.normalizeToolName($0.name)) == false }
    }
    return definitions
}
```

问题：

```text
如果 allowedToolNames 为 nil，filteredToolDefinitions 不会做最后一层白名单裁剪。
```

### 2.4 ToolHub 当前工具定义来源是 SparkToolName.all

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ToolHub/ToolHub+Schema.swift
```

当前事实：

```swift
func toolDefinitions() -> [AIRuntimeToolDefinition] {
    SparkToolName.all.map { toolName in
        ...
    }
}
```

工具分组位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ToolHub/Models/ToolingModels.swift
```

当前分组包含：

| 分组 | 工具类型 |
| --- | --- |
| health | 步数、能量、营养、睡眠、运动、健康资料、结构化健康卡片 |
| member | 当前成员、成员选择、成员切换、成员查找、成员档案 |
| location | 位置、天气、路线、附近地点 |
| memory | 保存/读取/更新记忆、生成标题 |
| knowledge | 知识库检索、创建知识文档、在线搜索、网页读取、arXiv、远程文件 |
| system | 日历、系统事件、自定义卡片、风险提示、canvas、小任务、ask_user |

当前偏差：

```text
DeepTutor 普通聊天没有必要默认暴露上面全部工具。
尤其普通寒暄、简单知识问答、解释类问题，应该只暴露最小工具面，甚至只暴露 ask_user_question 或完全不暴露工具。
```

## 3. DeepTutor Web 参考实现事实

### 3.1 TurnRuntime 先确认本轮用户启用工具

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/services/session/turn_runtime.py
```

关键事实：

```text
如果 payload 没有显式传 tools，DeepTutor Web 会从用户 Settings 的 enabled optional tools 回填。
然后再经过 allowed_optional_tools 做账号/管理员级白名单过滤。
```

这说明 Web 端第一步不是让模型看全部工具，而是先得到“用户允许的可选工具集合”。

### 3.2 工具组合策略核心在 compose_enabled_tools

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/agents/_shared/tool_composition.py
```

核心对象：

```text
AUTO_MOUNTED_TOOLS
ToolMountFlags
default_optional_tools()
compose_enabled_tools()
```

`ToolMountFlags` 负责表达本轮上下文：

```text
has_kb
has_sources
has_memory
has_notebooks
has_skills
has_deferred_tools
has_exec
has_code
```

`compose_enabled_tools()` 的工具排序与来源：

| 顺序 | 来源 | 说明 |
| --- | --- | --- |
| 1 | 用户开关工具 | 只接收用户可控工具，如 brainstorm、web_search、paper_search、reason |
| 2 | 条件自动挂载 | 有 KB 才挂 rag/kb_files，有 memory 才挂 read_memory，有 notebook 才挂 list_notebook/write_note |
| 3 | capability-owned tools | 能力自己拥有的工具，例如 mastery / solve / research 专属工具 |
| 4 | always-on 自动工具 | ask_user、web_fetch、github、cron 等基础工具 |
| 5 | forced/suppressed | partner 等特殊场景可以强制挂载或强制移除 |

### 3.3 Chat pipeline 在进入 AgentLoop 前收窄工具集

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/agents/chat/agentic_pipeline.py
```

关键链路：

```text
ChatAgenticPipeline.run()
  -> _prepare_deferred_tools(context)
  -> _prepare_kb_manifests(context)
  -> _exec_allowed(context)
  -> _compose_enabled_tools(context)
  -> _build_llm_tool_schemas(enabled_tools, context)
  -> AgentLoop(enabled_tools, tool_schemas)
```

这说明 DeepTutor Web 是先组合本轮工具集，再构造 tool schemas。

### 3.4 模型层仍使用 tool_choice=auto

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/core/agentic/client.py
```

关键事实：

```text
tools = 本轮组合后的 tool_schemas
tool_choice = auto
```

结论：

```text
Web 的“是否使用工具”不是靠前端按钮或 prompt 强压，也不是把全部工具丢给模型。
它是：策略层先裁剪可见工具，模型再在小集合内自主决定是否调用。
```

## 4. 目标架构

### 4.1 iOS 需要新增本轮工具策略层

建议新增职责，不在本工单直接实现：

```text
DeepTutorToolPolicyResolver
DeepTutorToolMountContext
DeepTutorToolPolicyResult
```

建议目录：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorToolPolicyResolver.swift
```

职责边界：

| 对象 | 职责 | 禁止 |
| --- | --- | --- |
| DeepTutorPromptBuilder | 只构造角色、能力、回答风格、提示词 | 不直接决定全部工具策略 |
| DeepTutorToolPolicyResolver | 根据 capability、用户输入、上下文、设置生成本轮 allowedToolNames | 不执行工具 |
| ChatOrchestrator | 根据 allowedToolNames 过滤 schema，执行模型 tool loop | 不理解 DeepTutor 产品策略 |
| ToolHub | 提供工具 schema、解析参数、执行单个工具 | 不决定本轮哪些工具应该暴露给 AI |
| DeepTutorChatViewModel | 提供 UI 状态、上下文和发送入口 | 不直接拼工具白名单 |

### 4.2 目标链路

```text
DeepTutorChatViewModel.submit
  -> SendDeepTutorAIMessageUseCase
  -> DeepTutorRuntimeRequestBuilder.build(...)
  -> DeepTutorToolPolicyResolver.resolve(...)
  -> ChatOrchestratorInferenceOptions(
       useTools: resolved.useTools,
       useKnowledgeBag: resolved.useKnowledgeBag,
       useWebSearch: resolved.useWebSearch,
       allowedToolNames: resolved.allowedToolNames
     )
  -> ChatOrchestrator.filteredToolDefinitions()
  -> runtimeService.generateTextStream(toolChoice=.auto)
```

### 4.3 allowedToolNames 语义必须重新冻结

后续实现必须明确区分：

| 值 | 语义 |
| --- | --- |
| `useTools=false` | 完全不传工具 schema |
| `useTools=true + allowedToolNames=[]` | 允许工具机制但本轮没有可见工具，最终应等价于不传工具 |
| `useTools=true + allowedToolNames=非空集合` | 只暴露集合内工具 |
| `useTools=true + allowedToolNames=nil` | 仅允许 Core Chat 旧链路代表“不限制”；DeepTutorChat 禁止使用 nil 作为默认聊天策略 |

DeepTutorChat 后续应做到：

```text
普通 chat 不再产生 allowedToolNames=nil。
只有经过明确审计的特殊调试/兼容路径才允许 nil。
```

## 5. iOS 本轮工具组合策略设计

### 5.1 DeepTutorToolMountContext 字段建议

```text
capability: DeepTutorCapability
userInput: String
conversationID: UUID
conversationTitle: String
hasKnowledgeContext: Bool
hasHealthResourceContext: Bool
hasSelectedMember: Bool
hasLocationPermission: Bool
hasMemory: Bool
hasNotebook: Bool
hasAttachment: Bool
userEnabledOptionalTools: Set<String>
modelSupportsToolCalling: Bool
debugOverrideAllowedTools: Set<String>?
```

说明：

```text
当前阶段如果某些上下文还没有接入，可以先用 fail-closed 策略：未知即 false，不挂载对应工具。
```

### 5.2 DeepTutorToolPolicyResult 字段建议

```text
useTools: Bool
useKnowledgeBag: Bool
useWebSearch: Bool
allowedToolNames: Set<String>
policyReason: String
mountFlags: [String: Bool]
suppressedToolNames: Set<String>
```

`policyReason` 需要进入日志，方便排查为什么本轮暴露/不暴露某个工具。

### 5.3 普通 chat 默认工具集

默认聊天不应暴露全部工具。建议默认最小集合：

```text
ask_user_question
generate_chat_title 可选，若标题生成仍走工具
```

如果后续确认 `generate_chat_title` 会污染普通回答或触发无意义工具调用，则默认聊天只保留：

```text
ask_user_question
```

### 5.4 意图与上下文挂载建议

本工单不要求先实现复杂 LLM router，第一阶段可用轻量规则 + 上下文 flags。

| 场景 | 触发条件 | 允许工具 |
| --- | --- | --- |
| 普通寒暄 | 问候、闲聊、无外部信息需求 | `ask_user_question` 或无工具 |
| 普通知识问答 | “解释/讲讲/为什么/怎么理解”且无联网词 | `ask_user_question` |
| 明确要求追问用户 | “先问我/需要我提供/你问我” | `ask_user_question` |
| 天气/城市/位置 | 天气、气温、城市、附近、路线、定位 | `ask_user_question`、`query_weather`、必要时 `query_location/get_current_location` |
| 健康数据 | 步数、睡眠、运动、饮食、营养、能量 | `ask_user_question`、成员选择工具、对应健康读取工具 |
| 问报告/健康资料 | 报告、检查、病历、化验单、资料 | `ask_user_question`、`list_member_health_sources`、`get_health_resource_reference`、`get_health_resource_context` |
| 知识库 | 用户显式选择 KB 或会话有知识上下文 | `ask_user_question`、`search_knowledge_bag` |
| 联网搜索 | “搜索/最新/新闻/论文/arXiv/网页/查一下” | `ask_user_question`、`search_online`、`read_web_page`、必要时 `search_arxiv_papers` |
| 可视化/动画 | capability 为 visualize/math_animator | `ask_user_question`，后续如有专属渲染工具再按 capability-owned 挂载 |
| Quiz | capability 为 deep_question | `ask_user_question`，不默认暴露健康/位置/知识库工具 |
| Deep Research | capability 为 deep_research | `ask_user_question`、搜索/知识类工具按配置和上下文挂载 |

### 5.5 fail-closed 原则

任何权限、上下文、设置读取失败时：

```text
不要暴露对应工具。
记录 deeptutor.tool_policy.context_unavailable。
继续让模型用纯文本回答或 ask_user_question 澄清。
```

示例：

| 上下文失败 | 策略 |
| --- | --- |
| 成员状态未知 | 不挂健康数据读取工具，只保留 `ask_user_question` |
| 定位权限未知 | 不挂 `get_current_location`，可挂 `ask_user_question` 询问城市 |
| KB 状态未知 | 不挂 `search_knowledge_bag` |
| 模型不支持 tool calling | `useTools=false`，提示词中保留“需要信息时先追问” |

## 6. 日志与可观测性需求

本工单需要增加全流程工具策略日志，日志不需要脱敏，但必须结构化、可检索、避免重复刷屏。

### 6.1 工具策略决策日志

日志名：

```text
deeptutor.tool_policy.resolved
```

字段：

```text
conversation
message
capability
inputLength
policyReason
useTools
useKnowledgeBag
useWebSearch
allowedToolCount
allowedTools
suppressedTools
mountFlags
modelSupportsToolCalling
```

示例：

```text
deeptutor.tool_policy.resolved conversation=ABC123 message=DEF456 capability=chat inputLength=7 policyReason=casual_chat useTools=true allowedToolCount=1 allowedTools=ask_user_question suppressedTools=health,location,knowledge mountFlags=has_kb:false,has_member:false,has_location:false
```

### 6.2 工具 schema 出站日志

日志名：

```text
deeptutor.tool_schema.outbound
```

字段：

```text
conversation
message
toolChoice
schemaCount
schemaNames
reason
```

目标：

```text
可以直接验证本轮是否还把 SparkToolName.all 全量传给 AI。
```

### 6.3 模型工具调用日志

日志名：

```text
deeptutor.tool_call.received
```

字段：

```text
conversation
message
round
toolName
toolCallID
argumentsLength
wasAllowedByPolicy
allowedToolCount
```

如果模型返回了不在本轮白名单内的工具，必须记录：

```text
deeptutor.tool_call.denied_by_policy
```

并走安全降级，不执行工具。

### 6.4 工具执行结果日志

日志名：

```text
deeptutor.tool_call.completed
```

字段：

```text
conversation
message
round
toolName
toolCallID
status
durationMs
resultLength
sideEffectCount
awaitingUserInput
```

### 6.5 ask_user 特殊日志

日志名：

```text
deeptutor.ask_user.policy_selected
deeptutor.ask_user.card_emitted
deeptutor.ask_user.reply_submitted
deeptutor.ask_user.resume_requested
```

目标：

```text
能从日志中完整看出：为什么本轮选择 ask_user、模型是否调用 ask_user、卡片是否进入消息 reducer、用户回复是否恢复本轮生成。
```

## 7. UI 与体验验收

### 7.1 普通寒暄

输入：

```text
你好 哈哈哈
```

期望：

```text
1. 允许工具集最多只包含 ask_user_question，推荐不暴露健康/位置/知识库/系统卡片工具。
2. 模型直接回答，不触发天气、健康、成员、知识库等工具。
3. trace 显示“无需工具”或只显示普通思考完成，不出现工具使用列表。
4. 日志中 allowedTools 不等于 SparkToolName.all。
```

### 7.2 明确要求先追问

输入：

```text
今天的天气怎么样？先使用工具，问问我在哪个城市。
```

期望：

```text
1. 工具策略允许 ask_user_question。
2. 如果尚无城市/定位上下文，优先展示 ask_user 问题卡片。
3. ask_user 卡片出现在助手消息内，不只弹系统 sheet。
4. 用户回答城市后，后续可以继续天气查询或文本回答。
```

### 7.3 明确天气查询

输入：

```text
北京今天的天气怎么样？
```

期望：

```text
1. 工具策略允许 query_weather。
2. 如果 query_weather 工具可用，则模型可以调用。
3. 不暴露健康、成员、知识库、canvas、小任务等无关工具。
```

### 7.4 明确健康数据查询

输入：

```text
我昨天睡得怎么样？
```

期望：

```text
1. 工具策略只在成员和健康权限满足时挂载 fetch_sleep_details。
2. 如果成员不明确，先允许 request_member_selection 或 ask_user_question。
3. 不暴露天气、路线、网页、canvas 等无关工具。
```

### 7.5 明确知识库查询

输入：

```text
根据我选中的知识库解释这份资料。
```

期望：

```text
1. 只有存在 KB 上下文时挂载 search_knowledge_bag。
2. 没有 KB 上下文时不挂载知识库工具，改为追问用户或普通回答。
```

## 8. 关键实现拆分

### 8.1 P0：冻结 DeepTutorChat 工具策略语义

任务：

```text
1. 明确 DeepTutorChat 禁止默认 allowedToolNames=nil。
2. 设计 DeepTutorToolMountContext / DeepTutorToolPolicyResult。
3. 梳理 SparkToolName 到 DeepTutor 场景的分组映射。
4. 写单元测试覆盖普通寒暄、ask_user、天气、健康、知识库、联网。
```

验收：

```text
普通 chat 的 allowedToolNames 必须是非空最小集合或空集合，不是 nil。
```

### 8.2 P1：实现本轮工具组合策略层

目标文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorToolPolicyResolver.swift
```

调用点：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorRuntimeRequestBuilder.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorAIRuntimeAdapter.swift
```

要求：

```text
1. 在构造 ChatOrchestratorInferenceOptions 前计算策略。
2. allowedToolNames 显式传入。
3. 不把策略写进 ToolHub。
4. 不让 ViewModel 直接拼工具集合。
```

### 8.3 P2：补齐日志和调试面

目标：

```text
1. 增加 deeptutor.tool_policy.resolved。
2. 增加 deeptutor.tool_schema.outbound。
3. 增加 deeptutor.tool_call.received / completed / denied_by_policy。
4. 日志要能还原从用户输入到工具 schema 出站再到工具执行的完整链路。
```

### 8.4 P3：ask_user 与工具策略联动

目标：

```text
1. ask_user_question 必须是 DeepTutorChat 最小可见工具。
2. 当策略判断需要用户补充上下文时，允许模型调用 ask_user_question。
3. ask_user 工具调用必须稳定转成消息内卡片。
4. 用户回复后恢复同一会话上下文，不创建游离消息。
```

### 8.5 P4：与项目通用 Chat 策略收敛

目标：

```text
DeepTutorChat 的策略层先在 Feature 内落地，后续如果通用 Chat 也需要同类能力，可以抽象为 Core AIRuntime 的 CapabilityToolPolicy。
```

禁止：

```text
不要一开始就重构整个 ChatOrchestrator。
不要因为 DeepTutorChat 的问题破坏通用 Chat 现有工具链路。
```

## 9. 测试与验收矩阵

| 用例 | 输入 | 期望工具集 | 期望结果 |
| --- | --- | --- | --- |
| 普通寒暄 | `你好 哈哈哈` | `[]` 或 `ask_user_question` | 不调用健康/位置/知识工具，直接回答 |
| 追问用户 | `先问我在哪个城市` | `ask_user_question` | 展示 ask_user 消息内卡片 |
| 天气查询 | `北京今天的天气` | `ask_user_question, query_weather` | 可以查天气，不暴露健康工具 |
| 位置不明确天气 | `今天的天气怎么样` | `ask_user_question, query_weather` | 优先追问城市或请求定位，不胡乱调用 |
| 健康睡眠 | `我昨天睡得怎么样` | `ask_user_question, request_member_selection, fetch_sleep_details` | 成员/权限不明时先澄清 |
| 知识库 | `根据知识库回答` | 有 KB 才含 `search_knowledge_bag` | 无 KB 不暴露知识库工具 |
| 联网 | `查一下最新论文` | `ask_user_question, search_online, search_arxiv_papers` | 可联网/论文搜索 |
| Quiz | capability=`deep_question` | `ask_user_question` | 不暴露健康/位置/系统卡片工具 |
| Visualize | capability=`visualize` | `ask_user_question` | 不暴露无关工具 |
| 模型不支持工具 | 任意 | 无 schema | 纯文本回答或提示用户补充信息 |

## 10. 风险与注意事项

### 10.1 不要把 tool_choice=auto 当成策略层

`toolChoice=.auto` 只是模型侧选择策略，不是产品侧工具治理策略。即使 `auto` 最终不调用工具，全部 schema 也已经进入模型上下文，带来以下风险：

```text
1. 普通聊天上下文被工具描述污染。
2. 模型更容易误判需要工具。
3. token 消耗增加。
4. 健康/位置/成员等敏感能力暴露面扩大。
5. ask_user 这类关键工具在大量无关工具中稳定性下降。
```

### 10.2 不要在 ToolHub 内写 DeepTutor 产品策略

ToolHub 应保持“工具注册、schema、参数解析、执行、审计”的原子能力层。DeepTutor 的本轮工具选择属于 capability/application 策略层。

### 10.3 不要让 prompt 代替工具白名单

仅在 system prompt 中写“不要随便使用工具”不可靠。必须用 `allowedToolNames` 从协议层限制工具 schema。

### 10.4 兼容通用 Chat

本工单只要求优化 DeepTutorChat。通用 Chat 可能仍依赖现有 `allowedToolNames=nil` 的行为，不能直接全局改变 `ChatOrchestratorInferenceOptions` 的 nil 语义。

## 11. 依赖与关联文档

| 文档/代码 | 关系 |
| --- | --- |
| `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/需求文档/对话/DeepTutorChat/DEEPTUTORCHAT-000001-iOS本地消息UI对齐DeepTutor-Web需求文档.md` | 消息 UI、trace、工具卡片渲染基础工单 |
| `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/需求文档/对话/DeepTutorChat/DEEPTUTORCHAT-000003-接入项目AIConfigCenter真实大模型系统工单.md` | 使用项目已有 `.chat` 场景和真实模型消费 |
| `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/需求文档/对话/DeepTutorChat/DEEPTUTORCHAT-000006-会话列表对齐日志分析思考自动折叠与手势收键盘工单.md` | 日志、trace、思考折叠与 UI 刷新前置问题 |
| `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/需求文档/对话/CHAT-000007-AI统一入口与Runtime单链路重构需求工单.md` | 通用 Chat 能力层/工具层分离原则 |
| `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/agents/_shared/tool_composition.py` | DeepTutor Web 本轮工具组合策略事实源 |
| `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/agents/chat/agentic_pipeline.py` | DeepTutor Web chat pipeline 使用策略层的位置 |
| `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/services/session/turn_runtime.py` | Web 会话本轮 tools payload、用户设置与权限过滤事实 |

## 12. 最终验收标准

完成实现后必须满足：

```text
1. DeepTutorChat 普通 .chat 不再默认把 SparkToolName.all 全量传给 AI。
2. 每一轮请求都有 deeptutor.tool_policy.resolved 日志，能看到 allowedTools。
3. 每一轮出站 AI 请求都有 schemaCount/schemaNames 日志。
4. 普通寒暄不会触发无关工具。
5. 明确 ask_user 的问题能稳定展示消息内卡片。
6. 天气、健康、知识库、联网等场景只暴露相关工具。
7. 通用 Chat 原有工具链路不被破坏。
8. 单元测试覆盖工具策略 resolver。
9. UI 验收截图和日志能证明工具策略与 DeepTutor Web 对齐。
```

本工单到此只完成需求与技术方案创建，未修改 Swift 业务实现代码。
