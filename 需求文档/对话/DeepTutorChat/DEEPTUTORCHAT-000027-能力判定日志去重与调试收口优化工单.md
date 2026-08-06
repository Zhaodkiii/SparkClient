# DEEPTUTORCHAT-000027 DeepTutorChat 能力判定日志去重与调试收口优化工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000027 |
| 工单类型 | P1 能力判定日志降噪 + 重复状态去重 + 调试收口优化 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标模块 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| 核心文件 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorChatLogging.swift` |
| 关联调用点 | `DeepTutorChatViewModel`、`SendDeepTutorAIMessageUseCase`、`DeepTutorAIRuntimeAdapter` |
| 创建日期 | 2026-08-06 |
| 触发问题 | 运行时持续打印 `deeptutor.capability.effective`、`deeptutor.capability.snapshot`，重复次数高、信息增量低，继续刷屏 |
| 关联工单 | `DEEPTUTORCHAT-000024`、`DEEPTUTORCHAT-000026` |

## 1. 本工单目标

本工单解决的是“能力判定链路本身的重复日志”：

```text
1. 同一个 conversation、同一个 capability、同一轮发送过程中，`capability.effective` 不要反复打印。
2. `capability.snapshot` 只在快照发生变化或切换调试模式时打印，不要在每次流式/重载路径重复输出。
3. `selected / effective / snapshot` 这类能力判定中间态默认收口，只保留真正发生变化、发生异常或显式调试时的日志。
4. 保留一条最终 summary，替代若干条重复中间态。
```

用户当前看到的现象可以概括为：

```text
1. 一次对话里出现大量 `deeptutor.capability.effective conversation=... selected=chat effective=chat`
2. 同一能力值没有变化，但日志仍在反复打印。
3. `capability.snapshot` 也跟着出现在运行路径里，进一步放大控制台噪音。
4. 这些日志不是错误，但在默认状态下没有持续诊断价值。
```

## 2. 现象证据

附件日志里可以直接看到：

```text
deeptutor.capability.effective conversation=ABED3F13 selected=chat effective=chat
deeptutor.capability.snapshot conversation=ABED3F13 requestSnapshot=chat message=chat
```

同时在同一轮运行中，相关流式和状态刷新日志会不断插入：

```text
deeptutor.stream.partial.mapped conversation=ABED3F13 assistant=451666E8 ...
deeptutor.message.persist.completed conversation=ABED3F13 message=451666E8 status=流式生成中 ...
deeptutor.trace.final_phase message=451666E8 isStreaming=false ...
deeptutor.messages.load.rows conversation=ABED3F13 fetchedRows=8 decoded=8 ...
```

这说明能力判定日志并不是“偶尔出现”，而是混在常规发送、流式回调、恢复和刷新链路里持续输出。

## 3. 当前实现事实

### 3.1 能力判定日志目前是直接打印

日志实现位于：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorChatLogging.swift
```

当前方法：

```swift
nonisolated static func capabilitySelected(
    conversationID: UUID,
    selected: String,
    previous: String
)

nonisolated static func capabilityEffective(
    conversationID: UUID,
    selected: String,
    effective: String
)

nonisolated static func capabilitySnapshot(
    conversationID: UUID,
    requestSnapshotCapability: String?,
    messageCapability: String?
)
```

其中 `capabilityEffective` 的现状是：

```text
1. 直接 logInfo。
2. 没有 `logOnce`。
3. 没有 `logIfChanged`。
4. selected == effective 时也照样打印。
```

### 3.2 调用点分散在发送和重试路径

已确认调用点：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorChatViewModel.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/SendDeepTutorAIMessageUseCase.swift
```

典型调用场景包括：

```text
1. 正常发送消息。
2. 重试 assistant 消息。
3. 发送链路中根据当前 state / message capability 重算 effective capability。
```

问题在于：

```text
1. 这些路径本来都会走到同一个“能力判定结果”。
2. 但日志没有做 conversation 级或 turn 级幂等。
3. 于是同一能力值被重复打印多次。
```

### 3.3 `capabilitySnapshot` 也是低价值高频日志

`capabilitySnapshot` 当前是 `logDebug`，但它仍然会在实际流程里频繁被触发。

其问题不是级别太高，而是：

```text
1. 快照值通常在同一轮里不怎么变。
2. 这类日志更多是诊断内部状态机，不是默认控制台需要持续看的内容。
3. 在有流式 partial、恢复、重载的场景下，它会和其他日志一起淹没关键边界事件。
```

## 4. 根因判断

本次问题的根因是能力判定日志没有被当成“状态日志”来处理，而是当成了“过程日志”。

### 4.1 `capability.effective` 本质上是状态结果，不该每次过程都重复打

`selected` 和 `effective` 一旦相同，通常就只是“这轮还是 chat”。

如果同一 conversation、同一轮、多次经过发送或恢复路径都打印：

```text
selected=chat effective=chat
```

那它传达的信息基本没有新增量。

### 4.2 `capability.snapshot` 应该是变化日志，不该是回调噪音

快照只在这些情况有价值：

```text
1. capability 发生切换。
2. requestSnapshot 和 messageCapability 不一致。
3. 调试开关显式打开。
4. 排查工具面和消息面不一致问题。
```

除此之外，默认打印只会增加噪音。

### 4.3 现有日志体系里已经有去重基础，但没覆盖这里

同一文件里已经存在：

```text
1. `logOnce`
2. `logIfChanged`
```

说明当前问题不是“没有能力做去重”，而是：

```text
1. 能力判定链路没有接入这套去重能力。
2. 该链路的日志被默认当成了每次必打的过程输出。
```

## 5. 优化目标

### 5.1 默认控制台目标

```text
1. 同一 conversation 的 `capability.effective` 只在变化时输出。
2. `selected == effective` 的稳定结果不再重复刷屏。
3. `capability.snapshot` 默认不输出，或者只在变化时输出。
4. 异常态仍然保留告警。
```

### 5.2 调试目标

```text
1. 需要时可以打开能力判定 verbose 日志。
2. 打开后能看清 selected、effective、snapshot 的关系。
3. 默认态仍然保持安静。
```

## 6. 优化方案

### 6.1 给 capability 日志加 conversation 级幂等

建议把以下信息作为去重键的一部分：

```text
1. conversationID
2. selected
3. effective
4. requestSnapshotCapability
5. messageCapability
6. 当前调试开关状态
```

建议规则：

```text
1. selected/effective 没有变化时，不再重复输出。
2. 相同快照重复进入时，静默。
3. 只有真正发生切换时再打一次状态变化日志。
```

### 6.2 把 `capability.snapshot` 降级成 debug-only

`capability.snapshot` 建议默认只保留 debug 级，并加额外去重。

可接受的输出条件：

```text
1. capability 值变了。
2. message 和 request 的 capability 不一致。
3. 显式 verbose 打开。
```

### 6.3 给能力判定链路增加“变化摘要”而不是逐次过程日志

建议新增一条 summary，例如：

```text
deeptutor.capability.summary conversation=ABED3F13 selected=chat effective=chat snapshot=chat source=send changed=false
```

这样可以替代：

```text
1. capability.selected
2. capability.effective
3. capability.snapshot
```

默认情况下，一轮只保留一条 summary 就够了。

### 6.4 对 mismatch / mutation 仍保留 warning

以下情况必须保留：

```text
1. selected != effective
2. capability 发生意外 mutation
3. snapshot 和 message 侧能力不一致且可能影响工具挂载
```

这些日志不能删，只能降频。

### 6.5 给 capability 日志单独加开关

建议新增类似：

```text
1. `DeepTutorDebugFlags.verboseCapabilityLogs`
2. `DeepTutorDebugFlags.verboseCapabilitySnapshots`
```

默认值建议：

```text
1. Release: 关闭。
2. Debug: 关闭，需通过 UserDefaults 显式开启。
```

## 7. 建议落点

### 7.1 优先改造文件

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorChatLogging.swift
```

### 7.2 配套查看文件

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorChatViewModel.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/SendDeepTutorAIMessageUseCase.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorAIRuntimeAdapter.swift
```

### 7.3 需要收口的日志方法

```text
1. `capabilitySelected`
2. `capabilityEffective`
3. `capabilitySnapshot`
```

## 8. 验收标准

### 8.1 日志层面

```text
1. 同一 conversation 内，重复发送、重试、流式更新不会把 capability 日志刷满控制台。
2. capability 没变时，不再重复输出相同的 effective/snapshot。
3. selected != effective 时仍然能看到 warning。
4. 打开 verbose 后，可以恢复调试信息。
```

### 8.2 体验层面

```text
1. 控制台输出更安静。
2. 调试时仍能定位能力选择和工具面问题。
3. 不会因为降噪丢失关键的 capability mismatch 证据。
```

### 8.3 技术层面

```text
1. capability 日志接入稳定的去重机制。
2. 去重不会误吞真正的 capability 切换。
3. 默认开关不影响业务行为，只影响输出量。
```

## 9. 不做项

```text
1. 不改能力选择业务本身。
2. 不改工具挂载逻辑。
3. 不删除 mismatch warning。
4. 不把所有诊断信息一刀切静音。
```

## 10. 建议执行顺序

```text
1. 先给 `capability.effective` 加幂等去重。
2. 再把 `capability.snapshot` 改成 debug-only 并去重。
3. 然后补一个 capability summary。
4. 最后给 verbose 开关接入 UserDefaults。
```

