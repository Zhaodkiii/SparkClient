# DEEPTUTORCHAT-000023 卡片流式可见但完成后丢失与工具展示对齐 DeepTutor-main 修复工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000023 |
| 工单类型 | P0 卡片/工具展示稳定性修复 + DeepTutor-main 对齐 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| iOS 功能目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| Web 参考工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main` |
| 创建日期 | 2026-08-05 |
| 触发问题 | AI 回复过程中能看到卡片，消息完成后卡片消失 |
| 关联工单 | `DEEPTUTORCHAT-000013`、`DEEPTUTORCHAT-000019`、`DEEPTUTORCHAT-000021`、`DEEPTUTORCHAT-000022` |
| 核心约束 | 工具使用、卡片展示、完成态保留都要完全对齐 DeepTutor-main；禁止用临时状态或 fixture 伪装 |

## 1. 本工单目标

用户反馈的实际问题：

```text
1. AI 回复中可以正常看到卡片。
2. 消息回复完成之后卡片就看不到了。
3. 工具使用或者卡片的显示功能需要完全对齐 DeepTutor-main。
```

本工单目标：

```text
1. 明确“流式可见、完成后消失”不是单纯卡片样式问题，而是流式态与最终态的归约/持久化/重放不一致。
2. 对比 DeepTutor-main Web 的工具卡片与问答卡片渲染方式，冻结 iOS 端应该保持的展示语义。
3. 记录 iOS 当前卡片/工具展示链路的失配点。
4. 给出修复方案：最终态保留卡片、重放一致、工具状态不因 ready 态丢失。
5. 明确后续不能把卡片仅当作“流式动画”，必须成为消息 block 的稳定一部分。
```

## 2. 现场问题证据

### 2.1 现象描述

用户实际观察到：

```text
AI 回复进行中时，卡片可见；
回复完成后，卡片消失；
工具使用 / 卡片显示效果与 DeepTutor-main 不一致。
```

这意味着：

```text
1. 流式阶段存在临时可见的卡片状态。
2. ready/final 阶段发生了重建、重放或刷新，导致卡片未被保留。
3. 当前 iOS 可能把“是否显示卡片”错误地绑定到了流式生命周期，而不是 message block 的最终状态。
```

### 2.2 当前 iOS 代码事实

iOS 消息气泡入口：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Bubbles/DeepTutorAssistantBubble.swift
```

该组件按 `message.blocks` 渲染：

```text
ForEach(displayBlocks) { block in
    blockView(block)
}

if message.status == .ready {
    actionsRow
}
```

结论：

```text
只要 block 还在，ready 状态本身不会隐藏卡片。
因此“完成后消失”更像是 final/reload 之后 message.blocks 变了，而不是 Bubble 组件主动把卡片藏掉。
```

消息归约入口：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorMessageReducer.swift
```

问答分支当前逻辑：

```text
1. 先用 DeepTutorQuizExtractor.extract(from: message) 提取 payload。
2. 成功则 append .quiz block。
3. 失败且 ready，则记录 quizBlockMissingAfterFinal。
4. 失败且有 parse failure，则可能 append .quizParseError block。
```

结论：

```text
卡片是否存在，取决于最终消息是否还能重建出结构化 payload。
一旦最终态重放没有恢复同样的 quiz/tool block，UI 就会消失。
```

### 2.3 本次日志信号

本次已经反复看到的日志模式包括：

```text
deeptutor.trace.final_phase ... isStreaming=true hasFinalContent=false isFinalAnswerPhase=false
deeptutor.quiz.extract.failed ... reason=no_quiz_data
deeptutor.quiz.block.missing_after_final ... reason=no_quiz_payload
```

同时 debug snapshot 里已经补出了：

```text
quizBlockCount
quizQuestionCount
quizExtractionSource
quizParseFailureReason
resultHasSummaryJSON
streamingQuizQuestionEventCount
```

结论：

```text
当前问题不是“完全没有生成卡片”，而是“流式时生成过，完成态重建时丢了”。
```

## 3. DeepTutor-main Web 对标事实

### 3.1 Web 工具/卡片的触发不是流式临时态

Web 文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ChatMessages.tsx
```

问答分支的关键逻辑：

```text
if resultEvent exists -> extractQuizQuestions(resultEvent.metadata)
else -> extractStreamingQuizQuestions(msg.events)
quizQuestions && quizQuestions.length > 0 -> render QuizViewer
```

结论：

```text
Web 不是靠“当前还在流式中”来决定卡片是否存在。
卡片是由 message.events / result metadata 重新导出的稳定结果。
```

### 3.2 Web 完成后仍保留卡片语义

Web 的 QuizViewer 直接消费：

```text
questions
sessionId
turnId
language
```

它会持续展示：

```text
1. 题号导航。
2. 题目卡片。
3. 答题输入。
4. 检查答案。
5. 追问/收藏/解释。
```

结论：

```text
Web 的完成态不是“卡片消失”，而是“卡片稳定保留在消息里”。
iOS 需要对齐这个语义。
```

### 3.3 Web 的 ask_user / quiz / tool 卡片都是消息子块

Web 消息渲染：

```text
AssistantActivity
AssistantResponse
QuizViewer
AskUserOptions
```

它们的共同点：

```text
1. 都从消息事件或结构化结果中提取。
2. 都是消息的一部分，不是纯临时 overlay。
3. 完成后仍然回显在消息流里。
```

## 4. iOS 当前偏差与疑点

### 4.1 主要偏差

偏差不是单一 UI 组件，而是整条链路：

```text
1. 流式阶段出现的临时卡片，最终态没有稳定落成消息 block。
2. ready 之后可能走了重放/重建逻辑，但最终消息没有保住同样的卡片结构。
3. 当前 iOS 对工具卡片、问答卡片、恢复态卡片的状态一致性不足。
```

### 4.2 重点怀疑位置

需要优先审计的点：

```text
1. `SendDeepTutorAIMessageUseCase`
   - ready 后的最终状态写回与数据库 flush 是否覆盖掉了流式期间的 block 形态。

2. `DeepTutorMessageReducer`
   - final ready 时是否重新归约了消息，但缺失了 quiz / ask_user / memberSelection 等 block。

3. `DeepTutorLocalChatStore`
   - block 编解码是否对某些 tool/card block 做了降级或丢弃。

4. `DeepTutorChatViewModel`
   - 是否在 ready / database change 后触发了重载覆盖当前内存态。

5. `DeepTutorAssistantBubble`
   - 是否存在某些 block 在 ready 后被错误过滤、被上层条件包裹、或被消息刷新替换。
```

### 4.3 当前不是要修的错误方向

不要把问题误判成：

```text
1. 只是卡片高度不够。
2. 只是完成态 actionsRow 覆盖了卡片。
3. 只是某个按钮状态问题。
4. 只是问答题目本身有问题。
5. 只是某个颜色或动画没对齐。
```

实际问题是：

```text
完成态重建后，卡片相关的 block / payload / 渲染条件没有和 Web 保持同一份稳定数据源。
```

## 5. 根因分析

### 5.1 直接根因

```text
流式阶段的卡片很可能来自临时 in-memory 状态；
final ready 阶段的消息重建或持久化回放，没有保住相同的结构化卡片数据；
因此卡片从消息流里消失。
```

### 5.2 架构根因

```text
当前 iOS 还没有把“工具/卡片”完全定义成消息事件和 block 的单一事实源。
Web 的做法是：事件 -> 归约 -> 消息 block -> 组件渲染。
iOS 当前更像：流式时先临时画出来，完成后再重新同步状态。
这会天然造成卡片消失或闪断。
```

### 5.3 可能的技术断点

```text
1. 事件流中某些 tool/card payload 没有被完整保存。
2. ready 状态的 flush/reload 触发了重算，但新算出来的 message.blocks 不等于流式态。
3. 某些 tool/card block 在编码/解码时被降级丢弃。
4. reducer 只在流式 partial 下补齐了 block，final ready 没有二次确认。
5. 当前 debug / reload 路径没有把“最终态是否保留卡片”作为验收项。
```

## 6. 修复方案

### 6.1 P0 方案一：卡片必须成为最终态消息 block

要求：

```text
1. 流式期间出现的 quiz / ask_user / memberSelection / tool card，最终必须落成可重放的 message block。
2. ready 状态不能把这些 block 从消息里抹掉。
3. 重启、切换会话、刷新、数据库重载后，卡片仍然要重新出现。
4. 卡片的最终展示必须由 block 决定，而不是由“当前是不是还在 streaming”决定。
```

### 6.2 P0 方案二：重建路径与流式路径使用同一份归约规则

要求：

```text
1. streaming 中的临时呈现和 ready 后的最终呈现，必须经过同一套 reducer 语义。
2. 不允许 final ready 再走一套更弱的 fallback 逻辑。
3. tool/card block 的生成应以 events + result metadata 为准，不以 content 文本是否还在为准。
4. 如果流式阶段能看到卡片，ready 阶段必须用同一数据重新算出同样的卡片。
```

### 6.3 P0 方案三：持久化和恢复必须保持卡片块

要求：

```text
1. block 编解码必须保证 .quiz、.askUser、.memberSelection、.quizParseError 等工具块可完整 round-trip。
2. ready 后触发的数据库落库和重新加载，不能丢失这些 block。
3. 如果某个 block 无法反序列化，必须记录明确 decode failure，并提供修复兜底，而不是静默消失。
4. Debug snapshot 必须能证明“完成后卡片仍在”。
```

### 6.4 P1 方案四：对齐 Web 的展示分层

Web 的稳定模式是：

```text
AssistantActivity
正文
QuizViewer / AskUserOptions / 其他能力卡片
```

iOS 应对齐为：

```text
1. 先显示 assistant trace / activity。
2. 再显示正文。
3. 再显示工具/卡片 block。
4. ready 只影响动作按钮和状态，不影响卡片存在。
```

### 6.5 P1 方案五：增加完成态回归日志

建议补充：

```text
deeptutor.block.lifecycle.visible_during_stream
deeptutor.block.lifecycle.preserved_on_ready
deeptutor.block.lifecycle.lost_on_ready
deeptutor.block.lifecycle.rehydrated_from_db
deeptutor.block.codec.roundtrip_failed
deeptutor.block.reducer.final_mismatch
```

日志必须至少携带：

```text
conversationID
assistantMessageID
blockKind
source
statusBefore
statusAfter
reason
```

## 7. 需要重点检查的文件

### 7.1 业务归约

| 文件 | 检查点 |
| --- | --- |
| `SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorMessageReducer.swift` | streaming 与 ready 的 block 生成是否一致，final 是否会丢卡片 |
| `SparkClient/Projects/Features/DeepTutorChat/Application/SendDeepTutorAIMessageUseCase.swift` | ready 后的 flush / commit / status 变更是否覆盖 block |
| `SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorChatViewModel.swift` | database change / reload 是否重建了更弱的 message 形态 |

### 7.2 持久化与解码

| 文件 | 检查点 |
| --- | --- |
| `SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorLocalChatStore.swift` | block encode / decode 是否会丢失卡片块 |
| `SparkClient/Projects/Features/DeepTutorChat/Domain/DeepTutorMessageBlock.swift` | block enum / payload 是否支持稳定 round-trip |
| `SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorChatDebugExporter.swift` | 是否能直接证明 ready 后 quiz/tool block 仍存在 |

### 7.3 展示层

| 文件 | 检查点 |
| --- | --- |
| `SparkClient/Projects/Features/DeepTutorChat/Presentation/Bubbles/DeepTutorAssistantBubble.swift` | 是否有条件把已存在的 block 隐藏掉 |
| `SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorMessageRowModel.swift` | 是否在状态变化时重算行模型导致卡片丢失 |
| `SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorChatPage.swift` | 列表刷新 / 复位是否使已完成消息重排后卡片消失 |

## 8. 与 DeepTutor-main 的对齐要求

### 8.1 Web 侧对齐

Web 对齐基线：

```text
1. 卡片由消息事件/结构化结果驱动。
2. 消息完成后仍然保留卡片。
3. 追问、答案卡、问答卡都属于消息内容，不是临时浮层。
4. 重新打开会话时，卡片仍可从事件或结果重建。
```

### 8.2 iOS 侧对齐

要求：

```text
1. 流式可见不算完成。
2. 完成态必须和流式态拥有同一消息 block 语义。
3. 任何工具卡片都不能因为 status.ready 而自动消失。
4. 消息列表重载后，卡片恢复结果必须与 Web 一致。
```

## 9. 验收标准

### 9.1 基础验收

Given：

```text
用户发送一条会触发工具/问答卡片的消息。
```

When：

```text
AI 生成过程中先展示卡片，随后消息状态变为 ready。
```

Then：

```text
1. 卡片在流式阶段可见。
2. 卡片在 ready 完成后仍然可见。
3. 切换页面、返回会话、数据库重载后卡片仍然可见。
4. debug snapshot 中 blockKinds 和 blockCount 在 ready 前后保持一致或可解释一致。
5. 无“只在 streaming 可见、ready 后丢失”的回归。
```

### 9.2 Web 对齐验收

Given：

```text
同一能力在 DeepTutor-main Web 中完成后依然能看到卡片。
```

Then：

```text
1. iOS 的消息完成态不应比 Web 更弱。
2. iOS 的卡片展示层级、操作区、恢复后的重建结果必须一致。
3. 工具使用与问答卡片语义应完全对齐 Web。
```

### 9.3 持久化验收

```text
1. block round-trip 不丢失 quiz / ask_user / memberSelection / tool block。
2. ready 后从数据库恢复，卡片仍能重新出现。
3. decode failure 需要可观测，不可静默消失。
```

## 10. 风险与待确认项

| 风险 | 影响 | 处理 |
| --- | --- | --- |
| 流式态和 ready 态由两套不同逻辑驱动 | 卡片闪现或消失 | 收敛到单一 reducer 与单一持久化语义 |
| block 编解码不完整 | 重载后卡片丢失 | 补 round-trip 测试和 decode failure 日志 |
| ready 后 rehydrate 覆盖了内存态 | 用户看到卡片消失 | 检查 ViewModel 的刷新时机和快照来源 |
| 工具卡片只作为临时 UI | 与 Web 长期不一致 | 改成消息 block 驱动的稳定结构 |
| 只修 UI 不修数据链路 | 问题会反复出现 | 先修 block/source，再修展示 |

待确认：

```text
1. 具体是哪个 final/reload 路径让卡片丢失。
2. 目前工具卡片在 DB 中是否完整序列化。
3. 卡片消失是否发生在新消息生成后立即，还是切换会话/重载后才出现。
4. 是否存在某些 capability 在 ready 后被消息行模型合并掉。
```

## 11. 结论

本次问题的准确结论：

```text
卡片在 AI 回复中可见，但完成后消失，说明当前 iOS 的卡片/工具展示不是稳定消息块事实源。
流式阶段和 ready 完成态没有共享同一份保留语义。
这与 DeepTutor-main Web 的做法不一致。
```

修复方向：

```text
1. 让卡片成为最终消息 block，而不是临时流式 UI。
2. 确保 ready 后重建、数据库恢复、页面刷新都能重新得到同样的卡片。
3. 对齐 Web 的消息事件驱动卡片展示模式。
4. 禁止用临时状态、fixture 或流式专用 UI 代替最终态。
```
