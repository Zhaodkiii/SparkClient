# DEEPTUTORCHAT-000011 AskUser 提交后未继续回答与同 Turn 恢复链路对齐工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000011 |
| 工单类型 | P0 交互阻断 + DeepTutor Web 同 Turn 恢复对齐 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| iOS 功能目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| Web 参考工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main` |
| 日志附件 | `/Users/hua/.codex/attachments/5311a866-aafa-4804-814c-39e6ee129948/pasted-text.txt` |
| 问题截图 | `/var/folders/l4/gly2bq810gz95r7ttwj23l9h0000gn/T/codex-clipboard-d38a2d48-bf6e-4c5f-a78c-076e233bb8f0.png` |
| 创建日期 | 2026-08-05 |
| 模型场景约束 | 继续使用项目已有通用 `.chat` 场景，不新增 `.deepTutor` |
| 关联工单 | `DEEPTUTORCHAT-000008`、`DEEPTUTORCHAT-000009`、`DEEPTUTORCHAT-000010` |

## 1. 本工单目标

本工单解决 AskUser 卡片选择城市并点击 `Submit` 后，DeepTutorChat 没有继续生成天气回答的问题。

用户期望：

```text
1. 用户选择“上海”并点击 Submit。
2. AskUser 卡片进入已回答状态。
3. AI 继续同一轮工具链路。
4. 后续调用 query_location / query_weather，或至少继续生成“上海天气”回答。
5. 对话流对齐 DeepTutor-main，不把用户的卡片回答当成普通新消息，也不只更新本地卡片状态。
```

当前实际：

```text
1. 点击 Submit 后日志显示“提交 ask_user 完成”。
2. 本地只追加了 askUserResolved。
3. 没有出现新的 AI 推理开始。
4. 没有出现 query_weather 工具调用。
5. UI 停在提问卡片附近，没有继续回答。
```

本工单只创建需求与技术方案，不直接改动 Swift 代码。

## 2. 日志结论摘要

### 2.1 提交动作已经触发

日志：

```text
提交 ask_user 开始，conversation=9567AB5D, message=5100DBF8, answers=上海
DeepTutor 追问已恢复（inline），toolCall=legacy-ask-user-5FFD499D, answers=1
deeptutor.message.persist.completed conversation=9567AB5D message=5100DBF8 status=已就绪 blockCount=4 askUserBlockCount=1 contentLength=30
提交 ask_user 完成，conversation=9567AB5D, cost=0.193s
```

说明：

```text
1. 卡片 Submit 的点击事件已经到达 ViewModel。
2. `resolveAskUser` 已经执行。
3. 本地消息已重新落库。
4. 但这只是本地状态更新，不等于继续 AI 回答。
```

### 2.2 提交后没有继续 AI 推理

日志中提交后没有出现：

```text
DeepTutor AI 推理开始
deeptutor.tool_policy.resolved
deeptutor.tool_schema.outbound
AI 流式网关请求开始
query_weather tool_call
DeepTutor AI 流式完成
```

说明：

```text
AskUser 提交后没有恢复 agent loop，也没有启动新的同上下文 AI turn。
```

### 2.3 toolCallID 在兼容恢复中不断变化

日志中同一条 message 出现多个不同的 legacy toolCallID：

```text
legacy-ask-user-5FFD499D
legacy-ask-user-6446F5D0
legacy-ask-user-19630B75
legacy-ask-user-427D13B6
legacy-ask-user-BA32FF35
legacy-ask-user-FEA6C78F
```

对应代码线索：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorMessageCodec+Compatibility.swift

legacyCallID(prefix:) 使用 UUID() 生成：
legacy-\(prefix)-\(UUID().uuidString.prefix(8))
```

影响：

```text
1. 用户提交时 resolve 的 toolCallID 和重载后 askUser block 的 toolCallID 不一致。
2. `.askUserResolved(toolCallID: answers:)` 很可能匹配不到当前卡片。
3. 卡片无法稳定进入 resolved 状态。
4. 同一 tool call 无法作为后续继续推理的上下文锚点。
```

### 2.4 reload 被重复触发，但只是重新生成同一张卡片

日志：

```text
deeptutor.messages.reload.start conversation=9567AB5D ...
deeptutor.messages.load.block_recovered ...
deeptutor.ask_user.payload_validated ...
deeptutor.message_reducer.ask_user_block_created ...
deeptutor.messages.reload.done ...
```

说明：

```text
提交后系统反复 load/reload，本地 block 被重建，但没有转入下一步 AI 回答。
```

## 3. DeepTutor-main 对齐基线

### 3.1 Web 的 AskUser 提交语义

参考文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/context/UnifiedChatContext.tsx
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/lib/unified-ws.ts
```

Web 关键链路：

```text
AskUserOptions.onSubmit
  -> ChatMessageList.onSubmitUserReply
  -> UnifiedChatContext.submitUserReply
  -> WebSocket send({ type: "submit_user_reply", turn_id, text/answers })
  -> backend substitutes reply into matching role=tool message
  -> agent loop resumes on the same turn
  -> new stream events continue arriving
  -> original assistant message gains ask_user_resolved progress
  -> final answer renders below card
```

Web 的 `SubmitUserReplyMessage` 语义：

```text
type: "submit_user_reply"
turn_id: string
text?: string
answers?: Array<{ questionId: string; text: string }>
```

关键对齐点：

```text
1. 提交 AskUser 不是普通新消息。
2. 提交 AskUser 不是只改本地卡片状态。
3. 它必须恢复同一个 active turn。
4. 恢复后后续模型输出应继续进入同一个 assistant turn 的消息流。
```

### 3.2 Web 的 resolved 状态

参考：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/AskUserOptions.tsx
```

Web 行为：

```text
progress event metadata.ask_user_resolved=true
  -> 找到匹配 tool_call_id 的 ask_user segment
  -> data.resolved=true
  -> ResolvedAskUserCard 展示用户答案摘要
```

iOS 对齐含义：

```text
1. `.askUserResolved` 必须使用同一个稳定 toolCallID。
2. 卡片 resolved 只是第一步。
3. resolved 后必须继续接收后续 content/tool events。
```

## 4. 当前 iOS 偏差清单

| 类型 | DeepTutor-main 目标 | iOS 当前表现 | 影响 |
| --- | --- | --- | --- |
| 提交语义 | `submit_user_reply` 恢复同一 turn | 只调用本地 `resolveAskUser` | 不继续回答 |
| 后续推理 | 继续 agent loop 并流式输出 | 没有新 AI 推理日志 | query_weather 不会执行 |
| toolCallID | 使用同一个 tool_call_id 匹配卡片 | legacy ID 每次 reload 变化 | resolved 匹配不稳定 |
| 状态机 | ask_user pending -> resolving -> streaming -> ready | resolvingAskUser -> ready | 跳过 streaming |
| 消息追加 | 后续回答追加到同一助手消息或同一 turn | 只重写原消息 blocks | 没有最终回答 |
| 日志 | 能看到 submit、resume、tool call、final answer | 只看到 submit 完成和 reload | 无法定位是否恢复推理 |
| UI | 卡片已回答后继续展示最终回答 | 卡片仍停在提问态附近 | 用户以为按钮无效 |

## 5. 当前 iOS 关键代码位置

| 职责 | 文件 |
| --- | --- |
| AskUser 卡片提交入口 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Cards/DeepTutorAskUserCardView.swift` |
| 助手气泡转发提交 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/Bubbles/DeepTutorAssistantBubble.swift` |
| 页面提交到 ViewModel | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorChatPage.swift` |
| ViewModel 提交方法 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorChatViewModel.swift` |
| 当前本地 resolveAskUser | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/SendDeepTutorAIMessageUseCase.swift` |
| AskUser resolved 事件 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Domain/DeepTutorStreamEvent.swift` |
| block reducer resolved 匹配 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorMessageReducer.swift` |
| legacy toolCallID 兼容 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorMessageCodec+Compatibility.swift` |
| AI runtime adapter | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorAIRuntimeAdapter.swift` |
| 真实模型发送 UseCase | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/SendDeepTutorAIMessageUseCase.swift` |

## 6. 根因假设与排查顺序

### 6.1 P0 根因一：resolveAskUser 只更新本地消息，没有继续 AI

当前 iOS 逻辑：

```text
DeepTutorChatViewModel.submitAskUser
  -> sendMessageUseCase.resolveAskUser(...)
  -> events.append(.askUserResolved)
  -> DeepTutorMessageReducer.applyBlocks
  -> repository.upsertMessage
  -> reloadMessages
  -> state.phase = .ready
```

缺失：

```text
1. 没有调用 AI Runtime 继续推理。
2. 没有把 answer 作为 role=tool 或等价上下文传给模型。
3. 没有生成 query_weather 所需的下一轮工具链路。
4. 没有 activeTurnID / pendingAskUserTurn 状态。
```

### 6.2 P0 根因二：DeepTutorChat 只有本地对话，没有 Web 的 live turn 语义

DeepTutor-main 使用 WebSocket：

```text
activeTurnId
submit_user_reply
same-turn resume
```

iOS 当前是本地数据库 + 真实 AI 模型：

```text
conversationID
assistantMessageID
toolCallID
local events
```

需要补一个 iOS 本地等价物：

```text
DeepTutorPendingAskUserTurn
```

建议字段：

```text
conversationID
assistantMessageID
precedingUserMessageID
toolCallID
capability
originalUserPrompt
toolName
toolArguments
allowedTools
createdAt
expiresAt
status
```

用途：

```text
提交 AskUser 后恢复同一业务 turn，并继续调用 AI Runtime。
```

### 6.3 P0 根因三：legacy toolCallID 不稳定

当前兼容逻辑会用 `UUID()` 生成 legacy ID。

问题：

```text
1. 每次 decode/reload 都可能产生新 ID。
2. askUserResolved 事件与 askUser block 无法稳定匹配。
3. trace 去重只能事后去重，不能修复身份漂移。
```

要求：

```text
1. legacy toolCallID 必须改成稳定派生。
2. 可由 messageID + blockID + question hash 派生。
3. 同一条历史 askUser block 每次加载必须得到同一个 toolCallID。
4. 新数据必须优先使用模型真实 tool_call_id。
```

### 6.4 P0 根因四：提交后状态机直接回 ready

当前日志：

```text
提交 ask_user 完成，cost=0.193s
```

但没有：

```text
resumingAskUser
streaming
tool_call.query_weather
final answer ready
```

要求：

```text
1. Submit 后进入 `.resolvingAskUser`。
2. 本地写入 `.askUserResolved` 后进入 `.streaming`。
3. AI 继续完成后进入 `.ready`。
4. AI 继续失败时进入 `.error`，但保留已提交答案。
```

## 7. 修复方案

### 7.1 P0：提交 AskUser 后必须继续 AI Runtime

目标链路：

```text
DeepTutorAskUserCardView Submit
  -> DeepTutorChatViewModel.submitAskUser
  -> append .askUserResolved
  -> mark askUser card resolved
  -> build resume request from pending turn
  -> AI Runtime generateTextStream(...)
  -> consume tool calls / content / result
  -> append final answer below resolved card
  -> persist and reload
```

关键要求：

```text
1. 不创建普通用户气泡。
2. 不新开无关 conversation。
3. 不只做本地落库。
4. 继续推理必须继承原 capability、tool policy、history、model settings。
```

### 7.2 P0：构造等价 Web `submit_user_reply` 的本地协议

iOS 可以不使用 WebSocket，但必须有等价语义：

```text
DeepTutorSubmitUserReplyCommand
```

建议字段：

```text
conversationID: UUID
assistantMessageID: UUID
toolCallID: String
answers: [DeepTutorAskUserAnswer]
replyText: String
resumeMode: sameAssistantMessage
```

恢复上下文：

```text
1. 原用户问题。
2. 原助手已产生的 reasoning/tool trace。
3. ask_user_question 的工具调用。
4. 用户回答作为 tool result / role=tool 等价消息。
5. 后续可用工具，例如 query_location/query_weather。
```

### 7.3 P0：天气场景的工具恢复策略

选择城市“上海”后，下一步不应再问城市。

目标策略：

```text
1. 如果用户答案是城市名，下一轮 allowedTools 应包含 query_location 和 query_weather。
2. 如果没有 query_location 能力，则需要本地 geocode 或提示缺少定位工具。
3. 不应再次 allowedTools 只有 ask_user_question。
4. 不应再次生成同一张 AskUser 卡片。
```

推荐流程：

```text
上海
  -> resolve ask_user
  -> query_location(city=上海)
  -> query_weather(latitude, longitude, timeRange=now)
  -> final answer
```

如果当前项目没有 `query_location`：

```text
上海
  -> resolve ask_user
  -> 构建清晰错误/降级回答：当前缺少城市转经纬度工具，无法查询实时天气
  -> 不停留在提问卡片
```

### 7.4 P0：稳定 legacy toolCallID

要求：

```text
1. 禁止在兼容解码里用随机 UUID 生成 toolCallID。
2. 对历史缺失 ID 的 askUser block 使用稳定算法。
3. 同一 message/block/payload 每次 load 都恢复同一个 ID。
4. resolved 匹配必须基于稳定 ID。
```

建议算法：

```text
legacy-ask-user-\(stableHash(messageID + blockID + prompt + options))
```

如果 codec 层拿不到 messageID：

```text
1. 优先使用 block row 的 toolCallID 回填。
2. 如果 row 也为空，在仓储层 decode 时传入 blockID/messageID 参与修复。
3. 修复后立即重写 row.toolCallID 和 payloadData，避免下次继续漂移。
```

### 7.5 P0：提交后 UI 状态

要求：

```text
1. Submit 点击后按钮显示 loading 或禁用态。
2. 卡片立即切换为已提交/已回答摘要。
3. trace 显示“继续处理...”或“查询天气中...”。
4. Composer 可以继续禁用，直到恢复推理完成。
5. 如果恢复失败，卡片保持已回答，并显示可重试继续按钮。
```

## 8. 日志需求

### 8.1 AskUser submit 生命周期日志

新增：

```text
deeptutor.ask_user.submit.started
deeptutor.ask_user.submit.resolved_local
deeptutor.ask_user.submit.resume_started
deeptutor.ask_user.submit.resume_streaming
deeptutor.ask_user.submit.resume_completed
deeptutor.ask_user.submit.resume_failed
```

字段：

```text
conversation
assistantMessage
toolCallID
answers
answerCount
phaseBefore
phaseAfter
resumeMode
durationMs
```

### 8.2 pending turn 日志

新增：

```text
deeptutor.ask_user.pending_turn.created
deeptutor.ask_user.pending_turn.loaded
deeptutor.ask_user.pending_turn.missing
deeptutor.ask_user.pending_turn.consumed
```

字段：

```text
conversation
assistantMessage
precedingUserMessage
toolCallID
capability
allowedTools
createdAt
status
```

### 8.3 toolCallID 稳定性日志

新增：

```text
deeptutor.ask_user.tool_call_id.stabilized
deeptutor.ask_user.tool_call_id.changed
deeptutor.ask_user.tool_call_id.missing
```

要求：

```text
同一 message/block 多次 reload 不应出现 changed。
```

### 8.4 继续回答日志

提交“上海”后必须看到：

```text
DeepTutor AI 追问恢复推理开始
deeptutor.tool_policy.resolved ... reason=ask_user_resume+weather_location
deeptutor.tool_schema.outbound ... schemaNames=query_location,query_weather
AI 流式网关请求开始
DeepTutor AI 追问恢复推理完成
```

如果没有 query_location：

```text
deeptutor.ask_user.resume.blocked reason=missing_query_location
```

## 9. 验收用例

### 9.1 选择上海后继续回答

步骤：

```text
1. 用户输入：今天的天气怎么样？先问问我在哪个城市
2. AI 展示 AskUser 卡片。
3. 用户选择“上海”。
4. 用户点击 Submit。
```

期望：

```text
1. Submit 后卡片进入已回答状态，显示“上海”。
2. trace 显示继续处理。
3. AI 继续生成回答。
4. 不再停留在提问卡片。
5. 不出现重复 AskUser 卡片。
6. 不出现“提交 ask_user 完成”后无任何 AI 推理日志的情况。
```

### 9.2 toolCallID 稳定

期望：

```text
1. 同一条 askUser block reload 10 次，toolCallID 不变化。
2. askUserResolved 与 askUser block 能稳定匹配。
3. `legacy-ask-user-*` 不会每次变成新值。
```

### 9.3 对齐 DeepTutor-main 同 turn 语义

期望：

```text
1. AskUser 提交不是普通用户新消息。
2. 同一 assistant turn 能继续接收后续内容。
3. resolved card 上方/下方的正文顺序与 Web 一致。
4. 后续回答在视觉上出现在已回答卡片后面。
```

### 9.4 恢复失败可重试

如果 query_weather 或 AI Runtime 失败：

```text
1. 卡片仍显示已提交答案。
2. trace 显示失败原因。
3. UI 提供“继续重试”入口。
4. 不要求用户重新选择城市。
```

## 10. 风险与注意事项

### 10.1 不要只把卡片改成 resolved

本问题的核心不是卡片有没有变样式，而是提交后没有继续 AI 推理。只改 UI 会让用户看到“已提交”，但仍然没有答案。

### 10.2 不要把用户答案当普通新消息

DeepTutor-main 的语义是 same-turn resume。iOS 如果把“上海”作为普通用户消息重新发送，会破坏原工具调用上下文，也会导致 trace 和卡片顺序不一致。

### 10.3 不要继续使用随机 legacy toolCallID

随机 ID 会让所有 resolved 匹配和去重都不可靠。必须先稳定 ID，再做恢复推理。

### 10.4 不要忽略工具策略的下一步变化

选择城市后，工具策略应该从“问用户城市”切换到“城市解析/天气查询”。如果仍然只允许 `ask_user_question`，模型会继续问同一个问题。

## 11. 最终验收标准

实现完成后必须满足：

```text
1. 选择上海并点击 Submit 后，DeepTutorChat 会继续生成后续回答。
2. 日志出现 AskUser submit -> local resolved -> resume AI -> tool call/final answer 的完整链路。
3. 卡片稳定切换为已回答状态。
4. 同一条 askUser 的 toolCallID 在 reload 前后保持一致。
5. 不重复生成同一张城市提问卡片。
6. 不把“上海”作为普通新用户消息处理。
7. 后续回答出现在 resolved AskUser 卡片之后，顺序对齐 DeepTutor-main。
8. 如果缺少 query_location/get_current_location，必须给出可见降级说明和日志，不允许静默停住。
```

本工单只完成分析与需求创建，未修改 Swift 业务实现代码。
