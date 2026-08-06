# DEEPTUTORCHAT-000030 设置内开启 AI 搜索供应商配置并接入 DeepTutorChat 联网搜索工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000030 |
| 工单类型 | P1 设置入口恢复 + 搜索供应商配置 + DeepTutorChat 联网搜索链路接入 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| iOS 功能目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| AI 设置目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/AISettings` |
| 搜索运行时目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/Search` |
| Web/后端参考工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main` |
| 创建日期 | 2026-08-06 |
| 触发问题 | 设置内联网搜索供应商配置入口未开放，DeepTutorChat 虽有 `web_search` 工具面但缺少用户可配置、可验证、可追踪的搜索供应商启用流程 |
| 关联工单 | `DEEPTUTORCHAT-000022`、`DEEPTUTORCHAT-000024`、`DEEPTUTORCHAT-000028`、`DEEPTUTORCHAT-000029` |
| 核心约束 | 对齐 DeepTutor-main 的“设置选择搜索 provider -> 工具调用读取当前配置”流程；不能只打开 UI，也不能把 API Key 写死在 DeepTutorChat 内 |

## 1. 本工单目标

用户要求：

```text
设置内开启 ai 搜索的供应商配置。
参考 DeepTutor-main 内搜索流程接入。
目标目录为 SparkClient/Projects/Features/DeepTutorChat。
```

本工单目标：

```text
1. 在 AI 设置中恢复“联网搜索/AI 搜索工具”入口，让用户可以配置搜索供应商。
2. 支持新增、编辑、启用、禁用搜索供应商，并校验 API Key、endpoint、搜索结果数量等核心字段。
3. 让 DeepTutorChat 的 `web_search` / `search_online` 工具调用读取同一份 AISettings 搜索配置。
4. 对齐 DeepTutor-main：搜索工具只关心当前 active provider，不在聊天模块硬编码 provider。
5. 增加日志和验收用例，确保用户启用 Tavily/Brave/Exa/Perplexity 等供应商后，DeepTutorChat 能实际走该供应商返回结果。
```

## 2. 当前现状

### 2.1 AI 设置里已有搜索配置页面，但入口被关闭

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Root/AISettingsView.swift
```

现状：

```text
1. `AISearchToolSettingsView(viewModel:)` 已存在。
2. `AISettingsView` 的工具区中，“联网搜索/搜索工具”入口被整段注释。
3. 用户无法从设置页进入搜索供应商配置。
4. 底层配置即使存在，也缺少可见开关和可操作入口。
```

需要恢复：

```text
Section(ai_settings.section.tools)
  -> SmallTasksSettingsView
  -> AISearchToolSettingsView
```

恢复时注意：

```text
1. 使用项目当前的 `MainNavigationLink` 风格，保持设置页导航一致。
2. 继续调用 `.hidesMainTabBarWhenPushed()`，避免进入二级设置页后底部栏干扰。
3. 文案复用现有 L10n key：`ai_settings.row.search_tools`、`ai_settings.row.search_tools.subtitle`。
```

### 2.2 搜索供应商配置 UI 已有主体能力

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Preferences/AISearchToolSettingsView.swift
```

已有能力：

```text
1. 全局 `useSearch` 开关。
2. `searchCount` 结果数量配置。
3. `bilingualSearch` 双语搜索配置。
4. 搜索供应商列表展示。
5. 新增/编辑 `SearchKeys`。
6. 启用供应商前校验非 Spark provider 必须有 API Key。
7. 删除搜索供应商。
8. 内置测试入口 `WebSearchGateway.search(query:config:)`。
```

需要补齐/验收：

```text
1. 入口恢复后页面可达。
2. 默认列表必须包含当前支持的供应商，或至少支持用户新增相同 provider id。
3. `company` 必须能映射到 `SearchProviderID`，不能出现 UI 可保存但运行时回退到 SPARK 的错配。
4. 同一时刻允许一个或多个 provider `isUsing=true` 时，运行时选择规则必须明确。
```

### 2.3 搜索运行时已有 Provider 适配层

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/Search/SearchRuntimeModels.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/Search/SearchRuntimeConfigResolver.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/Search/WebSearchGateway.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/Search/Providers/WebSearchProviders.swift
```

当前支持的 `SearchProviderID`：

```text
SPARK
TAVILY
SERPAPI
ZHIPUAI
BOCHAAI
EXA
BRAVE
LANGSEARCH
PERPLEXITY
```

当前 resolver 规则：

```text
1. `snapshot.searchToolPreferences.useSearch=false` 时抛出 `SearchRuntimeError.disabled`。
2. 从 `snapshot.searchKeys` 里选择 `searchClass=web && isUsing=true` 的候选。
3. 候选按 `priority` 降序、`timestamp` 降序选择第一项。
4. 非 SPARK provider 必须有 API Key。
5. 输出 `SearchRuntimeConfig` 给 `WebSearchGateway`。
```

需要确认：

```text
1. 设置页启用 provider 时是否会维护 `priority` 或至少让用户理解当前生效 provider。
2. 搜索测试与 DeepTutorChat 实际调用使用同一个 resolver。
3. 错误文案能引导用户回到“AI 设置 -> 联网搜索”修复。
```

### 2.4 DeepTutorChat 已有工具策略，但需要证明搜索配置被消费

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorToolPolicyResolver.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorRuntimeRequestBuilder.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorAIRuntimeAdapter.swift
```

当前工具策略中，联网搜索对应 Spark 工具：

```text
search_online
read_web_page
search_arxiv_papers
```

当前推理选项：

```text
ChatOrchestratorInferenceOptions.useWebSearch = toolPolicy.useWebSearch
ChatOrchestratorInferenceOptions.allowedToolNames = toolPolicy.allowedToolNames
```

需要完成：

```text
1. DeepTutorChat 的 `web_search` canonical tool 必须稳定映射到 `search_online`。
2. 当用户本轮开启 web_search，且 AI 设置里的联网搜索启用时，运行时必须读取 active SearchRuntimeConfig。
3. 当 AI 设置未启用搜索或无 active provider 时，工具不要静默失败，需要产生可读 tool result 或前置提示。
4. 日志必须带出 provider、rawKeyID、revision、searchCount，但不能输出 API Key。
```

## 3. DeepTutor-main 对标结论

### 3.1 DeepTutor-main 的搜索设置链路

参考文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/services/setup/init.py
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/tools/web_search.py
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/services/search/__init__.py
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/services/search/base.py
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/services/search/providers/__init__.py
```

DeepTutor-main 的关键流程：

```text
1. 初始化配置里存在 `tools.web_search.enabled`。
2. `web_search()` 每次执行时读取当前 runtime config。
3. provider 不是由聊天 UI 硬编码，而是由 `resolve_search_runtime_config()` 决定。
4. provider registry 只注册支持的 provider。
5. 缺少凭据时按 provider 类型 fallback 或报错。
6. `get_current_config()` 给 UI/CLI 展示当前生效 provider、缺失凭据、fallback 原因和支持列表。
```

对应到 SparkClient：

```text
DeepTutor-main `tools.web_search.enabled`
  -> SparkClient `AISearchToolPreferences.useSearch`

DeepTutor-main `resolve_search_runtime_config()`
  -> SparkClient `SearchRuntimeConfigResolver.resolve(from:)`

DeepTutor-main provider registry
  -> SparkClient `SearchProviderID` + `WebSearchGateway.providers`

DeepTutor-main `web_search()` tool
  -> SparkClient `search_online` / `WebSearchGateway.search(query:config:)`
```

### 3.2 不照搬的部分

DeepTutor-main 支持：

```text
brave
tavily
jina
searxng
duckduckgo
perplexity
serper
```

SparkClient 当前支持：

```text
tavily
serpapi
zhipuai
brave
exa
bochaai
langsearch
perplexity
spark
```

本工单不要求强行照搬 DeepTutor-main 的 provider 集合。要求是：

```text
1. 学习 DeepTutor-main 的配置消费方式。
2. 使用 SparkClient 已有 Provider 适配器。
3. 如果要新增 `duckduckgo`、`jina`、`searxng`、`serper`，必须另开工单，因为涉及新 Swift provider 适配。
```

## 4. 目标用户流程

### 4.1 设置内配置搜索供应商

目标流程：

```text
设置
  -> AI 设置
  -> 联网搜索
  -> 开启“使用搜索”
  -> 新增/选择搜索供应商
  -> 填写 API Key 与 endpoint
  -> 测试搜索
  -> 启用该供应商
  -> 返回 DeepTutorChat
```

验收点：

```text
1. 设置入口可见。
2. 新增 provider 后列表立即显示。
3. 非 SPARK provider 未填 key 时禁止启用。
4. endpoint 无效时测试失败并展示原因。
5. 测试成功后可保存并启用。
6. 当前启用 provider 有明确状态。
```

### 4.2 DeepTutorChat 中触发联网搜索

目标流程：

```text
DeepTutorChat
  -> 用户打开 web_search 工具或 capability 默认允许 web_search
  -> 发送需要实时信息的问题
  -> DeepTutorToolPolicyResolver 允许 `search_online`
  -> ChatOrchestrator 调用 ToolHub
  -> WebSearchGateway 读取 SearchRuntimeConfig
  -> active provider 返回结果
  -> 工具结果进入模型上下文
  -> 消息内展示“联网搜索”工具思考/结果卡片
```

验收问题示例：

```text
今天最新的 Apple Developer 新闻是什么？
请搜索 2026 年最新的 iOS 健康数据隐私政策变化。
帮我查一下 Tavily 和 Brave Search API 的差异。
```

预期结果：

```text
1. 日志显示 `allowedTools` 包含 `search_online`。
2. 日志显示 `useWebSearch=true`。
3. 搜索执行日志显示 provider、revision、searchCount。
4. 最终回答引用搜索结果，而不是直接用模型旧知识回答。
```

## 5. 实施方案

### 5.1 恢复 AI 设置搜索入口

修改文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Root/AISettingsView.swift
```

要求：

```text
1. 取消 `AISearchToolSettingsView` 入口注释。
2. 使用 `MainNavigationLink`，和同页其它设置项保持一致。
3. 入口放在 `ai_settings.section.tools` 下，位置建议在“小任务”之后。
4. 保留 `.hidesMainTabBarWhenPushed()`。
```

### 5.2 统一供应商 id 与默认模板

涉及文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/AISettings/Domain/AISettingsSeedCatalog.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/AISettings/Domain/AISettingsDomainModels.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Preferences/AISearchToolSettingsView.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/Search/SearchRuntimeModels.swift
```

要求：

```text
1. UI 允许选择或新增的 provider company 必须严格映射 `SearchProviderID`。
2. 推荐内置供应商模板：TAVILY、BRAVE、EXA、PERPLEXITY、SERPAPI、ZHIPUAI、BOCHAAI、LANGSEARCH、SPARK。
3. 每个模板包含默认 endpoint、是否需要 API Key、帮助文案、价格提示。
4. 对未知 company，不要默认静默使用 SPARK；应提示“当前搜索引擎还没有本地适配器”。
```

### 5.3 生效 Provider 选择规则

涉及文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/Search/SearchRuntimeConfigResolver.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Preferences/AISearchToolSettingsView.swift
```

目标规则：

```text
1. MVP 保持当前 resolver：`priority` 高者优先，优先级相同取更新时间最新者。
2. UI 文案必须让用户知道“当前生效”的供应商。
3. 启用某个 provider 时，建议自动将它设为最高 priority，避免多个开关都开但用户不知谁生效。
4. 如果产品希望单选语义，应将 row toggle 改成 radio-like active provider 选择，但仍可保留 provider 是否保存。
```

本工单建议：

```text
优先采用“单个当前生效供应商”语义。
保存多个供应商配置可以存在，但运行时 active provider 应在 UI 上唯一、明确。
```

### 5.4 DeepTutorChat 消费搜索配置

涉及文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorToolPolicyResolver.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorRuntimeRequestBuilder.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorAIRuntimeAdapter.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ChatOrchestrator.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ToolHub/ToolHub+Routing.swift
```

要求：

```text
1. 不在 DeepTutorChat 里保存 provider key。
2. DeepTutorChat 只负责决定本轮是否允许 `search_online`。
3. 真正执行搜索时由 AIRuntime/ToolHub 从 AIConfigCenter 当前 snapshot 解析 SearchRuntimeConfig。
4. 如果 `SearchRuntimeConfigResolver.resolve` 抛错，工具结果应返回可展示错误，而不是让模型继续假装搜索完成。
5. requestSnapshot 和 debug export 中记录搜索配置 revision，便于复现同一轮搜索行为。
```

### 5.5 日志与脱敏

涉及文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorChatLog.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/AIRuntimeRequestLogRedactor.swift
```

新增日志建议：

```text
deeptutor.search.config_resolved conversation=<id> provider=TAVILY keyID=<uuid> revision=<n> count=<n> bilingual=<bool>
deeptutor.search.config_failed conversation=<id> error=missing_api_key provider=TAVILY
deeptutor.search.tool_result conversation=<id> provider=TAVILY resultCount=<n> elapsedMs=<n>
```

脱敏要求：

```text
1. 不输出 API Key。
2. 不输出完整 Authorization header。
3. endpoint 可输出 host，不建议输出带 query 的完整 URL。
4. rawKeyID 可输出 UUID，用于定位配置记录。
```

## 6. 数据流设计

目标数据流：

```text
AISettingsView
  -> AISearchToolSettingsView
  -> AISettingsViewModel.snapshot.searchToolPreferences/searchKeys
  -> SaveAISettingsUseCase
  -> AISettingsRepository
  -> AIConfigCenter current snapshot
  -> SearchRuntimeConfigResolver.resolve(snapshot)
  -> WebSearchGateway.search(query, config)
  -> ToolHub search_online result
  -> ChatOrchestrator tool loop
  -> DeepTutorChat message blocks / trace cards
```

失败流：

```text
useSearch=false
  -> SearchRuntimeError.disabled
  -> 工具结果提示“联网搜索未启用”
  -> DeepTutorChat 可提示去 AI 设置开启

无 active provider
  -> SearchRuntimeError.missingActiveProvider
  -> 工具结果提示“尚未配置可用的联网搜索引擎”

缺少 API Key
  -> SearchRuntimeError.missingAPIKey(provider)
  -> 工具结果提示“请在设置中的联网搜索补充密钥”

provider 未适配
  -> SearchRuntimeError.unsupportedProvider(provider)
  -> 工具结果提示“当前搜索引擎还没有本地适配器”
```

## 7. 测试计划

### 7.1 单元测试

建议新增/更新：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Tests/AI/SearchRuntimeConfigResolverTests.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/Tests/DeepTutorChat/DeepTutorToolPolicyResolverTests.swift
```

测试项：

```text
1. `useSearch=false` 时 resolver 抛出 disabled。
2. 多个 provider 同时启用时，priority 高者生效。
3. priority 相同时时间新的生效。
4. 非 SPARK provider 空 key 抛出 missingAPIKey。
5. 未知 company 不应静默降级为 SPARK。
6. DeepTutorChat 允许 `web_search` 时，policy 输出 `search_online` 且 `useWebSearch=true`。
7. DeepTutorChat 禁用 `web_search` 时，policy 不输出 `search_online`。
```

### 7.2 手工验收

步骤：

```text
1. 打开设置 -> AI 设置。
2. 确认工具区出现“联网搜索/AI 搜索工具”入口。
3. 进入后开启搜索。
4. 新增 Tavily 或 Brave 搜索供应商。
5. 填写 API Key 和 endpoint。
6. 使用设置页测试搜索。
7. 回到 DeepTutorChat，启用 web_search 工具。
8. 发送“请搜索今天最新的 Apple Developer 新闻”。
9. 查看日志和消息卡片。
```

通过标准：

```text
1. 设置页测试搜索成功。
2. DeepTutorChat 日志出现 `useWebSearch=true`。
3. 搜索执行日志显示选中的 provider。
4. 消息流出现联网搜索工具调用状态。
5. 最终回答包含搜索结果引用或明确来源信息。
6. 关闭 `useSearch` 后，同样问题不应假装搜索成功。
```

## 8. 风险与边界

### 8.1 风险

```text
1. 只恢复设置入口但未接入 ToolHub，用户会以为已配置成功，DeepTutorChat 实际仍无法搜索。
2. 多 provider 同时启用但 UI 不显示 active provider，会导致排查困难。
3. 未知 company 当前可能被 `SearchProviderID(company:)` 回退为 SPARK，需要避免错配。
4. API Key 日志脱敏不完整会带来安全风险。
5. DeepTutor-main 与 SparkClient 支持的 provider 集合不同，不能直接照搬文案和枚举。
```

### 8.2 非本工单范围

```text
1. 新增 DeepTutor-main 中的 duckduckgo、jina、searxng、serper Swift provider 适配。
2. 改造所有 Chat 功能的搜索入口。
3. 搜索结果引用样式大改版。
4. 搜索供应商账号购买、配额管理和计费展示。
5. 服务端同步搜索 key。
```

## 9. 开发拆分建议

### Phase 1：设置入口与配置可达

```text
1. 恢复 `AISettingsView` 中 `AISearchToolSettingsView` 入口。
2. 检查 L10n 文案是否存在。
3. 确认新增/编辑/启用 provider 可以持久化。
4. 设置页搜索测试跑通至少一个 provider。
```

### Phase 2：Provider 规则收口

```text
1. 梳理 `SearchProviderID(company:)` 对未知 provider 的回退行为。
2. 明确 active provider 单选或 priority 策略。
3. UI 标记当前生效 provider。
4. 补 resolver 单元测试。
```

### Phase 3：DeepTutorChat 搜索消费与日志

```text
1. 确认 `web_search` canonical tool 映射到 `search_online`。
2. 确认 ToolHub 搜索执行读取 AISettings snapshot。
3. 补 `deeptutor.search.*` 日志。
4. requestSnapshot/debug export 记录 search revision。
5. 手工验收 DeepTutorChat 联网搜索。
```

## 10. 完成定义

本工单完成时必须同时满足：

```text
1. 用户可以从设置页打开 AI 搜索供应商配置。
2. 用户可以配置并启用至少一个真实搜索供应商。
3. 设置页测试搜索成功。
4. DeepTutorChat 中启用 web_search 后，真实调用当前 active provider。
5. 搜索失败时展示可行动错误，不静默降级、不伪造结果。
6. 日志可定位 provider、revision、结果数量，并确认 API Key 未泄露。
7. 单元测试覆盖 resolver 和 DeepTutorChat 工具策略关键分支。
```
