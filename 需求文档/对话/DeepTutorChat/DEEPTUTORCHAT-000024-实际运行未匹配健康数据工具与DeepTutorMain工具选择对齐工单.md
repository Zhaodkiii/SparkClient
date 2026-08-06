# DEEPTUTORCHAT-000024 实际运行未匹配健康数据工具与 DeepTutor-main 工具选择对齐工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000024 |
| 工单类型 | P0 工具匹配失败修复 + 健康数据工具扩展层对齐 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| iOS 功能目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| Web/后端参考工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main` |
| 创建日期 | 2026-08-06 |
| 触发问题 | 实际运行中用户询问睡眠数据，系统没有找出并开放合适的健康数据工具 |
| 关联工单 | `DEEPTUTORCHAT-000007`、`DEEPTUTORCHAT-000022`、`DEEPTUTORCHAT-000023` |
| 核心约束 | 对齐 DeepTutor-main 的工具组合框架，同时为 SparkClient 健康数据工具建立明确扩展层；不能让模型看到错误提示词但拿不到对应工具 |

## 1. 本工单目标

用户反馈：

```text
实际运行中并没有找出合适的工具。
分析 DeepTutor-main 是如何对齐的。
如何更好地匹配工具。
创建新的工单，给出优化对齐方案。
```

本工单目标：

```text
1. 基于真实日志确认“睡眠数据工具没有匹配”的具体原因。
2. 说明 DeepTutor-main 的工具选择不是关键词直接选工具，而是“工具面组合 + schema 暴露 + agent loop 让模型自主调用”。
3. 将 SparkClient 健康数据工具定义为 iOS 项目扩展层，而不是伪装成 DeepTutor-main canonical 工具。
4. 设计 health intent -> member gate -> health tool surface -> resume 的稳定链路。
5. 建立可验收标准：用户问“最近睡眠怎么样”时，必须先触发成员选择或已有成员绑定，然后调用 `fetch_sleep_details`，而不是回答无法访问数据。
```

## 2. 本次实际运行证据

### 2.1 用户输入与 capability

日志：

```text
deeptutor.capability.effective conversation=363F61C5 selected=chat effective=chat
发送 DeepTutor 对话开始，conversation=363F61C5, capability=chat, userContent=我最近的睡眠怎么样 今天是20260806
deeptutor.capability.snapshot conversation=363F61C5 requestSnapshot=chat message=chat
```

结论：

```text
本轮是普通 chat capability。
用户输入明确包含“睡眠”，属于 SparkClient 个人健康数据查询场景。
```

### 2.2 工具策略日志

日志：

```text
deeptutor.tool_policy.input conversation=363F61C5 message=E16953C6 capability=chat
selectedTools=brainstorm,geogebra_analysis,web_search,code_execution,reason,paper_search,imagegen,videogen
snapshotTools=brainstorm,geogebra_analysis,web_search,code_execution,reason,paper_search,imagegen,videogen
```

组合日志：

```text
deeptutor.tool_policy.compose conversation=363F61C5
requestedTools=brainstorm,geogebra_analysis,web_search,code_execution,reason,paper_search,imagegen,videogen
autoMountedTools=write_memory,web_fetch,github,ask_user,cron
resolvedTools=brainstorm,geogebra_analysis,web_search,code_execution,reason,paper_search,imagegen,videogen,write_memory,web_fetch,github,ask_user,cron
aliasFailures=brainstorm:optional_tool_not_implemented,...,cron:tool_not_implemented
intentHints=health_data
```

最终 resolved：

```text
policyReason=compose+requested=8+phase=answer_loop;intentHints=health_data
allowedToolCount=6
allowedTools=ask_user_question,read_web_page,save_memory,search_arxiv_papers,search_online,update_memory
suppressedTools=create_canvas,create_knowledge_document,edit_canvas,extract_remote_file_content,fetch_energy_details,fetch_nutrition_details,fetch_sleep_details,fetch_step_details
mountFlags=... spark_health_data_eligible:false
```

结论：

```text
1. iOS 已识别到 intentHints=health_data。
2. 但 `health_data` 只进入日志，不参与工具挂载。
3. `spark_health_data_eligible=false`，所以 Spark 健康数据扩展工具没有加入 allowedTools。
4. `fetch_sleep_details` 被放进 suppressedTools。
5. `request_member_selection` 没有出现在 allowedTools。
```

### 2.3 模型实际看到的工具

出站 schema：

```text
schemaNames=ask_user_question,read_web_page,save_memory,search_arxiv_papers,search_online,update_memory
```

模型没有看到：

```text
request_member_selection
get_current_member
find_member
query_member_profile
fetch_sleep_details
fetch_step_details
fetch_energy_details
fetch_nutrition_details
fetch_workout_details
```

结论：

```text
模型不可能调用睡眠工具，因为 schema 没有给它。
```

### 2.4 模型推理结果

assistant reasoning：

```text
用户问睡眠情况，我将检索健康数据，先请求成员选择。
经核实，当前可用工具中无成员选择及健康数据检索相关工具，
无法直接获取用户的睡眠数据，我将告知用户该情况，并可提供一般性睡眠建议或请用户提供相关信息。
```

最终回答：

```text
我目前无法直接访问你的个人睡眠监测数据...
```

结论：

```text
模型的判断是正确的：它想走成员选择和睡眠数据工具，但工具面没有提供。
问题在 iOS 工具匹配/挂载链路，不在模型选择能力。
```

## 3. DeepTutor-main 如何匹配工具

### 3.1 DeepTutor-main 不靠关键词直接选工具

DeepTutor-main 的核心链路：

```text
Web capability allowedTools/defaultTools
  -> 用户 enabled optional tools
  -> requestSnapshot.enabledTools
  -> start_turn.tools
  -> turn_runtime 权限过滤
  -> UnifiedContext.enabled_tools
  -> compose_enabled_tools(context flags)
  -> ToolRegistry.build_openai_schemas()
  -> AgentLoop native tool calling
  -> 模型根据 tool schema 和系统提示自主调用
```

关键点：

```text
DeepTutor-main 更好地“匹配工具”的方式不是写大量关键词 if/else。
它先把当前 capability 合法工具面稳定暴露给模型，再由 agent loop 和模型 tool_choice 自动选择具体工具。
```

### 3.2 Web 前端工具面

Web 文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/app/(workspace)/home/[[...sessionId]]/page.tsx
```

`chat` capability：

```text
allowedTools=[
  brainstorm,
  geogebra_analysis,
  web_search,
  code_execution,
  reason,
  paper_search,
  imagegen,
  videogen
]
defaultTools=[]
```

Web 选择逻辑：

```text
state.enabledTools = userEnabledTools ∩ activeCap.allowedTools
```

发送时：

```text
tools: effectiveTools
capability: effectiveCapability
```

结论：

```text
Web 负责把“用户启用且当前 capability 允许”的工具列表发给后端。
```

### 3.3 后端工具组合

后端文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/agents/_shared/tool_composition.py
```

`compose_enabled_tools` 顺序：

```text
1. requested_tools ∩ optional_whitelist。
2. context flags 触发条件自动挂载：rag/read_source/read_memory/list_notebook/write_note/read_skill/load_tools/exec/code_execution。
3. capability_owned tools。
4. always-on：write_memory/web_fetch/github/ask_user/cron。
5. forced/suppressed。
6. ordered unique。
```

结论：

```text
DeepTutor-main 通过 context flags 和 tool registry 组合工具面，然后让模型在工具面内自主调用。
```

### 3.4 后端 tool schema 与 native tool calling

后端文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/agents/chat/agentic_pipeline.py
```

关键逻辑：

```text
enabled_tools = self._compose_enabled_tools(context)
use_native_tools = bool(enabled_tools) and self._can_use_native_tool_calling()
tool_schemas = self._build_llm_tool_schemas(enabled_tools, context)
AgentLoop(... enabled_tools=enabled_tools if use_native_tools else [], tool_schemas=tool_schemas)
```

结论：

```text
没有工具时不启用 native tool calling。
有工具时传入 schema，模型基于 schema 名称、描述、参数和系统提示决定是否调用。
```

### 3.5 DeepTutor-main 与 Spark 健康数据的边界

需要明确：

```text
DeepTutor-main 没有 SparkClient 的 Apple Health / HealthKit 睡眠、步数、营养等工具。
这些是 SparkClient 的项目扩展能力。
```

因此 iOS 对齐 DeepTutor-main 时要分层：

```text
1. DeepTutor-main canonical tool composition：负责通用工具面。
2. Spark domain extension tools：负责健康数据、成员选择、报告资料等项目工具。
3. 两者必须在同一个 per-turn tool policy 结果中合并，并以日志说明 source。
```

## 4. 当前 iOS 未对齐与缺陷

### 4.1 intentHints 没有转成 domain extension tools

当前代码事实：

```text
DeepTutorToolIntentHints.detect(...) 返回 health_data。
DeepTutorToolPolicyResolver.resolve(...) 仅把 intentHints 拼进 policyReason。
sparkExtensionTools(for:) 只看 context.sparkHealthDataEligible，不看 intentHints。
```

缺陷：

```text
health_data 被识别出来，但没有任何机制把它转换为：
request_member_selection + fetch_sleep_details + get_current_member + find_member 等工具面。
```

### 4.2 sparkHealthDataEligible 默认 false 且来源不清

当前默认：

```text
sparkHealthDataEligible=false
```

实际日志：

```text
mountFlags=spark_health_data_eligible:false
```

缺陷：

```text
1. 即使命中“睡眠”，仍不会挂载健康数据工具。
2. 没有日志说明为什么 eligible=false。
3. 用户、设备、HealthKit 授权、成员绑定、功能开关、工具注册是否可用无法区分。
```

### 4.3 Prompt 要求调用不存在的工具

当前出站 system prompt：

```text
When querying personal or family health data without memberID in context:
1. Call `request_member_selection` first.
```

但出站 schema：

```text
schemaNames=ask_user_question,read_web_page,save_memory,search_arxiv_papers,search_online,update_memory
```

缺陷：

```text
Prompt 指示模型调用 request_member_selection，但 schema 没有该工具。
这会让模型只能在 reasoning 里承认“没有相关工具”，最终给出降级回答。
```

### 4.4 member gate 与健康工具 surface 没有绑定

健康数据查询应该有两阶段：

```text
1. 未绑定成员：
   暴露 request_member_selection/get_current_member/find_member。
   先让用户选择成员。

2. 已绑定成员：
   暴露 fetch_sleep_details/fetch_step_details/fetch_energy_details/fetch_nutrition_details/fetch_workout_details/query_member_profile。
```

当前实际：

```text
未绑定成员时没有暴露 request_member_selection。
因此无法进入第二阶段。
```

### 4.5 allowedTools 与 suppressedTools 可解释性不足

当前 suppressedTools 中有：

```text
fetch_sleep_details
fetch_step_details
fetch_energy_details
fetch_nutrition_details
```

但日志没有给出每个工具被 suppress 的原因：

```text
是因为 spark_health_data_eligible=false？
是因为没有成员？
是因为用户未授权？
是因为 alias 不存在？
是因为 capability allow-list 不包含？
```

缺陷：

```text
排查时只能看到结果，看不到 gate 决策原因。
```

## 5. 优化对齐方案

### 5.1 增加 Spark Domain Tool Extension 层

在 DeepTutor-main canonical composition 之后、alias 映射之前或之后，明确增加一层：

```text
DeepTutorDomainToolExtensionResolver
```

职责：

```text
1. 接收 capability、intentHints、mountFlags、用户权限、设备能力、成员绑定状态。
2. 输出 domain extension tools。
3. 标记 source=health_data / health_report / weather_location。
4. 对每个工具输出 gate reason。
5. 不修改 capability。
```

目标输出模型：

```text
DomainToolExtensionResult
  canonicalOrSparkTools
  source
  gateResults
  requiresUserInteraction
  nextPhase
```

### 5.2 健康数据工具匹配规则

当满足：

```text
capability=chat 或 masteryPath
intentHints 包含 health_data
用户已授权健康数据能力或 HealthKit 可用
```

应挂载：

未绑定成员：

```text
request_member_selection
get_current_member
find_member
```

已绑定成员：

```text
get_current_member
query_member_profile
fetch_sleep_details
fetch_step_details
fetch_energy_details
fetch_nutrition_details
fetch_workout_details
make_nutrition_data
```

如果用户输入命中具体子类型：

| 输入意图 | 最小工具面 |
| --- | --- |
| 睡眠 | `request_member_selection` 或 `fetch_sleep_details` |
| 步数/走路 | `request_member_selection` 或 `fetch_step_details` |
| 能量/卡路里 | `request_member_selection` 或 `fetch_energy_details` |
| 饮食/营养 | `request_member_selection` 或 `fetch_nutrition_details`、`make_nutrition_data` |
| 运动/锻炼 | `request_member_selection` 或 `fetch_workout_details` |

原则：

```text
1. 未绑定成员时，优先只开放成员选择相关工具，不直接开放所有健康数据工具。
2. 已绑定成员后，再开放对应健康数据工具。
3. 如果设备或授权不可用，应生成明确可见的工具不可用状态，不让模型猜。
```

### 5.3 Prompt 与 schema 一致性检查

新增硬性检查：

```text
如果 system prompt 提到 `request_member_selection`，则 schemaNames 必须包含 request_member_selection。
如果 schemaNames 不包含 request_member_selection，则 prompt 不能要求模型调用它。
```

同理：

```text
如果 prompt 提到健康数据检索，则 schemaNames 必须包含至少一个健康数据工具或成员选择工具。
```

失败处理：

```text
1. 发送前阻断并记录 deeptutor.tool_policy.prompt_schema_mismatch。
2. 或动态删除相关 prompt 段，改成“当前未接入健康数据工具”的明确系统上下文。
```

### 5.4 工具选择从“匹配关键词”升级为“意图槽位”

当前：

```text
normalizedInput.contains(pattern)
```

目标：

```text
DeepTutorToolIntentClassifier
  domain: health_data
  subdomain: sleep
  timeRange: recent / today / explicit_date
  dateAnchor: 2026-08-06
  memberRequirement: required
  confidence: high
```

本次输入应解析为：

```text
domain=health_data
subdomain=sleep
timeRange=recent
dateAnchor=2026-08-06
memberRequirement=required
confidence=high
```

然后工具面：

```text
if no member:
  request_member_selection
else:
  fetch_sleep_details
```

### 5.5 与 DeepTutor-main 的一致边界

对齐点：

```text
1. 仍然遵循 capability manifest + requestedTools + autoMountedTools + model native tool calling。
2. 仍然让模型基于 schema 自主选择工具，而不是客户端直接替模型执行。
3. Domain extension tools 是 SparkClient 项目扩展层，进入同一个 tool policy result。
4. 每个扩展工具必须有 gate reason 和 snapshot。
```

不对齐也不应强行伪装的点：

```text
DeepTutor-main 没有 Spark 健康数据工具。
iOS 不能把 `fetch_sleep_details` 伪装成 Web `web_search` 或 `rag`。
应明确记录为 `source=spark_health_extension`。
```

## 6. 文件级改造清单

### 6.1 需要新增或重构的 iOS 文件

| 文件/模块 | 目标 |
| --- | --- |
| `DeepTutorToolIntentHints.swift` | 从字符串 hint 升级为结构化 intent slot，至少支持 health sleep/steps/nutrition/workout/weather/report |
| `DeepTutorDomainToolExtensionResolver.swift` | 新增，负责 Spark 健康/成员/报告/天气扩展工具面 |
| `DeepTutorToolPolicyResolver.swift` | 合并 canonical composition + domain extension tools；输出 gate reasons |
| `DeepTutorPromptBuilder.swift` | 根据实际 schema 动态包含/删除工具使用规则，避免 prompt/schema 不一致 |
| `DeepTutorRuntimeRequestBuilder.swift` | 保存 domain extension snapshot，保证重试/恢复复现 |
| `DeepTutorChatDebugExporter.swift` | 输出 health intent、health eligible reason、domain extension tools |
| `DeepTutorChatLogging.swift` | 增加工具匹配、gate、prompt/schema 一致性日志 |

### 6.2 已存在可复用能力

| 现有能力 | 代码位置 | 用途 |
| --- | --- | --- |
| 成员选择工具 | `Projects/Core/AIRuntime/ToolHub/Executors/ToolHubRequestMemberSelection.swift` | 未绑定成员时弹出成员选择 |
| 睡眠工具 | `Projects/Core/AIRuntime/ToolHub/Executors/ToolHubFetchSleepDetails.swift` | 查询 HealthKit 睡眠详情并发布睡眠可视化卡片 |
| 成员选择卡片/恢复 | `DeepTutorMemberSelectionResumeBuilder.swift`、`DeepTutorMessageReducer.swift` | 成员选择后继续同一 turn |
| ToolHub schema | `Projects/Core/AIRuntime/ToolHub/ToolHub+Schema.swift` | 工具参数 schema |
| SparkToolName | `Projects/Core/AIRuntime/ToolHub/Models/ToolingModels.swift` | 工具枚举 |

结论：

```text
底层工具存在，当前失败主要是 DeepTutorChat 工具策略没有把这些工具开放给模型。
```

## 7. 日志补充要求

### 7.1 新增日志

```text
deeptutor.tool_intent.detected
字段：conversation、message、domain、subdomain、timeRange、dateAnchor、confidence、rawInputLength

deeptutor.domain_tool_extension.resolve
字段：conversation、message、source、inputIntent、hasMember、healthEligible、candidateTools

deeptutor.domain_tool_extension.gate
字段：toolName、allowed、reason、requiredFlag、actualFlag

deeptutor.health_data.eligibility
字段：conversation、message、healthKitAvailable、authorizationState、hasSelectedMember、memberID、reason

deeptutor.tool_policy.prompt_schema_mismatch
字段：conversation、message、promptMentionsTool、schemaContainsTool、action

deeptutor.tool_policy.health_surface
字段：conversation、message、phase、healthTools、memberTools、suppressedHealthTools、reason
```

### 7.2 Debug snapshot 字段

必须增加：

```text
latestStructuredIntent=health_data/sleep/recent/2026-08-06
latestDomainExtensionTools=request_member_selection 或 fetch_sleep_details
latestHealthDataEligible=true/false
latestHealthDataIneligibleReason
latestPromptSchemaMismatch
latestSuppressedHealthToolsWithReasons
```

## 8. 分阶段实施

### P0.1 修复健康数据工具面缺失

任务：

```text
1. 当 intent=health_data 且 subdomain=sleep 时，未绑定成员必须开放 request_member_selection。
2. 已绑定成员必须开放 fetch_sleep_details。
3. `sparkHealthDataEligible=false` 时必须输出具体原因。
```

验收：

```text
用户输入“我最近的睡眠怎么样 今天是20260806”后，schemaNames 至少包含 request_member_selection 或 fetch_sleep_details。
```

### P0.2 修复 prompt/schema 不一致

任务：

```text
1. 出站前扫描 prompt 提到的工具名。
2. 与 schemaNames 做一致性校验。
3. 不一致时记录日志并修正 prompt 或工具面。
```

验收：

```text
不再出现 prompt 要求调用 request_member_selection，但 schema 没有 request_member_selection 的情况。
```

### P0.3 建立结构化 intent classifier

任务：

```text
1. 将 `health_data` 从字符串 hint 升级为结构化 intent。
2. 支持 sleep/steps/energy/nutrition/workout 子类型。
3. 支持日期解析：今天是 20260806 -> dateAnchor=2026-08-06。
4. 支持 recent/today/week/month 等时间范围。
```

验收：

```text
debug snapshot 显示 domain=health_data subdomain=sleep timeRange=recent dateAnchor=2026-08-06。
```

### P0.4 成员选择后恢复工具面

任务：

```text
1. request_member_selection 提交后，同一 turn resume。
2. resume 时移除 request_member_selection。
3. 注入 selectedMemberID。
4. 开放 fetch_sleep_details。
5. 继续生成真实数据回答。
```

验收：

```text
选择成员后，AI 继续调用 fetch_sleep_details，而不是重复提问或结束。
```

### P1.1 对齐 DeepTutor-main 的 agent loop 选择方式

任务：

```text
1. 不由客户端直接执行 sleep 工具。
2. 客户端只负责提供正确 schema 和上下文。
3. 模型通过 tool_choice=auto 选择 request_member_selection/fetch_sleep_details。
4. 工具结果进入 trace 和消息卡片。
```

验收：

```text
trace 中出现工具调用步骤，最终回答引用工具结果。
```

## 9. 验收标准

### 9.1 未绑定成员的睡眠查询

Given：

```text
capability=chat
用户输入：我最近的睡眠怎么样 今天是20260806
conversation 没有绑定成员
健康数据能力可用
```

Then：

```text
1. intent 解析为 health_data/sleep。
2. schemaNames 包含 request_member_selection。
3. assistant 触发成员选择卡片或 sheet。
4. 不直接回答“无法访问你的睡眠数据”。
```

### 9.2 已绑定成员的睡眠查询

Given：

```text
capability=chat
用户输入：我最近的睡眠怎么样 今天是20260806
conversation 已绑定 memberID
HealthKit 睡眠授权可用
```

Then：

```text
1. schemaNames 包含 fetch_sleep_details。
2. 模型调用 fetch_sleep_details。
3. trace 展示工具调用。
4. 消息内展示睡眠数据分析和睡眠可视化卡片。
```

### 9.3 健康能力不可用

Given：

```text
HealthKit 不可用或未授权
```

Then：

```text
1. 不挂载 fetch_sleep_details。
2. 日志输出 healthDataIneligibleReason。
3. Prompt 不要求模型调用健康工具。
4. UI 给出明确授权/设备不可用说明。
```

### 9.4 与 DeepTutor-main 工具策略一致

Then：

```text
1. 通用工具仍按 capability manifest + user settings + compose policy 组合。
2. 健康工具作为 Spark domain extension 合并进同一 policy result。
3. 每个扩展工具都有 source 和 gate reason。
4. requestSnapshot 保存本轮工具快照。
5. regenerate/resume 不发生工具集合漂移。
```

## 10. 风险与待确认项

| 风险 | 影响 | 处理 |
| --- | --- | --- |
| `sparkHealthDataEligible` 来源不清 | 健康工具持续被 suppress | 必须拆分为 HealthKit 可用、授权、成员、账号权限、工具注册等原因 |
| Prompt/schema 不一致 | 模型无法调用被提示的工具 | 出站前一致性校验 |
| 未绑定成员直接开放健康工具 | 工具缺 memberID 执行失败 | 成员选择作为前置 gate |
| 已绑定成员仍只开放成员选择 | 重复提问 | resume 后切换到 fetch 工具面 |
| 健康工具不属于 DeepTutor-main canonical | 跨端对齐混乱 | 标记为 Spark domain extension，不伪装 |
| 只靠关键词 contains | 误判或漏判 | 升级为结构化 intent slot |

待确认：

```text
1. `sparkHealthDataEligible` 当前在哪里被设置，为什么本次为 false。
2. DeepTutorChat 是否能读取当前会话绑定成员。
3. 当前账号是否已授权 HealthKit 睡眠读取。
4. `fetch_sleep_details` 是否需要 date range 参数，是否支持“最近”默认范围。
5. 成员选择 sheet 在 DeepTutorChat 内是否已完整接入。
6. 健康数据工具执行结果是否已经能生成消息内卡片。
```

## 11. 结论

本次实际运行没有找出合适工具的直接原因：

```text
用户输入命中了 health_data intent，
但 intent 只进入日志，
没有转换为 Spark 健康数据扩展工具面；
同时 spark_health_data_eligible=false，
导致 request_member_selection 和 fetch_sleep_details 都没有出现在 schemaNames。
模型只能看到通用工具，所以无法获取睡眠数据。
```

DeepTutor-main 的可借鉴方案：

```text
1. 不靠关键词直接执行工具。
2. 先组合正确工具面。
3. 通过 tool schema 暴露给模型。
4. agent loop 让模型根据问题自主调用。
5. 所有工具选择可通过 context flags、tool registry、snapshot 和日志复现。
```

iOS 需要补齐的关键层：

```text
DeepTutorDomainToolExtensionResolver
  -> health intent 结构化
  -> member gate
  -> health tool surface
  -> prompt/schema 一致性
  -> per-turn snapshot
  -> resume 后继续调用真实健康工具
```
