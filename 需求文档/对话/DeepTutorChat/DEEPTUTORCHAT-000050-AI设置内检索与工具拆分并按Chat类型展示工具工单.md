# DEEPTUTORCHAT-000050 AI 设置内检索与工具拆分并按 Chat 类型展示工具工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000050 |
| 工单类型 | P1 设置结构优化 / 工具可见性 / DeepTutor-main 对齐 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 参考工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main` |
| 创建日期 | 2026-08-10 |
| 触发问题 | AI 设置中“检索”和“工具”概念混在一起；当前搜索设置已能配置联网搜索供应商，但缺少类似 DeepTutor-main 的工具列表说明与开关视图，且需要区分 DeepTutorChat 与 Chat 两套工具体系 |
| 关联工单 | `DEEPTUTORCHAT-000030`、`DEEPTUTORCHAT-000040`、`DEEPTUTORCHAT-000043`、`DEEPTUTORCHAT-000048`、`DEEPTUTORCHAT-000049` |
| 核心约束 | 检索设置保持当前独立页面；工具设置新增独立入口/页面，按 `DeepTutorChat` 与 `Chat` 分组展示，不把搜索供应商配置页改造成工具总览页 |

## 1. 需求背景

当前 SparkClient 的 AI 设置里已经存在“联网搜索/AI 搜索工具”页面：

```text
SparkClient/Projects/Features/AISettings/Presentation/Preferences/AISearchToolSettingsView.swift
```

该页面职责是：

```text
1. 启用搜索。
2. 设置搜索条数。
3. 开关双语搜索。
4. 管理搜索引擎/供应商列表，例如博查、智谱、Brave、Exa 等。
5. 通过 AISettingsViewModel.snapshot 读取 searchToolPreferences + searchKeys。
```

这部分应该继续保留为“检索 / 搜索供应商配置”，不要和“工具列表说明、工具开关、工具分组展示”混成一个页面。

DeepTutor-main 的参考形态则是“设置 > Chat > 工具”页面，它不配置搜索供应商，而是展示 chat agent 可调用的工具，并区分用户可开关工具、自动挂载工具、能力专属工具。

因此本工单目标是：在 SparkClient AI 设置中显式拆开“检索”和“工具”。

## 2. 本工单目标

```text
1. 保持当前 AI 搜索设置入口和页面职责不变：只负责搜索供应商、搜索条数、双语搜索、启用搜索。
2. 在 AI 设置的工具区新增“工具”入口，进入独立工具设置/说明页面。
3. 工具页面按 DeepTutorChat、Chat 两组展示工具。
4. DeepTutorChat 组展示 DeepTutorChat 独立工具架构中的工具简介、可用状态、是否自动挂载/用户可开关。
5. Chat 组展示现有 Chat / ToolHub 工具简介、分类和可用状态。
6. 对齐 DeepTutor-main 的工具信息架构：用户可开关、内置自动挂载、能力专属工具分开表达。
7. 不在本工单内新增搜索供应商；搜索供应商继续由 `AISearchToolSettingsView` 负责。
```

## 3. DeepTutor-main 页面主要代码位置

用户问题：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main 页面主要代码位置 在哪里？
```

结论：

| 职责 | DeepTutor-main 路径 | 说明 |
| --- | --- | --- |
| 设置 > Chat > 工具主 UI | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/app/(utility)/settings/tools/page.tsx` | 主要页面；加载 `/api/v1/tools`，展示工具列表、简介、参数、开关 |
| 设置导航结构 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/lib/settings-nav.ts` | `CHAT_CHILDREN` 中定义 `tools -> /settings/tools` |
| 前端工具设置缓存 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/lib/tools-settings.ts` | `getEnabledOptionalTools()` 读取用户启用的可选工具 |
| Chat 页工具集合 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/app/(workspace)/home/[[...sessionId]]/page.tsx` | 定义 `ALL_TOOLS`、capability allowed/default tools，并把设置中的 enabled tools 与当前能力求交集 |
| 后端工具列表 API | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/api/routers/tools.py` | `/api/v1/tools` 返回工具名、描述、参数、是否 toggleable、是否 enabled、是否 coming soon、所属 capability |
| 后端启用工具设置 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/api/routers/settings.py` | `enabled_optional_tools` 默认等于用户可开关工具全集；`PUT /api/v1/settings/enabled-tools` 持久化 |
| 内置工具注册与可开关集合 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/tools/builtin/__init__.py` | `BUILTIN_TOOL_TYPES`、`USER_TOGGLEABLE_TOOL_NAMES` |
| 运行时回填工具 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor/services/session/turn_runtime.py` | 当请求未显式带 tools 时，从用户设置回填 `enabled_optional_tools` |

DeepTutor-main 页面当前的工具分组语义：

```text
1. Experience Enhancement：用户可选工具，例如 brainstorm、web_search、paper_search、reason、geogebra_analysis、imagegen、videogen。
2. Built-in Tools：自动挂载工具，不给用户手动开关。
3. Capability Tools：能力专属工具，例如 solve / mastery 下的专用工具。
4. Coming soon：展示但不可启用。
```

这套结构可以作为 SparkClient 工具页面的信息架构参考，但不能照搬 Web 的 API 形态。

## 4. SparkClient 当前相关代码位置

### 4.1 当前检索设置

| 职责 | 路径 |
| --- | --- |
| 搜索设置主 UI | `SparkClient/Projects/Features/AISettings/Presentation/Preferences/AISearchToolSettingsView.swift` |
| AI 设置入口导航 | `SparkClient/Projects/Features/AISettings/Presentation/Root/AISettingsView.swift` |
| ViewModel 读写偏好 | `SparkClient/Projects/Features/AISettings/Presentation/Root/AISettingsViewModel.swift` |
| 偏好模型 | `SparkClient/Projects/Features/AISettings/Domain/AISettingsDomainModels.swift` |
| Snapshot | `SparkClient/Projects/Features/AISettings/Domain/AISettingsSnapshot.swift` |
| 持久化 | `SparkClient/Projects/Features/AISettings/Infrastructure/DefaultAISettingsRepository.swift` |
| 运行时 active 引擎解析 | `SparkClient/Projects/Core/AIRuntime/Search/SearchRuntimeConfigResolver.swift` |
| 搜索运行时模型 | `SparkClient/Projects/Core/AIRuntime/Search/SearchRuntimeModels.swift` |
| 联网请求与 Provider | `SparkClient/Projects/Core/AIRuntime/Search/WebSearchGateway.swift`、`SparkClient/Projects/Core/AIRuntime/Search/Providers/WebSearchProviders.swift` |
| 文案 | `SparkClient/Projects/App/Resources/zh-Hans.lproj/Localizable.strings` |

当前 `AISettingsView.swift` 的工具区已经有：

```text
SmallTasksSettingsView
AISearchToolSettingsView
AIWeatherToolSettingsView
```

本工单建议在这一组中新增独立“工具”入口，而不是改名或替换 `AISearchToolSettingsView`。

### 4.2 DeepTutorChat 工具体系

| 职责 | 路径 |
| --- | --- |
| DeepTutor canonical 工具名 | `SparkClient/Projects/Features/DeepTutorChat/Domain/DeepTutorCanonicalToolName.swift` |
| DeepTutor 工具别名映射 | `SparkClient/Projects/Features/DeepTutorChat/Domain/DeepTutorToolAliasMap.swift` |
| DeepTutor 工具策略 | `SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorToolPolicyResolver.swift` |
| DeepTutor 工具组合策略 | `SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorToolCompositionPolicy.swift` |
| DeepTutor 原生工具注册 | `SparkClient/Projects/Features/DeepTutorChat/Application/Tools/DeepTutorToolRegistryFactory.swift` |
| DeepTutor 工具协议与 compose | `SparkClient/Projects/Features/DeepTutorChat/Application/Tools/DeepTutorToolRegistry.swift` |
| DeepTutor 工具 schema | `SparkClient/Projects/Features/DeepTutorChat/Application/Tools/DeepTutorToolSchemaBuilder.swift` |
| DeepTutor 工具提示词 manifest | `SparkClient/Projects/Features/DeepTutorChat/Application/Tools/DeepTutorToolPromptManifestBuilder.swift` |
| DeepTutor 工具执行 loop | `SparkClient/Projects/Features/DeepTutorChat/Application/Tools/DeepTutorAgenticRuntime.swift` |
| DeepTutor 工具交互 Sheet | `SparkClient/Projects/Features/DeepTutorChat/Presentation/ToolInteraction/` |

当前 DeepTutorChat 已注册的原生工具至少包括：

```text
ask_user
get_current_member_binding
query_member_profile
request_member_selection
read_memory
show_custom_message_card
write_memory
```

同时 `DeepTutorCanonicalToolName` 已声明 DeepTutor-main 参考工具名：

```text
brainstorm
geogebra_analysis
web_search
code_execution
reason
paper_search
imagegen
videogen
rag
kb_files
read_source
read_memory
write_memory
read_skill
list_notebook
write_note
web_fetch
github
exec
load_tools
cron
ask_user
show_custom_message_card
```

工具页面展示时要区分：

```text
1. 已在 SparkClient DeepTutorChat 原生实现的工具。
2. 仅作为 DeepTutor-main canonical 名称存在、当前未实现或由 Chat ToolHub 映射承接的工具。
3. 由搜索设置控制可用性的检索类工具，例如 web_search / paper_search。
4. 由附件、成员绑定、记忆、健康资料上下文决定自动挂载的工具。
```

### 4.3 Chat / ToolHub 工具体系

| 职责 | 路径 |
| --- | --- |
| ToolHub 模块说明 | `SparkClient/Projects/Core/AIRuntime/ToolHub/工具中枢说明.md` |
| ToolHub 注册、路由、审计 | `SparkClient/Projects/Core/AIRuntime/ToolHub/ToolHub.swift` |
| 工具 schema | `SparkClient/Projects/Core/AIRuntime/ToolHub/ToolHub+Schema.swift` |
| 工具路由限制 | `SparkClient/Projects/Core/AIRuntime/ToolHub/ToolHub+Routing.swift` |
| 工具模型 | `SparkClient/Projects/Core/AIRuntime/ToolHub/Models/ToolingModels.swift` |
| 工具执行器 | `SparkClient/Projects/Core/AIRuntime/ToolHub/Executors/` |
| Chat 编排器 | `SparkClient/Projects/Core/AIRuntime/ChatOrchestrator.swift` |
| Chat 工具交互 UI | `SparkClient/Projects/Features/Chat/Presentation/ToolInteraction/` |

Chat / ToolHub 当前工具分类参考：

```text
1. 健康数据工具：步数、能量、营养、睡眠、运动、成员健康资料等。
2. 健康资料工具：list_member_health_sources、get_health_resource_reference、get_health_resource_context。
3. 记忆工具：save_memory、retrieve_memory、update_memory。
4. 成员工具：get_current_member、request_member_selection、find_member、switch_member、query_member_profile。
5. 卡片/副作用工具：show_custom_message_card、show_medical_risk_notice、generate_structured_health_card。
6. 外部连接器工具：search_online、read_web_page、search_arxiv_papers、extract_remote_file_content、query_weather、位置、日历等。
7. 内容工具：create_knowledge_document、search_knowledge_bag、create_canvas、edit_canvas。
8. 任务工具：query_tasks_by_member、generate_task。
```

## 5. 目标设置结构

建议 AI 设置工具区调整为：

```text
AI 设置
├── 模型
│   ├── API Keys
│   ├── 模型
│   └── 默认模型配置
├── 工具
│   ├── 小任务
│   ├── 检索
│   │   └── 当前 AISearchToolSettingsView：启用搜索、搜索条数、双语搜索、供应商列表
│   ├── 天气查询
│   └── 工具
│       └── 新增 AIToolSettingsView：DeepTutorChat / Chat 工具展示与开关
```

页面命名建议：

```text
入口标题：工具
入口副标题：查看 DeepTutorChat 与 Chat 可调用工具
页面标题：AI 工具
一级分组：DeepTutorChat、Chat
```

如果担心“工具区里还有一个工具入口”拗口，可以把 Section 名改成“能力与工具”，入口为：

```text
检索
天气
AI 工具
小任务
```

## 6. 新增工具页面产品要求

### 6.1 顶部说明

页面顶部只说明边界：

```text
检索供应商、搜索条数、双语搜索请到“检索”设置。
本页展示模型在不同对话体系中可调用的工具。
```

不要在工具页面内重复展示博查、智谱、Brave、Exa 的 API Key 表单。

### 6.2 DeepTutorChat 分组

DeepTutorChat 分组建议展示：

| 工具 | 类型 | 状态 | 简介 |
| --- | --- | --- | --- |
| `ask_user` | 自动挂载 / 交互工具 | 已接入 | 让模型向用户提出结构化问题并暂停本轮 |
| `request_member_selection` | 自动挂载 / 交互工具 | 已接入 | 需要成员上下文时请求用户选择成员 |
| `get_current_member_binding` | 自动挂载 / 上下文工具 | 已接入 | 查询当前 DeepTutorChat 会话绑定成员 |
| `query_member_profile` | 自动挂载 / 健康资料工具 | 已接入 | 读取成员医疗资料、健康画像和体检摘要 |
| `read_memory` | 条件挂载 / 记忆工具 | 已接入 | 有记忆档案时读取偏好和长期上下文 |
| `write_memory` | 自动挂载 / 记忆工具 | 已接入 | 保存用户明确表达的长期偏好 |
| `show_custom_message_card` | 自动挂载 / 卡片工具 | 已接入 | 插入上传/拍照卡片并等待用户补充附件 |
| `web_search` | 用户可选 / 检索工具 | 依赖检索设置 | 映射到 SparkClient 搜索运行时，是否可用取决于“检索”设置 |
| `paper_search` | 用户可选 / 检索工具 | 依赖检索设置 | 论文搜索能力，需明确当前是否已有 Spark 端执行器 |

展示原则：

```text
1. 已接入工具展示为可用。
2. 依赖设置的工具展示“需开启检索/配置供应商”。
3. 仅在 canonical 列表存在但尚未实现的工具展示“未接入”或“规划中”，不能让用户误以为可调用。
4. 如果工具当前由模型策略决定自动挂载，不提供用户开关，只显示“自动”。
5. 如果后续新增 DeepTutorChat 用户可开关工具，才引入开关并持久化到独立偏好。
```

### 6.3 Chat 分组

Chat 分组建议按 ToolHub 分类展示，不需要逐项做过长说明：

| 分类 | 代表工具 | 展示方式 |
| --- | --- | --- |
| 健康数据 | `fetch_step_details`、`fetch_sleep_details`、`fetch_nutrition_details` | 已接入 / 受权限影响 |
| 健康资料 | `list_member_health_sources`、`get_health_resource_context` | 已接入 / 问报告相关 |
| 成员 | `get_current_member`、`request_member_selection`、`query_member_profile` | 已接入 / 需要成员上下文 |
| 记忆 | `save_memory`、`retrieve_memory`、`update_memory` | 已接入 / 受记忆设置影响 |
| 检索 | `search_online`、`read_web_page`、`search_arxiv_papers` | 依赖“检索”设置 |
| 天气 | `query_weather` | 依赖“天气查询”设置 |
| 卡片 | `show_custom_message_card`、`show_medical_risk_notice` | 已接入 / 会产出 UI block |
| 知识与画布 | `search_knowledge_bag`、`create_knowledge_document`、`create_canvas`、`edit_canvas` | 已接入 / 受上下文影响 |
| 任务 | `query_tasks_by_member`、`generate_task` | 已接入 / 小任务相关 |

展示原则：

```text
1. Chat 分组面向现有 ToolHub，不展示 DeepTutor-main 的 web 工具名，避免名称混乱。
2. 检索类工具只展示“依赖检索设置”，具体供应商仍跳转到检索页面。
3. 天气类工具只展示“依赖天气设置”，具体供应商仍跳转到天气页面。
4. 权限类工具需要展示“受系统权限/健康授权影响”，但本工单不新增授权流程。
```

## 7. 数据模型建议

新增轻量展示模型，不要复用 `SearchKeys`。

建议模型：

```swift
struct AIToolSettingsSection: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let tools: [AIToolSettingsItem]
}

struct AIToolSettingsItem: Identifiable, Equatable {
    let id: String
    let displayName: String
    let canonicalName: String
    let source: AIToolSettingsSource
    let category: String
    let availability: AIToolAvailability
    let mountMode: AIToolMountMode
    let summary: String
    let relatedSettings: AIToolRelatedSettings?
}

enum AIToolSettingsSource: String, Equatable {
    case deepTutorChat
    case chat
}

enum AIToolAvailability: String, Equatable {
    case available
    case requiresSearchSettings
    case requiresWeatherSettings
    case requiresPermission
    case planned
    case unavailable
}

enum AIToolMountMode: String, Equatable {
    case auto
    case conditional
    case userToggleable
    case capabilityOnly
}

struct AIToolRelatedSettings: Equatable {
    let title: String
    let destination: AIToolSettingsDestination
}

enum AIToolSettingsDestination: Equatable {
    case search
    case weather
    case smallTasks
    case memory
}
```

第一阶段可以静态组装，后续再接入真实运行时 introspection。

## 8. UI 建议

新增页面建议：

```text
AIToolSettingsView.swift
```

路径建议：

```text
SparkClient/Projects/Features/AISettings/Presentation/Preferences/AIToolSettingsView.swift
```

页面结构：

```text
Form/List
├── 顶部说明卡
├── DeepTutorChat
│   ├── 工具行
│   └── 点击展开：简介 / 挂载方式 / 关联设置 / 当前状态
└── Chat
    ├── 分类行或工具行
    └── 点击展开：代表工具 / 关联设置 / 当前状态
```

工具行字段：

```text
1. 图标：按类别选择 SF Symbol。
2. 标题：displayName。
3. 副标题：canonicalName + 简介。
4. 状态徽标：已接入、依赖检索、依赖天气、需授权、规划中。
5. 挂载方式徽标：自动、条件、用户可选、能力专属。
6. 关联设置按钮：检索 / 天气 / 记忆 / 小任务。
```

## 9. ViewModel 与持久化要求

第一阶段建议不引入新的持久化写链路，只做展示和跳转：

```text
1. DeepTutorChat 已接入工具从静态清单或 registry 汇总。
2. Chat 工具从 ToolHub 静态清单/说明文档对应枚举汇总。
3. 检索类工具读取 snapshot.searchToolPreferences.useSearch 和 activeSearchKeyID 显示状态。
4. 天气类工具读取 weather preferences 显示状态。
5. 用户点击“检索设置”跳转到 AISearchToolSettingsView。
6. 用户点击“天气设置”跳转到 AIWeatherToolSettingsView。
```

后续如果要做“用户可开关工具”，再新增独立偏好：

```text
AIChatToolPreferences
DeepTutorChatToolPreferences
```

不要把用户工具开关塞进 `AISearchToolPreferences`。

## 10. 实施步骤

### Phase A：新增工具设置页面骨架

```text
1. 新增 `AIToolSettingsView.swift`。
2. 新增 `AIToolSettingsModels.swift` 或放在 AISettings Domain 中。
3. 静态构建 DeepTutorChat 与 Chat 两个 section。
4. 行 UI 支持状态徽标、挂载方式徽标、展开说明。
5. 文案接入 `Localizable.strings`。
```

### Phase B：接入 AI 设置入口

```text
1. 在 `AISettingsView.swift` 工具区新增 `MainNavigationLink`。
2. 标题建议：`AI 工具` 或 `工具`。
3. 副标题建议：`查看 DeepTutorChat 与 Chat 可调用工具`。
4. 保持 `AISearchToolSettingsView` 独立入口，标题建议统一为“检索”或“联网搜索”。
```

### Phase C：读取当前设置状态

```text
1. 检索类工具行读取 `viewModel.snapshot.searchToolPreferences.useSearch`。
2. 如果搜索未启用，状态显示“未启用检索”。
3. 如果搜索启用但没有 active provider，状态显示“未配置供应商”。
4. 如果 active provider 存在，状态显示“检索已启用”。
5. 天气类工具按天气配置同理。
```

### Phase D：对齐运行时和调试

```text
1. DeepTutorChat 调试导出中增加本轮工具来源：DeepTutorChat 原生 / Chat ToolHub / 搜索运行时。
2. Chat 工具调用日志保留 ToolHub 工具名。
3. DeepTutorChat 工具调用日志保留 canonical tool name 与 alias resolution。
4. 工具页面的名称必须与日志一致，方便用户从日志反查设置。
```

## 11. 验收标准

### 11.1 设置结构验收

```text
1. AI 设置工具区同时存在“检索”和“工具/AI 工具”两个入口。
2. “检索”进入当前搜索供应商配置页。
3. “工具/AI 工具”进入新增工具展示页。
4. 两个页面职责不混淆：检索页不展示完整工具总览，工具页不编辑搜索供应商 API Key。
```

### 11.2 DeepTutorChat 工具展示验收

```text
1. DeepTutorChat 分组至少展示 ask_user、request_member_selection、get_current_member_binding、query_member_profile、read_memory、write_memory、show_custom_message_card。
2. `web_search` / `paper_search` 显示为依赖检索设置，而不是直接可用。
3. 未实现工具不能显示为“已接入”。
4. 工具简介能说明“什么时候会被模型调用”。
```

### 11.3 Chat 工具展示验收

```text
1. Chat 分组至少覆盖 ToolHub 说明文档中的主要分类。
2. 检索类工具能跳转或提示去“检索”设置。
3. 天气类工具能跳转或提示去“天气查询”设置。
4. 健康权限类工具明确显示受系统权限/成员上下文影响。
```

### 11.4 不回归验收

```text
1. `AISearchToolSettingsView` 原有启用搜索、搜索条数、双语搜索、供应商增删改启用不受影响。
2. DeepTutorChat 工具调用与卡片展示不受影响。
3. Chat ToolHub 工具调用不受影响。
4. 不新增 API Key 明文日志。
5. 不改变 SearchRuntimeConfigResolver 的 active provider 选择规则。
```

## 12. 风险与注意事项

| 风险 | 说明 | 处理 |
| --- | --- | --- |
| 工具名混乱 | DeepTutor-main 使用 `web_search`，Spark Chat ToolHub 使用 `search_online` | DeepTutorChat 分组展示 canonical 名；Chat 分组展示 ToolHub 名；必要时在详情中写“映射到” |
| 搜索被误认为工具开关 | 用户可能在工具页打开 `web_search` 后以为供应商也配置完成 | 第一阶段不提供 `web_search` 开关，只显示依赖“检索设置” |
| 两套工具体系混用 | DeepTutorChat 已有独立工具，Chat 有 ToolHub | 页面必须按 DeepTutorChat / Chat 分组，不能合并成一张无来源列表 |
| 展示和运行时不一致 | 静态清单可能滞后 | 清单旁标注代码来源，后续可由 registry/ToolHub introspection 生成 |
| 设置入口过多 | 工具区已有小任务、检索、天气 | 可将 Section 标题改为“能力与工具”，但不要合并页面职责 |

## 13. 非目标

```text
1. 不在本工单内新增搜索供应商。
2. 不在本工单内重构 SearchRuntimeConfigResolver。
3. 不在本工单内把 DeepTutorChat 强行接入 Chat ToolHub。
4. 不在本工单内实现所有 DeepTutor-main 工具。
5. 不在本工单内新增用户级工具开关持久化，除非后续另开工单。
```

## 14. 交付结论

本工单完成后，SparkClient 的 AI 设置会形成清晰边界：

```text
检索：管搜索是否启用、搜索条数、双语搜索、搜索供应商。
工具：管 DeepTutorChat / Chat 可调用工具的可见性、简介、来源、状态和关联设置跳转。
```

这样既保留当前搜索供应商配置，又能对齐 DeepTutor-main 的“设置 > Chat > 工具”体验，并避免 DeepTutorChat 与 Chat 两套工具体系继续在设置入口上混淆。
