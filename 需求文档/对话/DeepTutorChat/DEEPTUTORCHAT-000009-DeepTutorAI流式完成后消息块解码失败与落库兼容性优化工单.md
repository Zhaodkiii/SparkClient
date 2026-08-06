# DEEPTUTORCHAT-000009 DeepTutor AI 流式完成后消息块解码失败与落库兼容性优化工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000009 |
| 工单类型 | P0 日志分析 + 本地落库兼容性优化 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 功能目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| 关联日志 | `/Users/hua/.codex/attachments/5de9b042-9186-42ce-82f7-200b7879f11a/pasted-text.txt` |
| 关联工单 | `DEEPTUTORCHAT-000003`、`DEEPTUTORCHAT-000005`、`DEEPTUTORCHAT-000007`、`DEEPTUTORCHAT-000008` |
| 创建日期 | 2026-08-05 |
| 场景约束 | 继续使用项目已有通用 `.chat` 场景，不新增 `.deepTutor` |

## 1. 本工单目标

本工单聚焦一个已经出现在真实日志中的问题：DeepTutor AI 流式对话已完成并成功落库，但在会话重新加载、列表刷新、消息重绘时，消息块解码失败，导致历史消息和 AskUser block 无法稳定恢复。

本次问题不是“AI 没有完成”，而是：

```text
1. 流式完成成功。
2. 助手消息与 askUser block 已写入本地库。
3. 重新加载时 deepTutorEnvelope / deepTutorAskUser block 解码失败。
4. 导致消息部分恢复、块丢失、日志刷屏、历史会话不稳定。
```

本工单要解决的重点：

```text
1. 分析 `callID` / `toolCallID` 解码失败的真实原因。
2. 明确当前 block 编解码协议与历史落库数据是否存在版本漂移。
3. 设计本地库兼容读取、降级兜底和数据修复策略。
4. 补充 DeepTutorChat 的流式完成后回放/重载日志。
5. 给出不会破坏现有消息流和 askUser 卡片的优化方案。
6. 本工单只写需求与技术方案，不直接改动 Swift 代码。
```

## 2. 日志结论摘要

本次日志的核心状态如下：

```text
DeepTutor AI 流式完成，conversation=5E338FA4, model=doubao-seed-1-6, finishReason=awaiting_user_input, textLen=0, reasoningLen=617, assistantContent=, cost=10.535s
deeptutor.message_reducer.ask_user_block_created message=48D6A62A toolCallID=call_ch8m7f2f135xi9xc4m3tei3t questionCount=1 blockID=29A5CD07
deeptutor.trace.final_phase message=48D6A62A isStreaming=false hasFinalContent=false isFinalAnswerPhase=false
deeptutor.trace.state_changed message=48D6A62A rows=2 askUserBlocks=1 blocks=envelope|trace|askUser
助手消息落库成功，conversation=5E338FA4, messageID=48D6A62A, status=已就绪, content=
```

从“发送结束”这一段看，流程是成功的：

```text
1. 模型返回 awaiting_user_input。
2. DeepTutorMessageReducer 已经创建 askUser block。
3. 助手消息成功落库。
```

但紧接着在 reload / load all 阶段出现了解码失败：

```text
deeptutor.messages.load.block_decode_failed conversation=5E338FA4 message=48D6A62A block=2DB8D04F kind=deepTutorEnvelope payloadBytes=21042 error=keyNotFound key=callID path=wrapper.envelope.events.Index 324
deeptutor.messages.load.block_decode_failed conversation=5E338FA4 message=48D6A62A block=29A5CD07 kind=deepTutorAskUser payloadBytes=233 error=keyNotFound key=toolCallID path=wrapper.askUser
deeptutor.messages.load.partial_blocks conversation=5E338FA4 message=48D6A62A decodedBlocks=1 blockRows=3 contentLength=0
```

关键结论：

```text
1. 不是生成失败，而是“写入后重读失败”。
2. envelope block 内 events 某一项缺少 callID。
3. askUser block 内缺少 toolCallID。
4. 当前加载器只要遇到单块解码失败，就会降级成 partial blocks。
5. 历史会话列表里同类错误很多，说明不是单条脏数据，而是系统性兼容问题。
```

## 3. 当前日志中发现的问题

### 3.1 deepTutorEnvelope 解码时 `callID` 缺失

报错样式：

```text
kind=deepTutorEnvelope ... error=keyNotFound key=callID path=wrapper.envelope.events.Index 324
```

说明：

```text
DeepTutorMessageEnvelope.payload 里嵌套的 events 数组存在至少一个事件项，当前解码器期望该项包含 callID，但实际数据里没有。
```

可能原因：

```text
1. 旧版本写入的事件 schema 与当前 `DeepTutorStreamEvent` 不一致。
2. 某些 event 在编码时丢了 callID。
3. 迁移前后字段命名有漂移，例如 callID / call_id / toolCallID / tool_call_id。
4. 历史数据中混有 simulator、真实 AI、工具流、调试流四种不同来源。
```

### 3.2 deepTutorAskUser 解码时 `toolCallID` 缺失

报错样式：

```text
kind=deepTutorAskUser ... error=keyNotFound key=toolCallID path=wrapper.askUser
```

说明：

```text
askUser block 的 payload 数据与当前 `DeepTutorAskUserBlockPayload` 编码/解码协议不完全一致。
```

可能原因：

```text
1. 旧数据只有 `payload`，没有 `toolCallID`。
2. 某次写入后只保存了 UI 所需内容，没有保存恢复 toolCallID 的字段。
3. block 编码更新了，但历史数据没有迁移。
```

影响：

```text
1. 重新打开会话时 askUser 卡片不能恢复。
2. messages.load.partial_blocks 只能恢复一部分块。
3. 消息列表内容与实际落库状态不一致。
4. 相关会话的调试与回放成本很高。
```

### 3.3 目前不是单条消息问题，而是批量历史会话都能复现

日志里不仅有 `5E338FA4`，还有大量其它 conversation：

```text
B6CD359D
2F868527
1E64CDB0
D2E9455A
0C1DC879
96CA4480
3E9884BB
...
```

说明：

```text
1. 这不是偶发脏数据。
2. 更像是消息块 schema 漂移后，老数据没有迁移或读取时没有兼容。
3. 只修一条消息没有意义，必须在仓储和 codec 层补兼容。
```

### 3.4 `partial_blocks` 说明当前恢复策略不够稳

日志中反复出现：

```text
deeptutor.messages.load.partial_blocks ... decodedBlocks=1 blockRows=3 contentLength=0
```

这意味着：

```text
1. 解码失败不会中断整个会话，但会造成块缺失。
2. UI 可能只看到 envelope 或 trace，看不到 askUser / text / thinking 等完整结构。
3. 同一个消息在“发送成功”与“重载后不完整”之间出现分裂。
```

### 3.5 流式结束后的最终状态日志缺少“恢复结果”快照

当前日志已经有：

```text
assistantMessage落库成功
messages.reload.start
messages.load.block_decode_failed
messages.reload.done
```

但缺少一个明确的“恢复总结”：

```text
1. 本次 reload 最终恢复了哪些 block。
2. 哪些 block 因兼容问题被降级。
3. 是否存在 askUser 卡片丢失。
4. 是否需要触发一次后台修复或重写入。
```

## 4. 当前 iOS 关键代码位置

| 职责 | 文件 |
| --- | --- |
| 消息块编码/解码协议 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorMessageCodec.swift` |
| 消息 block 数据模型 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Domain/DeepTutorMessageBlock.swift` |
| 流式事件数据模型 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Domain/DeepTutorStreamEvent.swift` |
| 本地仓储加载与落库 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorLocalChatStore.swift` |
| 消息块重建逻辑 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorMessageReducer.swift` |
| 流式事件到 UI/日志映射 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorAIRuntimeAdapter.swift` |
| trace 排版与恢复判断 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorTraceFormatter.swift` |
| 流式发送与重试入口 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/SendDeepTutorAIMessageUseCase.swift` |
| 会话页与消息列表刷新 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorChatPage.swift` |

## 5. 根因假设与排查顺序

### 5.1 P0 根因一：历史消息块 schema 与当前 codec 不兼容

最像的根因是：

```text
1. 旧消息是按旧字段写入。
2. 当前加载器按新字段解码。
3. 旧记录没有兼容别名或版本号判断。
```

需要确认：

```text
1. 这些失败记录是否都来自旧版本写入。
2. `callID` / `toolCallID` 是否存在命名分叉。
3. `StoredPayload` 是否缺少版本字段，导致无法判断向后兼容。
```

### 5.2 P0 根因二：单块解码失败被放大成消息恢复不完整

当前行为更像是：

```text
1. 一个 block 解码失败。
2. 整个消息变成 partial block。
3. 该消息的 UI 重新加载结果与写入结果不一致。
```

应该排查：

```text
1. 是否可以对单块失败进行降级跳过，而不是让整个 envelope 受影响。
2. 是否可以把 envelope / askUser / trace / text 分别容错恢复。
3. 是否需要补“修复后重写入”的数据补偿策略。
```

### 5.3 P0 根因三：askUser block 持久化字段不足

当前 `DeepTutorAskUserBlockPayload` 需要至少满足：

```text
payload
toolCallID
isResolved
answers
```

需要确认：

```text
1. 旧数据是否没有 `toolCallID`。
2. 这个字段是否在某次重构时才新增。
3. 是否存在从 event 恢复 block 时没有把 toolCallID 回写到 payload 的路径。
```

### 5.4 P1 根因四：流式完成后缺少一致的最终重建步骤

日志显示：

```text
assistantMessage 已落库成功
messages.reload.start
messages.load.block_decode_failed
```

说明落库和 reload 之间没有一个统一的“最终完整重建”校验。

需要确认：

```text
1. complete 后是否应该主动做一次本地自检。
2. 自检失败时是否应该立即记录一条 repair 日志。
3. 是否需要在保存前对 block payload 做一次 round-trip 编解码验证。
```

## 6. 后续实现要求

### 6.1 codec 层增加向后兼容解码

要求：

```text
1. `DeepTutorStreamEvent` 对历史字段名提供兼容。
2. `DeepTutorAskUserBlockPayload` 对旧记录进行容错读取。
3. `DeepTutorMessageBlockPayload` 统一支持版本判断或别名字段。
```

建议兼容方向：

```text
1. 为 callID / toolCallID 增加别名容错。
2. 为旧版 askUser payload 提供默认值或迁移映射。
3. 不要因为单字段缺失把整条消息完全丢掉。
```

### 6.2 本地仓储增加单块降级与修复标记

要求：

```text
1. block 解码失败时要明确记录是哪个 block、哪个 kind、哪个字段失败。
2. 允许 partial recovery，但要把失败块单独标记为可修复。
3. 不能静默吞掉失败，也不能让 UI 误以为完全恢复。
```

### 6.3 流式完成后增加 round-trip 校验

要求：

```text
1. 消息写入完成后，立即对 envelope / askUser / trace 做一次编码解码自检。
2. 自检失败时输出 repair 级日志。
3. 自检成功时输出 completed 级恢复摘要。
```

### 6.4 加入历史数据迁移或重写入策略

如果确认是旧 schema 导致的：

```text
1. 需要提供一次性迁移或按需重写入机制。
2. 迁移优先处理 `deepTutorEnvelope` 和 `deepTutorAskUser`。
3. 迁移后重新打开会话时必须能完整恢复。
```

### 6.5 DeepTutorChat 需要补齐恢复态日志

要求增加日志：

```text
deeptutor.messages.reload.summary
deeptutor.messages.load.block_recovered
deeptutor.messages.load.block_dropped
deeptutor.messages.load.repair_needed
```

字段建议：

```text
conversation
message
block
kind
decodedBlocks
droppedBlocks
repairCount
contentLength
askUserBlockCount
traceBlockCount
```

## 7. 日志需求

### 7.1 编解码失败日志补充

现有 `block_decode_failed` 已经有基本信息，但还需要补：

```text
1. payload schema 版本。
2. 失败块所属消息的 status。
3. 该消息的总 block 数与成功块数。
4. 是否来自历史迁移数据。
```

### 7.2 流式完成日志补充

需要增加：

```text
deeptutor.message.persist.completed
deeptutor.message.persist.roundtrip_ok
deeptutor.message.persist.roundtrip_failed
```

字段：

```text
conversation
message
model
finishReason
textLen
reasoningLen
blockCount
askUserBlockCount
roundtripStatus
durationMs
```

### 7.3 reload 结果摘要日志

需要增加：

```text
deeptutor.messages.reload.summary conversation=... total=... recovered=... dropped=... repairNeeded=...
```

用途：

```text
让排查者一眼知道：这次会话到底恢复完整了没有。
```

## 8. 验收用例

### 8.1 流式完成后可完整回放

输入：

```text
今天的天气怎么样
```

期望：

```text
1. 流式完成后消息正常落库。
2. 重新进入会话时 envelope、trace、askUser block 都能正常恢复。
3. 不再出现 `block_decode_failed ... callID` 或 `toolCallID`。
4. 消息列表与首次发送完成时一致。
```

### 8.2 历史消息至少可降级恢复

对于已有旧数据：

```text
1. 不要求一次性全部完美迁移，但不能整条消息不可读。
2. 即使有单块失败，也应尽量恢复文本和 trace。
3. askUser block 若无法完整恢复，必须明确标记缺失原因。
```

### 8.3 AskUser block 可重新打开

期望：

```text
1. 含 askUser 的消息重新加载后仍能看到提问块。
2. toolCallID 能正确关联用户回复。
3. 用户回复后消息状态能继续恢复到后续回答。
```

### 8.4 reload 摘要可见

期望：

```text
1. reload 完成后打印恢复摘要。
2. 摘要能清楚看到 droppedBlocks 和 repairNeeded。
3. 排查时无需翻完整个 block_decode_failed 刷屏日志。
```

## 9. 风险与注意事项

### 9.1 不要只压日志，不修协议

如果只是把 `block_decode_failed` 静音，问题仍然存在，历史数据仍然不可恢复。

### 9.2 不要只修 askUser

`deepTutorEnvelope` 的 `callID` 失败说明问题不止 askUser，必须一起处理事件流和 envelope 编解码。

### 9.3 不要把兼容写成吞错

兼容读取可以降级，但不能让系统看起来“正常”，实际上丢了完整事件流。

### 9.4 不要破坏现有流式完成

修复目标是“完成后能稳定重载”，不是改坏 `awaiting_user_input`、trace、askUser block 的现有成功路径。

## 10. 最终验收标准

实现完成后必须满足：

```text
1. 流式完成后的 assistant message 重新打开时不再出现 deepTutorEnvelope / deepTutorAskUser 的 keyNotFound 解码失败。
2. 历史会话可尽量完整恢复，至少不会因为单块失败导致整条消息不可用。
3. askUser block 能稳定恢复并和 toolCallID 关联。
4. reload 后有明确的恢复摘要日志。
5. 兼容策略不会吞掉真实错误，也不会导致消息内容错乱。
6. DeepTutorChat 的流式完成、重载、回放行为在本地库层对齐当前协议，不再出现大面积 partial_blocks。
```

本工单只完成分析与需求创建，未修改 Swift 业务实现代码。
