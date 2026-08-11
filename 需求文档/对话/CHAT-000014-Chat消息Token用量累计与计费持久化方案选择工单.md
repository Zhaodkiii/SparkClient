# CHAT-000014 Chat 消息 Token 用量累计与计费持久化方案选择工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | CHAT-000014 |
| 工单类型 | P0 计费统计准确性 / Token 用量累计 / 持久化方案选择 |
| 当前范围 | 只创建工单，不实现代码改造 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标模块 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/Chat` |
| 关键模型 | `ChatMessage.swift` 中 `ChatMessageBlock`、`ChatMessage` |
| 创建日期 | 2026-08-11 |
| 触发问题 | 当前按消息最终内容反推 token 和 calls 的方案严重失真，无法准确覆盖 AI 多轮工具调用、思考过程、工具结果回填和恢复续写 |
| 核心目标 | 在 AI 运行过程中增量累计 token 与调用次数，并持久化到本地数据库和/或服务端，消息卡片底部只读取已落库的 usage summary 展示 |

## 1. 背景与问题

上一版 `CHAT-000013` 将 token 计算放在 UI 展示阶段，通过消息字符数 / `3.5` 反推 token，并按工具块数量估算 calls。这个方案只能作为临时 UI 估算，不能作为 Chat 计费展示的正式实现。

实际 Chat 流程中，一个 assistant 消息不是一次简单文本返回，而是可能包含：

- 初始 LLM 请求。
- 流式正文输出。
- reasoning / deep thought 输出。
- 一个或多个工具调用。
- 工具参数、工具结果。
- 工具交互卡片，例如成员选择、用户问答。
- 工具结果回填后的继续 LLM 请求。
- 最终 assistant 输出完成。

用户提供的调试样本中，同一条 assistant 消息包含多个 `tool` block 和工具展示 block。仅根据完成后的 `ChatMessage.blocks` 反推 calls/token，会出现以下严重偏差：

- 无法知道每次 LLM 请求真实 prompt token。
- 无法区分模型返回 token、reasoning token、工具结果文本 token。
- 无法准确统计工具调用前后的多次 LLM calls。
- 无法识别被截断、重试、恢复续写、用户补充输入后的新增用量。
- 历史消息重新打开时会重复按当前 blocks 再估算，数值可能随渲染逻辑变化而变化。

因此正式方案必须改为“运行时增量统计 + 完成后固化结果 + 展示层只读”。

## 2. 现有模型上下文

当前 `ChatMessage.swift` 中的关键结构：

- `ChatMessageBlock`
  - `toolCallId`
  - `parentToolCallId`
  - `parentBlockId`
  - `nodeRole`
  - `payload`
  - `status`
  - `revision`
  - `orderKey`
- `ChatMessage`
  - `id`
  - `threadId`
  - `role`
  - `blocks`
  - `clientMessageId`
  - `serverMessageId`
  - `deliveryState`
  - `modelName`

这些字段适合承载“消息内容与工具展示”，但不适合直接承担计费用量事实源。计费用量应独立建模，避免把 usage 统计塞进文本 block 或通过 block 内容反推。

## 3. 正确计算原则

### 3.1 统计时机

Token 和调用次数必须在 AI 运行过程中累计：

1. 创建 assistant 占位消息时，初始化本轮 usage accumulator。
2. 每次发起 LLM 请求前，记录本次 call 的上下文、模型、序号和关联 assistant message。
3. 每次收到 provider usage 时，累加真实 token：
   - `promptTokens`
   - `completionTokens`
   - `reasoningTokens`
   - `cachedPromptTokens`
   - `totalTokens`
4. 如果 provider 未返回 usage，才使用 fallback 估算，并标记 `isEstimated = true`。
5. 每次工具调用开始时，累计工具调用次数和工具名。
6. 每次工具调用完成时，记录工具结果字符数、状态、耗时、是否参与下一次 prompt。
7. 工具结果触发后续 LLM 请求时，该后续请求必须作为新的 call 累计。
8. assistant 最终完成时，将 accumulator 固化为 message-level usage summary。

### 3.2 展示口径

消息卡片底部展示只读取固化后的 usage summary：

```text
cost · total tokens · calls
```

示例：

```text
$0.0009 · 6.0k tokens · 1 次调用
```

展示层禁止再遍历 `ChatMessage.blocks` 重新计算真实费用。blocks 只能用于缺失历史数据的迁移兜底估算。

## 4. 建议新增领域模型

建议新增 Chat 专属 usage 模型，不直接复用 UI 估算对象：

```swift
nonisolated struct ChatMessageUsageSummary: Codable, Equatable, Sendable {
    let messageID: UUID
    let threadID: UUID
    let modelName: String?
    let priceTier: Int
    let currencyCode: String
    let promptTokens: Int
    let completionTokens: Int
    let reasoningTokens: Int
    let cachedPromptTokens: Int
    let totalTokens: Int
    let llmCallCount: Int
    let toolCallCount: Int
    let estimatedAmountMinor: Int
    let isEstimated: Bool
    let source: ChatUsageSource
    let createdAt: Date
    let updatedAt: Date
}

nonisolated enum ChatUsageSource: String, Codable, Sendable {
    case providerUsage
    case localFallbackEstimate
    case serverComputed
    case migratedEstimate
}

nonisolated struct ChatMessageUsageEvent: Codable, Equatable, Sendable {
    let id: UUID
    let messageID: UUID
    let threadID: UUID
    let runID: UUID?
    let eventType: ChatUsageEventType
    let callIndex: Int
    let modelName: String?
    let toolCallID: String?
    let toolName: String?
    let promptTokens: Int
    let completionTokens: Int
    let reasoningTokens: Int
    let cachedPromptTokens: Int
    let totalTokens: Int
    let isEstimated: Bool
    let createdAt: Date
}

nonisolated enum ChatUsageEventType: String, Codable, Sendable {
    case llmRequestStarted
    case llmUsageReceived
    case llmUsageEstimated
    case toolCallStarted
    case toolCallFinished
    case assistantCompleted
    case assistantFailed
}
```

## 5. 累加流程

推荐业务流程：

```text
用户发送消息
  -> 创建 assistant 占位消息
  -> 初始化 ChatUsageAccumulator
  -> LLM call #1 started
  -> 流式接收 text / reasoning / tool_call delta
  -> provider usage received 后累加 token
  -> 如果产生工具调用
      -> toolCallStarted 累加 toolCallCount
      -> 执行工具
      -> toolCallFinished 记录工具结果元数据
      -> 将工具结果写入下一次 LLM prompt
      -> LLM call #2 started
      -> provider usage received 后继续累加 token
  -> 重复直到最终回答完成
  -> assistantCompleted
  -> 固化 ChatMessageUsageSummary
  -> 本地 DB / 服务端持久化
  -> 消息卡片读取 summary 展示
```

关键要求：

- 一个 assistant message 可以包含多次 LLM call。
- 每次工具调用都要独立累计。
- 每次 LLM provider 返回的 usage 必须只累计一次，避免流式结束、重试、恢复时重复写入。
- 如果请求失败，已发生的 token usage 仍应保留，并标记 message usage 为 partial / failed。
- 如果用户通过成员选择卡、问答卡继续同一轮，对应恢复请求仍计入同一个 assistant message 的 usage summary。

## 6. 价格规则

沿用模型价格档，但费用计算应从 usage summary 读取真实 token：

| priceTier | 名称 | 建议 USD / 1K tokens |
| --- | --- | --- |
| 0 | 免费 | 0 |
| 1 | 经济 | 0.00030 |
| 2 | 标准 | 0.00500 |
| 3 | 高级 | 0.03000 |

正式实现建议保留可配置空间：

- 如果服务端有模型真实单价，优先使用服务端单价。
- 如果只有客户端 priceTier，客户端按上述分段估算。
- 中国大陆展示人民币，非中国大陆展示美元。
- 货币换算不要由消息渲染层临时写死，至少应集中在 pricing service / formatter。

## 7. 方案 A：服务端权威持久化

### 7.1 方案说明

由服务端作为 token usage 和计费金额事实源。客户端在 AI 调用结束或每个 usage event 发生时上报，服务端校验、聚合、定价并返回 message usage summary。

### 7.2 数据流

```text
iOS Chat Runtime
  -> usage events / provider usage
  -> SparkService Chat Usage API
  -> 服务端落库
  -> 服务端计算 summary + price
  -> iOS 同步 message usage summary
  -> 消息卡片展示
```

### 7.3 建议服务端表

```text
chat_message_usage_events
  id
  user_id
  thread_id
  message_id
  run_id
  event_type
  call_index
  model_name
  tool_call_id
  tool_name
  prompt_tokens
  completion_tokens
  reasoning_tokens
  cached_prompt_tokens
  total_tokens
  is_estimated
  provider_request_id
  idempotency_key
  created_at

chat_message_usage_summaries
  id
  user_id
  thread_id
  message_id
  model_name
  price_tier
  currency_code
  prompt_tokens
  completion_tokens
  reasoning_tokens
  cached_prompt_tokens
  total_tokens
  llm_call_count
  tool_call_count
  estimated_amount_minor
  source
  is_estimated
  created_at
  updated_at
```

### 7.4 优点

- 费用结果可信，适合后续真实计费、用量报表、跨设备同步。
- 服务端可以统一模型单价、汇率、折扣、免费额度。
- 客户端重装或多设备登录后，历史消息费用仍可恢复。
- 可以用 `idempotency_key` 防止 usage 重复累计。

### 7.5 缺点

- 需要新增服务端 API、数据库表和同步字段。
- 离线或弱网时，消息卡片可能先显示“统计中”。
- 客户端与服务端需要处理 eventual consistency。

### 7.6 适用场景

如果该功能未来会进入真实扣费、会员额度、账单中心、用量审计，优先选择方案 A。

## 8. 方案 B：本地数据库持久化

### 8.1 方案说明

由 iOS 本地 Chat runtime 在 AI 运行过程中维护 `ChatUsageAccumulator`，并将 usage events 和 summary 落到 Core Data。服务端暂不感知计费用量，消息卡片读取本地 summary。

### 8.2 数据流

```text
iOS Chat Runtime
  -> ChatUsageAccumulator
  -> Core Data usage event / usage summary
  -> 消息卡片展示
```

### 8.3 建议本地 Core Data 实体

```text
ChatMessageUsageEventEntity
  id: UUID
  threadID: UUID
  messageID: UUID
  runID: UUID?
  eventType: String
  callIndex: Int64
  modelName: String?
  toolCallID: String?
  toolName: String?
  promptTokens: Int64
  completionTokens: Int64
  reasoningTokens: Int64
  cachedPromptTokens: Int64
  totalTokens: Int64
  isEstimated: Bool
  createdAt: Date

ChatMessageUsageSummaryEntity
  id: UUID
  threadID: UUID
  messageID: UUID
  modelName: String?
  priceTier: Int16
  currencyCode: String
  promptTokens: Int64
  completionTokens: Int64
  reasoningTokens: Int64
  cachedPromptTokens: Int64
  totalTokens: Int64
  llmCallCount: Int64
  toolCallCount: Int64
  estimatedAmountMinor: Int64
  source: String
  isEstimated: Bool
  createdAt: Date
  updatedAt: Date
```

### 8.4 优点

- 改造范围较小，可以更快落地消息卡片展示。
- 不依赖服务端发版。
- 离线和弱网场景也能展示本机生成的历史 usage。
- 能先验证 UI、数据口径和运行时累计逻辑。

### 8.5 缺点

- 不是权威计费来源，不能直接用于真实扣费。
- 多设备不同步；换设备或重装后历史费用可能丢失。
- 本地汇率、价格档变更后，历史金额是否重算需要额外规则。
- 如果部分 AI 调用由服务端代理完成，本地可能拿不到真实 provider usage。

### 8.6 适用场景

如果当前目标只是本机消息卡片展示、成本感知和 Debug 辅助，可以先选择方案 B。后续进入真实计费时，再迁移到方案 A。

## 9. 推荐决策

推荐优先级：

1. 如果费用会影响用户余额、套餐额度、正式账单：选择方案 A。
2. 如果只是 Chat 消息底部展示估算成本：选择方案 B。
3. 如果希望兼顾快速落地和未来账单：先做方案 B 的领域模型和 UI，字段设计与方案 A 保持同构；随后服务端接入后将 `source` 切到 `serverComputed`。

推荐折中路线：

```text
第一阶段：本地 DB 持久化 + 运行时累计 + UI 展示
第二阶段：服务端 usage API + 同构字段同步
第三阶段：服务端定价权威化 + 本地只缓存展示
```

### 9.1 本次确认

已选择方案 B：本地数据库持久化。

历史消息不迁移、不生成 `migratedEstimate`、不展示计费 footer。只有新产生的 assistant 消息在运行时累计出 `ChatMessageUsageSummary` 后才展示计费用量。

## 10. 实施边界

本工单仅用于方案确认，不要求立即改代码。

后续实现时需要注意：

- 不再使用 UI 层遍历 message blocks 计算正式 token。
- 不把 usage 结果塞进 `ChatMessageBlockPayload.text`。
- 不用工具块数量反推 LLM calls。
- 不在消息列表滚动渲染时动态重算费用。
- 已有历史消息没有 usage summary 时，可以展示“估算”或隐藏，不应误装成真实计费。

## 11. 验收标准

方案确认后的正式开发工单应满足：

- AI 完成输出时，能固化该 assistant 消息的 usage summary。
- 每次工具调用开始和完成都能形成可追踪 usage event。
- 多次 LLM call 的 token 能累计到同一 assistant message。
- provider 返回 usage 时优先使用真实 usage。
- provider 未返回 usage 时才走 fallback 估算，并明确标记。
- 本地重启、重新打开会话后，消息卡片展示的 token/cost/calls 不变化。
- 服务端方案下，多设备打开同一会话展示一致。
- 同一次流式完成、重试或恢复不会重复累计 token。

## 12. 待确认问题

请在方案 A / 方案 B 中选择一个作为下一步实现方向：

- 方案 A：服务端权威持久化，适合真实计费和跨设备。
- 方案 B：本地数据库持久化，适合快速实现消息卡片展示。

还需要确认：

- 当前模型供应商是否一定能返回 usage；如果不能，哪些供应商只能 fallback。
- reasoning token 是否单独展示，还是只计入 total tokens。
- 工具调用费用是否只展示 calls，还是未来也要按工具耗时/API 成本单独计价。
- 历史消息是否需要迁移生成 `migratedEstimate`，还是只对新消息生效。
