# CHAT-000008 P0 AI 主干统一与 Runtime 协议收口需求工单

## 工单状态

已实现（CHAT-000008，2026-08-05；在 CHAT-000007 入口统一基础上收口）。

## 1. 背景

### Q：这张 P0 工单要解决什么问题？

A：当前 `SparkClient` 的 AI 主链路已经具备雏形，但“主干统一”还没有形成严格的工程约束。随着聊天、问报告、知识问答、医疗抽取、营养识别等能力持续扩展，最容易失控的点有三个：

1. 不同业务继续各自组装 AI 请求，导致 `request / stream / completed / toolCall` 协议漂移。
2. 模型选择逻辑分散，出现页面层、Feature 层、Runtime 层各自判断来源与模型来源标记的情况。
3. 未来新增 AI 能力时，最容易从 `AIRuntimeService` 外面再绕出一条临时直连路径。

本工单只做 P0，不讨论工具生态扩展，也不讨论 capability 继续细分。P0 的目标只有一个：

> 先把所有 AI 调用收束到同一条 Runtime 主干，并把请求/事件协议统一成唯一事实源。

### Q：为什么要参考 DeepTutor？

A：DeepTutor 最值得学的不是“功能多”，而是“主干稳”：

1. 所有入口最终落到统一 runtime。
2. 请求上下文、流式事件、工具调用、模型路由各自有明确边界。
3. 上层只表达“做什么”，底层只负责“怎么执行”。

本工单只学习这类架构方法，不复制 DeepTutor 的全部复杂度。

参考代码位置：

- DeepTutor 统一编排入口：[orchestrator.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/runtime/orchestrator.py)
- DeepTutor turn 级运行时：[turn_runtime.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/services/session/turn_runtime.py)
- DeepTutor 统一上下文：[context.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/core/context.py)

## 2. 一句话目标

### Q：一句话需求是什么？

A：建立 SparkClient AI 主干的 P0 收口规则：

1. 所有 AI 请求统一进入 `AIRuntimeService`。
2. 所有流式结果统一使用同一套 `request / stream / completed / toolCall` 协议。
3. 所有模型选择与来源标记统一由 `AIConfigCenter` / `ScenarioPolicyResolver` 计算。
4. 聊天多轮能力继续走 `ChatOrchestrator`，但它必须依赖统一 Runtime 协议，而不是自成一套。

## 3. P0 范围边界

### Q：这次 P0 只做什么？

A：P0 只做“主干统一”，不做能力扩展。

本次只关注下面三块：

1. 统一 AI 入口到 `AIRuntimeService`
2. 统一 request / stream / completed / toolCall 协议
3. 统一模型选择逻辑和来源标记

### Q：这次 P0 不做什么？

A：以下内容不在 P0 范围内：

1. 不重做工具目录
2. 不重做 capability 体系
3. 不重做 UI
4. 不重做知识库/RAG 细节
5. 不重做消息读模型和同步
6. 不重做完整的 AI 设置页交互

P0 的重点是“主干收口”，不是“功能大扩张”。

## 4. 当前代码对齐现状

### Q：现在有哪些代码已经接近目标态？

A：当前项目里，下面这些代码已经是正确主干的基础：

| 角色 | 当前代码位置 | 当前职责 |
| --- | --- | --- |
| 统一 Runtime 入口 | [AIRuntimeService.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/AIRuntimeService.swift) | 统一模型路由、工具降级、本地/云端推理 |
| 聊天编排入口 | [ChatOrchestrator.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ChatOrchestrator.swift) | 聊天多轮、tool loop、流式回传 |
| 请求协议 | [AIRuntimeModels.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/AIRuntimeModels.swift) | 消息、工具、reasoning、流式事件定义 |
| 模型解析中心 | [AIConfigCenter.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AI/AIConfigCenter.swift) | 场景解析、模型解析、配置汇总 |
| 场景策略解析 | [ScenarioPolicyResolver.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AI/ScenarioPolicyResolver.swift) | 模型选择顺序、source 标记、override 解析 |
| 装配根 | [AssemblyProducts.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/App/Sources/App/Architecture/AssemblyProducts.swift) | 创建 Runtime 依赖图 |

### Q：当前缺口在哪里？

A：当前缺口不在“有没有入口”，而在“入口还没变成硬约束”：

1. `AIRuntimeService` 已经存在，但还没有成为所有 AI 请求的唯一强入口。
2. `AIRuntimeTextRequest` / `AIRuntimeStreamEvent` 已经存在，但下游消费协议还可以继续收紧。
3. `AIConfigCenter` / `ScenarioPolicyResolver` 已经能解析模型，但来源标记和模型来源边界还需要更明确。
4. 聊天、知识、医疗、营养等 feature 已开始共用 Runtime，但后续新代码最容易重新分叉。

## 5. P0 必须满足的硬规则

### Q：P0 落地后必须满足哪些硬规则？

A：必须满足以下规则：

1. Feature 层不直接 new `OpenAICompatibleTextGateway`、`LocalGGUFTextGateway` 或 `AIClientFactory`。
2. 所有 AI 调用统一先经过 `AIRuntimeService.generateTextStream(request:)`。
3. 聊天型调用可继续由 `ChatOrchestrator` 编排，但它只能构造和消费统一 Runtime 协议。
4. 事件协议统一，不能为某个 feature 再引入另一套 SSE / callback / tool event 格式。
5. 模型选择逻辑只能由 `AIConfigCenter` / `ScenarioPolicyResolver` 决定。
6. 所有配置来源都必须有 source 标记，并在日志中可追踪。
7. 本地 / 云端 / override / trial / pro overlay 的来源标记要统一，不允许不同路径自说自话。

### Q：新增 AI 功能前应该先问什么？

A：先问这 4 个问题：

1. 这次调用是聊天型多轮，还是单次任务型？
2. 它能不能复用 `AIRuntimeService` 现有 request 协议？
3. 它是否需要 `ChatOrchestrator` 的 tool loop？
4. 它的模型来源标记是谁算出来的，在哪里写日志？

## 6. 需要统一的协议

### Q：P0 要统一哪些协议？

A：统一三组协议：

#### 6.1 请求协议

所有上层调用统一表达为 `AIRuntimeTextRequest`，至少包含：

- `scenario`
- `messages`
- `tools`
- `toolChoice`
- `reasoning`
- `preferredModelName`
- `providerCompanyUppercased`
- `temperature`
- `topP`
- `maxTokens`
- `cancellationToken`

#### 6.2 流式协议

统一消费同一套事件语义：

- `textDelta`
- `reasoningDelta`
- `toolCallDelta`
- `completed`

#### 6.3 来源协议

统一来源标记与模型解析结果：

- `localDefault`
- `localCatalog`
- `proOverlay`
- `userOverride`
- `runtimeOverride`
- `trialPolicy`

### Q：这些协议现在在哪些代码里？

A：对应位置如下：

- [AIRuntimeModels.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/AIRuntimeModels.swift)
- [AIRuntimeService.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/AIRuntimeService.swift)
- [AIConfigCenter.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AI/AIConfigCenter.swift)
- [ScenarioPolicyResolver.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AI/ScenarioPolicyResolver.swift)

## 7. 代码替代清单

### Q：这次要替代哪些现有写法？

A：不是删业务能力，而是替换掉绕过 Runtime 的写法。

| 旧写法 | 新写法 | 替换原因 |
| --- | --- | --- |
| Feature 直接拼 provider / HTTP 请求 | 统一注入 `AIRuntimeServing` | 避免业务层理解模型协议细节 |
| 页面层自己做本地 / 云端路由 | `AIRuntimeService` 统一路由 | 避免路由分叉 |
| 每个 feature 自己定义流式回调格式 | 统一 `AIRuntimeStreamEvent` | 避免 UI 和业务各认各的协议 |
| 聊天里散落多轮 tool loop | 统一 `ChatOrchestrator` | 避免 tool loop 不一致 |
| 各处重复写模型来源日志 | 统一 `AIConfigCenter` / `AIRuntimeService` 打标 | 避免 source 信息不可信 |

### Q：哪些代码需要去除或禁止回流？

A：以下代码形态需要长期禁止出现在 Feature 边界：

1. `new OpenAICompatibleTextGateway(...)`
2. `new LocalGGUFTextGateway(...)`
3. `AIClientFactory.makeClient(...)`
4. `URLSession.bytes(`
5. `/v1/chat/completions`
6. 自己写 SSE parser
7. 自己写 completed / toolCall 的回调协议

## 8. 新架构主流程

### Q：P0 的新架构主流程是什么？

A：主流程建议固定为：

```text
Feature / UseCase 发起 AI 请求
  ↓
组装 AIRuntimeTextRequest
  ↓
交给 AIRuntimeService.generateTextStream(request:)
  ↓
AIConfigCenter / ScenarioPolicyResolver 计算模型、来源、override
  ↓
AIRuntimeService 统一决定本地 / 云端 / 降级逻辑
  ↓
产出统一流式事件 request / stream / completed / toolCall
  ↓
聊天场景再进入 ChatOrchestrator 做多轮循环
  ↓
UI / 业务侧只消费协议，不接触 provider 细节
```

### Q：聊天型和单次任务型怎么分？

A：

- 聊天型、多轮型、工具型：走 `ChatOrchestrator`
- 单次抽取、润色、识别、结构化输出：直接走 `AIRuntimeService`

这条边界在 P0 里不强行改业务能力，只要求它们都走统一 Runtime 主干。

### Q：模型来源标记在哪一层算？

A：模型来源标记必须由 Runtime 配置层统一计算，不能分散在页面、ViewModel 或 Feature 里。

建议原则：

1. `AIConfigCenter` 负责读取配置快照和 overlay。
2. `ScenarioPolicyResolver` 负责决定最终命中的模型与来源。
3. `AIRuntimeService` 负责在日志和事件里携带来源信息。

## 9. 关键代码对齐点

### Q：P0 要重点看哪些代码？

A：建议优先对齐以下文件：

- [AssemblyProducts.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/App/Sources/App/Architecture/AssemblyProducts.swift)
- [AIRuntimeService.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/AIRuntimeService.swift)
- [AIRuntimeModels.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/AIRuntimeModels.swift)
- [ChatOrchestrator.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/ChatOrchestrator.swift)
- [AIConfigCenter.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AI/AIConfigCenter.swift)
- [ScenarioPolicyResolver.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AI/ScenarioPolicyResolver.swift)
- [SendChatMessageUseCase.swift](/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat/Application/SendChatMessageUseCase.swift)

### Q：这几处代码各自承担什么职责？

A：

#### `AssemblyProducts`

只负责装配，不负责业务判断。

#### `AIConfigCenter`

只负责读取和汇总配置，不负责具体请求发送。

#### `ScenarioPolicyResolver`

只负责根据场景、模型名、override、trial 等信息选择最终模型。

#### `AIRuntimeService`

只负责统一发起请求、统一做路由、统一输出事件。

#### `ChatOrchestrator`

只负责聊天型多轮编排、tool loop、partial 汇总。

#### `SendChatMessageUseCase`

只负责把聊天场景参数组装好并交给 `ChatOrchestrator`。

## 10. 落地实施步骤

### Q：P0 应该按什么顺序做？

A：建议按下面四步推进：

1. **先收口入口**
   - 所有 AI 请求改为优先进入 `AIRuntimeService`
   - 聊天入口保留 `ChatOrchestrator`

2. **再统一协议**
   - 请求统一用 `AIRuntimeTextRequest`
   - 流统一用 `AIRuntimeStreamEvent`
   - 完成态统一 `completed`
   - 工具态统一 `toolCall`

3. **再统一来源**
   - 模型选择只能由 `AIConfigCenter` / `ScenarioPolicyResolver` 决定
   - 日志必须打出 source

4. **最后补门禁**
   - 禁止 Feature 层直接 new gateway / client
   - 禁止新流式协议回流
   - 禁止新模型来源判断散落

### Q：P0 不建议做什么？

A：不建议在 P0 里做以下事情：

1. 不重写全部 tool 生态
2. 不重做能力层抽象
3. 不重做 UI
4. 不重做消息同步链路
5. 不把所有非聊天任务都强制改成 `ChatOrchestrator`

P0 只做主干，不做扩张。

## 11. 测试与门禁

### Q：P0 要补哪些测试？

A：建议至少补三类测试：

1. `AIRuntimeService` 测试
   - 空消息报错
   - tools 降级
   - 本地/云端选择

2. `ScenarioPolicyResolver` 测试
   - runtimeOverride 优先
   - proOverlay 源标记
   - local / trial 来源正确

3. 架构门禁测试
   - Feature 层禁止直接引用 gateway / client
   - Feature 层禁止直接写 `/v1/chat/completions`
   - Feature 层禁止自己定义流式协议

### Q：建议的测试文件名是什么？

A：

- `AIRuntimeArchitectureGateTests.swift`
- `AIRuntimeProtocolTests.swift`
- `AIRuntimeServiceTests.swift`
- `ScenarioPolicyResolverTests.swift`

## 12. 验收标准

### Q：P0 完成后如何验收？

A：满足以下条件才算通过：

1. 所有 AI 请求都能收敛到 `AIRuntimeService`。
2. 聊天入口继续通过 `ChatOrchestrator`，但协议已统一。
3. `request / stream / completed / toolCall` 没有第二套平行格式。
4. 模型选择逻辑和来源标记统一由配置层决定。
5. Feature 层不能再直接访问 gateway / client / HTTP 请求。
6. 新增架构门禁测试后，错误写法会直接被挡住。

## 13. 最终交付物

### Q：这张工单最终要交付什么？

A：

1. 一个统一的 AI 主干入口。
2. 一套统一的 Runtime 请求与流式协议。
3. 一套统一的模型选择与来源标记规则。
4. 一组能防回流的架构门禁测试。
5. 一份可以继续承接后续 capability / tool 重构的主干底座。

## 14. 实施记录

### 实施日期

2026-08-05

### 已完成项

1. **现状确认**：CHAT-000007 已交付统一入口、Guest/Embedding 收口与 `AIRuntimeArchitectureGateTests`；P0 硬规则在代码层已满足，本次不修改 Runtime 实现逻辑。
2. **来源测试补齐**：新增 `ScenarioPolicyResolverTests.swift`，覆盖 `localCatalog` 默认行解析、`trialPolicy` 来源标记契约、缺失 preferred 模型异常。
3. **门禁扩展**：在 `AIRuntimeArchitectureGateTests.swift` 新增 `testFeatureLayerDoesNotDefineParallelStreamingProtocols`，禁止 Feature 层自定义并行 `*StreamEvent` 协议。
4. **文档更新**：总领文档追加「P0 主干协议收口（CHAT-000008）」小节。

### 变更文件清单

| 操作 | 文件 |
| --- | --- |
| 新增 | `Tests/AI/ScenarioPolicyResolverTests.swift` |
| 修改 | `Tests/AI/AIRuntimeArchitectureGateTests.swift` |
| 修改 | `总领文档/对话、AI Runtime 与工具调用/AI Runtime 推理编排需求.md` |

### 已知测试缺口（留待后续）

- `AIRuntimeServiceTests.swift`（空消息报错、tools 降级、本地/云端选择）尚未单独立文件覆盖。
