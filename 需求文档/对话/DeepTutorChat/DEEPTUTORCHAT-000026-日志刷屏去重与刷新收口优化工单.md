# DEEPTUTORCHAT-000026 DeepTutorChat 日志刷屏去重与刷新收口优化工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000026 |
| 工单类型 | P1 日志降噪 + 刷新链路收口 + 调试可观测性优化 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标模块 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| 核心文件 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorChatLogging.swift` |
| 关联刷新链路 | `DeepTutorChatViewModel`、`DeepTutorPublishGate`、`DeepTutorMessageListView` |
| 创建日期 | 2026-08-06 |
| 触发问题 | DeepTutorChat 运行时出现大量重复、无信息增量的刷新日志，刷屏严重，影响排障效率 |
| 关联工单 | `DEEPTUTORCHAT-000014`、`DEEPTUTORCHAT-000015`、`DEEPTUTORCHAT-000016`、`DEEPTUTORCHAT-000025` |

## 1. 本工单目标

本工单不解决业务功能错误，而是解决 DeepTutorChat 的日志噪音问题：

```text
1. 让“重复刷新但没有状态变化”的日志不再刷屏。
2. 让高频 UI 刷新、消息重建、diffable apply、cell 配置这类内部细节默认不再输出。
3. 只保留真正有诊断价值的日志：错误、首次出现、状态变化、关键边界事件、显式开启的调试日志。
4. 给后续排障保留一个可控的“verbose”通道，而不是默认把所有刷新过程都打到控制台。
```

用户当前感知到的问题可以概括为：

```text
1. 同一轮刷新里，日志重复打印相同的 load / reload / apply / configure 信息。
2. 同一 conversation 的状态没有真正变化，但日志仍在连续输出。
3. 列表重建、cell 配置、render commit、publish guard 等内部过程过于细碎。
4. 这些日志本来是排障辅助，现在变成了干扰项。
```

## 2. 现象证据

附件日志里可以看到典型模式：

```text
deeptutor.conversation.open.start conversation=ABED3F13
deeptutor.messages.reload.start conversation=ABED3F13 lockBottom=false forceFullRediff=false source=open
deeptutor.messages.load.start conversation=ABED3F13 limit=50 before=-
deeptutor.messages.reload.done conversation=ABED3F13 totalCount=6 pageLoaded=6 allLoaded=6 visible=6 visibleAll=6 isStreaming=false durationMs=80
deeptutor.render.transaction.begin conversation=ABED3F13 source=diffable_apply
deeptutor.list.snapshot.apply_start conversation=ABED3F13 items=6 ...
deeptutor.message_row.configure_cell conversation=ABED3F13 message=6E89CEB3 signature=...
deeptutor.message_row.configure_cell conversation=ABED3F13 message=279CCFF3 signature=...
deeptutor.render.transaction.end conversation=ABED3F13 durationMs=232
deeptutor.list.snapshot.apply_done conversation=ABED3F13 pending=false durationMs=232
```

这类日志的问题不是“有一条错了”，而是“同一条刷新路径里持续打印同类中间态”，导致：

```text
1. 真实错误被冲掉。
2. 调试时很难快速看到关键状态跳变。
3. 控制台输出成本过高。
4. 刷新次数越多，日志噪音越严重。
```

## 3. 当前实现事实

### 3.1 日志文件本身非常集中

日志都收敛在：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorChatLogging.swift
```

这个文件里既有：

```text
1. list / reload / apply / render 的过程日志。
2. stream / reasoning / publish gate 的高频日志。
3. load / repair / recover / persist 的恢复日志。
4. 少量已经做过一次性去重的日志。
```

### 3.2 现有“去重”只覆盖了一部分

当前已经存在：

```text
1. `logOnce(key:)`
2. `logIfChanged(scope:signature:)`
```

而且部分方法已经使用了它们，例如：

```text
1. `messagesLoadBlockRecovered`
2. `messagesLoadRepairNeeded`
3. `messagePersistCompleted`
4. `messagesReloadSkippedActiveStream`
```

这说明问题不是“完全没有去重”，而是：

```text
1. 去重只覆盖了少数恢复/持久化路径。
2. 刷新链路和 UI 渲染链路仍在大量直接输出。
3. 许多日志虽然技术上有意义，但对默认控制台来说没有持续价值。
```

### 3.3 刷新链路里本身已经有很多中间态

相关代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorPublishGate.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorMessageListView.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorChatViewModel.swift
```

链路中会产生：

```text
1. open / reload 触发日志。
2. publish gate 阻塞与恢复日志。
3. diffable apply 开始 / 结束 / 队列中 / 跳过日志。
4. message row build / configure 日志。
5. stream coalesced / commit 日志。
```

这些日志如果全部默认打印，本质上就是把内部状态机完整摊到控制台。

## 4. 根因判断

本次问题的根因不是单条日志写错，而是日志策略缺少“默认收口”。

### 4.1 业务层面

DeepTutorChat 的消息链路本身是高频刷新型：

```text
1. 流式回答会持续更新。
2. database change 会触发重载。
3. ask_user / quiz / tool card 会带来额外的状态变更。
4. diffable apply 和 cell 配置本来就是高频中间过程。
```

### 4.2 日志层面

当前很多日志都属于以下三类之一：

```text
1. 中间态确认日志：打印“我正在刷新”“我已配置 cell”“我已进入 commit”。
2. 频繁重复但语义不变的日志：同一 conversation 同一状态重复打印。
3. 仅对开发者内部实现有意义的日志：用户排障时几乎不需要。
```

### 4.3 现有缺口

```text
1. 没有统一的 refresh transaction 级别日志入口。
2. 没有针对 conversation + scope 的频率控制。
3. 没有区分“默认可见日志”和“仅调试开关可见日志”。
4. UI 渲染细节日志没有被默认降噪。
```

## 5. 优化目标

### 5.1 默认控制台目标

```text
1. 同一 conversation 的重复刷新不再连续刷屏。
2. 同一状态重复进入时，不再重复打印。
3. 只有真正的状态变化、失败、恢复成功、关键边界事件才输出。
```

### 5.2 调试能力目标

```text
1. 需要时仍能打开 verbose 调试日志。
2. 打开后能看见完整刷新链路，但默认必须关闭。
3. 日志结构要能支撑按 conversation / scope 排查。
```

## 6. 优化方案

### 6.1 建立日志分级收口

把 DeepTutorChat 的日志分成三层：

```text
1. 必须保留：error / warning / 首次恢复 / 持久化失败 / 真正状态变化。
2. 默认保留一条：每轮刷新只保留一个 summary，其他过程日志默认不输出。
3. 仅 verbose 可见：diffable apply start / done、cell configure、render transaction、publish gate blocked 等内部过程日志。
```

### 6.2 对高频日志加“conversation + scope”级去重

建议把下面几类日志统一纳入 `logIfChanged` 或等价机制：

```text
1. `listSnapshotApplyStart / Queued / Done / Skipped`
2. `publishGuardBlocked`
3. `streamReasoningCoalesced / Commit`
4. `databaseChangeDeferred / Commit`
5. `messagesReloadSkippedActiveStream`
6. `messageRowModelBuilt`
7. `messageRowConfigureCell`
```

去重原则：

```text
1. 相同 conversation + 相同 scope + 相同 signature，只打一条。
2. 若值没有变化，就静默。
3. 只有状态跳变时才补一条。
```

### 6.3 把 cell 级日志默认下沉到 verbose

`message_row.model_built` 和 `message_row.configure_cell` 这类日志是最容易刷屏的。

建议：

```text
1. 默认关闭。
2. 仅在显式 verbose 开关下开启。
3. 需要时只保留按 conversation 的抽样日志，不对每个 cell 都打印。
```

### 6.4 收口刷新事务日志

当前刷新路径已经有 `render.transaction.begin/end`、`list.snapshot.apply_start/done`、`publish_commit` 等多层日志。

建议收成单一事务模型：

```text
1. 每次刷新只记录一个 transaction ID 或一个 scope。
2. 事务开始时记录一次 summary。
3. 事务结束时记录一次 summary。
4. 中间过程默认静默。
```

### 6.5 给日志加全局可控开关

现有 `DeepTutorDebugFlags` 只管本地模拟器，不管日志降噪。

建议新增独立开关，例如：

```text
1. `DeepTutorDebugFlags.verboseChatRefreshLogs`
2. `DeepTutorDebugFlags.verboseChatRenderLogs`
3. `DeepTutorDebugFlags.verboseChatStreamLogs`
```

默认值建议：

```text
1. Release: 全关。
2. Debug: 也默认全关，需通过 UserDefaults 显式开启。
```

### 6.6 保留一条“总结日志”，替代十几条过程日志

建议每轮刷新最后只保留类似下面这种总结：

```text
deeptutor.refresh.summary conversation=ABED3F13 source=open messages=6 reload=1 apply=1 skipped=0 queued=0 durationMs=80
```

这类 summary 可以替代：

```text
1. open start
2. reload start
3. load start
4. apply start
5. apply done
6. render transaction begin/end
```

默认控制台只看 summary，就足够判断是否异常。

## 7. 建议落点

### 7.1 优先改造文件

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorChatLogging.swift
```

### 7.2 次级配套文件

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorPublishGate.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorMessageListView.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorChatViewModel.swift
```

### 7.3 需要收口的日志方法示例

```text
1. `listLoadStart`
2. `listLoadDone`
3. `listSnapshotApplyStart`
4. `listSnapshotApplyQueued`
5. `listSnapshotApplyDone`
6. `messageRowModelBuilt`
7. `messageRowConfigureCell`
8. `renderTransactionBegin`
9. `renderTransactionEnd`
10. `publishGuardBlocked`
```

## 8. 验收标准

### 8.1 功能验收

```text
1. 同一 conversation 在正常打开、滚动、流式回答、数据库回补时，不再连续刷同类日志。
2. 同一状态重复发生时，不再重复打印。
3. 真正的错误、警告、恢复失败仍然可见。
4. 开启 verbose 后，仍能恢复完整排障链路。
```

### 8.2 体验验收

```text
1. 默认控制台从“刷屏”变成“可读”。
2. 调试时能快速定位到一次刷新发生了什么。
3. 既不会丢关键异常，也不会被中间态淹没。
```

### 8.3 技术验收

```text
1. 高频刷新场景下，重复日志输出显著下降。
2. 日志去重逻辑不影响业务状态机。
3. 去重键或 signature 设计不会把真正不同的事件误吞掉。
4. 新增开关默认关闭，不改变现有业务结果。
```

## 9. 不做项

```text
1. 不改消息业务逻辑。
2. 不改 diffable 刷新架构本身。
3. 不为了“安静”而删除错误 / warning 日志。
4. 不把所有日志都静默，必须保留可排障的最小闭环。
```

## 10. 建议的执行顺序

```text
1. 先把 cell 级和 render 级日志默认关掉。
2. 再给刷新事务加 conversation + scope 去重。
3. 然后把过程日志收敛成 summary。
4. 最后补一个可显式开启的 verbose 开关。
```

