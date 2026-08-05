# CHAT-000007 AI 统一入口与 Runtime 单链路重构需求工单

## 工单状态

已实现（CHAT-000007，2026-08-05）。

## 1. 背景

### Q：这次工单要解决什么问题？

A：`SparkClient` 已经有 `AIAssemblyProduct -> AIRuntimeService -> ChatOrchestrator` 这一条主链路，但当前“统一入口”还主要体现在工程约定，不是硬约束。随着问报告、医疗抽取、营养识别、知识润色等能力继续扩张，风险会集中在两类问题上：

1. 业务功能各自拼装模型调用细节，导致模型选择、流式事件、取消、日志、工具降级规则出现分叉。
2. Feature 或页面层未来为了赶需求，绕过 `AIRuntimeService` 直接访问 gateway / provider / HTTP，破坏统一链路。

本工单的目标不是“重写整个 AI 架构”，而是把当前雏形收束成明确的单链路约束：**页面和业务 Feature 不直接拼 LLM；所有模型调用都必须先进入统一 Runtime 入口。**

### Q：为什么要参考 DeepTutor？

A：DeepTutor 的强项不是模型更多，而是入口更稳：

1. 不同入口最终落到统一编排层。
2. 上层描述“任务和能力”，下层统一处理模型路由、工具、流式事件、取消和日志。
3. 入口协议稳定，后续新增能力不需要复制一套推理链路。

本工单只学习这部分工程方法，不复制 DeepTutor 的全部复杂度。

参考代码位置：

- DeepTutor 统一编排入口：[orchestrator.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/runtime/orchestrator.py)
- DeepTutor turn 级运行时：[turn_runtime.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/services/session/turn_runtime.py)
- DeepTutor 统一上下文：[context.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/core/context.py)

## 2. 一句话目标

### Q：一句话需求是什么？

A：在 `SparkClient` 中建立明确的 AI 单链路规则：

- 页面层、ViewModel、Feature 不直接访问模型厂商网关、HTTP 或 provider。
- 所有 AI 请求至少先经过 `AIRuntimeService`。
- 对话型、多轮型、工具型请求统一经 `ChatOrchestrator`。
- 新增 AI 能力必须先判断：它是 Runtime 已有入口的一个场景，还是需要扩一个新的 orchestrator / capability，而不是直接加一段临时模型调用代码。

## 3. 架构边界

### Q：这里说的“统一入口”到底统一到哪一层？

A：本工单建议采用两级入口，不要求所有东西都强行走 `ChatOrchestrator`：

1. `AIRuntimeService` 是所有模型调用的最低统一入口。
2. `ChatOrchestrator` 是聊天、多轮工具调用、流式回写的统一高层入口。

换句话说：

- `Chat`、问报告聊天态、带工具调用的对话态：走 `ChatOrchestrator`
- 单次抽取、单次润色、单次结构化识别：走 `AIRuntimeService`

不建议把所有非对话能力硬塞进 `ChatOrchestrator`，否则会把聊天编排和批处理型任务耦死。

### Q：什么叫“业务页不要直接拼 LLM”？

A：指以下行为都不应该出现在页面层或业务 Feature 中：

1. 直接 new `OpenAICompatibleTextGateway`
2. 直接 new `URLSession` 去请求 `/v1/chat/completions`
3. 直接拼 provider headers、SSE、reasoning payload
4. 在页面层自行处理本地 / 云端模型路由

这些逻辑只能出现在：

1. `AssemblyProducts`
2. `AIConfigCenter`
3. `AIRuntimeService`
4. `ChatOrchestrator`
5. 明确归属 Runtime 的 gateway / ToolHub / coordinator

## 4. 当前代码对齐现状

### Q：`SparkClient` 现在已经有哪些基础是对的？

A：当前主链路已经具备雏形，主要代码位置如下：

| 角色 | 当前代码位置 | 已有职责 |
| --- | --- | --- |
| AI 装配根 | [AssemblyProducts.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/App/Sources/App/Architecture/AssemblyProducts.swift) | 创建 `AIConfigCenter`、`OpenAICompatibleTextGateway`、`LocalGGUFTextGateway`、`AIRuntimeService`、`ChatOrchestrator` 依赖图 |
| 统一模型执行入口 | [AIRuntimeService.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/AIRuntimeService.swift) | 场景解析、本地/云端路由、tools 降级、统一输出日志 |
| 对话统一编排入口 | [ChatOrchestrator.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ChatOrchestrator.swift) | 历史组包、多轮 tool call、流式 partial、空输出保护 |
| 聊天发送用例 | [SendChatMessageUseCase.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Application/SendChatMessageUseCase.swift) | 通过 `ChatOrchestrator` 发送消息 |
| 知识文本处理 | [KnowledgeTextProcessingUseCases.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Knowledge/Application/KnowledgeTextProcessingUseCases.swift) | 已通过 `AIRuntimeService` 走统一请求 |
| 营养识别 | [NutritionFoodImageDescriber.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Nutrition/Application/Recognition/NutritionFoodImageDescriber.swift) | 已通过 `AIRuntimeService` 走统一请求 |
| 医疗文档识别/抽取 | [DefaultMedicalDocumentTypeResolver.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/MedicalDocumentUpload/Infrastructure/DefaultMedicalDocumentTypeResolver.swift)、[DefaultTypedMedicalDocumentExtractor.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/MedicalDocumentUpload/Infrastructure/DefaultTypedMedicalDocumentExtractor.swift) | 已通过 `AIRuntimeService` 走统一请求 |

### Q：当前缺口主要在哪里？

A：当前缺口主要不是“已经有很多页面直接请求模型”，而是以下三类工程风险：

1. 统一入口规则还没有被工单、测试和门禁明确固定。
2. Feature 层虽然大多通过 `AIRuntimeService`，但“请求组装放在哪一层”的边界仍可能继续漂移到 ViewModel 或页面。
3. 如果未来新增 AI 功能赶需求，最容易出现直接 new gateway 或直接发 HTTP 的回退。

## 5. 本工单要求的统一入口规则

### Q：落地后必须满足哪些硬规则？

A：必须满足以下规则：

1. 页面层和 ViewModel 不直接构造 gateway、provider client、HTTP 请求。
2. 所有 AI 调用只能依赖注入 `AIRuntimeServing` 或 `ChatOrchestrator`。
3. `AssemblyProducts` 是 runtime / gateway 的唯一装配入口。
4. 聊天类入口一律通过 `SendChatMessageUseCase -> ChatOrchestrator -> AIRuntimeService`。
5. 单次抽取/识别/润色类入口通过 Application/Infrastructure UseCase 调用 `AIRuntimeService`，而不是页面直接调。
6. 本地 GGUF / 云端模型路由只允许 `AIRuntimeService` 决定。
7. provider 兼容、SSE 解析、reasoning payload、tools 降级只允许 Runtime 层处理。

### Q：如果以后要新增一个 AI 功能，应该先反问什么？

A：新增前先回答这 6 个反问：

1. 这是聊天多轮能力，还是单次任务能力？
2. 它能复用现有 `AIScenario` 吗，还是必须新建场景？
3. 它应走 `ChatOrchestrator`，还是直接走 `AIRuntimeService` 即可？
4. 业务层是否正在拼 provider / SSE / gateway 细节？如果是，方案方向就错了。
5. 本地模型、远端模型、试用模型、override 模型的解析是否仍由 `AIConfigCenter` 统一决定？
6. 取消、日志、tool 降级、错误映射是否仍留在 Runtime，而不是散落到 Feature？

## 6. 建议改动范围

### Q：这次工单具体要改哪些地方？

A：建议改动分三层推进。

#### 第一层：文档与边界补齐

1. 在总领文档中明确写出“统一入口”规则。
2. 在聊天和 AI Runtime 文档中补充“禁止绕过 Runtime”的边界。
3. 在新增 AI 功能工单模板里加入“入口选择反问”。

建议对齐文档位置：

- [AI Runtime 推理编排需求.md](</Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/总领文档/对话、AI Runtime 与工具调用/AI Runtime 推理编排需求.md>)
- [对话、AI Runtime 与工具调用需求.md](</Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/总领文档/对话、AI Runtime 与工具调用/对话、AI Runtime 与工具调用需求.md>)

#### 第二层：代码结构收束

1. 保证所有聊天发送只经 `SendChatMessageUseCase -> ChatOrchestrator`
2. 保证所有非聊天模型任务只注入 `AIRuntimeServing`
3. 把 Feature 中可能继续增长的 prompt/request 组包逻辑压回 Application/Infrastructure，而不是页面层
4. 禁止任何 Feature 新建 gateway / client

建议重点对齐代码位置：

- [AssemblyProducts.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/App/Sources/App/Architecture/AssemblyProducts.swift)
- [AIRuntimeService.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/AIRuntimeService.swift)
- [ChatOrchestrator.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ChatOrchestrator.swift)
- [SendChatMessageUseCase.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Application/SendChatMessageUseCase.swift)

#### 第三层：测试与门禁

1. 新增 Runtime 架构门禁测试，禁止 Feature 层直接引用 gateway / client
2. 保留并扩展现有聊天架构门禁测试
3. 为新增 AI 能力增加“是否通过统一入口”的测试约束

建议参考现有测试：

- [ChatArchitectureGateTests.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Tests/Chat/ChatArchitectureGateTests.swift)
- [AISettingsAndResolverTests.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Tests/AI/AISettingsAndResolverTests.swift)

## 6.1 替代哪些代码，去除哪些代码

### Q：这次不是抽象讨论，具体要替代哪些现有写法？

A：先区分两件事：

1. `替代`：保留业务能力，但改走统一入口。
2. `去除`：彻底禁止某类代码再出现。

当前仓库里大部分 Feature 已经走 `AIRuntimeService`，所以“替代”更多是给后续改造立规则，不是要大面积删现有代码。

### Q：需要被替代的代码模式有哪些？

A：以下写法后续一律用统一入口替代：

| 旧写法/风险写法 | 新写法 | 说明 |
| --- | --- | --- |
| Feature 直接拼 `AIClientFactory.makeClient(...)` | Feature 只持有 `AIRuntimeServing` | `AIClientFactory` 只能被 `AIRuntimeService` 使用 |
| Feature 直接 new `OpenAICompatibleTextGateway(...)` | 由 `AssemblyProducts` 装配 `AIRuntimeService` 后注入 | gateway 只属于 Runtime 下游实现 |
| ViewModel 或页面层自己处理 `/v1/chat/completions` | 页面只调 UseCase / Runtime 协议 | 页面层不该知道 provider 协议细节 |
| 聊天 Feature 自己做多轮 tool loop | `ChatOrchestrator.generateReply(...)` | tool loop 只能有一套 |
| 每个 Feature 自己写一套流式事件解释 | 统一消费 `AIRuntimeStreamEvent` | 文本增量、reasoning、tool delta 用统一协议 |
| Feature 自己决定本地/云端模型 | `AIRuntimeService.generateTextStream(...)` | 路由只允许 Runtime 决定 |

### Q：需要被去除或禁止的代码有哪些？

A：以下代码不一定要现在“删除文件”，但要从 Feature 边界里清掉，并用测试门禁长期禁止：

1. 在 `Projects/Features/**` 中直接引用 `OpenAICompatibleTextGateway`
2. 在 `Projects/Features/**` 中直接引用 `LocalGGUFTextGateway`
3. 在 `Projects/Features/**` 中直接引用 `AIClientFactory`
4. 在 `Projects/Features/**` 中直接写 `/v1/chat/completions`
5. 在页面层或 ViewModel 中直接写 `URLSession.bytes(for:)` 去请求模型服务
6. 在聊天链路外复制一套 tool call 循环和 partial 拼装逻辑

### Q：当前有哪些代码是保留的，不需要误删？

A：以下代码应保留，而且属于新架构中的合法调用方：

1. [SendChatMessageUseCase.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Application/SendChatMessageUseCase.swift)
2. [KnowledgeTextProcessingUseCases.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Knowledge/Application/KnowledgeTextProcessingUseCases.swift)
3. [NutritionFoodImageDescriber.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Nutrition/Application/Recognition/NutritionFoodImageDescriber.swift)
4. 医疗识别/抽取 UseCase 与 Infrastructure 中通过 `AIRuntimeService` 发请求的实现

这些不是要删，而是要作为“正确入口样板”保留。

## 6.2 迁移矩阵

### Q：从旧结构到新结构，职责怎么迁？

A：按层迁移，不按页面迁移。

| 层 | 迁移前常见风险 | 迁移后职责 |
| --- | --- | --- |
| Page / View | 持有模型名、provider、HTTP 细节，直接触发推理 | 只收集输入、展示状态、调用 ViewModel / UseCase |
| ViewModel | 同时做 UI 状态和推理协议拼装 | 只编排界面状态；AI 请求细节尽量下沉到 UseCase |
| Feature UseCase | 既调仓储又自己拼厂商协议 | 只构造业务请求，调用 `ChatOrchestrator` 或 `AIRuntimeServing` |
| ChatOrchestrator | 角色不清，可能继续被绕过 | 独占聊天 history、tool loop、partial 汇总 |
| AIRuntimeService | 只是一个薄转发层 | 独占模型解析、tools 降级、本地/云端路由、日志、取消 |
| Gateway | 可能被业务直接调 | 只能被 Runtime 调用 |

## 7. 新架构流程

### Q：新架构整体流程图是什么？

A：目标链路如下：

```text
Page / View
  ↓
ViewModel
  ↓
Feature UseCase / Application Service
  ↓
  ├─ 聊天类：ChatOrchestrator
  │          ↓
  │      AIRuntimeService
  │          ↓
  │      AIConfigCenter.resolve
  │          ↓
  │      LocalGGUFTextGateway 或 OpenAICompatibleTextGateway
  │
  └─ 单次任务类：AIRuntimeService
             ↓
         AIConfigCenter.resolve
             ↓
         LocalGGUFTextGateway 或 OpenAICompatibleTextGateway
```

### Q：为什么是两级入口，而不是单一超级入口？

A：因为 `SparkClient` 当前能力分两种：

1. `聊天/多轮/工具调用`：必须保留 `ChatOrchestrator`
2. `单次识别/润色/抽取`：直接走 `AIRuntimeService` 更简单

统一的是 Runtime 主链路，不是强行让所有事情都变成“聊天”。

## 7.1 聊天链路的落地流程

### Q：聊天消息从点击发送到模型返回，关键流程是什么？

A：建议明确成下面这条固定链路：

```text
ChatView
  ↓
ChatDetailViewModel.startSendingCurrentDraft()
  ↓
SendChatMessageUseCase.execute(...)
  ↓
1. resolveThread
2. 组装附件 / OCR / health refs / member context
3. 解析 preferredModelName 与 thread generation config
4. 生成 systemPrompt / inference options
5. 调用 ChatOrchestrator.generateReply(...)
  ↓
ChatOrchestrator
  ↓
1. makeRuntimeMessages(history + context)
2. filteredToolDefinitions(inference)
3. runtimeService.generateTextStream(request: .chat)
4. collectRuntimeResponse
5. 如果有 tool_calls：
   ToolHub.executeToolCall(...)
   MessageRunActor.apply(sideEffects)
   回灌 tool 结果，继续下一轮
6. 无 tool_calls：
   buildOutputBlocks(...)
   返回 ChatOrchestratorOutput
  ↓
SendChatMessageUseCase
  ↓
assistant message 落库 / snapshot 更新 / partial UI 回写
```

### Q：这条链路里哪些地方是关键，不允许散到别处？

A：关键收口点如下：

1. history 转 Runtime messages：只能在 `ChatOrchestrator`
2. tool 定义过滤和 tool loop：只能在 `ChatOrchestrator`
3. 模型解析和本地/云端路由：只能在 `AIRuntimeService`
4. provider 请求体、SSE、reasoning payload：只能在 gateway
5. side effect 落库：只能在 `MessageRunActor`

## 7.2 单次任务链路的落地流程

### Q：像知识润色、营养图片描述、医疗抽取这类非聊天任务，推荐流程是什么？

A：这类统一使用 `UseCase/Infrastructure -> AIRuntimeServing`：

```text
Page / ViewModel
  ↓
Feature UseCase
  ↓
构造 AIRuntimeTextRequest
  - scenario
  - messages
  - reasoning
  - preferredModelName
  - cancellationToken
  ↓
runtime.generateTextStream(request:)
  ↓
collectText / decode / parse structured output
  ↓
返回业务结果
```

### Q：这条链路允许 Feature 做什么，不允许做什么？

A：允许做：

1. 构造业务 prompt
2. 组装 `AIRuntimeTextRequest`
3. 把 `AIRuntimeStreamEvent` 汇总为文本或结构化结果

不允许做：

1. 自己 resolve provider / apiKey / endpoint
2. 自己判断本地模型还是云端模型
3. 自己 new gateway 或 client
4. 自己解析厂商特定 SSE 协议

## 7.3 装配层流程

### Q：依赖注入应该怎么落地？

A：所有 AI 基础设施只从 `AssemblyProducts` 装配一次，再注入到 Feature：

```text
AppContainer
  ↓
AssemblyProducts.makeCore(...)
  ↓
AIConfigCenter
OpenAICompatibleTextGateway
LocalGGUFTextGateway
AIRuntimeService
ChatOrchestrator
  ↓
Feature UseCase / ViewModel 注入
```

不允许在 Feature 内部再次创建上述对象。

## 8. 详细代码对齐点

### Q：`AssemblyProducts` 需要承担什么职责？

A：它应继续作为唯一装配根，统一创建 Runtime 相关对象，不允许 Feature 私自创建。

当前对齐代码：

```swift
let aiRuntimeGateway = OpenAICompatibleTextGateway(logger: logger)
let localRuntimeGateway = LocalGGUFTextGateway(
    localModelService: localModelService,
    logger: logger
)
let aiRuntimeService = AIRuntimeService(
    configCenter: aiConfigCenter,
    gateway: aiRuntimeGateway,
    localGateway: localRuntimeGateway,
    logger: logger
)
```

代码位置：

- [AssemblyProducts.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/App/Sources/App/Architecture/AssemblyProducts.swift)

### Q：`AIRuntimeService` 需要继续收口哪些逻辑？

A：它是最低统一入口，必须继续独占以下逻辑：

1. `AIConfigCenter.resolve`
2. 本地 / 云端模型路由
3. 模型是否支持 tools 的降级
4. 输出日志和耗时
5. cancellation 透传

当前对齐代码：

```swift
let resolved = try await configCenter.resolve(
    for: request.scenario,
    preferredModelName: request.preferredModelName
)

if let localSelection = resolveLocalModelSelection(modelName: resolved.model, allRows: allRows) {
    return try await localGateway.generateTextStream(...)
}

let upstream = try await gateway.generateTextStream(
    client: client,
    request: ...
)
```

代码位置：

- [AIRuntimeService.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/AIRuntimeService.swift)

### Q：`ChatOrchestrator` 的职责边界是什么？

A：它不是所有 AI 的统一入口，但它是所有聊天型 AI 的统一入口，职责应保持在：

1. 历史转 Runtime messages
2. tool list 过滤
3. 多轮 tool call loop
4. partial delta 汇总
5. 输出 block 构建

当前对齐代码：

```swift
collected = try await collectRuntimeResponse(
    from: try await runtimeService.generateTextStream(
        request: AIRuntimeTextRequest(
            scenario: .chat,
            messages: loopMessages,
            tools: activeToolDefinitions,
            toolChoice: activeToolChoice,
            reasoning: reasoningOpts,
            preferredModelName: preferredModelName,
            providerCompanyUppercased: providerCompanyUppercased,
            temperature: temperature,
            topP: topP,
            maxTokens: maxTokens,
            cancellationToken: cancellationToken
        )
    ),
    cancellationToken: cancellationToken,
    onPartial: onPartial
)
```

代码位置：

- [ChatOrchestrator.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ChatOrchestrator.swift)

### Q：Feature 层应该怎么调用？

A：Feature 层只依赖 UseCase 或 Runtime 协议，不依赖 gateway。

正确示例一：聊天发送走 `ChatOrchestrator`

```swift
let output = try await orchestrator.generateReply(
    userInput: userQuestionForAI,
    history: history,
    memberContextSummary: memberContextSummary,
    memberID: memberID,
    threadID: threadID,
    inference: effectiveInference,
    preferredModelName: preferredModelName,
    cancellationToken: cancellationToken,
    onPartial: onPartial,
    messageRunActor: messageRunActor
)
```

正确示例二：单次任务走 `AIRuntimeServing`

```swift
let stream = try await runtime.generateTextStream(
    request: AIRuntimeTextRequest(
        scenario: .optimizationText,
        messages: messages,
        preferredModelName: preferredModelName,
        cancellationToken: cancellationToken
    )
)
```

错误示例：Feature 直接构造 gateway

```swift
let gateway = OpenAICompatibleTextGateway(logger: logger)
let client = AIClientFactory.makeClient(...)
let stream = try await gateway.generateTextStream(client: client, request: request)
```

上述错误示例不允许出现在 Feature、ViewModel、页面层。

### Q：当前哪些现有代码可以直接当作“新架构落地样板”？

A：建议把下面几处当作基准实现，后续新能力按这个口径对齐：

1. 聊天统一入口样板：
   [SendChatMessageUseCase.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Application/SendChatMessageUseCase.swift)
2. 单次任务统一入口样板：
   [KnowledgeTextProcessingUseCases.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Knowledge/Application/KnowledgeTextProcessingUseCases.swift)
3. 多模态单次任务样板：
   [NutritionFoodImageDescriber.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Nutrition/Application/Recognition/NutritionFoodImageDescriber.swift)
4. Runtime 下游网关样板：
   [OpenAICompatibleTextGateway.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/OpenAICompatibleTextGateway.swift)

## 9. 关键落地细节

### Q：真正落地时，最容易做错的细节有哪些？

A：最容易出问题的是下面 8 个点：

1. `ViewModel` 偷偷开始持有 `AIRuntimeTextRequest` 细节，后面又变成第二套编排层。
2. 新功能为省事，直接在 Feature 里拼 `AIClientFactory`。
3. 非聊天能力开始复制 `collectRuntimeResponse`、partial、tool loop 逻辑。
4. 页面层为了做 loading/cancel，直接操作 gateway 层任务。
5. 本地模型可用性判断散落到 Feature，而不是由 Runtime 统一报错。
6. 同一类错误在聊天和非聊天链路里返回格式不同。
7. 工具降级规则有的在 Runtime，有的在 Orchestrator，有的在 Feature。
8. 装配根之外出现第二个 `OpenAICompatibleTextGateway` 或第二个 `LocalGGUFTextGateway` 创建点。

### Q：这次工单建议配套做哪些小收口？

A：建议顺手做以下工程收口，但不扩大成大重构：

1. 给 `AIRuntimeArchitectureGateTests` 增加禁止符号扫描
2. 在 AI 新需求模板里追加“入口选择反问”
3. 在总领文档中加入“统一入口”一节，作为团队约定
4. 对新的 AI Feature，优先新增 `UseCase`，而不是直接在 ViewModel 中拼 request

## 10. 实施阶段建议

### Q：具体落地分几步做最稳？

A：建议分四步。

1. 文档阶段
   明确规则、边界、反问和目标流程。
2. 门禁阶段
   新增 `AIRuntimeArchitectureGateTests`，先把错误写法堵住。
3. 收口阶段
   扫描 Feature 层是否有 gateway/client/provider 细节泄漏，逐一收回 Runtime。
4. 增量阶段
   后续每个新 AI 功能都按“聊天入口”或“单次任务入口”二选一接入。

## 11. 需要新增的门禁测试

### Q：怎样防止后面又绕回去？

A：建议新增一个 AI 架构门禁测试，扫描以下目录，禁止直接出现 runtime 下游实现类引用：

- `SparkClient/Projects/Features`
- `SparkClient/Projects/App/Sources/App` 中除装配根之外的业务文件

建议禁止符号：

```text
OpenAICompatibleTextGateway
LocalGGUFTextGateway
AIClientFactory
URLSession.bytes(
/v1/chat/completions
generateTextStream(client:
```

允许例外文件：

1. `AssemblyProducts.swift`
2. `AIRuntimeService.swift`
3. `OpenAICompatibleTextGateway.swift`
4. `LocalGGUFTextGateway.swift`
5. Runtime 层测试文件

建议测试命名：

- `AIRuntimeArchitectureGateTests.swift`

## 12. 验收标准

### Q：这次工单完成后，怎么判定达标？

A：验收标准如下：

1. 页面层和 ViewModel 不直接 new gateway、provider client、HTTP AI 请求。
2. 聊天发送链路统一走 `SendChatMessageUseCase -> ChatOrchestrator -> AIRuntimeService`。
3. 非聊天 AI 任务统一通过注入的 `AIRuntimeServing` 触发，不绕过 Runtime。
4. 本地 / 云端模型路由、tool 降级、reasoning payload、SSE 解析仍只在 Runtime 层。
5. 新增 AI 能力工单必须回答“走哪个统一入口”。
6. 新增架构门禁测试后，Feature 层引入 gateway / provider 细节会直接测试失败。

## 13. 实施建议

### Q：落地顺序建议是什么？

A：建议按以下顺序实施：

1. 先补文档和门禁测试，明确规则，防止继续扩散。
2. 再扫描并收束现有 Feature 的请求组包位置，确认页面层不持有 LLM 细节。
3. 最后再推进后续 AI 能力时，统一按本工单执行入口选择。

### Q：这次工单不建议做什么？

A：不建议在本工单内做以下过度改造：

1. 不把所有非聊天任务都强制改走 `ChatOrchestrator`
2. 不引入一个比 `AIRuntimeService` 更重的新总线，只为追求形式统一
3. 不在本工单内重构全部 prompt 设计、工具协议或消息模型

本工单聚焦的是**入口统一和边界收口**，不是一次性重做整个 AI 系统。

## 14. 统一 Runtime 协议细化

### Q：这次重构真正统一的是什么？

A：统一的是三件事：

1. 请求协议
2. 流式事件协议
3. 入口边界

也就是说，业务层以后不再自己发明“我自己的 LLM 交互方式”，而是统一包成 `AIRuntimeTextRequest`，统一收回 `AIRuntimeStreamEvent`。

### Q：这套协议和 DeepTutor 的对应关系是什么？

A：可以直接对照成下面这张表：

| DeepTutor | SparkClient |
| --- | --- |
| `UnifiedContext` | `AIRuntimeTextRequest` + 聊天上下文参数集合 |
| `StreamEvent` | `AIRuntimeStreamEvent` |
| `StreamBus` | `AsyncThrowingStream<AIRuntimeStreamEvent, Error>` |
| `ChatOrchestrator` | `ChatOrchestrator` |
| `TurnRuntimeManager` | 聊天发送运行时 + `MessageRunActor` + 线程生命周期管理 |

### Q：请求协议需要包含哪些字段？

A：建议把以下字段视为 Runtime 协议的稳定输入：

```swift
struct AIRuntimeTextRequest {
    let scenario: AIScenario
    let messages: [AIRuntimeMessage]
    let tools: [AIRuntimeToolDefinition]
    let toolChoice: AIRuntimeToolChoice
    let reasoning: AIRuntimeReasoningOptions
    let preferredModelName: String?
    let providerCompanyUppercased: String?
    let temperature: Double?
    let topP: Double?
    let maxTokens: Int?
    let cancellationToken: AIRuntimeCancellationToken?
}
```

### Q：事件协议需要包含哪些字段？

A：建议统一成以下语义顺序：

1. `textDelta`
2. `reasoningDelta`
3. `toolCallDelta`
4. `completed`

这样后续聊天、问报告、知识问答、结构化抽取都能消费同一套流。

### Q：现有代码里这些协议在哪？

A：对应代码主要在：

- [AIRuntimeModels.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/AIRuntimeModels.swift)
- [AIRuntimeService.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/AIRuntimeService.swift)
- [ChatOrchestrator.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ChatOrchestrator.swift)

## 15. 需要替换、删除和禁止新增的代码

### Q：这次重构要替换什么？

A：替换对象不是 UI，而是“绕过 Runtime 的写法”。

#### 15.1 必须替换的旧调用方式

| 旧方式 | 替换成 | 原因 |
| --- | --- | --- |
| 页面 / ViewModel 自己拼 LLM 请求 | `AIRuntimeServing.generateTextStream(request:)` | 避免业务层理解 provider、SSE、reasoning、降级 |
| 聊天逻辑直接调网关 | `SendChatMessageUseCase -> ChatOrchestrator` | 避免多轮工具回灌散落在 feature 中 |
| 非聊天任务直接调 provider | `AIRuntimeService` | 保证模型路由、取消、日志统一 |
| 工具结果直接改 UI 状态 | `MessageRunActor` | 保证串行落库和可回放 |

#### 15.2 需要删除或禁止新增的代码形态

以下代码一旦再次出现在 Feature 层，应视为回退：

- `new OpenAICompatibleTextGateway(...)`
- `new LocalGGUFTextGateway(...)`
- `AIClientFactory.makeClient(...)`
- `URLSession.bytes(`
- `/v1/chat/completions`
- 自己写 SSE parser
- 自己写 reasoning payload builder
- 自己写 tool loop

#### 15.3 需要收口的职责

| 职责 | 应收口到哪里 |
| --- | --- |
| 模型选择 / 场景解析 | `AIConfigCenter` / `ScenarioPolicyResolver` |
| 本地 / 云端路由 | `AIRuntimeService` |
| 多轮聊天 / 工具循环 | `ChatOrchestrator` |
| 工具执行 / 审计 | `ToolHub` |
| 工具副作用落库 | `MessageRunActor` |
| UI 进度展示 | Presentation 层 |

### Q：这些代码要重点排查哪些文件？

A：优先排查以下位置：

- [AssemblyProducts.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/App/Sources/App/Architecture/AssemblyProducts.swift)
- [AIRuntimeService.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/AIRuntimeService.swift)
- [ChatOrchestrator.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ChatOrchestrator.swift)
- [SendChatMessageUseCase.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Application/SendChatMessageUseCase.swift)
- [MessageRunActor.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Application/MessageRunActor.swift)
- [ToolHub.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ToolHub/ToolHub.swift)
- [AISettingsAndResolverTests.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Tests/AI/AISettingsAndResolverTests.swift)

## 16. 新架构流程

### Q：重构后的主流程长什么样？

A：建议按下面的主链路执行：

```text
用户点击发送 / 业务 feature 发起 AI 请求
  ↓
Feature 只组装业务入参，不碰 provider / HTTP
  ↓
进入 AIRuntimeServing.generateTextStream(request:)
  ↓
AIConfigCenter 解析场景、模型、Key、来源、override
  ↓
AIRuntimeService 决定本地 / 云端，并统一做 tools 降级
  ↓
流式事件回传给上层
  ↓
聊天场景进入 ChatOrchestrator 做多轮 tool loop
  ↓
工具执行交给 ToolHub
  ↓
副作用和消息块写入交给 MessageRunActor
  ↓
UI 只消费最终事件和持久化结果
```

### Q：聊天和非聊天怎么分流？

A：

- 聊天、多轮工具、问用户、知识检索、模型反复回灌：走 `ChatOrchestrator`
- 单次抽取、结构化识别、文本润色、医疗解读、营养识别：走 `AIRuntimeService`

### Q：工具调用放哪一层最合适？

A：工具调用必须放在 Runtime 的编排层和工具层，不允许下沉到页面和 ViewModel。

推荐链路：

```text
ChatOrchestrator
  → 判断是否需要工具
  → ToolHub.runIfNeeded / executeToolCall
  → ToolHub 执行工具
  → 返回 ToolExecutionResult
  → MessageRunActor 串行写库
  → UI 通过消息投影展示
```

## 17. 关键代码示例

### 17.1 统一装配根

```swift
let aiRuntimeGateway = OpenAICompatibleTextGateway(logger: logger)
let localRuntimeGateway = LocalGGUFTextGateway(
    localModelService: localModelService,
    logger: logger
)
let aiRuntimeService = AIRuntimeService(
    configCenter: aiConfigCenter,
    gateway: aiRuntimeGateway,
    localGateway: localRuntimeGateway,
    logger: logger
)
```

对齐文件：

- [AssemblyProducts.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/App/Sources/App/Architecture/AssemblyProducts.swift)

### 17.2 统一 Runtime 协议入口

```swift
protocol AIRuntimeServing: Sendable {
    func generateTextStream(
        request: AIRuntimeTextRequest
    ) async throws -> AsyncThrowingStream<AIRuntimeStreamEvent, Error>
}
```

对齐文件：

- [AIRuntimeService.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/AIRuntimeService.swift)

### 17.3 聊天编排入口

```swift
let output = try await orchestrator.generateReply(
    userInput: userQuestionForAI,
    history: history,
    memberContextSummary: memberContextSummary,
    memberID: memberID,
    threadID: threadID,
    inference: effectiveInference,
    preferredModelName: preferredModelName,
    cancellationToken: cancellationToken,
    onPartial: onPartial,
    messageRunActor: messageRunActor
)
```

对齐文件：

- [ChatOrchestrator.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ChatOrchestrator.swift)

### 17.4 单次任务调用入口

```swift
let stream = try await runtime.generateTextStream(
    request: AIRuntimeTextRequest(
        scenario: .optimizationText,
        messages: messages,
        preferredModelName: preferredModelName,
        cancellationToken: cancellationToken
    )
)
```

对齐文件：

- [AIRuntimeModels.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/AIRuntimeModels.swift)

## 18. 需要新增的门禁测试

### Q：怎么防止以后再绕回去？

A：至少要补两层门禁：

#### 18.1 代码引用门禁

建议在 `SparkClient/Projects/Features` 扫描以下符号：

- `OpenAICompatibleTextGateway`
- `LocalGGUFTextGateway`
- `AIClientFactory`
- `URLSession.bytes(`
- `/v1/chat/completions`
- `generateTextStream(client:`

允许例外：

1. `AssemblyProducts.swift`
2. `AIRuntimeService.swift`
3. `OpenAICompatibleTextGateway.swift`
4. `LocalGGUFTextGateway.swift`
5. Runtime 层测试文件

#### 18.2 场景行为门禁

建议新增以下测试：

1. `AIRuntimeService` 空消息报错
2. 模型不支持 tools 时自动降级
3. `ChatOrchestrator` 仅消费 Runtime 事件，不直接依赖 gateway
4. `ChatOrchestrator` tool loop 最多 30 轮且可取消
5. `AssemblyProducts` 是唯一装配入口

建议测试文件名：

- `AIRuntimeArchitectureGateTests.swift`
- `AIRuntimeProtocolTests.swift`
- `ChatOrchestratorContractTests.swift`

## 19. 验收标准

### Q：什么时候算真正完成？

A：满足下面条件才算完成：

1. 页面层和 ViewModel 不直接 new gateway、provider client、HTTP AI 请求。
2. 聊天发送链路统一走 `SendChatMessageUseCase -> ChatOrchestrator -> AIRuntimeService`。
3. 非聊天 AI 任务统一通过注入的 `AIRuntimeServing` 触发，不绕过 Runtime。
4. 本地 / 云端模型路由、tool 降级、reasoning payload、SSE 解析仍只在 Runtime 层。
5. 新增 AI 能力工单必须回答“走哪个统一入口”。
6. 新增架构门禁测试后，Feature 层引入 gateway / provider 细节会直接测试失败。

### Q：最终交付物是什么？

A：

1. 一份清楚的 AI 单链路重构需求文档。
2. 一份替换 / 删除清单。
3. 一组架构门禁测试。
4. 一个可以继续承接聊天、问报告、知识问答、健康摘要的统一 Runtime 主干。

## 20. 能力层和工具层分离

### Q：为什么要把 Capability 和 Tool 分开？

A：因为它们解决的是两种完全不同的问题：

- `Capability` 解决“这次要做什么”
- `Tool` 解决“这件事具体怎么做”

如果这两层混在一起，最后通常会变成：

1. 工具知道太多业务意图
2. 业务能力知道太多工具细节
3. UI 知道太多执行路径
4. 后续扩展时只能继续加 if/else

DeepTutor 的价值就在于，它把这条线切得比较干净。SparkClient 也应该继续朝这个方向收口。

### Q：SparkClient 现在对应的能力层和工具层分别是什么？

A：可以先按现状这样理解：

#### 能力层

能力层负责“任务编排”和“策略选择”，现有代码主要落在这些地方：

- [ChatOrchestrator.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ChatOrchestrator.swift)
- [ChatOrchestratorInferenceOptions.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ChatOrchestratorInferenceOptions.swift)
- [SendChatMessageUseCase.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Application/SendChatMessageUseCase.swift)
- [ChatComposerRuntimeFlags.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Domain/ChatComposerRuntimeFlags.swift)

这些位置负责：

1. 决定当前是不是聊天、多轮、问报告、知识检索、小任务
2. 决定是否允许 tools / knowledge / web search
3. 决定工具白名单
4. 决定是否进入多轮 tool loop
5. 决定是否要把请求交给 `ChatOrchestrator`

#### 工具层

工具层负责“原子动作”和“副作用执行”，现有代码主要落在这些地方：

- [ToolHub.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ToolHub/ToolHub.swift)
- [ToolingModels.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ToolHub/Models/ToolingModels.swift)
- [ToolHubTaskModels.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ToolHub/ToolHubTaskModels.swift)

这些位置负责：

1. 把工具暴露成 schema
2. 解析 tool_call 参数
3. 执行单个工具
4. 做 Consent / 审计
5. 产出 `ToolExecutionResult` 和 `ToolSideEffect`

### Q：现在代码里这条边界是怎么体现的？

A：从现有实现看，边界已经有雏形，但还没有完全“硬化”。

#### 已经比较正确的部分

1. `ChatOrchestrator` 负责 `useTools / useKnowledgeBag / useWebSearch` 这种策略判断。
2. `ToolHub` 负责具体工具执行，不直接承担聊天多轮编排。
3. `ChatOrchestrator` 负责把模型的 `tool_calls` 回灌成下一轮消息。
4. `MessageRunActor` 负责工具副作用的串行落库。

#### 还需要继续收口的部分

1. `ChatOrchestrator` 里已经有一部分工具过滤逻辑，还可以继续抽成更明确的 capability policy。
2. `SendChatMessageUseCase` 里负责选择工具白名单和任务工具集合，这部分应该明确标记为“能力策略组装”，不能下沉进 ToolHub。
3. `ToolHub` 只应该知道“怎么执行工具”，不应该知道“这个工具属于哪个能力策略层级”。

### Q：建议的分层模型是什么？

A：建议采用下面这三层：

```text
Capability Layer
  → 决定任务、策略、白名单、是否启用 tools
  → 例如：chat / question / report / knowledge / task

Runtime Layer
  → 统一请求协议、流式事件、模型路由、tool loop
  → 例如：AIRuntimeService / ChatOrchestrator

Tool Layer
  → 单个原子动作执行、Consent、审计、副作用
  → 例如：ToolHub / Executors / ToolSideEffect
```

可以把它理解成：

- Capability：我想让系统做什么
- Runtime：我怎么组织这次执行
- Tool：每一步具体干什么

### Q：SparkClient 里哪些地方应该保持在 Capability 层？

A：这些应该保持在能力层，不要挪到工具层：

1. `ChatOrchestratorInferenceOptions.useTools`
2. `ChatOrchestratorInferenceOptions.useKnowledgeBag`
3. `ChatOrchestratorInferenceOptions.useWebSearch`
4. `ChatOrchestratorInferenceOptions.allowedToolNames`
5. `SendChatMessageUseCase` 根据模型、小任务、场景生成的 tool whitelist
6. Composer 里对“本轮允许什么能力”的 UI 开关

### Q：哪些东西不应该放进 Tool 层？

A：以下内容不应该出现在 `ToolHub` 里：

1. 聊天多轮循环
2. `AIRuntimeTextRequest` 的生成逻辑
3. knowledge / web search 的场景策略判断
4. Composer 的 UI 开关读取
5. ChatMessage 的 UI 投影逻辑
6. 模型是否支持 reasoning / tool 的全局策略判断

`ToolHub` 的职责应该尽量保持成：

```text
输入 tool 名称 + 参数
  ↓
校验 / Consent / 审计
  ↓
执行单个工具
  ↓
返回 ToolExecutionResult / ToolSideEffect
```

### Q：这次重构要替换哪些耦合？

A：重点替换下面这些耦合关系：

| 旧耦合 | 新关系 | 为什么要改 |
| --- | --- | --- |
| `ToolHub` 参与太多策略判断 | `ChatOrchestrator` / capability policy 负责策略，`ToolHub` 只执行 | 避免工具层混入编排逻辑 |
| `ViewModel` 直接决定工具白名单 | `SendChatMessageUseCase` 或 capability policy 统一生成 | 避免 UI 层越权 |
| 工具执行与消息落库绑在一起 | `ToolHub` + `MessageRunActor` 分离 | 保证工具层纯执行、消息层纯落库 |
| 知识、搜索、工具、聊天混用同一段逻辑 | 按 capability / runtime / tool 三层拆分 | 方便后续扩展 |

### Q：哪些代码建议继续删掉或禁止回流？

A：如果未来改造中出现这些写法，应尽量删掉或禁止新增：

- 在 `ToolHub` 里判断“这是 chat 还是 knowledge 还是 report”
- 在 `ToolHub` 里读取 Composer runtime 开关
- 在 `ToolHub` 里决定某个工具是否属于本轮能力策略
- 在 `ViewModel` 里直接拼工具调用列表
- 在页面层直接组装 `AIRuntimeToolDefinition`

### Q：新的执行流程应该是什么？

A：推荐的流程如下：

```text
1. UI 选择能力开关 / 场景
2. Feature / UseCase 组装 capability policy
3. `ChatOrchestrator` 接收请求
4. `ChatOrchestrator` 过滤工具列表并组装 `AIRuntimeTextRequest`
5. `AIRuntimeService` 执行本轮模型推理
6. 模型返回 `tool_calls`
7. `ChatOrchestrator` 交给 `ToolHub.executeToolCall`
8. `ToolHub` 执行工具并返回 side effects
9. `MessageRunActor` 串行落库 side effects
10. UI 只消费最终事件和消息投影
```

### Q：如果后续要真的抽出 Capability 接口，应该长什么样？

A：现在不一定要马上新增一个硬接口，但如果后续要继续演进，建议把它定义成“策略对象”，而不是再做一个大而全的总线。

概念上可以是这样：

```swift
protocol CapabilityStrategy {
    var name: String { get }
    func buildInferenceOptions() -> ChatOrchestratorInferenceOptions
    func buildRuntimeMessages(...) async -> [AIRuntimeMessage]
    func allowedToolNames() -> Set<String>?
}
```

这个接口的目标不是马上落代码，而是明确：

1. capability 负责策略
2. runtime 负责执行
3. tool 负责原子动作

### Q：这一层拆分对 SparkClient 的直接收益是什么？

A：

1. 新能力更容易扩展，不用每次都复制一套请求逻辑。
2. 工具可以复用，不会被某一个业务场景绑死。
3. 权限、审计、白名单更容易统一做。
4. UI 配置更清晰，页面只关心“本轮允许什么能力”。
5. 后续要做问报告、健康抽取、知识问答、任务生成时，能复用同一条 Runtime 主链路。

## 21. 实施记录

### 实施日期

2026-08-05

### 已完成项

1. **Guest 聊天迁移**：删除 `OpenAICompatibleGuestAIChatClient`（Feature 层手写 HTTP），新增 `GuestAIRuntimeChatClient`（`Core/AIRuntime/`，复用 `AIRuntimeGateway`）。
2. **Embedding 归位**：`OpenAICompatibleEmbeddingClient` 从 `Features/Knowledge/Infrastructure/` 移至 `Core/AIRuntime/`。
3. **装配收口**：`AssemblyProducts` / `AppContainer` 新增 `guestAIChatClient` 装配与注入；`GuestChatViewModel` 去掉默认构造，改为外部注入。
4. **架构门禁**：新增 `AIRuntimeArchitectureGateTests.swift`，扫描 Feature / App 层禁止 gateway / client 引用。
5. **单测补充**：新增 `GuestAIRuntimeChatClientTests.swift`（无效配置、成功收集、错误映射）。
6. **文档更新**：总领文档补充「统一入口与单链路约束」「禁止绕过 Runtime」章节。

### 变更文件清单

| 操作 | 文件 |
| --- | --- |
| 新增 | `Core/AIRuntime/GuestAIRuntimeChatClient.swift` |
| 新增 | `Core/AIRuntime/OpenAICompatibleEmbeddingClient.swift`（从 Knowledge 迁入） |
| 新增 | `Tests/AI/AIRuntimeArchitectureGateTests.swift` |
| 新增 | `Tests/AI/GuestAIRuntimeChatClientTests.swift` |
| 删除 | `Features/Chat/Presentation/Guest/OpenAICompatibleGuestAIChatClient.swift` |
| 删除 | `Features/Knowledge/Infrastructure/OpenAICompatibleEmbeddingClient.swift` |
| 修改 | `AssemblyProducts.swift`、`AppContainer.swift` |
| 修改 | `GuestChatViewModel.swift`、`GuestChatView.swift` |
| 修改 | 总领文档 2 份 |
