# DEEPTUTORCHAT-000028 AI 流式请求报文脱敏与 stream.partial 日志收口工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000028 |
| 工单类型 | P1 请求报文降噪 + 流式日志采样 + 调试收口优化 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 关联模块 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime` |
| 关联功能 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| 核心文件 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/OpenAICompatibleTextGateway.swift` |
| 关键调用点 | `DeepTutorAIRuntimeAdapter`、`GenerateDeepTutorConversationTitleUseCase` |
| 创建日期 | 2026-08-06 |
| 触发问题 | 运行时持续打印整段 `AI 流式网关请求报文`，同时 `deeptutor.stream.partial.mapped` 高频输出，导致日志继续刷屏 |
| 关联工单 | `DEEPTUTORCHAT-000026`、`DEEPTUTORCHAT-000027` |

## 1. 本工单目标

本工单解决两类高噪音日志：

```text
1. AI 流式网关请求报文输出整段 JSON，请求一长就非常吵。
2. stream.partial.mapped 在每个 token/片段上都可能打日志，流式阶段会把控制台刷满。
```

目标是把它们从“默认全量过程日志”改成“默认摘要 + 变化时输出 + 显式调试才展开”：

```text
1. 请求报文默认只看摘要，不看完整 body。
2. 请求体敏感字段继续脱敏，但不再默认打印完整 payload。
3. 流式 partial 只在结构变化、工具边界、ask_user/memberSelection、completion 等关键点输出。
4. 高速 token 追加阶段只保留节流后的样本日志或汇总日志。
```

## 2. 现象证据

附件中可以看到典型请求报文：

```text
AI 流式网关请求报文={"max_tokens":80,"stream":true,"temperature":0.29999999999999999,"model":"doubao-seed-evolving","messages":[...],"thinking":{"type":"disabled"}}
```

这类日志的问题：

```text
1. JSON 本身很长。
2. messages 内容会包含完整系统提示、用户输入、助手回复。
3. 即便已经做了 redact，默认输出仍然过大。
4. 如果是标题生成、重试、补发等小任务，报文重复打印会非常明显。
```

同时运行时还存在大量 stream partial 日志，例如：

```text
deeptutor.stream.partial.mapped conversation=ABED3F13 assistant=451666E8 ... answerLen=76 reasoningLen=55 events=content(2) ...
deeptutor.stream.partial.mapped conversation=ABED3F13 assistant=451666E8 ... answerLen=79 reasoningLen=55 events=content(1) ...
deeptutor.stream.partial.mapped conversation=ABED3F13 assistant=451666E8 ... answerLen=85 reasoningLen=55 events=content(2) ...
```

这些日志的共同特征是：

```text
1. 频率高。
2. 每条之间变化很小。
3. 对默认排障来说，大多数中间态没有新增价值。
```

## 3. 当前实现事实

### 3.1 请求报文日志源头在 Core/AIRuntime

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/OpenAICompatibleTextGateway.swift
```

当前实现：

```swift
let requestBodyText = String(data: requestBodyData, encoding: .utf8) ?? "<non-utf8>"
let redactedRequestBodyText = AIRuntimeRequestLogRedactor.redact(requestBodyText)
logger.debug("AI 流式网关请求开始 ...", module: .aiConfig)
logger.debug("AI 流式网关请求报文=\(truncate(redactedRequestBodyText, limit: 20000))", module: .aiConfig)
```

问题判断：

```text
1. `truncate(..., 20000)` 仍然太长。
2. 这不是“错误日志”，而是“调试日志”。
3. 默认控制台不应该承受完整请求体。
4. 对 title generation 这类小任务来说，完整 body 的可读性很低。
```

### 3.2 stream.partial.mapped 位于 DeepTutorAIRuntimeAdapter

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorAIRuntimeAdapter.swift
```

当前实现大意：

```swift
let shouldLogPartial = shouldUpdateUI && hasNewEvents
if shouldLogPartial {
    logger.debug("deeptutor.stream.partial.mapped ...", module: DeepTutorChatLog.module)
}
```

问题判断：

```text
1. 这已经有一点节流，但还不够。
2. streaming 阶段 token 级更新很多，仍会大量命中。
3. 日志里带 answerLen / reasoningLen / events / blocks，信息密度不高但频率很高。
4. 对控制台来说，这些是典型的“过程噪音”。
```

## 4. 根因判断

### 4.1 请求体日志没有按“摘要 vs 展开”分层

当前请求体日志把以下信息一次性打出：

```text
1. model
2. stream / temperature / max_tokens
3. messages 全文
4. thinking 参数
```

问题在于：

```text
1. 这些信息并非每次都需要完整展开。
2. 真正排障时，通常先看模型、消息数量、工具数量、温度、是否开启 reasoning 即可。
3. 只有在深度排查时才需要 body 级别详情。
```

### 4.2 stream.partial 是高频变更流，不适合逐次打点

stream partial 的天然属性就是：

```text
1. 频繁。
2. 每次变化很小。
3. 大多数片段只是 token 追加。
```

如果每个可见变化都打日志，就会出现：

```text
1. 控制台被单个回答刷满。
2. 关键的 tool / ask_user / completion 信息被冲淡。
3. 追 bug 时反而更难看清边界事件。
```

## 5. 优化目标

### 5.1 默认输出目标

```text
1. 默认不输出完整请求报文。
2. 默认不逐条输出 token 级 partial。
3. 默认只保留关键边界日志、摘要日志和错误日志。
```

### 5.2 调试目标

```text
1. 需要时可以打开完整请求体。
2. 需要时可以打开更密的 stream partial 日志。
3. 但这些都必须是显式开关，不是默认行为。
```

## 6. 优化方案

### 6.1 请求报文改成“摘要优先”

建议把请求日志拆成两层：

```text
1. 默认摘要：model、endpoint、messages count、tools count、temperature、max_tokens、thinking enabled、request body hash/length。
2. 详情展开：仅在 verbose 开关打开时才打印完整 JSON。
```

建议摘要示例：

```text
AI 流式网关请求摘要 model=doubao-seed-evolving endpoint=https://... messages=2 tools=0 max_tokens=80 temperature=0.3 bodyBytes=12345 bodyHash=...
```

### 6.2 请求体做强脱敏与短预算

即便进入调试展开，也建议：

```text
1. 控制 body 输出上限远小于 20000。
2. 对 messages 内容继续脱敏。
3. 优先输出可读摘要，不输出整段对话正文。
4. 只在手动排查时允许完整 body。
```

### 6.3 stream.partial 只保留关键边界

建议把 `stream.partial.mapped` 的输出进一步收口为：

```text
1. 首次出现新 toolCall 时输出一次。
2. ask_user / memberSelection / quiz / result / completion 这类结构事件输出。
3. 连续内容追加阶段按时间窗采样，而不是逐条打印。
4. answerLen 只有跨阈值增长时才补打一条。
```

### 6.4 按事件类型分流日志

建议把 partial 事件分成三类：

```text
1. 结构事件：toolCall、ask_user、memberSelection、quizQuestion、result。
2. 进度事件：reasoning/content 追加。
3. 完成事件：completion / final turn / salvage。
```

默认策略：

```text
1. 结构事件必打或低频打。
2. 进度事件采样打。
3. 完成事件必打。
```

### 6.5 增加时间窗节流或增量阈值

建议给 partial 日志加一种或两种条件：

```text
1. 距离上次输出超过 N 毫秒。
2. answerLen / reasoningLen 增量超过阈值。
3. events 类型发生变化。
```

这样可以避免纯 token 级刷新把同一类日志刷到过密。

### 6.6 给这两类日志单独加 verbose 开关

建议新增：

```text
1. `DeepTutorDebugFlags.verboseAIRuntimeRequestLogs`
2. `DeepTutorDebugFlags.verboseAIRuntimeStreamLogs`
```

默认建议：

```text
1. Release: 关闭。
2. Debug: 关闭，需 UserDefaults 显式开启。
```

## 7. 建议落点

### 7.1 优先改造文件

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/AIRuntime/OpenAICompatibleTextGateway.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorAIRuntimeAdapter.swift
```

### 7.2 受益调用点

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/GenerateDeepTutorConversationTitleUseCase.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/SendDeepTutorAIMessageUseCase.swift
```

### 7.3 需要收口的日志

```text
1. `AI 流式网关请求报文`
2. `deeptutor.stream.partial.mapped`
3. `deeptutor.stream.completion.mapped`
4. 与 title generation 相关的 raw/sanitized/fallback 连续输出
```

## 8. 验收标准

### 8.1 日志层面

```text
1. 默认不再打印整段请求 JSON。
2. 默认不会被 token 级 stream partial 刷屏。
3. 关键结构事件仍然可见。
4. 显式打开 verbose 后，可以恢复完整排障信息。
```

### 8.2 体验层面

```text
1. 控制台显著安静。
2. 仍能看出一次请求发生了什么。
3. 调试时仍有足够上下文。
```

### 8.3 技术层面

```text
1. 请求报文只保留摘要与可控展开能力。
2. stream partial 引入采样/阈值策略。
3. 日志调整不影响 AI 请求和流式响应行为。
```

## 9. 不做项

```text
1. 不改变 AI 请求协议。
2. 不改模型参数计算逻辑。
3. 不删除错误响应和异常日志。
4. 不把结构事件也一并静音。
```

## 10. 建议执行顺序

```text
1. 先把请求报文改成摘要输出。
2. 再给 stream.partial 加时间窗或阈值采样。
3. 然后补 verbose 开关。
4. 最后再评估是否需要对 title generation 单独收口。
```

