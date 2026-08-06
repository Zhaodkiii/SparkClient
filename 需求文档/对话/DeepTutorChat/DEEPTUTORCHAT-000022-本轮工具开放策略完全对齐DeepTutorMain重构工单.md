# DEEPTUTORCHAT-000022 本轮工具开放策略完全对齐 DeepTutor-main 重构工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000022 |
| 工单类型 | P0 工具挂载策略重构 + DeepTutor-main 流程对齐 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| iOS 功能目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| Web/后端参考工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main` |
| 创建日期 | 2026-08-06 |
| 触发问题 | iOS 当前通过 `*Patterns` 关键词表决定本轮开放工具，未完全对齐 DeepTutor-main 的工具组合流程 |
| 关联工单 | `DEEPTUTORCHAT-000007`、`DEEPTUTORCHAT-000020`、`DEEPTUTORCHAT-000021` |
| 核心约束 | 关键词意图识别只能作为可解释信号，不能成为与 Web 不一致的工具挂载事实源 |

## 1. 本工单目标

本工单解决的问题：

```text
决定本轮给模型开放哪些工具，需要完全对齐 DeepTutor-main 流程。
梳理当前没有对齐的部分，并创建重构工单。
```

目标：

```text
1. 梳理 DeepTutor-main 中“本轮工具开放”的真实链路。
2. 对比 iOS 当前 `DeepTutorToolPolicyResolver` 的偏差。
3. 明确哪些逻辑可以保留、哪些必须重构、哪些必须删除或降级为日志信号。
4. 给出 iOS 端可落地的重构方案，不直接实现。
5. 建立验收标准：同一 capability、同一用户工具设置、同一上下文 flags 下，iOS 与 DeepTutor-main 输出同语义工具集合。
```

## 2. 当前 iOS 代码事实

### 2.1 当前入口

iOS 文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorToolPolicyResolver.swift
```

当前调用链：

```text
DeepTutorToolMountContext
  -> DeepTutorToolPolicyResolver.resolve(context)
  -> resolveChatLike / resolveDeepResearch / fixed capability branches
  -> DeepTutorToolPolicyResult
  -> ChatOrchestratorInferenceOptions(useTools, useKnowledgeBag, useWebSearch, allowedToolNames)
  -> ChatOrchestrator.filteredToolDefinitions()
  -> ToolHub.toolDefinitions()
  -> runtimeService.generateTextStream(toolChoice=.auto)
```

### 2.2 当前关键词 intent 策略

当前 intent：

```text
casualChat
knowledgeQA
askUserExplicit
weatherLocation
healthData
healthReport
knowledgeBag
webSearch
```

当前匹配方式：

```swift
private nonisolated static func matchesAny(_ normalizedInput: String, patterns: [String]) -> Bool {
    patterns.contains { normalizedInput.contains($0) }
}
```

当前效果：

| Pattern 数组 | Intent | 当前效果 |
| --- | --- | --- |
| `casualChatPatterns` | `.casualChat` | 只记 reason，不额外开工具 |
| `knowledgeQAPatterns` | `.knowledgeQA` | 只记 reason，不额外开工具 |
| `askUserExplicitPatterns` | `.askUserExplicit` | 只记 reason，`ask_user_question` 在 minimal |
| `weatherLocationPatterns` | `.weatherLocation` | 开放天气/定位工具 |
| `healthDataPatterns` | `.healthData` | 开放步数/睡眠/营养/运动等健康数据工具 |
| `healthReportPatterns` | `.healthReport` | 开放报告/病历相关工具 |
| `knowledgeBagPatterns` | `.knowledgeBag` | 有知识库上下文时开放 `search_knowledge_bag` |
| `webSearchPatterns` | `.webSearch` | 开放联网搜索工具 |

当前 chat-like 默认：

```text
未命中 intent 时只开放 minimalAlwaysOnTools。
minimalAlwaysOnTools = ask_user_question。
policyReason = chat_minimal_default 或 mastery_path_default。
```

### 2.3 当前能力分支

当前 `resolve(_:)`：

```text
deepQuestion:
  ask_user_question + search_online + read_web_page
  有 KB 时加 search_knowledge_bag

mathAnimator / visualize:
  ask_user_question

deepResearch:
  ask_user_question + search_knowledge_bag
  根据 intent 再可能加 webSearchTools

chat / masteryPath:
  走 detectIntents + resolveChatLike
```

### 2.4 当前 fail-closed 过滤

当前过滤：

```text
1. 无知识库上下文 -> 移除 search_knowledge_bag/create_knowledge_document。
2. 无定位权限 -> 移除 get_current_location。
3. 无成员 -> 移除 switch_member。
4. 无健康资料上下文 -> 移除 get_health_resource_context。
```

问题：

```text
该 fail-closed 过滤只覆盖 iOS 自己定义的若干上下文，不等同于 DeepTutor-main 后端的 per-user grant、auto-mounted tools、capability owned tools、exclusive capability、generation tool config gate。
```

## 3. DeepTutor-main 对标事实

### 3.1 Web capability 定义层

Web 文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/app/(workspace)/home/[[...sessionId]]/page.tsx
```

`CAPABILITIES` 定义：

| capability | allowedTools | defaultTools |
| --- | --- | --- |
| `chat` | `brainstorm`、`geogebra_analysis`、`web_search`、`code_execution`、`reason`、`paper_search`、`imagegen`、`videogen` | `[]` |
| `deep_solve` | `web_search`、`code_execution`、`reason` | `web_search`、`code_execution`、`reason` |
| `deep_question` | `web_search`、`code_execution` | `web_search`、`code_execution` |
| `deep_research` | `web_search`、`paper_search`、`code_execution` | `web_search`、`paper_search`、`code_execution` |
| `visualize` | `[]` | `[]` |
| `mastery_path` | `web_search`、`code_execution` | `[]` |

结论：

```text
Web 前端第一层事实源是 capability 的 allow-list/default-list。
不是根据本轮用户文本关键词临时决定开放天气、健康数据、健康报告等工具。
```

### 3.2 Web 用户工具设置层

Web 文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/lib/tools-settings.ts
```

用户设置来源：

```text
GET /api/v1/tools
返回 enabled_optional_tools
```

Web 页面逻辑：

```text
state.enabledTools = userEnabledTools ∩ activeCap.allowedTools
```

Web 文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/app/(workspace)/home/[[...sessionId]]/page.tsx
```

对应逻辑：

```text
const allowed = new Set(activeCap.allowedTools)
const next = userEnabledTools.filter((tool) => allowed.has(tool))
setTools(next)
```

选择 capability 时：

```text
baseline = userEnabledTools === null ? cap.allowedTools : userEnabledTools
enabledToolsForCap = baseline.filter(tool => cap.allowedTools.includes(tool))
setTools(enabledToolsForCap)
```

结论：

```text
Web 的工具开关是“用户全局工具设置”和“当前 capability allow-list”的交集。
```

### 3.3 Web requestSnapshot / start_turn 层

Web 文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/context/UnifiedChatContext.tsx
```

发送时：

```text
effectiveCapability = replaySnapshot?.capability ?? session.activeCapability
effectiveTools = replaySnapshot?.enabledTools ?? session.enabledTools
```

requestSnapshot：

```text
content
capability
enabledTools
knowledgeBases
language
attachments
config
notebookReferences
historyReferences
questionNotebookReferences
bookReferences
persona
memoryReferences
llmSelection
```

发送 `start_turn`：

```text
sendThroughRunner(key, {
  type: "start_turn",
  content,
  tools: effectiveTools,
  capability: effectiveCapability,
  knowledge_bases: effectiveKnowledgeBases,
  session_id: session.sessionId,
  ...
})
```

结论：

```text
Web 每轮发送的是已经冻结的 `tools` 列表。
编辑、重试、恢复时优先使用 requestSnapshot，保证同一轮工具选择可复现。
```

### 3.4 后端 start_turn 过滤层

后端文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/services/session/turn_runtime.py
```

后端流程：

```text
1. capability = payload.capability or "chat"。
2. validate_capability_config(capability, raw_config)。
3. 如果 payload.tools 是 None，才从 /settings/tools 回填 enabled optional tools。
4. 如果 payload.tools 显式传入，包括空数组，则保持调用方传值。
5. allowed_optional_tools() 做用户 grant 白名单过滤。
6. preference_update 持久化 capability/tools/knowledge_bases/language。
7. 构建 UnifiedContext(enabled_tools=payload.tools, active_capability=payload.capability, ...)。
```

结论：

```text
后端是权限和兜底层，不是通过用户自然语言重新识别工具意图。
```

### 3.5 后端 ToolComposition 层

后端文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/agents/_shared/tool_composition.py
```

核心函数：

```text
compose_enabled_tools(
  registry,
  requested_tools,
  optional_whitelist,
  mount_flags,
  capability_owned,
  exclusive,
  builtin_whitelist,
  forced,
  suppressed
)
```

组合顺序：

```text
1. 用户 toggled tools：
   requested_tools ∩ optional_whitelist，并通过 registry.get_enabled 过滤未知工具。

2. 条件自动挂载：
   rag -> has_kb
   kb_files -> has_kb
   read_source -> has_sources
   read_memory -> has_memory
   list_notebook/write_note -> has_notebooks
   read_skill -> has_skills
   load_tools -> has_deferred_tools
   exec/code_execution -> has_exec/has_code

3. active loop capability owned tools：
   例如 solve/mastery 自己拥有的工具。

4. always-on auto-mounts：
   write_memory
   web_fetch
   github
   ask_user
   cron

5. forced/suppressed：
   partner 等场景可强制挂载或压制工具。
```

结论：

```text
DeepTutor-main 的核心策略是“请求工具 + 上下文自动挂载 + 能力自有工具 + always-on + 权限/配置过滤”。
不是“关键词命中 -> 开某类工具”。
```

### 3.6 Chat pipeline 层

后端文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/agents/chat/agentic_pipeline.py
```

流程：

```text
CHAT_OPTIONAL_TOOLS = default_optional_tools()
enabled_tools = self._compose_enabled_tools(context)
use_native_tools = bool(enabled_tools) and self._can_use_native_tool_calling()
tool_schemas = self._build_llm_tool_schemas(enabled_tools, context)
AgentLoop(... enabled_tools=enabled_tools if use_native_tools else [], tool_schemas=tool_schemas)
```

重要判断：

```text
如果没有 resolved tools，则不启用 native tool calling，避免模型在文本里伪造工具调用。
```

结论：

```text
工具是否传给模型由最终 resolved tools 和模型 native tool calling 能力共同决定。
```

### 3.7 Quiz pipeline 层

后端文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/agents/question/pipeline.py
```

对标事实：

```text
QuestionPipeline 复用 shared tool-composition policy。
Phase 1 Explore 使用工具探索。
Phase 2 Plan 不使用工具。
Phase 3 Quiz 每题生成，严格 JSON，解析失败有 one-shot repair。
每题成功后发出 quiz_question_emitted 结构化事件。
```

关键逻辑：

```text
_resolved_tools(context) -> compose_enabled_tools(...)
_use_native_tools(context) -> bool(_resolved_tools) && can_use_native_tool_calling(...)
_build_llm_tool_schemas(context) -> registry.build_openai_schemas(_resolved_tools)
```

结论：

```text
DeepTutor-main 的 deep_question 不只是“给模型开放 web_search/code_execution”。
它有阶段化工具使用：Explore 可用工具，Plan/Quiz 按协议收窄，并产出结构化事件。
```

## 4. 当前 iOS 未对齐点

### 4.1 策略事实源不一致

当前 iOS：

```text
userInput -> detectIntents -> resolveChatLike -> allowedToolNames
```

DeepTutor-main：

```text
capability allow-list/defaultTools
  + user enabled tools
  + requestSnapshot/replay snapshot
  + backend grant filter
  + shared compose_enabled_tools(context flags)
  + model native tool support
  -> final schemas
```

偏差：

```text
iOS 将“用户文本关键词”放在工具开放决策中心。
Web 将“capability 配置 + 用户设置 + 上下文 flags + 后端权限”放在工具开放决策中心。
```

### 4.2 chat 默认策略不一致

iOS 当前：

```text
chat 默认只开放 ask_user_question。
命中“天气/报告/健康数据/搜索”等关键词才增加工具。
```

Web 当前：

```text
chat capability allowedTools 包含多种可选工具。
实际 enabledTools 来自用户设置与 chat allowedTools 交集。
后端还会自动挂载 ask_user、web_fetch、github、cron、memory/notebook/kb 等符合条件的工具。
```

偏差影响：

```text
1. iOS chat 下工具开放结果与 Web 不一致。
2. 同一问题在 Web 可能有工具，在 iOS 可能没有。
3. 同一问题在 iOS 可能因关键词误判开放健康/天气工具，Web 不会这样。
4. 调试日志 `policyReason` 无法和 Web/后端工具组合原因对应。
```

### 4.3 deep_question 策略不一致

iOS 当前：

```text
deepQuestion 固定开放：
ask_user_question
search_online
read_web_page
有 KB 时 search_knowledge_bag
```

DeepTutor-main：

```text
Web deep_question allowedTools/defaultTools = web_search + code_execution。
后端 QuestionPipeline 使用 compose_enabled_tools。
Explore 阶段可用工具由 requested_tools + mount_flags 组合。
Plan/Quiz 阶段有更严格协议，Quiz 输出结构化事件。
```

偏差影响：

```text
1. iOS 没有 code_execution 等价能力，或没有按 Web 名称映射。
2. iOS 用 search_online/read_web_page 替代 Web web_search/web_fetch，命名与语义不同。
3. iOS 没有阶段化收窄，导致模型可能在生成题目时仍看到不该看的工具。
4. 这会间接造成问答卡片结构化输出不稳定。
```

### 4.4 mastery_path 策略不一致

iOS 当前：

```text
masteryPath 走 chat-like 关键词 intent。
```

DeepTutor-main：

```text
mastery_path 是 loop capability。
Web allowedTools = web_search + code_execution。
后端 mastery tools auto-mount server-side when capability is active。
```

偏差影响：

```text
iOS 将 mastery_path 当 chat-like 简化处理，缺少 capability-owned tools 和 server-side auto-mount 的语义。
```

### 4.5 工具命名与语义不一致

当前 iOS 工具名：

```text
ask_user_question
search_online
read_web_page
query_weather
query_location
get_current_location
fetch_step_details
fetch_sleep_details
...
```

DeepTutor-main 工具名：

```text
ask_user
web_search
web_fetch
rag
kb_files
read_source
read_memory
write_memory
list_notebook
write_note
github
cron
code_execution / exec
...
```

偏差：

```text
两端工具名不是同一套协议名。
如果 iOS 要对齐 DeepTutor-main，必须建立 ToolNameAlias / CapabilityToolManifest 映射表。
不能只看“功能相似”就认为已对齐。
```

### 4.6 ask_user 语义不一致

iOS 当前：

```text
ask_user_question 是 minimalAlwaysOnTools。
```

DeepTutor-main：

```text
ask_user 是 always-on auto-mount。
```

偏差：

```text
表面结果类似，但语义不同。
DeepTutor-main 的 ask_user 属于 auto-mounted floor，不是用户可选工具，也不是关键词 intent。
```

### 4.7 权限与配置 gate 不一致

iOS 当前：

```text
modelSupportsToolCalling
hasKnowledgeContext
hasLocationPermission
hasSelectedMember
hasHealthResourceContext
```

DeepTutor-main：

```text
allowed_optional_tools()
allowed_mcp_tools()
allowed_cli_apps()
exec_override()
generation tool service configured gate
registry.get_enabled unknown tool filter
configured model native tool calling gate
```

偏差：

```text
iOS 缺少用户授权 grant、工具注册表、生成工具配置、exec policy、MCP/CLI 权限等统一 gate。
```

### 4.8 requestSnapshot 工具复现不完整

Web：

```text
requestSnapshot.enabledTools 固化本轮工具。
重试/编辑/恢复优先使用 replaySnapshot。
```

iOS 需要确认：

```text
1. 是否每条用户消息持久化本轮 allowedToolNames。
2. 编辑/重试是否复用原工具快照。
3. ask_user/member resume 是否复用原 turn 工具策略，而不是重新跑关键词。
```

如果没有：

```text
同一轮重试可能开放不同工具，导致回答不可复现。
```

## 5. 重构目标架构

### 5.1 新增统一工具组合模型

目标模型：

```text
DeepTutorCapabilityToolManifest
  capability
  allowedTools
  defaultTools
  ownedTools
  exclusive
  needsConfig

DeepTutorUserToolSettings
  enabledOptionalTools
  source
  updatedAt

DeepTutorToolMountFlags
  hasKB
  hasSources
  hasMemory
  hasNotebook
  hasSkills
  hasDeferredTools
  hasExec
  hasCode
  hasLocationPermission
  hasSelectedMember
  hasHealthResourceContext

DeepTutorPerTurnToolSnapshot
  capability
  requestedTools
  resolvedTools
  suppressedTools
  autoMountedTools
  policyReason
  mountFlags
  modelSupportsNativeTools
```

### 5.2 新工具组合顺序

iOS 目标顺序必须对齐 DeepTutor-main：

```text
1. 读取 activeCapability。
2. 获取 capability manifest 的 allowedTools/defaultTools。
3. 获取用户已启用 optional tools。
4. 计算 requestedTools = userEnabledTools ∩ capability.allowedTools。
5. 编辑/重试/恢复时优先使用 requestSnapshot.enabledTools。
6. 根据上下文生成 mountFlags。
7. composeEnabledTools：
   - requestedTools ∩ optionalWhitelist
   - conditional auto-mounts
   - capability owned tools
   - always-on auto-mounts
   - forced/suppressed
   - unknown tool registry filter
8. 应用权限/config gate。
9. 如果模型不支持 native tool calling，最终 useTools=false 且不传 schemas。
10. 将 resolvedTools 写入 requestSnapshot/debug/log。
```

### 5.3 关键词 intent 的目标定位

当前 `*Patterns` 不建议作为工具开放事实源。

保留方式：

```text
1. 只作为 debug explain 信号：
   userIntentHints=weather_location/health_report/web_search

2. 只作为未来“建议打开工具”的 UI 提示：
   例如“这轮可能需要联网搜索，是否开启？”

3. 只允许在用户明确启用“智能工具建议”时影响 requestedTools。
   默认必须关闭，避免和 Web 不一致。
```

禁止：

```text
1. 不能因为命中“查一下”就绕过 capability allowedTools。
2. 不能因为命中“报告”就开放报告工具。
3. 不能因为命中“天气”就开放定位/天气工具，除非该工具在 manifest 和用户设置中都允许。
4. 不能影响 capability 切换。
```

### 5.4 iOS 工具名映射

需要新增或冻结映射表：

| DeepTutor-main 工具 | iOS 当前近似工具 | 对齐状态 |
| --- | --- | --- |
| `ask_user` | `ask_user_question` | 需要 alias |
| `web_search` | `search_online` | 需要确认语义 |
| `web_fetch` | `read_web_page` | 需要 alias |
| `rag` | `search_knowledge_bag` | 需要 alias |
| `code_execution` / `exec` | 当前未确认 | 待确认 |
| `read_memory` | `retrieve_memory` | 需要 alias |
| `write_memory` | `save_memory` / `update_memory` | 需要拆分语义 |
| `list_notebook` / `write_note` | 当前未确认 | 待确认 |
| `github` | 当前未确认 | 待确认 |
| `cron` | 当前未确认 | 待确认 |

要求：

```text
对外日志和 requestSnapshot 优先记录 DeepTutor-main canonical tool name。
iOS 内部调用可通过 alias 转成 SparkToolName。
```

## 6. 文件级改造清单

### 6.1 iOS Application 层

| 文件 | 当前职责 | 目标改造 |
| --- | --- | --- |
| `DeepTutorToolPolicyResolver.swift` | 关键词 intent + capability 固定策略 | 重构为 `composeEnabledTools` 同源策略；关键词 intent 降级为 explain hints |
| `DeepTutorChatViewModel.swift` | 发送前组包、创建 inference options | 接入 per-turn tool snapshot；编辑/重试/恢复复用 requestSnapshot |
| `DeepTutorPromptBuilder.swift` | 根据 capability 组 prompt | 不再用 prompt 弥补工具策略；prompt 只能描述已挂载工具 |
| `DeepTutorChatLog.swift` | 记录 policy/tool schema 日志 | 增加 requested/resolved/autoMounted/suppressed/alias/gate 日志 |
| `DeepTutorMessageReducer.swift` | 消息 block 归约 | debug snapshot 显示本轮 tool snapshot |

### 6.2 iOS Domain 层

| 目标模型 | 说明 |
| --- | --- |
| `DeepTutorCapabilityToolManifest` | 对齐 Web `CAPABILITIES` 和后端 capability manifest |
| `DeepTutorToolAliasMap` | DeepTutor-main canonical name 到 SparkToolName 的映射 |
| `DeepTutorToolCompositionPolicy` | 对齐后端 `compose_enabled_tools` 的纯函数 |
| `DeepTutorPerTurnToolSnapshot` | 存入 requestSnapshot，保证重试/恢复复现 |
| `DeepTutorToolGateResult` | 记录权限、模型能力、配置缺失导致的 suppress |

### 6.3 Infrastructure 层

| 模块 | 目标 |
| --- | --- |
| 用户工具设置加载 | 对齐 `/api/v1/tools` 或项目已有工具设置来源 |
| 工具注册表 | 对齐 `ToolRegistry.get_enabled`，未知工具 fail-closed |
| 模型 native tool calling gate | 对齐 `can_use_native_tool_calling` |
| 生成工具配置 gate | imagegen/videogen 等未配置时不暴露 |
| 权限 gate | 接入项目已有用户/会员/能力权限系统 |

## 7. 日志与调试要求

### 7.1 新增日志

```text
deeptutor.tool_policy.input
字段：conversation、message、capability、selectedTools、snapshotTools、userSettingsVersion

deeptutor.tool_policy.manifest
字段：capability、allowedTools、defaultTools、ownedTools、exclusive

deeptutor.tool_policy.compose
字段：requestedTools、autoMountedTools、capabilityOwnedTools、alwaysOnTools、forcedTools、suppressedTools

deeptutor.tool_policy.alias
字段：canonicalName、sparkToolName、status

deeptutor.tool_policy.gate
字段：toolName、gate、allowed、reason

deeptutor.tool_policy.resolved
字段：resolvedTools、useTools、modelSupportsNativeTools、policyReason

deeptutor.tool_schema.outbound
字段：schemaNames、toolChoice、reason、droppedUnknownTools
```

### 7.2 Debug snapshot 字段

必须补充：

```text
activeCapability
requestSnapshot.enabledTools
toolPolicy.requestedTools
toolPolicy.resolvedTools
toolPolicy.autoMountedTools
toolPolicy.suppressedTools
toolPolicy.aliasFailures
toolPolicy.modelSupportsNativeTools
toolPolicy.mountFlags
toolPolicy.policyReason
```

### 7.3 日志原则

```text
1. 工具名、用户输入、模型名不需要脱敏。
2. 不打印 API Key、Bearer Token、内部凭证。
3. 每轮工具决策只打印一次完整 resolved 日志。
4. schema outbound 只打印工具名，不打印完整 schema body，避免日志过长。
```

## 8. 分阶段实施方案

### P0.1 冻结 DeepTutor-main canonical 工具名

任务：

```text
1. 列出 Web `CAPABILITIES` 中所有 allowedTools/defaultTools。
2. 列出后端 `ToolRegistry` 的 built-in tool names。
3. 建立 iOS `SparkToolName` 与 canonical tool name 映射。
4. 未映射工具必须显式进入 aliasFailures，不能静默丢失。
```

验收：

```text
debug 输出 canonical -> iOS alias 表。
```

### P0.2 建立 capability manifest

任务：

```text
1. 在 iOS 建立与 Web `CAPABILITIES` 同语义 manifest。
2. chat/deepQuestion/deepResearch/masteryPath 的 allowed/default 先完全按 Web 填。
3. iOS 不支持的工具先标为 unsupported，不允许用相似工具私自替代。
```

验收：

```text
选择不同 capability 时，requestedTools 与 Web 交集逻辑一致。
```

### P0.3 重构 composeEnabledTools

任务：

```text
1. 把关键词 intent 从工具集合计算中移出。
2. 实现 requestedTools + mountFlags + ownedTools + alwaysOn + gate 的组合顺序。
3. 输出 autoMountedTools/suppressedTools。
4. 保证模型不支持 native tool calling 时不传 schema。
```

验收：

```text
同一 manifest/settings/flags 下，iOS 组合结果与 DeepTutor-main `compose_enabled_tools` 语义一致。
```

### P0.4 requestSnapshot 复现

任务：

```text
1. 用户发送消息时保存 requestedTools/resolvedTools。
2. 编辑、重试、ask_user resume、member selection resume 优先复用 snapshot。
3. 只有用户明确切换 capability 或工具设置时，才重新计算。
```

验收：

```text
同一消息 regenerate 后工具集合不漂移。
```

### P0.5 deep_question 阶段化工具策略

任务：

```text
1. 不再把 deepQuestion 简化为固定 search/readWeb/askUser。
2. 对齐 Web QuestionPipeline：
   - Explore 阶段允许 resolved tools。
   - Plan 阶段不传工具。
   - Quiz 生成阶段按协议收窄。
3. iOS 如果当前没有阶段化 pipeline，应在工单/实现中明确为待实现，不用 prompt 假装对齐。
```

验收：

```text
Quiz 生成时不再把全部工具暴露给模型。
问答卡片结构化输出稳定性提升。
```

## 9. 验收标准

### 9.1 Chat 普通问候

Given：

```text
capability=chat
用户输入：你好 哈哈哈
用户设置没有开启可选工具
```

Then：

```text
1. iOS 不因为 casualChat 开放额外工具。
2. 最终工具集合只包含 DeepTutor-main always-on/可用 floor 的等价工具。
3. policyReason 不写成误导性的关键词主决策，只能记录 intentHint=casual_chat。
```

### 9.2 Chat 联网搜索

Given：

```text
capability=chat
用户输入：查一下最新研究
用户设置未启用 web_search
```

Then：

```text
1. iOS 不应仅因“查一下/最新”强行开放 web_search。
2. 可以记录 intentHint=web_search。
3. 如产品需要，应提示用户开启工具，而不是绕过设置。
```

### 9.3 Chat 用户启用 web_search

Given：

```text
capability=chat
userEnabledTools 包含 web_search
chat.allowedTools 包含 web_search
模型支持 native tool calling
```

Then：

```text
1. requestedTools 包含 web_search。
2. resolvedTools 包含 iOS alias 后的联网搜索工具。
3. tool_schema.outbound 包含对应 schema。
```

### 9.4 Quiz 能力

Given：

```text
capability=deep_question
defaultTools=web_search,code_execution
```

Then：

```text
1. iOS 以 Web manifest 为基线，不再固定写死 search_online/read_web_page。
2. 不支持 code_execution 时必须在 suppressedTools 写 reason=unsupported。
3. 不通过 health quiz 关键词额外加工具。
4. Quiz 阶段化策略必须在日志中可见。
```

### 9.5 恢复/重试

Given：

```text
已有消息 requestSnapshot.enabledTools=A
用户后来改了工具设置为 B
点击 regenerate
```

Then：

```text
本轮重试仍使用 A，除非用户明确选择“使用当前工具设置重新生成”。
```

## 10. 风险与待确认项

| 风险 | 影响 | 处理 |
| --- | --- | --- |
| iOS 工具名与 DeepTutor-main 工具名不一致 | 日志和策略无法对齐 | 建立 canonical alias 表 |
| iOS 缺少后端 `/api/v1/tools` 等价设置来源 | 无法复现 Web 用户设置交集 | 接入项目已有工具设置或新增本地等价配置 |
| iOS 没有 ToolRegistry | 未知工具可能误传 | 建立本地 registry/filter |
| 关键词继续直接开工具 | 与 Web 行为漂移 | 降级为 intentHint 或用户确认提示 |
| deepQuestion 无阶段化 pipeline | 工具暴露过宽，结构化题目不稳定 | 单独实施 QuestionPipeline 对齐 |
| 不保存 per-turn snapshot | 重试/恢复工具漂移 | requestSnapshot 必须持久化工具快照 |
| 模型不支持 native tool calling 仍传 prompt 工具说明 | 模型可能伪造文本工具调用 | 对齐 Web `bool(enabled_tools) && can_use_native_tool_calling` |

待确认：

```text
1. SparkClient 项目中已有工具设置中心在哪里，是否可表达 Web enabled_optional_tools。
2. iOS 当前 `SparkToolName.all` 中哪些能映射 DeepTutor-main canonical tool。
3. code_execution/exec 在 iOS 当前大模型链路中是否可用。
4. memory/notebook/kb/source/deferred tools 是否已有上下文 flags。
5. ask_user_question 是否应统一 alias 为 ask_user。
6. 工具权限是否需要对接当前账号/会员/AIConfigCenter 的能力授权。
```

## 11. 结论

当前 iOS `*Patterns` 的作用可以概括为：

```text
在 .chat/.masteryPath 下，通过用户输入关键词粗略判断意图，然后决定本轮开放哪些工具。
```

但 DeepTutor-main 的真实流程是：

```text
capability manifest
  -> user enabled tools
  -> capability allow-list intersection
  -> requestSnapshot 固化
  -> start_turn.tools
  -> backend grant filter
  -> shared compose_enabled_tools(context flags)
  -> model native tool calling gate
  -> final tool schemas
```

因此本工单要求：

```text
1. iOS 工具开放策略从关键词驱动重构为 manifest/settings/snapshot/context/gate 驱动。
2. 关键词 intent 只保留为日志或用户确认建议，不直接决定工具挂载。
3. 工具名必须以 DeepTutor-main canonical name 为跨端事实源，iOS 内部通过 alias 映射到 SparkToolName。
4. deep_question、mastery_path 等能力必须补齐 capability-owned tools 和阶段化工具策略，不再按 chat-like 简化。
5. 每轮工具决策必须可日志追踪、可 snapshot 复现、可与 Web/后端行为对比验收。
```
