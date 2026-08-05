# AI Runtime 推理编排需求

## 一、模块目标

本模块负责把「场景模型配置」解析成一次可执行的推理请求，并统一编排本地 / 远端推理、流式事件、深度思考（reasoning）、取消、以及模型不支持工具时的能力降级。它是聊天助手回复、医疗文档结构化抽取、营养识别、知识库润色等 AI 能力的共同执行内核。

本模块覆盖：

- 按 `AIScenario` 解析最终模型、endpoint、apiKey、temperature、maxTokens 与配置来源。
- 组装 `AIRuntimeTextRequest`，包含消息、tools、toolChoice、reasoning、线程级采样覆盖与取消令牌。
- 在本地 GGUF 路由与 OpenAI 兼容云端网关之间选择执行路径。
- 将 SSE / 本地流统一映射为 `AIRuntimeStreamEvent`，供聊天编排或业务抽取器消费。
- 在聊天路径上由 `ChatOrchestrator` 完成历史组包、多轮 tool 循环、流式 partial 回传与空输出保护。

本模块不覆盖：

- AI 设置页、厂商 Key、场景绑定、Pro overlay 与本地模型文件生命周期（见 `总领文档/AI 设置与本地模型/`）。
- ToolHub 工具注册、授权、审计与各执行器副作用（见 `工具调用与审计需求.md`）。
- 消息落库、附件上传、outbox 同步（见 `消息发送、附件与同步管线需求.md`）。
- 问报告健康资源选择与 timeline 注入细节（见 `问报告与健康资源上下文需求.md`）。

当前实现范围以 iOS `SparkClient` 代码为准。本地 GGUF **已接入路由**，但 `LocalGGUFTextGateway` **当前返回占位结果**，不能视为真实端侧推理已完成。

## 二、AI Runtime 推理编排模块结构

### 结构职责表

| 层级 | 职责 | 关键代码 |
| --- | --- | --- |
| Feature 入口 | 聊天发送 / 重生成；医疗、营养、知识库等直连 Runtime | `Features/Chat/Application/SendChatMessageUseCase.swift`、`Features/MedicalDocumentUpload/`、`Features/Nutrition/`、`Features/Knowledge/` |
| 聊天编排 | 历史组包、推理开关、工具白名单、多轮 tool 循环、流式汇总 | `Core/AIRuntime/ChatOrchestrator.swift` |
| Runtime 服务 | 场景解析、本地/远端路由、tools 降级、输出日志 | `Core/AIRuntime/AIRuntimeService.swift` |
| 配置解析 | 场景策略、有效 bundle、运行时覆盖 | `Core/AI/AIConfigCenter.swift`、`Core/AI/ScenarioPolicyResolver.swift` |
| 云端网关 | OpenAI 兼容 Chat Completions + SSE | `Core/AIRuntime/OpenAICompatibleTextGateway.swift` |
| 本地网关 | GGUF 本地路由入口（当前占位） | `Core/AIRuntime/LocalGGUFTextGateway.swift` |
| 领域模型 | 请求/响应/流事件/错误/推理选项 | `Core/AIRuntime/AIRuntimeModels.swift` |
| 取消 | 协作式取消令牌 | `Core/AIRuntime/AIRuntimeCancellation.swift` |
| 组合根 | 装配 `AIRuntimeService` / `ChatOrchestrator` | `App/Architecture/AssemblyProducts.swift` |
| 测试 | 场景解析与相关边界 | `Tests/AI/AISettingsAndResolverTests.swift` |

### 具体目录结构

```text
SparkClient/
├── SparkClient/Projects/Core/AI/
│   ├── AIScenario.swift
│   ├── AIConfigCenter.swift
│   ├── ScenarioPolicyResolver.swift
│   ├── AIConfigModels.swift
│   ├── AIRuntimeStore.swift
│   ├── AIRuntimeConfigStore.swift
│   ├── AIClientFactory.swift
│   └── LocalModelService.swift
├── SparkClient/Projects/Core/AIRuntime/
│   ├── AIRuntimeService.swift
│   ├── AIRuntimeGateway.swift
│   ├── AIRuntimeModels.swift
│   ├── AIRuntimeCancellation.swift
│   ├── AIRuntimeOutputLog.swift
│   ├── AIRuntimeRequestLogRedactor.swift
│   ├── ChatOrchestrator.swift
│   ├── ChatOrchestratorInferenceOptions.swift
│   ├── ChatSystemPromptResolver.swift
│   ├── OpenAICompatibleTextGateway.swift
│   ├── OpenAICompatibleEmbeddingClient.swift
│   ├── GuestAIRuntimeChatClient.swift
│   ├── OpenAIReasoningPayload.swift
│   ├── LocalGGUFTextGateway.swift
│   ├── PromptLocalizer.swift
│   └── ToolHub/                         # 边界：工具专题文档覆盖
├── SparkClient/Projects/Features/Chat/
│   ├── Application/SendChatMessageUseCase.swift
│   ├── Application/MessageRunActor.swift
│   └── Presentation/ChatDetailViewModel.swift
├── SparkClient/Projects/App/Sources/App/
│   ├── AppContainer.swift
│   └── Architecture/AssemblyProducts.swift
└── SparkClient/Tests/
    ├── AI/AISettingsAndResolverTests.swift
    ├── AI/AIRuntimeArchitectureGateTests.swift
    ├── AI/ScenarioPolicyResolverTests.swift
    ├── AI/GuestAIRuntimeChatClientTests.swift
    ├── Chat/ChatArchitectureGateTests.swift
    └── MedicalDocumentUpload/MedicalExtractionInputSourceTests.swift
```

### 目录职责与依赖方向

```text
Features (Chat / Medical / Nutrition / Knowledge)
  → ChatOrchestrator（仅聊天路径）或直接 AIRuntimeServing
    → AIRuntimeService
      → AIConfigCenter / ScenarioPolicyResolver
      → LocalGGUFTextGateway  或  OpenAICompatibleTextGateway + AIClientFactory
        → URLSession / LocalModelService
```

- `Core/AI`：配置与场景解析，不发推理请求。
- `Core/AIRuntime`：推理编排、网关、流事件与聊天编排；可依赖 `Core/AI`。
- Feature 层不得绕过 `AIRuntimeService` 直接拼厂商 HTTP（当前实现以 Runtime 为统一入口）。
- 当前未单独拆 Application/Domain 包：Runtime 以 Core 服务 + 协议 `AIRuntimeServing` 形式存在。

### 统一入口与单链路约束（CHAT-000007）

本模块采用**两级入口**，所有模型调用必须先进入 Runtime 层：

| 入口 | 适用场景 | 调用方 |
| --- | --- | --- |
| `ChatOrchestrator` | 聊天、多轮 tool loop、流式 partial 回写 | `SendChatMessageUseCase` |
| `AIRuntimeServing` | 单次抽取、润色、识别、embedding | Feature Application / Infrastructure UseCase |

**硬规则（由 `AIRuntimeArchitectureGateTests` 门禁保障）：**

1. 页面层、ViewModel、Feature **不得**直接引用 `OpenAICompatibleTextGateway`、`LocalGGUFTextGateway`、`AIClientFactory`。
2. **不得**在 Feature 层手写 `URLSession` 请求 `/v1/chat/completions` 或自行解析 SSE。
3. `AssemblyProducts` 是 gateway / Runtime 对象的**唯一装配根**。
4. 本地 / 云端模型路由、tools 降级、reasoning payload 只允许在 `AIRuntimeService` 与 gateway 处理。

**特殊路径说明：**

- **Guest 简化聊天**：用户自填凭据，不经 `AIConfigCenter.resolve`，但底层仍复用 `OpenAICompatibleTextGateway`（`GuestAIRuntimeChatClient`）。
- **Embedding**：`OpenAICompatibleEmbeddingClient` 归属 `Core/AIRuntime/`，仅在装配根创建；Knowledge Feature 只依赖 `KnowledgeEmbeddingClient` 协议。

**新增 AI 能力前的 6 个反问：**

1. 聊天多轮还是单次任务？
2. 能复用现有 `AIScenario` 吗？
3. 走 `ChatOrchestrator` 还是 `AIRuntimeService`？
4. 业务层是否在拼 provider / SSE / gateway 细节？
5. 模型解析是否仍由 `AIConfigCenter` 统一决定？
6. 取消、日志、tool 降级是否留在 Runtime？

### P0 主干协议收口（CHAT-000008）

CHAT-000008 在 CHAT-000007 入口统一基础上，进一步把**协议与来源标记**固化为唯一事实源：

#### 三组统一协议

| 协议 | 类型 | 关键字段 / 语义 |
| --- | --- | --- |
| 请求协议 | `AIRuntimeTextRequest` | `scenario`、`messages`、`tools`、`toolChoice`、`reasoning`、`preferredModelName`、`providerCompanyUppercased`、`temperature`、`topP`、`maxTokens`、`cancellationToken` |
| 流式协议 | `AIRuntimeStreamEvent` | `textDelta` → `reasoningDelta` → `toolCallDelta` → `completed` |
| 来源协议 | `AIConfigSource` | `localDefault`、`localCatalog`、`proOverlay`、`userOverride`、`runtimeOverride`、`trialPolicy` |

#### 模型来源计算边界

1. `AIConfigCenter` 读取配置快照与 overlay。
2. `ScenarioPolicyResolver` 决定最终命中模型与 `source`。
3. `AIRuntimeService` 在日志与事件中携带来源信息（`resolved.source.rawValue`）。

Guest 等 bypass 路径（用户自填凭据）不经 `AIConfigCenter.resolve`，但须通过 `toResolvedConfig(source: .trialPolicy)` 等方式显式标记来源。

#### 新增 AI 功能前的 4 个反问（P0）

1. 这次调用是聊天型多轮，还是单次任务型？
2. 它能不能复用 `AIRuntimeService` 现有 request 协议？
3. 它是否需要 `ChatOrchestrator` 的 tool loop？
4. 它的模型来源标记是谁算出来的，在哪里写日志？

#### 测试与门禁

| 测试文件 | 覆盖范围 |
| --- | --- |
| `AIRuntimeArchitectureGateTests.swift` | Feature/App 禁止 gateway/client/HTTP；禁止自定义并行 `*StreamEvent` 协议 |
| `ScenarioPolicyResolverTests.swift` | `localCatalog` 默认行、`trialPolicy` 来源标记、缺失模型异常 |
| `AISettingsAndResolverTests.swift` | `runtimeOverride` 优先、`proOverlay` 来源（已有） |

`AIRuntimeService` 的空消息报错 / tools 降级 / 本地云端路由行为测试缺口记录在案，留待后续工单补 `AIRuntimeServiceTests.swift`。

### 能力 / 工具 / 副作用三层边界（CHAT-000009）

CHAT-000009 在 P0 主干之上，把聊天链路里隐式的「做什么 / 怎么做 / 怎么落库展示」拆成三层，对齐 DeepTutor 的 `BaseCapability` + `ToolRegistry` + `StreamBus` 分工：

| 层 | 职责 | SparkClient 关键代码 |
| --- | --- | --- |
| Capability（做什么） | 决定 `useTools` / `useKnowledgeBag` / `useWebSearch`、工具白名单、是否替换 AI 历史 | `Core/AIRuntime/ChatCapabilityStrategy.swift`（`StandardChatCapabilityStrategy`、`SmallTaskCapabilityStrategy`、`ReportInterpretationCapabilityStrategy`）；`SendChatMessageUseCase` 经 `ChatCapabilityStrategyResolver` 选取策略 |
| Tool（怎么做） | Schema、路由、Consent、执行、审计；**不承担** capability 决策 | `Core/AIRuntime/ToolHub/`；`ChatOrchestrator` 传入的 `ChatOrchestratorInferenceOptions` 已由上游策略算好 |
| Side Effect（怎么落库） | `ToolSideEffect` → 串行 Actor → 块映射 → UI 协调 | `MessageRunActor` → `ToolSideEffectBlockMapper` → `ToolInteractionCoordinator` |

**聊天侧三条显式策略（CHAT-000010 扩展）：**

- `StandardChatCapabilityStrategy`（`name = "chat"`）：`ChatComposerRuntimeFlags` 原样映射为 `ChatOrchestratorInferenceOptions`；`allowedToolNames` 取自模型侧白名单。
- `SmallTaskCapabilityStrategy`（`name = "small_task"`）：`useTools` 由 `SmallTask.toolList` 是否为空决定；白名单为任务工具列表与模型白名单交集；`aiHistory` 替换为合成用户消息。
- `ReportInterpretationCapabilityStrategy`（`name = "report_interpretation"`）：问报告路径显式标记；`plan()` 与标准聊天等价（仍用 `AIScenario.chat`，不改历史/scenario）；`ChatCapabilityStrategyResolver` 在 `healthResourceContext` 非空时选取（小任务优先）。

**非聊天单次任务 capability（代码内显式 `capabilityName`，不引入运行时 Registry）：**

| capability 名称 | 显式标识位置 | 既有实现 |
| --- | --- | --- |
| `report_interpretation` | `ChatCapabilityStrategy`（聊天编排） | 问报告 + `healthResourceContext` |
| `medical_extraction` | `TypedMedicalDocumentExtracting.capabilityName` / `MedicalDocumentTypeResolving.capabilityName` | `DefaultTypedMedicalDocumentExtractor` + `DefaultMedicalDocumentTypeResolver` |
| `knowledge_processing` | `KnowledgeProcessingCapability.capabilityName` | `PolishKnowledgeTextUseCase` / `TranslateKnowledgeTextUseCase` / `AutoFillAgentPromptUseCase` |
| `task_generation` | （工具白名单覆盖） | `ToolHubGenerateTask` |

**测试与门禁：**

| 测试文件 | 覆盖范围 |
| --- | --- |
| `ChatCapabilityStrategyTests.swift` | 标准聊天 / 小任务 / 问报告三条策略与 resolver |
| `MedicalExtractionCapabilityTests.swift` | `medical_extraction` capabilityName |
| `KnowledgeProcessingCapabilityTests.swift` | `knowledge_processing` capabilityName |
| `ToolSideEffectPipelineTests.swift` | `ToolSideEffectBlockMapper` 映射；`MessageRunActor` 串行 apply |
| `ChatOrchestratorDebugToolSideEffectTests.swift` | 调试 slash 早退路径 apply 副作用 |
| `AIRuntimeArchitectureGateTests.swift` | `testToolHubDoesNotReferenceCapabilityPolicyTypes`：ToolHub 目录（含 `ToolHub+*.swift`）禁止引用 capability 策略类型 |

## 三、场景模型解析

### 需求说明

每次推理必须先确定「用哪个模型、打哪个 endpoint、带什么 Key 与采样参数」。解析结果必须可追溯来源，以便日志、降级与设置页诊断。

### 基础要求与业务规则

解析优先级（`ScenarioPolicyResolver`）：

1. 显式 `preferredModelName`（非空）命中场景 bundle 中的模型行。
2. `AIRuntimeStore.runtimeOverride(for:)` 运行时覆盖。
3. 场景 bundle 默认行（`defaultModelName` → `isDefault` → `models.first`）。

额外规则：

- `AIConfigCenter.resolve(for:preferredModelName:)` 先取 `runtimeConfigStore.effectiveBundles()`，再委托 Resolver。
- 找不到模型时抛出 `AIConfigError.missingModelForScenario`。
- Agent 身份模型：目录/策略仍用 agent 名；对外 API 调用时 `AIRuntimeService` 用 `baseModelName` 替换 `model`。
- `AIResolvedConfig` 至少包含：`endpoint`、`model`、`apiKey`、`temperature`、`maxTokens`、`source`。
- `source` 取值包括：`localDefault`、`localCatalog`、`proOverlay`、`userOverride`、`runtimeOverride`、`trialPolicy`。

`AIScenario` 当前枚举（代码事实）：

| rawValue | 用途摘要 |
| --- | --- |
| `chat` | 主聊天 |
| `embedding` / `voice` | 向量 / 语音（配置分流） |
| `medical_*` / `health_exam_extraction` 等 | 医疗文档识别与抽取 |
| `optimization_text` / `optimization_visual` | 文本润色、视觉描述 |
| `nutrition_intake_extraction` | 营养结构化抽取 |
| `report_interpretation` | 报告解读 |
| `medical_exam_plan_generation` | 体检计划；**bundle 映射到 `reportInterpretation`** |
| `context_folding` / `router` / `model_config` | 折叠、路由、配置元场景 |

### 验收标准

- 指定 `preferredModelName` 后，推理使用该模型；模型不存在时失败而非静默回退到默认。
- 运行时覆盖优先于 bundle 默认。
- Agent 模型日志/目录仍显示 agent 名，实际 HTTP `model` 字段为 `baseModelName`。
- 解析日志能看到 `scenario`、`source`、`model`。

### 技术细节与设计代码位置

- 入口：`AIConfigCenter.resolve(for:preferredModelName:)` → `ScenarioPolicyResolver.resolve(...)`。
- 调用方：`AIRuntimeService.generateTextStream` 在发流前调用 `configCenter.resolve`。
- 关键路径：
  - `SparkClient/Projects/Core/AI/AIConfigCenter.swift`
  - `SparkClient/Projects/Core/AI/ScenarioPolicyResolver.swift`
  - `SparkClient/Projects/Core/AI/AIScenario.swift`
  - `SparkClient/Projects/Core/AI/AIConfigModels.swift`
- 测试：`SparkClient/Tests/AI/AISettingsAndResolverTests.swift`

## 四、推理请求模型与流式事件

### 需求说明

统一请求/响应/事件模型，使聊天编排与非聊天抽取器共用同一套 Runtime 契约，避免各业务自行定义 SSE 或消息结构。

### 基础要求与业务规则

`AIRuntimeTextRequest` 字段：

| 字段 | 含义 |
| --- | --- |
| `scenario` | 业务场景 |
| `messages` | `AIRuntimeMessage` 列表；不得为空 |
| `tools` / `toolChoice` | 工具 schema 与 `auto`/`none` |
| `reasoning` | 是否启用思考、effortTier(0...3)、prompt fallback |
| `preferredModelName` | 线程/调用级模型覆盖 |
| `providerCompanyUppercased` | 厂商 id（兼容旧字段名） |
| `temperature` / `topP` / `maxTokens` | 线程级采样覆盖 |
| `cancellationToken` | 协作式取消 |

`AIRuntimeStreamEvent`：

| 事件 | 含义 |
| --- | --- |
| `.textDelta` | 正文增量 |
| `.reasoningDelta` | 思考过程增量 |
| `.toolCallDelta` | 工具调用增量（index/id/name/arguments） |
| `.completed` | 最终 `AIRuntimeTextResponse` |

消息角色：`system` / `user` / `assistant` / `tool`。用户消息支持纯文本或 `contentParts` 多模态（含 `spark:inline-jpeg-base64:` 内联图约定）。

### 验收标准

- `messages` 为空时抛出 `AIRuntimeError.emptyMessages`。
- 流至少在成功路径产出 `.completed`；聊天编排在缺少 completed 时可回退用缓冲拼装。
- 多模态消息不得在组包时被纯文本覆盖丢掉图片 part。

### 技术细节与设计代码位置

- `SparkClient/Projects/Core/AIRuntime/AIRuntimeModels.swift`
- 网关编码：`OpenAICompatibleTextGateway.swift`
- 请求日志脱敏：`AIRuntimeRequestLogRedactor.swift`
- 最终输出日志：`AIRuntimeOutputLog.swift`（仅 `AIRuntimeService` 成功完成后调用）

## 五、本地 / 远端推理路由

### 需求说明

`AIRuntimeService` 是统一推理入口：先解析配置，再决定走本地 GGUF 还是云端 OpenAI 兼容网关，并在模型不支持 tools 时严格降级。

### 基础要求与业务规则

路由规则：

1. `configCenter.resolve` 得到 `AIResolvedConfig`。
2. 从有效 bundle 判断 `supportsToolUse`；不支持且请求带 tools → 清空 tools、`toolChoice = .none`，记 info 日志。
3. 若模型行 `provider` 为本地，且存在 `localFilename`（agent 则用 base 模型文件）→ `LocalGGUFTextGateway`。
4. 否则 → `AIClientFactory.makeClient` + `OpenAICompatibleTextGateway`。
5. Agent：对外 `model` 替换为 `baseModelName`，内部仍保留 agent 名用于目录判断。

本地网关当前行为（代码事实）：

- 不加载真实 GGUF 推理。
- 取最后一条 user 文本 echo，或返回 `"Local GGUF is temporarily disabled."`。
- 产出单次 `.textDelta` + `.completed`；无 reasoning / toolCalls。
- 日志明确写「本地 GGUF 能力已临时禁用」。

云端网关关键行为：

- `URLSession.bytes` 解析 SSE `data: ` 行；支持 `[DONE]`；兼容 backend 包裹 chunk（`code==0`）；无帧时 fallback 整包 JSON。
- reasoning 请求侧由 `OpenAIReasoningBuilder` 按厂商注入字段。
- 超时：request 约 300s，resource 约 900s（以网关实现为准）。

### 验收标准

- 同一 `generateTextStream` 入口可服务聊天与非聊天场景。
- 不支持 tools 的模型不会带着 tools schema 出站。
- 选择本地模型时进入 `LocalGGUFTextGateway` 分支（即使当前为占位）。
- 消费者取消流时，`onTermination(.cancelled)` 会取消 token 与内部 Task。

### 技术细节与设计代码位置

```text
AIRuntimeService.generateTextStream
  → resolve + tools 降级
  → resolveLocalModelSelection ?
       yes → LocalGGUFTextGateway.generateTextStream
       no  → AIClientFactory.makeClient + gateway.generateTextStream
  → 包装 AsyncThrowingStream（转发事件、记耗时、OutputLog）
```

- `SparkClient/Projects/Core/AIRuntime/AIRuntimeService.swift`
- `SparkClient/Projects/Core/AIRuntime/OpenAICompatibleTextGateway.swift`
- `SparkClient/Projects/Core/AIRuntime/LocalGGUFTextGateway.swift`
- `SparkClient/Projects/Core/AIRuntime/OpenAIReasoningPayload.swift`
- `SparkClient/Projects/Core/AI/AIClientFactory.swift`
- 装配：`AssemblyProducts.swift` 中 `AIAssembly.makeCore`

## 六、聊天编排与流式汇总

### 需求说明

聊天路径在 Runtime 之上增加 `ChatOrchestrator`：把本地 `ChatMessage` 历史转成 Runtime 消息，按 Composer 开关过滤工具，消费流式事件回写 UI，并在模型返回 `tool_calls` 时驱动多轮循环。

### 基础要求与业务规则

入口：`ChatOrchestrator.generateReply(...)`。

主流程要点：

1. `checkCancellation`。
2. `inference.useTools` 时先 `toolHub.runIfNeeded`；显式 `/tool` 等命中且 bypass 模型则直接返回 tool 输出。
3. `makeRuntimeMessages` 组包：system prompt、成员上下文、历史、LocalOCR / 多模态附件。
4. `applyOutboundUserTurn` 合并本轮 `userInput` 与可选 `healthResourceContext`（问报告前缀），避免覆盖 LocalOCR / 多模态 parts。
5. `filteredToolDefinitions`：按 `useKnowledgeBag` / `useWebSearch` / `allowedToolNames` 过滤。
6. 循环最多 `maxToolRounds = 30`：
   - 调 `runtimeService.generateTextStream(scenario: .chat, ...)`
   - `collectRuntimeResponse` 汇总事件并 `onPartial`
   - 无 tool_calls：正文 trim 为空 → `AIRuntimeError.emptyOutput`；否则返回文本/blocks
   - 有 tool_calls：逐个 `toolHub.executeToolCall`，回灌 `role: .tool`；若 `isAwaitingUserInput` 则锁定工具（清空 definitions、`toolChoice=.none`、追加禁止继续调工具的 system 提示）
7. 超过 30 轮：返回 `PromptLocalizer.fallbackAssistantText()`，`finishReason: "length"`。

推理开关映射（`buildRuntimeReasoningOptions`）：

| 模型能力 | 用户开关 | 结果 |
| --- | --- | --- |
| 支持且可控制 | `reasoningEnabled` | 按用户开关与 effortTier，无 prompt fallback |
| 支持但不可控 | 任意 | 强制 `isEnabled=true` |
| 不支持 | 用户开启 | `usePromptFallback=true` |

DeepSeek 思考模式：`RuntimeToolCallLoopStrategy` 在 assistant tool_calls 消息上回传 `reasoning_content`。

流式汇总：

- 缓冲 text / reasoning；按 index 累加 toolCallDelta。
- 优先采用 `.completed`；否则用缓冲拼装响应。
- reasoning 时长由首次与末次 reasoning delta 时间差估算。

### 验收标准

- 发送消息后 UI 能看到流式正文与（若开启）思考过程。
- 工具参数流式增量可展示；执行完成后可展示参数+输出。
- 空正文回复转为可见错误，而不是空白气泡。
- 用户停止生成后，循环与网关均可中断。
- 工具等待用户输入后，本轮不再继续暴露 tools。

### 技术细节与设计代码位置

调用链：

```text
ChatDetailViewModel.sendCurrentDraft / regenerate
  → SendChatMessageUseCase.execute / executeRegenerateReply
  → MessageRunActor（助手占位与 partial 落库）
  → ChatOrchestrator.generateReply
  → AIRuntimeService.generateTextStream
```

- `SparkClient/Projects/Core/AIRuntime/ChatOrchestrator.swift`
- `SparkClient/Projects/Core/AIRuntime/ChatOrchestratorInferenceOptions.swift`
- `SparkClient/Projects/Features/Chat/Application/SendChatMessageUseCase.swift`
- `SparkClient/Projects/Features/Chat/Presentation/ChatDetailViewModel.swift`
- ToolHub 执行细节见 `工具调用与审计需求.md`，本文只固定编排层契约。

## 七、取消、并发与工具能力降级

### 需求说明

聊天、工具内二次抽取、文档抽取等 AI 流程共用同一套取消语义；不支持工具的模型必须在 Runtime 层硬降级，避免厂商 400。

### 基础要求与业务规则

`AIRuntimeCancellationToken`：

- 轻量原子布尔；`cancel()` / `checkCancellation()`。
- UI 应同时取消外层 `Task` 与该 token。
- Runtime、Gateway、本地循环、Orchestrator 每轮/每事件检查。
- 流 `onTermination(.cancelled)` 才向下传播取消；正常 finish 不得误触发。

工具能力降级：

- 依据目录行 `supportsToolUse`；agent 取自身或 base 模型能力并集。
- 降级后本回合纯文本；Orchestrator 若仍收到 tool_calls，追加锁定提示并继续循环要求直接回复。

并发：

- 单次助手生成由 `MessageRunActor` 串行落库副作用。
- 同一线程多次发送的互斥由聊天发送管线负责（本模块消费单次 `generateReply` 契约）。

### 验收标准

- 停止生成后不再继续写入助手 partial。
- 不支持 tools 的模型不会因 tools schema 导致请求失败。
- 取消错误以 `CancellationError` 传播，不包装成普通 `AIRuntimeError`。

### 技术细节与设计代码位置

- `SparkClient/Projects/Core/AIRuntime/AIRuntimeCancellation.swift`
- `AIRuntimeService` / `OpenAICompatibleTextGateway` / `LocalGGUFTextGateway` / `ChatOrchestrator` 内的 `checkCancellation` 与 `onTermination`

## 八、非 chat 场景直连 Runtime

### 需求说明

医疗上传、营养识别、知识库文本处理等不走 `ChatOrchestrator`，但必须复用同一 `AIRuntimeService` 与场景配置，保证模型选择与取消语义一致。

### 基础要求与业务规则

| 调用方（当前实现） | 典型 scenario |
| --- | --- |
| `DefaultMedicalDocumentTypeResolver` | `medicalDocumentTypeRecognition` |
| `DefaultMedicalDocumentRecognizer` | `medicalStructuredExtraction` |
| `DefaultTypedMedicalDocumentExtractor` | 各类型 `*_extraction` |
| `NutritionIntakeStructuredExtractor` | `nutritionIntakeExtraction` |
| `NutritionFoodImageDescriber` | `optimizationVisual`（多模态） |
| Knowledge 润色 / Agent Prompt | `optimizationText` |
| Knowledge 翻译 | 使用 `chat` + 专用 system/user 提示（代码事实） |
| ToolHub 内部二次抽取 | `medicalStructuredExtraction` / `optimizationText` 等 |

业务侧自行消费 stream（例如 `StructuredJSONStreamDecoder`），自行处理 JSON 完整性与失败。

### 验收标准

- 非聊天场景可独立指定 `AIScenario`，不受聊天线程模型绑定强制覆盖（除非调用方传入 `preferredModelName`）。
- 抽取类场景默认不依赖 ChatOrchestrator 的 30 轮 tool 循环。

### 技术细节与设计代码位置

- `Features/MedicalDocumentUpload/Infrastructure/DefaultTypedMedicalDocumentExtractor.swift` 等
- `Features/Nutrition/Application/Recognition/`
- `Features/Knowledge/Application/KnowledgeTextProcessingUseCases.swift`
- `Core/AIRuntime/ToolHub/ToolHub+Shared.swift`（内部二次 AI）

## 九、整体业务流程

```text
触发（聊天发送 / 业务抽取）
  ↓
前置：校验输入、准备 cancellationToken、解析 preferredModel / provider
  ↓
[聊天] ChatOrchestrator 组包 + 可选 ToolHub.runIfNeeded
  ↓
AIRuntimeService.generateTextStream
  ↓
AIConfigCenter.resolve(scenario, preferredModelName)
  ↓
tools 能力降级（如需要）
  ↓
本地 GGUF 路由 或 云端 OpenAI 兼容网关
  ↓
流式事件：text / reasoning / toolCall / completed
  ↓
[聊天] collectRuntimeResponse → onPartial → 可选 tool 执行 → 多轮
[业务] 自定义 collector / JSON 解码
  ↓
成功输出 / emptyOutput / CancellationError / transport|server 错误
  ↓
聊天落库与 UI 反馈 / 业务结果回写
```

### 成功路径

- 云端流式完成并带 `.completed`；聊天得到非空正文或合法 tool 结果。
- 非聊天抽取得到可解码结构化文本。

### 失败、重试和恢复

- 配置缺失：`AIConfigError.missingModelForScenario` → 上层提示检查 AI 设置。
- 网络：`AIRuntimeError.transport` / `.server` → 聊天发送管线决定是否可重试消息。
- 空输出：`AIRuntimeError.emptyOutput` → 错误气泡。
- 本地占位：当前不视为真实成功推理；产品侧应避免把占位 echo 当最终能力验收。
- Runtime 本身不做自动重试；重试由 Feature UseCase（如 `RetryFailedMessageUseCase`）发起。

### 取消、并发和幂等

- 取消：token + Task 双通道。
- 幂等：同一次 `generateReply` 不保证幂等；聊天以助手 `clientID` 锚定 partial 更新。
- 工具轮次硬上限 30，防止无限循环。

## 十、状态模型

| 状态 | 进入条件 | 用户可见结果 | 退出条件 |
| --- | --- | --- | --- |
| 未开始 | 无进行中的 generate | Composer 可发送 | 触发发送/抽取 |
| 解析配置中 | `resolve` 进行中 | 通常不可见或仍显示生成中 | 解析成功/失败 |
| 流式生成中 | 已建立 stream | 正文/思考增量 | completed / 取消 / 错误 |
| 工具执行中 | 收到 tool_calls | 工具名/参数/结果 partial | 工具回灌或等待用户 |
| 工具已锁定 | `isAwaitingUserInput` | 等待用户交互 | 用户完成后下一轮纯文本 |
| 成功完成 | 非空输出或合法 tool bypass | 助手气泡/业务结果 | — |
| 空输出失败 | trim 后正文为空 | 错误气泡 | 用户重试 |
| 已取消 | token/Task 取消 | 停止增量 | — |
| 配置/传输失败 | resolve 或 HTTP 失败 | 错误提示 | 用户修改设置或重试 |

## 十一、数据与持久化

| 数据 | 所有者 | 存储位置 | 生命周期 | 清理时机 |
| --- | --- | --- | --- | --- |
| 有效场景 bundle | `AIRuntimeConfigStore` | 内存 | 账号会话内 | 登出/切账号 prewarm |
| 运行时覆盖 | `AIRuntimeStore` | 内存 | 进程内 | 覆盖清除或账号切换 |
| 推理请求/流 | Runtime | 瞬时 | 单次请求 | 请求结束 |
| 取消令牌状态 | 调用方 | 瞬时 | 单次生成 | 生成结束 |
| 聊天 partial / 最终消息 | Chat Feature | CoreData | 线程生命周期 | 删线程/清账号 |
| 本地 GGUF 文件 | `LocalModelService` | Application Support | 账号/设备文件 | 用户删除模型 |
| API Key | AI 设置 | CoreData/Key 相关存储 | 账号级 | 登出清理策略见 AI 设置文档 |

Runtime 编排层不持久化对话内容；敏感请求日志需经 `AIRuntimeRequestLogRedactor` 脱敏。

## 十二、错误模型

| 错误类别 | 触发条件 | 是否重试 | 用户反馈 | 清理动作 |
| --- | --- | --- | --- | --- |
| `AIRuntimeError.emptyMessages` | messages 为空 | 否 | 开发期/防护错误 | 无 |
| `AIRuntimeError.emptyOutput` | 模型完成但正文为空 | 可由上层重试 | 错误气泡 | 结束本次 run |
| `AIRuntimeError.invalidResponse` | 响应无法解析 | 通常否 | 通用失败文案 | 结束 stream |
| `AIRuntimeError.transport` | URLError | 视网络策略 | 网络错误 | 取消未完成写入 |
| `AIRuntimeError.server` | HTTP 业务/状态错误 | 视状态码 | 服务端 message | 结束 |
| `CancellationError` | 用户停止或 token 取消 | 否 | 停止生成 | 停止 partial |
| `AIConfigError.missingModelForScenario` | 场景无可用模型 | 否 | 引导配置模型 | 不发请求 |
| `LocalModelServiceError.modelLoadFailed` | 本地路由但无 gateway | 否 | 本地模型不可用 | 不发请求 |
| 超过 30 轮 tool | 循环耗尽 | 否（本次） | 兜底文案 | 返回 fallback |

## 十三、与其他模块的接口边界

### 本模块负责

- 场景配置解析到 `AIResolvedConfig`。
- 统一 `generateTextStream` 入口与流事件模型。
- 本地/远端路由与 tools 能力降级。
- 聊天侧 `ChatOrchestrator` 组包、流式汇总、多轮 tool 循环控制。
- 取消令牌语义与最终输出日志。

### 本模块不负责

- 厂商 Key / 模型目录 / Pro overlay 持久化与设置 UI。
- Tool 具体业务执行、授权弹窗、审计存储。
- 聊天 CoreData 读写、同步、附件上传 OCR。
- 问报告资源选择器 UI 与健康资源 JSON 组装细节。

### 上游调用方

- `SendChatMessageUseCase` / `ChatDetailViewModel`
- MedicalDocumentUpload、Nutrition、Knowledge UseCase/Extractor
- ToolHub 内部二次推理

### 下游依赖

- `AIConfigCenter`、`AIClientFactory`
- `OpenAICompatibleTextGateway` / `LocalGGUFTextGateway`
- `ToolHub`（聊天编排）
- `FileCacheManager`（多模态读缓存）
- `MessageRunActor`（工具副作用落库）

### 输入和输出契约

- 输入：`AIRuntimeTextRequest` 或 `ChatOrchestrator.generateReply` 参数集。
- 输出：`AsyncThrowingStream<AIRuntimeStreamEvent, Error>` 或 `ChatOrchestratorOutput`（text、reasoning、blocks、finishReason、tool 痕迹）。

## 十四、关键代码对应关系

| 能力 | 入口 | 编排 | 配置/领域 | 网关/基础设施 | 测试 |
| --- | --- | --- | --- | --- | --- |
| 场景解析 | `AIRuntimeService.generateTextStream` | `AIConfigCenter.resolve` | `ScenarioPolicyResolver`、`AIScenario` | `AIRuntimeConfigStore` | `Tests/AI/AISettingsAndResolverTests.swift` |
| 云端流式 | 同上 | `AIRuntimeService` | `AIResolvedConfig`、`AIRuntimeModels` | `OpenAICompatibleTextGateway`、`AIClientFactory` | 当前缺口 |
| 本地路由 | 同上 | `resolveLocalModelSelection` | 本地 provider 目录行 | `LocalGGUFTextGateway`、`LocalModelService` | 当前缺口（占位实现） |
| tools 降级 | `AIRuntimeService` | `modelSupportsTools` | 目录 `supportsToolUse` | 出站 request 改写 | 当前缺口 |
| 聊天编排 | `SendChatMessageUseCase` | `ChatOrchestrator.generateReply` | `ChatOrchestratorInferenceOptions` | `ToolHub`、`MessageRunActor` | Chat 架构门禁测试；无 Orchestrator 单测 |
| 流式汇总 | Orchestrator | `collectRuntimeResponse` | `AIRuntimeStreamEvent` | — | 当前缺口 |
| 取消 | UI / UseCase | token 贯穿 | `AIRuntimeCancellationToken` | Gateway `onTermination` | 当前缺口 |
| 医疗/营养直连 | 各 Extractor | 直接 `generateTextStream` | 对应 `AIScenario` | 同上网关 | `MedicalExtractionInputSourceTests`（含脱敏） |

装配：

- `AIAssembly.makeCore`：`AIConfigCenter` + `OpenAICompatibleTextGateway` + `LocalGGUFTextGateway` + `AIRuntimeService`
- `ChatAssembly.makeCore`：`ToolHub` + `ChatOrchestrator` + `SendChatMessageUseCase`

## 十五、测试策略

### 已有测试

- `Tests/AI/AISettingsAndResolverTests.swift`：Resolver 优先级、runtimeOverride、preferredModel、proOverlay/trial 等配置来源。
- `Tests/Chat/ChatArchitectureGateTests.swift`：禁止旧 streaming 符号回归。
- `Tests/MedicalDocumentUpload/MedicalExtractionInputSourceTests.swift`：含请求日志脱敏相关断言。

### 当前测试缺口

- `AIRuntimeService` 本地/远端路由与 tools 降级。
- `OpenAICompatibleTextGateway` SSE 解析、reasoning 字段映射、取消。
- `ChatOrchestrator` 30 轮循环、tool lock、emptyOutput、DeepSeek reasoning_content 回传。
- 本地 GGUF 真实推理（当前占位，无法做端到端能力验收）。

### 建议补充测试

- 用假 gateway 注入 stream 事件，覆盖 Orchestrator 汇总与空输出。
- 对不支持 tools 的模型行断言出站 tools 为空。
- 取消令牌在事件循环中部触发，断言不再 yield。
- Agent `baseModelName` 替换仅影响 API client.model。

## 十六、当前实现、缺口与演进

### 当前实现

- 统一 `AIRuntimeServing.generateTextStream` 入口已落地。
- 场景解析优先级与 Agent baseModel 解耦已落地。
- 云端 OpenAI 兼容 SSE、reasoning 多厂商字段、多模态 inline JPEG 约定已落地。
- 聊天编排、流式 partial、工具多轮循环与等待用户锁定已落地。
- 非 chat 场景普遍直连 Runtime。

### 当前缺口

- `LocalGGUFTextGateway` 仅为占位，本地模型不能作为真实推理能力验收。
- Runtime / Orchestrator / Gateway 缺少针对性单测与失败注入测试。
- `medicalExamPlanGeneration` 枚举存在但 bundle 映射到 `reportInterpretation`，文档与配置若假定独立 bundle 会漂移。

### 建议演进

- 恢复真实 GGUF 流式推理，并与取消、tools 降级（本地通常无 tools）对齐。
- 为 Orchestrator 增加可注入 `AIRuntimeServing` 的单元测试夹具。
- 将「推理编排」与「工具审计」文档边界保持现状，避免把 ToolHub 执行器细节回灌本文。

## 十七、整体验收标准

- [ ] 聊天发送能经 `SendChatMessageUseCase` → `ChatOrchestrator` → `AIRuntimeService` 完成流式回复。
- [ ] 场景模型解析优先级符合 preferred > runtimeOverride > bundle 默认；缺失模型失败可见。
- [ ] 不支持 tools 的模型出站无 tools schema；支持 tools 的模型可进入多轮循环。
- [ ] 流式事件覆盖正文、reasoning、toolCall、completed；空正文转 `emptyOutput`。
- [ ] 取消令牌能中断 Orchestrator 循环与 Gateway 流。
- [ ] Agent 模型对外使用 `baseModelName`，对内目录仍用 agent 名。
- [ ] 本地路由可进入 `LocalGGUFTextGateway`；当前占位行为有日志，不伪装为真实推理完成。
- [ ] 医疗/营养/知识库等非 chat 场景复用同一 Runtime 入口与场景枚举。
- [ ] 与 ToolHub、消息同步、AI 设置文档边界清晰，无职责互相覆盖。
- [ ] 关键代码路径真实存在；测试缺口已在文档中标明。
