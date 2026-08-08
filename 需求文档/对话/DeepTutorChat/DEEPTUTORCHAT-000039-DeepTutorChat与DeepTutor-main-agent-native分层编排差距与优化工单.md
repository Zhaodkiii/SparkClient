# DEEPTUTORCHAT-000039 DeepTutorChat 与 DeepTutor-main agent-native 分层编排差距与优化工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000039 |
| 工单类型 | P1 架构对齐 / Agent-Native 分层编排优化 / DeepTutorChat 对标 DeepTutor-main |
| 当前范围 | 只创建需求 / 架构优化工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标功能目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| 对标项目 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main` |
| 创建日期 | 2026-08-07 |
| 触发需求 | 用户要求分析 DeepTutorChat 与 DeepTutor-main 的 agent-native 分层编排系统差距，并给出 DeepTutorChat 的优化方案 |
| 关联工单 | `DEEPTUTORCHAT-000022`、`DEEPTUTORCHAT-000024`、`DEEPTUTORCHAT-000037`、`DEEPTUTORCHAT-000038`、`DeepTutor-main/AGENTS.md`、`DeepTutor-main/README.md`、`DeepTutor-main/deeptutor_cli/README.md` |
| 核心约束 | 不把 DeepTutorChat 只当成聊天 UI；要把它当成一个 agent turn orchestration client 来优化，向 DeepTutor-main 的两层插件模型、统一编排器、流式事件与上下文门控靠拢 |

## 1. 背景

DeepTutor-main 已经把 agent-native 架构讲得很清楚：

```text
Tools = 单次调用的能力
Capabilities = 接管整轮对话的多阶段流水线
ChatOrchestrator = 统一入口
StreamBus = 共享流式事件总线
Context gating = 按上下文自动挂载工具
ask_user = 一等公民的人机澄清中断点
```

而 DeepTutorChat 目前虽然已经接入了共享的 `ChatOrchestrator`、`ChatOrchestratorInferenceOptions`、`ToolHub`、`ask_user`、成员选择、健康数据和天气等能力，但整体结构仍然偏“应用内专用对话页”，而不是完整的 agent-native turn 编排客户端。

当前 DeepTutorChat 的主要形态是：

```text
DeepTutorChatViewModel
  -> DeepTutorAIRuntimeAdapter
  -> DeepTutorRuntimeRequestBuilder
  -> DeepTutorPromptBuilder / DeepTutorPromptMerger
  -> DeepTutorToolPolicyResolver
  -> ChatOrchestrator
  -> ToolHub / AI Runtime
```

这条链路已经能跑，但相比 DeepTutor-main，仍然存在“能力编排层、工具层、事件层、上下文层、恢复层”边界不够清晰的问题。

## 2. DeepTutor-main 的基准能力

### 2.1 两层架构

DeepTutor-main 把系统拆成两层：

1. `Tools`：单次调用的能力。
2. `Capabilities`：接管整轮对话的多阶段流水线。

参考 [`AGENTS.md`](</Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/AGENTS.md#L5>)。

### 2.2 统一编排器

所有入口统一进入 `ChatOrchestrator`，由它把 `UnifiedContext` 路由到 selected capability，再执行工具与流式输出。

参考 [`AGENTS.md`](</Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/AGENTS.md#L12>)。

### 2.3 流式事件总线

所有 capability 通过共享 `StreamBus` 发事件，orchestrator fan out 给 CLI / Web / SDK。

参考 [`AGENTS.md`](</Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/AGENTS.md#L27>) 和 [`README.md`](</Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/README.md#L702>)。

### 2.4 上下文门控工具

工具不是全开，而是根据 KB、附件、sandbox、memory 等上下文自动挂载；`ask_user` 是暂停和恢复 turn 的正式路径。

参考 [`AGENTS.md`](</Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/AGENTS.md#L32>)。

### 2.5 多阶段 capability 流水线

`chat`、`deep_solve`、`deep_question`、`deep_research`、`visualize`、`math_animator` 都是阶段化 pipeline，而不是单轮 prompt。

参考 [`AGENTS.md`](</Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/AGENTS.md#L54>)。

### 2.6 可中断协作

`ask_user` 允许模型不瞎猜，先结构化追问，再继续同一 turn。

参考 [`AGENTS.md`](</Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/AGENTS.md#L44>)。

### 2.7 统一协议与入口

CLI / WebSocket / Python SDK 三入口共用同一套 runtime，`run` 还能输出 NDJSON 给另一个 agent 接管。

参考 [`README.md`](</Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/README.md#L680>)、[`deeptutor_cli/README.md`](</Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/deeptutor_cli/README.md#L48>)。

## 3. DeepTutorChat 当前状态

DeepTutorChat 已经具备一些 agent 运行要素：

```text
DeepTutorCapability
DeepTutorCapabilityToolManifest
DeepTutorToolPolicyResolver
DeepTutorPromptBuilder
DeepTutorPromptMerger
DeepTutorModelContextResolver
DeepTutorAIRuntimeAdapter
DeepTutorRequestSnapshot
ask_user / member_selection / health / weather / quiz / debug exporter
```

但这些能力更多是“堆在一条对话链路里”，还没有完全形成 DeepTutor-main 那种清晰的层次：

1. capability 层不够显式。
2. tools 层和 capability 层的边界还不够统一。
3. turn 的流式事件没有一个独立的总线语义。
4. 上下文门控更多是 `DeepTutorToolMountContext` 和 policy resolver 的内部实现，没有像 DeepTutor-main 那样形成对外可解释的体系。
5. 各种恢复路径、成员选择、ask_user、模型选择、问报告等逻辑虽然已有，但缺少一个统一的 turn 状态机与 turn envelope。

## 4. 差距分析

### 4.1 架构层差距

| 维度 | DeepTutor-main | DeepTutorChat 当前 | 差距 |
| --- | --- | --- | --- |
| 架构主线 | 两层插件模型，Capabilities 接管 turn | 以聊天页面和 DeepTutor 专属类串起一条发送链路 | 仍偏 UI 驱动，而不是 runtime 驱动 |
| 编排中心 | `ChatOrchestrator` + capability registry | `DeepTutorAIRuntimeAdapter` + `DeepTutorRuntimeRequestBuilder` + `DeepTutorToolPolicyResolver` | 编排逻辑分散在多个类里 |
| 工具体系 | 工具注册化、上下文门控、自动挂载 | 已有 manifest / policy，但更多是专用枚举和 switch | 工具层还不够目录化、协议化 |
| 流式输出 | `StreamBus` 统一 fan out | 主要依赖回调、消息落库和日志 | 缺少统一 turn event envelope |
| Prompt 管理 | prompt / capability prompts i18n 化、分层 | `DeepTutorPromptBuilder` / `DeepTutorPromptMerger` 代码化生成 | 提示词资产化程度不够 |
| 恢复机制 | turn 级恢复、NDJSON、session reuse | 有 ask_user/member_selection resume，但偏局部实现 | 缺少统一 turn snapshot 语义 |
| 入口统一 | CLI / Web / SDK | 只有 iOS 客户端对话页 | 对话运行能力没被做成同一抽象 |

### 4.2 DeepTutorChat 现有优点

DeepTutorChat 不是从零开始，它已经有这些基础：

1. 已接入共享的 `ChatOrchestrator`。
2. 已有 `DeepTutorToolPolicyResolver`，支持上下文门控。
3. 已有 `DeepTutorModelContextResolver`，能统一选择模型、agent、prompt 来源和参数。
4. 已有 `DeepTutorPromptMerger`，能把 agent / session / 默认 prompt 合并。
5. 已有 ask_user、member selection、quiz、health、weather 等 domain 级能力。
6. 已有 `requestSnapshot` 和 `DeepTutorDebugExporter`，具备 turn 追踪雏形。

所以这不是“有没有 agent”的问题，而是“agent-native 分层是否已经做到和 DeepTutor-main 一样清晰”的问题。

## 5. 具体差距

### 5.1 Capability 层不够显式

DeepTutor-main 的 capability 是一等公民，每个 capability 有自己的 stage pipeline。

DeepTutorChat 虽然也有：

- `DeepTutorCapability`
- `DeepTutorCapabilityToolManifest`
- `DeepTutorPromptBuilder`
- `DeepTutorToolPolicyResolver`

但当前更多体现为：

```text
聊天页里的模式开关 + 工具策略分支 + prompt 拼接
```

而不是：

```text
一个明确的 capability registry，统一承接 turn state、stage、prompt、tools、resume
```

### 5.2 工具层还偏“专用工具表”

DeepTutor-main 把工具放在统一 registry 语义下，并允许 context gating 自动挂载。

DeepTutorChat 当前工具层的问题是：

1. 工具与 capability 有绑定，但更像手写枚举和 policy。
2. 工具策略里混合了 capability、健康数据、天气、成员选择、问报告等多个域。
3. 缺少一个可复用的“工具分类 + 依赖 + 自动挂载 + 失效降级”框架。

### 5.3 Prompt 层已分层，但还不够资产化

DeepTutorChat 已有：

- `DeepTutorPromptBuilder`
- `DeepTutorPromptMerger`
- `DeepTutorModelContextResolver`

这比最初版本已经强很多，但仍有差距：

1. prompt 主要还是 Swift 代码内拼接。
2. capability 协议 addendum 还不是独立资产包。
3. i18n prompt、按 capability 的 prompt 段、按工具 availability 的 prompt 段，还没有完全变成可维护配置。

### 5.4 Turn 流式事件不够统一

DeepTutor-main 的 `StreamBus` 是“所有 capability 共用事件通道”。

DeepTutorChat 当前主要通过：

- `onAssistantUpdate`
- message upsert
- logger
- `DeepTutorMessageReducer`

来实现流式状态传播。

这能工作，但缺少一个独立的 turn event protocol，导致：

1. 流式状态和持久化状态耦合更重。
2. 调试信息和 UI 事件分散在多个层。
3. 后续要做 CLI / Web / SDK 式的统一消费不容易。

### 5.5 恢复链路是局部实现，不是 turn state machine

DeepTutorChat 已有：

- ask_user 恢复
- member selection 恢复
- snapshot 传递
- `DeepTutorGenerationSession`

但目前这些恢复主要是“在已有链路上补分支”，而不是一个统一的 turn lifecycle：

```text
start → stream → ask_user pause → resume → tool call → finalize
```

DeepTutor-main 的优势是整轮生命周期更清楚，恢复是 runtime 的一部分，不是补丁。

### 5.6 入口统一性不足

DeepTutor-main 提供 CLI / Web / SDK 三入口统一。

DeepTutorChat 是 iOS 客户端，天然不需要把 CLI/Web/SDK 全搬过来，但它可以更好地对齐“同一 runtime、多入口消费”的思想：

1. 当前对话页和 debug exporter 还不能像 `run --format json` 那样把 turn 结果完整导出。
2. 对话状态的能力、工具、模型、prompt、snapshot 没有形成统一的外部消费契约。

## 6. 优化目标

DeepTutorChat 的优化方向不是复制 DeepTutor-main 全仓库，而是把它已经有的 agent-native 思想补齐到 iOS 客户端侧的 turn 编排层。

### 6.1 短期目标

1. 把 DeepTutorChat 的“对话发送链路”收敛成一个清晰的 turn pipeline。
2. 把模型 / agent / prompt / tool / snapshot 的解析收口到统一解析对象。
3. 把 ask_user、member selection、quiz、健康、天气等分支变成可解释的 capability / tool policy。
4. 把流式输出和最终落库之间的边界梳理清楚。

### 6.2 中期目标

1. 把 capability 变成更明确的 registry / manifest 体系。
2. 把工具层进一步做成“上下文门控 + 自动挂载 + 失效降级”的统一模型。
3. 把 prompt 进一步资产化，降低代码里硬拼接的比例。
4. 把 turn snapshot 和 debug export 做成可回放、可审计的标准输出。

## 7. 优化方案

### 7.1 建议的目标架构

DeepTutorChat 建议演进为下面这条主线：

```text
DeepTutorChatViewModel
  -> DeepTutorTurnCoordinator
  -> DeepTutorModelContextResolver
  -> DeepTutorCapabilityResolver
  -> DeepTutorToolPolicyResolver
  -> DeepTutorPromptMerger
  -> ChatOrchestrator
  -> ToolHub / MessageRunActor / Turn Snapshot
```

这里的关键是：

1. 让“turn 编排”显式化。
2. 让“模型上下文”显式化。
3. 让“能力选择”显式化。
4. 让“工具白名单”显式化。
5. 让“流式事件”更靠近独立 protocol。

### 7.2 架构落点

#### 7.2.1 新增 turn coordinator

建议抽出 `DeepTutorTurnCoordinator`，负责以下职责：

1. 汇总 UI 输入、当前会话、selected model、capability、附件、成员、快照。
2. 调用 model context resolver。
3. 调用 capability / tool policy resolver。
4. 生成最终 prompt / inference / snapshot。
5. 交给 adapter 执行。

这样可以把现在散在 `SendDeepTutorAIMessageUseCase`、`DeepTutorAIRuntimeAdapter`、`DeepTutorRuntimeRequestBuilder` 里的逻辑往一个中心收。

#### 7.2.2 抽象统一 turn envelope

建议给 DeepTutorChat 增加一个 turn envelope，至少包含：

```text
selectedModel
selectedCapability
promptSource
finalAllowedTools
requestSnapshot
resumeMode
modelResolutionMode
```

这样 ask_user / member selection / regenerate / replay 都能共用一套 turn 元数据。

#### 7.2.3 补齐流式事件层

DeepTutor-main 的优势是 `StreamBus`。

DeepTutorChat 可以不直接复制同名实现，但至少应该抽一个：

```text
DeepTutorTurnEventBus
```

用于统一承载：

1. content delta
2. reasoning delta
3. tool call start / tool result / tool error
4. ask_user pause / resume
5. member selection pause / resume
6. final done / failed / cancelled

这样 UI、调试器、落库、回放会更一致。

#### 7.2.4 把工具策略拆成三层

当前 DeepTutorChat 的工具策略已经有雏形，但还可再清楚一点：

1. `capability` 负责定义本轮默认工具集合。
2. `context gating` 负责按成员、附件、位置、KB、天气、健康资源等上下文自动挂载或屏蔽。
3. `model whitelist` 负责与 AI Settings 中的模型/agent 配置求交集。

最终输出应该只有一个：

```text
finalAllowedTools
```

而不是多处各算一遍。

#### 7.2.5 Prompt 资产化

建议把 DeepTutorChat 的 prompt 再拆细：

1. persona prompt
2. capability protocol prompt
3. tool availability prompt
4. resume prompt
5. domain-specific prompt addon

这样做的好处是：

1. 更接近 DeepTutor-main 的 capability prompts 组织方式。
2. 更容易国际化。
3. 更容易做单元测试。

#### 7.2.6 Snapshot 标准化

DeepTutorChat 现在已经有 `DeepTutorRequestSnapshot`，这是一个很好的基础。

建议把它提升成真正的 turn 回放上下文，至少补齐：

1. selected model
2. selected capability
3. prompt source
4. final allowed tools
5. generation parameters
6. resume mode

这样可以更好地支持：

- regenerate
- retry
- ask_user resume
- member selection resume
- debug export

## 8. 现有代码对齐点

### 8.1 已对齐的部分

DeepTutorChat 其实已经不是“裸聊天”了，已有这些对齐点：

1. 共享 `ChatOrchestrator`。
2. 共享 `ChatOrchestratorInferenceOptions`。
3. 共享 `ToolHub`。
4. 有 `DeepTutorToolMountContext` 和 `DeepTutorToolPolicyResolver`。
5. 有 `DeepTutorModelContextResolver` 和 `DeepTutorPromptMerger`。
6. 有 `ask_user`、member selection、health / weather / quiz 等多域能力。

### 8.2 仍需补齐的部分

1. turn coordinator。
2. turn event bus。
3. capability registry / manifest 化的进一步抽象。
4. 更统一的 prompt 资产层。
5. 更标准的 snapshot / replay protocol。
6. 更接近 DeepTutor-main 的“单引擎多入口”消费方式。

## 9. 实施拆解

### 9.1 Phase 1: 收口 turn 解析

目标：

1. 把 model / capability / tool / prompt / snapshot 的解析收口到一个中心。
2. 减少 `SendDeepTutorAIMessageUseCase`、`DeepTutorAIRuntimeAdapter` 的重复逻辑。

建议文件：

- `Application/DeepTutorTurnCoordinator.swift`（新建）
- `Application/DeepTutorModelContextResolver.swift`
- `Application/DeepTutorPromptMerger.swift`
- `Application/DeepTutorToolPolicyResolver.swift`

### 9.2 Phase 2: 抽流式事件协议

目标：

1. 把 ask_user / member selection / tool call / response delta / done 统一成 turn event。
2. UI、debug exporter、落库都能消费同一事件序列。

建议文件：

- `Domain/DeepTutorTurnEvent.swift`（新建）
- `Application/DeepTutorTurnEventBus.swift`（新建）
- `Infrastructure/DeepTutorChatLogging.swift`

### 9.3 Phase 3: 能力与工具目录化

目标：

1. capability 更清晰地表达 stage。
2. 工具更清晰地表达 auto-mount / gated / forced / disabled。

建议文件：

- `Domain/DeepTutorCapability.swift`
- `Domain/DeepTutorCapabilityToolManifest.swift`
- `Application/DeepTutorToolPolicyResolver.swift`

### 9.4 Phase 4: Prompt 与 Snapshot 资产化

目标：

1. prompt 更易测试。
2. snapshot 更易回放。
3. 恢复链路更统一。

建议文件：

- `Application/DeepTutorPromptBuilder.swift`
- `Application/DeepTutorPromptMerger.swift`
- `Domain/DeepTutorMessageBlock.swift`
- `Application/DeepTutorAIRuntimeAdapter.swift`

### 9.5 Phase 5: UI/Debug 消费统一 turn

目标：

1. 输入栏模型/能力切换与 turn 解析一致。
2. debug 导出与 turn 状态一致。

建议文件：

- `Presentation/DeepTutorChatPage.swift`
- `Presentation/DeepTutorComposerView.swift`
- `Application/DeepTutorChatDebugExporter.swift`

## 10. 细化风险

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| 过度抽象 | 进度变慢，改动范围扩大 | 分阶段拆解，只先收口 turn 解析与事件协议 |
| 与现有 ChatOrchestrator 重叠 | 逻辑重复，维护困难 | DeepTutorChat 只做客户端编排，不重复造 runtime |
| turn event bus 侵入性强 | 现有 UI/落库改动大 | 先做轻量 wrapper，再逐步替换回调 |
| prompt 再拆分后出现语义漂移 | 回复风格变化 | 通过快照与单测固化 prompt 输出 |
| capability registry 化过头 | 复杂度上升 | 只对 DeepTutorChat 需要的能力做抽象，避免全局重写 |

## 11. 验收标准

### 11.1 架构验收

1. DeepTutorChat 的 turn 解析有单一入口，不再分散在多个层里重复判断。
2. 模型 / capability / tools / prompt / snapshot 的职责边界明确。
3. ask_user、member selection、健康、天气、quiz 的 turn 恢复路径统一。

### 11.2 行为验收

1. 同一个 turn 的重试、恢复、再生成都能保留同一模型与工具上下文。
2. 工具是否可用能从 context 和 policy 明确推导，而不是散落在各层手写判断。
3. UI、日志、debug export、落库四处看到的 turn 信息一致。

### 11.3 对标验收

1. DeepTutorChat 能更明确地体现“两层架构”：工具层与 capability 层。
2. DeepTutorChat 的 turn 生命周期更接近 DeepTutor-main 的 agent-native 思路。
3. DeepTutorChat 的流式和恢复机制更像一个 runtime client，而不是单纯聊天页面。

## 12. 结论

DeepTutor-main 的核心优势不是“功能更多”，而是：

```text
能力层和工具层分得清
turn 编排统一
流式事件统一
上下文门控统一
ask_user / resume 正式化
prompt / capability / tool registry 化
```

DeepTutorChat 已经具备不少基础能力，但现在更像“把这些能力做进了 iOS 对话页”，还没有完全达到 DeepTutor-main 那种 agent-native 分层编排的清晰度。

建议优化方向是：

1. 收口 turn 编排。
2. 抽象 turn 事件。
3. 强化 capability / tool 的分层与目录化。
4. 继续把 prompt、snapshot、resume、debug 资产化。

这样 DeepTutorChat 就能从“能对话”升级成“真正按 agent-native 方式运行的 iOS 对话客户端”。

## 13. 按文件拆分的改造清单

这一节是给研发排期用的，按“先收口编排，再统一事件，再资产化快照”的顺序拆。

### 13.1 第一组：先把 turn 编排收口

#### 13.1.1 `Application/DeepTutorChatViewModel.swift`

职责现状：

1. 负责输入状态、能力切换、附件、发送、恢复。
2. 现在已经承担了一部分 turn orchestration 的职责。

建议改造：

1. 新增 `turnCoordinator` 依赖，只保留 UI 状态管理。
2. `sendMessage()` 不再直接拼装请求，只负责收集输入并调用 coordinator。
3. `updateCapability(_:)` 只更新 UI 选择，不再参与工具策略计算。
4. `retry` / `regenerate` / `ask_user resume` 全部改成走统一的 turn coordinator。
5. 把 `state.currentRequestSnapshot` 的写入点收口到 coordinator 返回值。

目标结果：

```text
ViewModel = UI 状态与交互入口
Coordinator = turn 编排入口
```

#### 13.1.2 `Application/SendDeepTutorAIMessageUseCase.swift`

职责现状：

1. 构建 request snapshot。
2. 处理 retry / regenerate / ask_user / member_selection。
3. 调用 runtime adapter。

建议改造：

1. 将“构建 snapshot + 解析 model context + 解析 tool policy”迁出，交给 `DeepTutorTurnCoordinator`。
2. 这个 use case 只保留“执行请求”的职责。
3. 把 `buildRequestSnapshot(...)` 改成薄包装，或者直接废弃，避免和 coordinator 重复。
4. `retryAssistant(...)`、`regenerateAssistant(...)`、`submitAskUser(...)` 保留执行逻辑，但输入参数改成 `DeepTutorTurnPlan` 或 `DeepTutorTurnEnvelope`。

建议最终形态：

```text
Coordinator -> UseCase.execute(plan)
```

#### 13.1.3 `Application/DeepTutorRuntimeRequestBuilder.swift`

职责现状：

1. 汇总 model context、tool policy、prompt、inference。
2. 产出 `BuiltRequest`。

建议改造：

1. 保留为纯构建器，不再访问 repository 或 UI 状态。
2. `build(...)` 只接受“已经整理过的 turn 输入”，不要再自己猜 capability、snapshot、model。
3. 拆出一个更轻的 `finalize(...)` 结果供 coordinator 复用。
4. 所有日志输出保留在 builder 内，但日志只描述“已解析结果”，不再承担业务决策。

#### 13.1.4 `Application/DeepTutorAIRuntimeAdapter.swift`

职责现状：

1. 负责把 request 喂给 `ChatOrchestrator`。
2. 负责流式回调、工具调用、ask_user、成员选择恢复。

建议改造：

1. 保持它是 runtime 适配层，不要继续往里塞业务规则。
2. 新增 `eventBus` 或 `eventSink`，把 `onPartial` 映射为统一的 `DeepTutorStreamEvent`。
3. `resolveModelContext`、`resolveToolPolicy` 这些前置动作尽量外移到 coordinator。
4. `stream(...)`、`resumeStream(...)`、`memberSelectionResumeStream(...)` 的 request 参数统一成同一种 turn envelope。

### 13.2 第二组：把 turn 的状态和事件标准化

#### 13.2.1 `Domain/DeepTutorStreamEvent.swift`

职责现状：

1. 已经有 content delta、reasoning delta、tool call、ask_user、member selection、quiz、result、error。

建议改造：

1. 保持它作为唯一的 turn event 协议，不再再造另一套事件枚举。
2. 补充必要字段，例如：
   - `turnID`
   - `conversationID`
   - `capability`
   - `promptSource`
   - `modelName`
3. 给 event 增加稳定的序列化兼容策略，方便 debug export 和回放。

#### 13.2.2 `Domain/DeepTutorMessageBlock.swift`

职责现状：

1. `DeepTutorRequestSnapshot` 已经定义在这里。
2. 消息块和请求快照的落库结构在一起。

建议改造：

1. 扩展 `DeepTutorRequestSnapshot`，补充 turn 级字段：
   - `selectedCapability`
   - `selectedModelName`
   - `selectedModelIdentity`
   - `finalAllowedToolNames`
   - `resumeMode`
   - `promptSource`
   - `resolvedTemperature`
   - `resolvedMaxTokens`
2. 如果字段继续膨胀，可以再考虑把快照拆到独立文件，但第一阶段不必急着拆。

#### 13.2.3 `Domain/DeepTutorConversationState.swift`

职责现状：

1. 保存会话级别的 active capability、模型状态、输入状态。

建议改造：

1. 增加 turn 级别的临时状态引用位，例如 `activeTurnID`、`activeTurnMode`、`activeResumeReason`。
2. 把“会话状态”和“turn 状态”区分开，避免一个 state 同时承载两种生命周期。

#### 13.2.4 `Domain/DeepTutorPerTurnToolSnapshot.swift`

职责现状：

1. 已记录本轮工具请求、解析、策略、阶段信息。

建议改造：

1. 让它成为 `requestSnapshot.toolSnapshot` 的核心来源。
2. 补上 `promptSource`、`finalAllowedToolNames`、`resumeMode` 的摘要字段。
3. 保证它能完整驱动 debug export。

### 13.3 第三组：把 capability 和工具层拆得更清楚

#### 13.3.1 `Domain/DeepTutorCapability.swift`

建议改造：

1. 为 capability 增加 stage 元信息，比如：
   - `stages`
   - `defaultToolPhase`
   - `supportsResume`
   - `supportsMemberSelection`
2. 让 capability 不只是一个枚举值，而是 turn 编排的入口标识。

#### 13.3.2 `Domain/DeepTutorCapabilityToolManifest.swift`

建议改造：

1. 明确区分三类工具：
   - capability owned tools
   - optional tools
   - exclusive tools
2. 给每个 capability 写清楚“默认可见工具”和“上下文触发工具”。
3. 补 `manifest(for:)` 的测试样例，确保不同 capability 的工具边界稳定。

#### 13.3.3 `Application/DeepTutorToolPolicyResolver.swift`

建议改造：

1. 保留为“上下文门控 + 工具合并”的唯一入口。
2. 把 policy 拆成三个清晰步骤：
   - intent 识别
   - capability 默认工具挂载
   - model whitelist 交集
3. 把 `resolveForAskUserResume`、`resolveForMemberSelectionResume` 继续保留，但输出字段要更明确标记 resume 语义。
4. 建议补一个 `DeepTutorToolPolicyDecision` 结构，方便 debug 和日志统一读取原因。

#### 13.3.4 `Application/DeepTutorDomainToolExtensionResolver.swift`

建议改造：

1. 这里应该只处理 domain 级扩展，不要混入通用工具逻辑。
2. 每个 domain extension 最好有独立的 eligibility reason，便于追踪为什么挂载成功或失败。

#### 13.3.5 `Application/DeepTutorToolIntentHints.swift`

建议改造：

1. 保持它只做“提示词意图检测”。
2. 如果后续 intent 越来越多，建议把 health、weather、member selection 这些分域 intent 提到更明确的 classifier。

### 13.4 第四组：把 prompt 资产化

#### 13.4.1 `Application/DeepTutorPromptBuilder.swift`

建议改造：

1. 把 prompt 拆成几个稳定段：
   - persona prompt
   - capability protocol addendum
   - tool availability note
   - resume addendum
   - domain addon
2. 每个 prompt 段独立生成，最后统一拼接。
3. 所有“硬编码长段落”尽量收敛到少数 builder 方法，减少散落在别的类里的字符串。

#### 13.4.2 `Application/DeepTutorPromptMerger.swift`

建议改造：

1. 保持它作为 prompt 合并总入口。
2. 让 `promptSource` 的选择逻辑和 `DeepTutorModelContextResolver` 完全一致。
3. 把 `agent / session / default` 三条路的输出差异压到最少。

#### 13.4.3 `Application/DeepTutorPromptSchemaConsistencyChecker.swift`

建议改造：

1. 增加更严格的 schema mismatch 报告。
2. 当 prompt 中声明了工具，但 schema 不存在时，日志要能直接定位到 capability 和 model 白名单交集。

### 13.5 第五组：把流式消费和 debug 消费统一

#### 13.5.1 `Application/DeepTutorAIRuntimeEventMapper.swift`

建议改造：

1. 保持它作为“runtime partial -> DeepTutorStreamEvent”的唯一映射层。
2. 让 `DeepTutorAIRuntimeAdapter` 不再直接理解 partial 语义。

#### 13.5.2 `Application/DeepTutorChatDebugExporter.swift`

建议改造：

1. 输出对象从“消息/日志片段”升级为“turn plan + stream events + snapshot”。
2. 让导出内容能回放 ask_user、成员选择、工具调用和 prompt 结果。

#### 13.5.3 `Infrastructure/DeepTutorChatLogging.swift`

建议改造：

1. 统一日志字段：`conversationID`、`turnID`、`capability`、`model`、`promptSource`、`finalTools`。
2. 所有日志都按 turn 聚合，减少只看单条 log 不能拼回完整链路的问题。

### 13.6 第六组：UI 只负责展示，不负责编排

#### 13.6.1 `Presentation/DeepTutorChatPage.swift`

建议改造：

1. 只负责页面层状态绑定、入口分发、错误展示。
2. 不再直接参与 turn 解析。

#### 13.6.2 `Presentation/DeepTutorComposerView.swift`

建议改造：

1. 只保留 capability selector、model selector、附件、输入框、按钮。
2. 让选中 capability/model 后的语义变化通过 ViewModel 和 coordinator 传递。

#### 13.6.3 `Presentation/DeepTutorComposerToolbarView.swift`

建议改造：

1. 把工具开关和 capability 的关系展示清楚。
2. 工具是否可用的最终解释，尽量来自 policy，而不是 toolbar 自己算。

### 13.7 推荐的落地顺序

#### Phase A

先做：

1. `DeepTutorChatViewModel`
2. `SendDeepTutorAIMessageUseCase`
3. `DeepTutorRuntimeRequestBuilder`

目的：先把 turn 编排收口。

#### Phase B

再做：

1. `DeepTutorStreamEvent`
2. `DeepTutorAIRuntimeEventMapper`
3. `DeepTutorChatDebugExporter`
4. `DeepTutorChatLogging`

目的：让事件与调试统一。

#### Phase C

然后做：

1. `DeepTutorRequestSnapshot`
2. `DeepTutorPerTurnToolSnapshot`
3. `DeepTutorConversationState`

目的：让恢复和回放统一。

#### Phase D

最后做：

1. `DeepTutorPromptBuilder`
2. `DeepTutorPromptMerger`
3. `DeepTutorPromptSchemaConsistencyChecker`

目的：把 prompt 彻底资产化。

### 13.8 这版改造的最小可交付结果

如果只做第一轮最小闭环，验收目标应该是下面四条：

1. `ViewModel` 不再直接拼装发送链路。
2. `UseCase` 不再兼任编排器。
3. `Snapshot` 能完整复现 turn 的模型、能力、工具、prompt 来源。
4. `StreamEvent` 能把一次对话的关键过程完整导出和回放。
