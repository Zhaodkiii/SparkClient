# DEEPTUTORCHAT-000029 Quiz 题型解析与会话列表刷新摘要去重工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000029 |
| 工单类型 | P1 题型解析降噪 + 会话列表刷新摘要收口 + 调试可观测性优化 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标模块 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| 相关核心文件 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Domain/DeepTutorQuizModels.swift` |
| 相关日志文件 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorChatLogging.swift` |
| 相关列表刷新文件 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorChatViewModel.swift` |
| 创建日期 | 2026-08-06 |
| 触发问题 | 运行时持续出现大量重复 `deeptutor.quiz.question_type.resolved / fallback`，以及重复的 `DeepTutor 会话列表已刷新` 摘要日志 |
| 关联工单 | `DEEPTUTORCHAT-000026`、`DEEPTUTORCHAT-000027`、`DEEPTUTORCHAT-000028` |

## 1. 本工单目标

本工单要解决的是“同一轮解析、同一轮刷新里重复打印同类结果”的问题：

```text
1. Quiz 题型解析日志不要对每个题目、每次重算都默认刷屏。
2. `resolved` / `fallback` 这类题型结论要按 questionID 做幂等去重。
3. `DeepTutor 会话列表已刷新` 不要在 count 和来源没变化时重复打印。
4. 默认控制台只保留真正有变化的摘要，调试时再显式展开更多细节。
```

用户当前感知到的问题：

```text
1. 同一批题目会反复输出大量 `quiz.question_type.resolved`
2. `quiz.question_type.fallback` 也会在多个回补/重解析路径里重复出现
3. `DeepTutor 会话列表已刷新` 这种列表摘要在 database_change 链路里出现频率过高
4. 这些日志不是错误，但默认状态下已经没有足够的新信息
```

## 2. 现象证据

附件日志片段：

```text
DeepTutor 会话列表已刷新，count=147, source=database_change, scenario=deepTutor
deeptutor.quiz.question_type.resolved questionID=1EF72213-D9B1-422B-832E-DE1AA75C0B9B rawType=- resolvedType=choice optionCount=4 reason=options_present_promote_choice
deeptutor.quiz.question_type.resolved questionID=A234181C-E6D3-430F-BD1E-740A26C29741 rawType=- resolvedType=choice optionCount=2 reason=options_present_promote_choice
deeptutor.quiz.question_type.fallback questionID=217954CD-A13A-4CEA-9717-A02448D56027 rawType=- fallbackType=choice reason=missing_type_default_choice
deeptutor.quiz.question_type.resolved questionID=q1 rawType=- resolvedType=choice optionCount=3 reason=options_present_promote_choice
```

这类输出的问题是：

```text
1. questionID 不同，但模式高度一致。
2. resolvedType 大多是 choice，fallback 大多是 missing_type_default_choice。
3. 在流式、回补、恢复、重新解析等路径上会重复出现。
4. 控制台看到的是大量“解析事实”，不是“异常事实”。
```

对于会话列表刷新：

```text
1. `database_change` 触发很频繁。
2. `refreshConversations` 每次都会输出 `DeepTutor 会话列表已刷新`
3. 只要 count 仍然相同，这条日志往往没有新增价值。
```

## 3. 当前实现事实

### 3.1 题型解析日志是在 resolve 里直接打的

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Domain/DeepTutorQuizModels.swift
```

关键逻辑：

```swift
static func resolve(
    raw: String?,
    options: [DeepTutorQuizOption],
    questionID: String
) -> DeepTutorQuizQuestionType {
    ...
    if options.count >= 2 {
        if looksLikeConcept {
            if rawNormalized != .concept {
                DeepTutorChatLog.quizQuestionTypeResolved(...)
            }
            return .concept
        }
        if rawNormalized != .choice {
            DeepTutorChatLog.quizQuestionTypeResolved(...)
        }
        return .choice
    }
    ...
    if raw == nil || ... {
        DeepTutorChatLog.quizQuestionTypeFallback(...)
        return .choice
    }
    ...
}
```

问题判断：

```text
1. 这是每题解析都会经过的逻辑。
2. 同一题在流式、结果、恢复路径里可能被多次 resolve。
3. 日志默认没有 questionID 级去重。
4. `resolved` 的大多数输出只是“options present, promote choice”。
```

### 3.2 会话列表刷新日志在 ViewModel 里直接输出

代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorChatViewModel.swift
```

关键代码：

```swift
logger.debug(
    "DeepTutor 会话列表已刷新，count=\(conversations.count), source=\(source), scenario=\(DeepTutorScenarioConstants.scenario)",
    module: DeepTutorChatLog.module
)
```

无论是否传入 `expectedCreatedID`，只要 refresh 跑完就会打这条摘要日志。

问题判断：

```text
1. database_change 场景下 refresh 可能很频繁。
2. count 没变化时，这条摘要几乎没有新增信息。
3. 如果同一 source 连续触发多次，会出现重复刷屏。
```

### 3.3 现有调试开关已经存在，但还不够细

`DeepTutorDebugFlags` 里已有：

```text
1. verboseChatRefreshLogs
2. verboseChatRenderLogs
3. verboseChatStreamLogs
4. verboseCapabilityLogs
5. verboseCapabilitySnapshots
6. verboseAIRuntimeRequestLogs
7. verboseAIRuntimeStreamLogs
```

这说明：

```text
1. 项目已经开始朝“默认收口、按需展开”走。
2. 但 quiz 题型解析和会话刷新摘要还没有接入更细的去重语义。
3. 因此即使有 debug 开关，重复结果仍可能在默认路径里持续出现。
```

## 4. 根因判断

### 4.1 Quiz 题型日志缺少幂等键

题型解析的稳定事实应该是：

```text
1. 同一个 questionID 的 resolvedType 通常不会频繁变。
2. 如果变了，说明题目结构或解析输入变了。
3. 如果没变，重复打印没有价值。
```

当前缺少：

```text
1. 按 questionID 去重
2. 按 questionID + resolvedType + reason 去重
3. 对 fallback 与 resolved 分别限制一次性输出
```

### 4.2 会话列表刷新摘要缺少变化条件

当前刷新摘要更像是：

```text
1. 每次 refresh 完成就打印。
2. 不管 count 是否变化。
3. 不管 source 是否已在短时间内重复。
```

这会把 `database_change` 这种高频事件放大成刷屏。

## 5. 优化目标

### 5.1 Quiz 题型解析目标

```text
1. 同一 questionID 的相同解析结论只打印一次。
2. 同一 questionID 的 repeated fallback 不再重复刷。
3. 只有题型真的从 shortAnswer 变成 choice，或者从 raw_type 变成 fallback 时才打印一次。
4. 默认输出以异常、变化和首次解析为主。
```

### 5.2 会话列表刷新目标

```text
1. count 未变化时，不再重复输出“已刷新”摘要。
2. source 相同且列表内容未变化时，不再重复打印。
3. database_change 触发的 reload 只在实际引起列表差异时输出摘要。
4. 调试时可以打开 verbose 查看每次刷新。
```

## 6. 优化方案

### 6.1 给题型解析加 questionID 级去重

建议去重键：

```text
questionID + resolvedType + reason + optionCount + rawType
```

去重策略：

```text
1. 同一 questionID 同一结论只打一次。
2. 只有从 fallback 切换为 resolved，或者 resolvedType 发生变化时才补打一条。
3. `options_present_promote_choice` 这种高频正常路径默认降级为 debug 或汇总日志。
```

### 6.2 题型解析保留异常优先

建议保留：

```text
1. fallback 发生且影响题型语义的日志
2. 解析失败日志
3. 题型从预期值变到不预期值的 warning
```

建议降噪：

```text
1. 纯 `choice` promotion 成功的 debug
2. 同一 questionID 重复的 resolved/fallback
```

### 6.3 会话列表刷新改成“变化摘要”

建议刷新摘要增加条件：

```text
1. count 变化
2. 列表 ID 顺序变化
3. latest preview 变化
4. source 变化且确实影响列表
```

建议输出改成：

```text
DeepTutor 会话列表已刷新，count=147, source=database_change, changed=true, scenario=deepTutor
```

若没有变化：

```text
1. 不打印
2. 或仅在 verbose 模式下打印 skipped summary
```

### 6.4 database_change 触发的刷新做合并

建议对数据库变化事件增加更强的 debounce / coalesce：

```text
1. 短时间内多次 database_change 合并成一次 refresh。
2. 如果合并后列表无变化，则不输出刷新摘要。
3. 只保留最终完成的那一次变化日志。
```

### 6.5 调试开关继续细分

建议新增：

```text
1. `DeepTutorDebugFlags.verboseQuizParseLogs`
2. `DeepTutorDebugFlags.verboseConversationListRefreshLogs`
```

默认建议：

```text
1. Release: 关闭
2. Debug: 也关闭，需显式打开
```

## 7. 建议落点

### 7.1 优先改造文件

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Domain/DeepTutorQuizModels.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorChatViewModel.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorChatLogging.swift
```

### 7.2 配套可检查文件

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorQuizExtractor.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorDebugFlags.swift
```

### 7.3 需要收口的日志

```text
1. `deeptutor.quiz.question_type.resolved`
2. `deeptutor.quiz.question_type.fallback`
3. `DeepTutor 会话列表已刷新`
4. `DeepTutor 会话列表已加载`
```

## 8. 验收标准

### 8.1 题型解析验收

```text
1. 同一 questionID 不会重复输出相同 resolved/fallback。
2. `options_present_promote_choice` 不再在正常路径刷屏。
3. 真正的 fallback / 解析失败仍然保留。
```

### 8.2 列表刷新验收

```text
1. database_change 触发的 refresh 不会无限重复打印“已刷新”。
2. count 未变化时，默认不输出刷新摘要。
3. 列表确实变化时，仍然可以看到一次明确的刷新结果。
```

### 8.3 技术验收

```text
1. 日志去重不影响解析结果和列表数据。
2. 去重键不会误吞真正不同的解析结论。
3. 调试开关默认关闭，不改变业务行为。
```

## 9. 不做项

```text
1. 不改 quiz 题目生成策略本身。
2. 不改数据库监听机制本身。
3. 不删除 warning 和 error。
4. 不把所有解析细节一刀切静音。
```

## 10. 建议执行顺序

```text
1. 先给 quiz 题型解析加 questionID 级去重。
2. 再把会话列表刷新改成变化摘要。
3. 然后把 database_change 合并成更强的 debounce。
4. 最后补一个 verbose 题型解析开关。
```

