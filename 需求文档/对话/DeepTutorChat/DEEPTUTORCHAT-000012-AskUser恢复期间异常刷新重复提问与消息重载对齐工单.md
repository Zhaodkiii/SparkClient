# DEEPTUTORCHAT-000012 AskUser 恢复期间异常刷新、重复提问与消息重载对齐工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000012 |
| 工单类型 | P0 UI 刷新异常 + 重复 AskUser + DeepTutor Web 对齐 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| iOS 功能目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| Web 参考工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main` |
| 日志附件 | `/Users/hua/.codex/attachments/41ccedc7-997c-45e3-9338-17767b7ad731/pasted-text.txt` |
| 创建日期 | 2026-08-05 |
| 模型场景约束 | 继续使用项目已有通用 `.chat` 场景，不新增 `.deepTutor` |
| 关联工单 | `DEEPTUTORCHAT-000009`、`DEEPTUTORCHAT-000010`、`DEEPTUTORCHAT-000011` |

## 1. 本工单目标

本工单解决 AskUser 回答后，DeepTutorChat 在继续推理过程中出现的 UI 异常刷新、重复弹出问题、重复回答和消息列表抖动问题。

当前用户可见问题：

```text
1. 用户选择城市并提交后，问题卡片仍反复出现。
2. 已回答状态不稳定，卡片可能回到未回答态。
3. 恢复推理期间消息列表异常刷新。
4. 同一条助手消息里重复出现“向你提问”或同一 AskUser 卡片。
5. 回答流式追加时，旧卡片被数据库重载覆盖或丢失。
```

本工单只写需求与技术方案，不直接修改 Swift 代码。

## 2. 日志结论摘要

### 2.1 初始 AskUser 已经生成成功

日志显示初始天气提问链路已经基本跑通：

```text
deeptutor.tool_policy.resolved ... policyReason=ask_user_explicit+weather_location ... allowedTools=ask_user_question,query_weather
deeptutor.ask_user.raw_arguments ... raw={"question": "你在哪个城市呢？请告诉我城市名称，我好帮你查询今天的天气～", "selection_mode": "single", "options": ["北京", "上海", "广州", "深圳", "其他城市"], "allows_other": true}
deeptutor.ask_user.mapped ... questionCount=1 optionCounts=5 allowsOther=true mode=options
deeptutor.message_reducer.ask_user_block_created message=3B33D6D0 toolCallID=call_00_sYssWVB6r7FnnlC4xRRA0650 questionCount=1 blockID=5A40BDFD
deeptutor.stream.completion.mapped ... finish=awaiting_user_input
DeepTutor AI 流式完成 ... finishReason=awaiting_user_input ... assistantContent=好的！在查询天气之前，我需要先知道你在哪个城市。让我来问问你吧～
```

说明：

```text
1. 模型能生成 ask_user_question。
2. iOS 能解析 arguments。
3. reducer 能创建 askUser block。
4. 本轮正确进入 awaiting_user_input。
```

### 2.2 提交答案后已经开始恢复推理

日志：

```text
提交 ask_user 开始，conversation=145D49EA, message=3B33D6D0, answers=上海
deeptutor.ask_user.submit.started ... toolCallID=legacy-ask-user-C26D3AB1
deeptutor.ask_user.submit.resolved_local ...
deeptutor.ask_user.submit.resume_started ...
DeepTutor AI 追问恢复推理开始，conversation=145D49EA, assistant=3B33D6D0
deeptutor.tool_policy.resolved ... policyReason=ask_user_resume+weather_location ... allowedTools=query_location,query_weather
AI 流式网关请求开始 ... messages=4, tools=2
```

说明：

```text
DEEPTUTORCHAT-000011 的“提交后继续 AI”链路已经开始出现，但刷新和数据恢复仍然把 UI 搞乱。
```

### 2.3 恢复推理期间数据库变更触发了多次 reload

日志中在 `isStreaming=true` 时频繁出现：

```text
deeptutor.list.load.start source=database_change
deeptutor.messages.reload.start conversation=145D49EA lockBottom=false forceFullRediff=false
deeptutor.messages.load.start conversation=145D49EA limit=50 before=-
deeptutor.messages.load.start conversation=145D49EA limit=all before=-
deeptutor.messages.reload.done ... isStreaming=true
```

当前代码线索：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorChatViewModel.swift

handleDatabaseChange:
  if isCreatingConversation || isSendingMessage { return }
  ...
  Task { await reloadMessages(for: conversationID) }
```

问题：

```text
1. 只避开了 isSendingMessage。
2. 没有避开 resolvingAskUser。
3. 没有避开 AskUser resume streaming。
4. 每次持久化 chunk 都可能触发数据库变更 -> 全量 reload。
5. reload 会用本地库当前半完成状态覆盖内存中的流式消息。
```

### 2.4 AskUser block 在 reload 中被 drop，又被重新创建

日志反复出现：

```text
deeptutor.messages.load.block_dropped conversation=145D49EA message=3B33D6D0 block=5A40BDFD kind=deepTutorAskUser payloadBytes=541
deeptutor.messages.load.block_decode_failed ... error=repair_failed
deeptutor.messages.load.partial_blocks ... dropped=1 recovered=1
deeptutor.ask_user.payload_validated message=3B33D6D0 toolCallID=legacy-ask-user-9AC1ECA6 ...
deeptutor.message_reducer.ask_user_block_created message=3B33D6D0 toolCallID=legacy-ask-user-9AC1ECA6 questionCount=1 blockID=5A40BDFD
```

说明：

```text
1. 持久化的 deepTutorAskUser block 自身解码失败。
2. load 阶段把 AskUser block drop。
3. envelope compatibility 又从 events 中重建 askUser。
4. 重建时生成新的 legacy toolCallID。
5. UI 看到的卡片身份不断变化，因此像“重复弹问题”。
```

### 2.5 toolCallID 仍然不稳定

同一个 message/block 在日志中出现多个 toolCallID：

```text
legacy-ask-user-C26D3AB1
legacy-ask-user-37A1681D
legacy-ask-user-107C994C
legacy-ask-user-FAA407FD
legacy-ask-user-ABC51FD9
legacy-ask-user-0808522F
legacy-ask-user-9AC1ECA6
legacy-ask-user-4FD019C2
legacy-ask-user-B9BD520A
legacy-ask-user-EAE6989B
```

影响：

```text
1. `.askUserResolved` 无法稳定匹配原始卡片。
2. reducer 认为是新的 ask_user，又创建一张卡片。
3. trace 去重只能去 UI 行，不能修复消息块身份。
4. Submit 后仍可能反复显示未回答问题。
```

### 2.6 流式内容追加时仍触发整列表重载

恢复推理期间多次出现：

```text
deeptutor.message.persist.completed ... status=流式生成中 blockCount=5 askUserBlockCount=1 contentLength=78
deeptutor.list.load.start source=database_change
deeptutor.messages.reload.start ...
```

这说明：

```text
每次流式内容写库后，都会把会话列表刷新和当前消息 reload 一起触发。
```

这是 UI 抖动、重复渲染、滚动位置异常、卡片状态回退的重要来源。

## 3. DeepTutor-main 对齐基线

### 3.1 Web 是事件 reducer 驱动，不靠每个数据库变更重载整条消息流

DeepTutor-main 关键链路：

```text
UnifiedChatContext
  -> WebSocket stream events
  -> reducer 合并到当前 session.messages
  -> active turn 保持在内存中
  -> ChatMessageList 渲染当前内存状态
```

AskUser 提交：

```text
submit_user_reply
  -> same active turn
  -> progress ask_user_resolved
  -> AskUserOptions 切换 resolved
  -> 后续 content/tool events 继续追加到同一助手消息
```

对齐含义：

```text
1. 流式期间以事件增量更新当前消息。
2. 不在每个 chunk 后全量 reload 当前会话。
3. AskUser 卡片的 identity 由 tool_call_id 稳定匹配。
4. resolved 卡片不会因为后续内容追加而回退成 pending。
```

### 3.2 Web 的 AskUser 去重依据

参考文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/AskUserOptions.tsx
```

Web 逻辑：

```text
seenAskUserCards by tool_call_id
progress ask_user_resolved by tool_call_id
如果 resolver 没有 echo id，回退到最近 unresolved ask_user segment
```

iOS 对齐要求：

```text
1. toolCallID 必须稳定。
2. 一个 toolCallID 只能对应一个 AskUser block。
3. resolved 后不得被新的 legacy ID 重建为新卡片。
```

## 4. 当前 iOS 偏差清单

| 类型 | DeepTutor-main 目标 | iOS 当前问题 | 影响 |
| --- | --- | --- | --- |
| 流式刷新 | 内存事件增量合并 | database_change 触发整会话 reload | UI 抖动、卡片回退 |
| AskUser 身份 | tool_call_id 稳定 | legacy ID 多次变化 | 重复卡片、重复问题 |
| resolved 状态 | submit 后稳定 resolved | reload 后重新创建 pending block | 用户以为没提交 |
| block decode | AskUser payload 可稳定重读 | deepTutorAskUser repair_failed | 卡片被 drop |
| 消息列表 diff | 当前 turn 局部更新 | page/all 双加载覆盖 state.messages | 滚动和卡片状态异常 |
| 会话列表刷新 | 非关键时机刷新 sidebar | 每次数据库变更刷新列表 | 性能与 UI 干扰 |
| 去重 | reducer 以 toolCallID 去重 | toolCallID 漂移导致去重失效 | 重复“向你提问” |

## 5. 当前 iOS 关键代码位置

| 职责 | 文件 |
| --- | --- |
| 数据库变更监听与 reload | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorChatViewModel.swift` |
| reloadMessages 双加载 page/all | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorChatViewModel.swift` |
| AskUser 提交与恢复推理 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/SendDeepTutorAIMessageUseCase.swift` |
| AskUser block reducer | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorMessageReducer.swift` |
| 兼容解码与 legacy ID | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorMessageCodec+Compatibility.swift` |
| stable toolCallID | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorStableToolCallID.swift` |
| 本地仓储 block load/drop | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorLocalChatStore.swift` |
| UIKit 消息列表 apply | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorMessageListView.swift` |
| 手动刷新协调器 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorRefreshCoordinator.swift` |

## 6. 根因假设与排查顺序

### 6.1 P0 根因一：database_change 在恢复流式期间覆盖内存状态

当前 `handleDatabaseChange` 缺少这些保护：

```text
1. state.phase == .resolvingAskUser
2. state.phase == .streaming
3. state.isStreaming == true
4. generationSession active
5. current assistant message is being updated
```

要求：

```text
AskUser resume / AI streaming 期间，当前会话不应被 database_change 全量 reload 覆盖。
```

### 6.2 P0 根因二：AskUser block 解码失败导致 drop/rebuild

日志中 `deepTutorAskUser payloadBytes=541 error=repair_failed` 是核心信号。

要求：

```text
1. 找出 payloadBytes=541 的 askUser block 为什么无法 decode。
2. 修复 DeepTutorAskUserBlockPayload 的兼容 decode。
3. 修复后新旧数据都能重读，不再 drop。
4. drop 不应触发“重新构建一张新的 pending AskUser 卡片”。
```

### 6.3 P0 根因三：legacy toolCallID 仍然随机或来源不一致

虽然已有 `DeepTutorStableToolCallID.swift`，日志仍显示多次变化。

排查方向：

```text
1. 哪条路径仍在生成随机 legacy ID。
2. repairAskUserWrapper 是否使用 block row toolCallID。
3. envelope repair 和 askUser block repair 是否生成同一个 ID。
4. repository 是否在 repair 后把稳定 ID 写回 row.toolCallID 和 payloadData。
```

### 6.4 P0 根因四：reducer 没有保护 resolved ask_user

当已有 `.askUserResolved` 时：

```text
1. 不应重新创建 pending AskUser。
2. 不应因为 toolCallID 漂移创建第二张卡。
3. 应按 prompt/options hash 找到旧卡并合并 resolved。
```

## 7. 修复方案

### 7.1 P0：恢复/流式期间暂停当前会话 database_change reload

要求：

```text
1. 当 activeConversationID 正在 streaming 或 resolvingAskUser 时，忽略或延迟当前会话的 database_change reload。
2. 允许刷新会话列表计数，但不能覆盖当前 state.messages。
3. 流式结束后执行一次 coalesced reload。
4. reload 必须 lockBottom=true 或保持当前 viewport，不产生跳动。
```

建议状态：

```text
isApplyingStreamingUpdate
isResolvingAskUser
pendingDatabaseReloadAfterStreaming
lastDatabaseReloadReason
```

### 7.2 P0：流式更新优先走内存增量合并

要求：

```text
1. streaming update 直接更新 state.messages 中的当前 assistant message。
2. repository upsert 只作为持久化，不反向驱动 UI 全量 reload。
3. 当前 turn 完成后再做一次一致性 reload。
```

对齐 DeepTutor-main：

```text
Web 是 stream events -> reducer -> current session state。
iOS 也应是 stream message -> in-memory state -> UIKit apply。
```

### 7.3 P0：AskUser block decode 必须稳定

要求：

```text
1. deepTutorAskUser 不再出现 repair_failed。
2. 旧 payload 可兼容读取。
3. 新 payload roundtrip_ok。
4. 如果读取失败，UI 不应重建 pending 卡片，而应保留内存中的 last-known-good block。
```

### 7.4 P0：AskUser identity 使用稳定三元组

建议去重 key：

```text
primary: toolCallID
fallback: messageID + blockID
fallback: promptHash + optionsHash
```

要求：

```text
1. 同一张卡每次 reload 都得到同一个 identity。
2. `.askUserResolved` 可通过 identity fallback 匹配。
3. resolved 后即使 toolCallID 兼容失败，也不能回退 pending。
```

### 7.5 P0：Submit 幂等

要求：

```text
1. 同一 assistantMessageID + askUser identity + answersHash 只能提交一次。
2. Submit 后按钮立即禁用。
3. 如果用户重复点击，不触发第二次 resolve/resume。
4. 日志记录 skipped_duplicate_submit。
```

### 7.6 P1：消息列表刷新节流与差量 apply

要求：

```text
1. database_change reload 至少 300-500ms coalesce。
2. streaming 中不 forceFullRediff。
3. UIKit list apply 必须按 messageID/blockID 做差量更新。
4. 手动下拉刷新才允许 forceFullRediff。
```

## 8. 日志需求

### 8.1 刷新决策日志

新增：

```text
deeptutor.messages.reload.deferred
deeptutor.messages.reload.coalesced
deeptutor.messages.reload.skipped_active_stream
deeptutor.messages.reload.applied_after_stream
```

字段：

```text
conversation
reason
phase
isStreaming
activeAssistantMessage
pendingReloadCount
```

### 8.2 AskUser identity 日志

新增：

```text
deeptutor.ask_user.identity.resolved
deeptutor.ask_user.identity.changed
deeptutor.ask_user.identity.merge_by_fallback
```

字段：

```text
conversation
message
block
oldToolCallID
newToolCallID
identityKey
promptHash
optionsHash
reason
```

### 8.3 重复提交日志

新增：

```text
deeptutor.ask_user.submit.skipped_duplicate
```

字段：

```text
conversation
message
identityKey
answersHash
phase
```

### 8.4 block drop 防护日志

新增：

```text
deeptutor.messages.load.block_drop_suppressed
deeptutor.messages.load.last_known_good_used
```

字段：

```text
conversation
message
block
kind
reason
```

## 9. 验收用例

### 9.1 提交上海后不重复弹问题

步骤：

```text
1. 发送：今天的天气怎么样？先问问我在哪个城市
2. 选择“上海”
3. 点击 Submit
```

期望：

```text
1. AskUser 卡片只出现一次。
2. Submit 后卡片进入已回答状态。
3. 不重复弹出同一张城市选择卡。
4. 不重复出现多个“向你提问”trace row。
5. 后续回答继续追加在同一消息下方。
```

### 9.2 恢复推理期间不全量覆盖当前消息

期望：

```text
1. streaming=true 时 database_change 不触发当前会话全量 reload。
2. 日志出现 reload.deferred 或 skipped_active_stream。
3. 流式完成后只执行一次 applied_after_stream。
4. UI 不跳动，不丢卡片。
```

### 9.3 AskUser block 不再 repair_failed

期望：

```text
1. deepTutorAskUser payload 可 roundtrip。
2. 不出现 payloadBytes=541 repair_failed。
3. 不出现 block_dropped kind=deepTutorAskUser。
```

### 9.4 toolCallID 稳定

期望：

```text
1. 同一 message/block reload 多次，toolCallID 不变化。
2. askUserResolved 始终匹配同一张卡。
3. 不再出现同一问题对应多个 legacy-ask-user-*。
```

### 9.5 对齐 DeepTutor-main

期望：

```text
1. AskUser 提交后同一 turn 继续。
2. resolved card 保持在原位置。
3. 后续 query_location/query_weather trace 和正文继续追加。
4. 消息列表不通过频繁整库 reload 来模拟流式更新。
```

## 10. 风险与注意事项

### 10.1 不要只做日志降噪

当前不是日志太多，而是日志暴露了真实 reload 竞争。只减少日志不会解决 UI 重复刷新。

### 10.2 不要在 streaming 中强行 reload 当前消息

强行 reload 会把内存中正在合并的事件流打断，导致卡片状态回退或 block 丢失。

### 10.3 不要依赖随机 legacy ID 去重

随机 legacy ID 是重复卡片的放大器。必须稳定身份，再谈 reducer 去重。

### 10.4 不要让会话列表刷新牵连当前消息流

会话列表可以延迟刷新 preview，不应在当前 turn streaming 时触发消息区重载。

## 11. 最终验收标准

实现完成后必须满足：

```text
1. AskUser 提交后不再重复弹出同一问题。
2. AskUser 卡片提交后稳定显示已回答状态。
3. 恢复推理期间当前消息不被 database_change 全量 reload 覆盖。
4. deepTutorAskUser block 不再 repair_failed / block_dropped。
5. 同一 AskUser 的 toolCallID / identity reload 前后稳定。
6. 流式内容追加时 UI 不跳动、不重复回答、不重复 trace。
7. 会话列表刷新与当前消息流解耦。
8. 行为对齐 DeepTutor-main：事件增量合并、same-turn resume、resolved card 稳定、最终回答继续追加。
```

## 12. 2026-08-05 二次补充：普通工具回答期间的异常刷新与卡片渲染偏差

### 12.1 新增日志附件

本次补充分析的新增日志：

```text
/Users/hua/.codex/attachments/45f48d0d-29e6-4c6c-8b7e-4dba9d697b85/pasted-text.txt
```

新增日志不只是 AskUser 场景，而是普通工具回答场景：

```text
用户问题：我最近的睡眠情况怎么样
conversation=F3DBD9AD
assistant=0CC4F7F3
model=agent-2-10-deepseek-v4-pro
tools=get_current_member, fetch_sleep_details
finishReason=stop
```

结论：

```text
1. 当前 UI 异常刷新不是 AskUser 专属问题。
2. 只要进入“工具调用 + 流式 Markdown 回答”，同样会出现高频刷新、卡片布局抖动、Markdown 表格测量警告和落库后重载。
3. DEEPTUTORCHAT-000012 需要从 AskUser 恢复专项扩展为“当前 Turn 流式渲染一致性”工单。
```

### 12.2 新增问题一：forceFlush 在普通 contentDelta 下过度触发

日志连续出现：

```text
deeptutor.stream.partial.mapped ... answerLen=1316 reasoningLen=1185 events=content(2) forceFlush=true blocks=envelope=1,text=1,trace=1
deeptutor.message.persist.completed ... status=流式生成中 blockCount=3 askUserBlockCount=0 contentLength=1212
deeptutor.stream.partial.mapped ... answerLen=1319 reasoningLen=1185 events=content(1) forceFlush=true blocks=envelope=1,text=1,trace=1
deeptutor.message.persist.completed ... status=流式生成中 blockCount=3 askUserBlockCount=0 contentLength=1215
```

当前代码线索：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorAIRuntimeAdapter.swift

let shouldForceFlush = hasAskUser
  || (partial.toolName != nil && hasNewEvents)
  || (hasNewEvents && partial.toolName == nil)
```

问题判断：

```text
1. `hasNewEvents && partial.toolName == nil` 会让普通正文流式 delta 也进入 forceFlush。
2. forceFlush 会绕过或弱化 flushTracker 的节流意义。
3. 每几个字符都触发 `stream.partial.mapped -> applyStreamingMessage -> persist.completed -> SwiftUI/UICollectionView 更新`。
4. 当正文里包含 Markdown 表格时，高频更新会放大布局测量成本。
```

DeepTutor-main 对齐要求：

```text
1. Web 的 AssistantResponse 使用 useSmoothStreamText 做视觉平滑，不把每个 token 都变成完整消息结构重建。
2. Web 的 ChatMessageList 以当前内存 message state 渲染，不要求每个 delta 都写库后再反向 reload。
3. iOS 应区分“UI smooth tick”和“持久化 flush tick”。
```

优化要求：

```text
1. forceFlush 只允许用于 AskUser、工具开始/结束、terminal result、错误状态等结构性事件。
2. 普通 contentDelta/reasoningDelta 走节流更新，例如 80-150ms UI tick。
3. 持久化写库单独节流，例如 500-1000ms 或重要节点强刷。
4. Markdown 表格/长回答场景应降低 UI 重建频率。
```

### 12.3 新增问题二：Markdown 表格高度 PreferenceKey 同帧多次更新

日志反复出现：

```text
Bound preference MarkdownTableHeightPreferenceKey tried to update multiple times per frame.
```

当前代码线索：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Core/Markdown/MarkdownDocumentView.swift

.background(
  GeometryReader { proxy in
    Color.clear.preference(
      key: MarkdownTableHeightPreferenceKey.self,
      value: [tableID: proxy.size.height]
    )
  }
)
.frame(height: tableHeights[tableID])
.onPreferenceChange(MarkdownTableHeightPreferenceKey.self) { heights in
  guard let height = heights[tableID], height > 0 else { return }
  if abs((tableHeights[tableID] ?? 0) - height) > 0.5 {
    tableHeights[tableID] = height
  }
}
```

问题判断：

```text
1. 流式 Markdown 表格每次追加字符都会触发表格重排。
2. GeometryReader 写 preference，onPreferenceChange 又更新 @State tableHeights。
3. @State 更新会再次触发布局，同一帧内形成多次 preference 写入。
4. 这类警告通常不会直接崩溃，但会导致滚动抖动、CPU 升高、列表 cell 高度不稳定。
```

DeepTutor-main 对齐要求：

```text
1. Web Markdown 表格在流式时不会依赖 SwiftUI PreferenceKey 测量闭环。
2. iOS 需要用移动端方式稳定表格高度，不让表格测量参与每个 token 的同步布局循环。
```

优化要求：

```text
1. 流式中 Markdown 表格高度更新需要 debounce 到下一帧或下一 runloop。
2. 高度变化阈值提高到 1-2pt，避免亚像素反复触发。
3. 对同一个 tableID，一帧内只允许提交最后一次测量结果。
4. 长表格可以在 streaming=true 时先使用自适应自然高度，streaming=false 后再缓存固定高度。
5. 如果 MarkdownDocumentView 是 Core 公共组件，修复需要评估 Chat、DeepTutorChat、科普等所有 Markdown 使用场景。
```

### 12.4 新增问题三：正文持久化内容丢失 Markdown 空格，导致回答卡片不一致

日志中最终模型输出保留了正常 Markdown：

```text
assistantContent=以下是您最近一周（12月15日–22日）的睡眠情况分析：

## 睡眠概览

| 日期 | 总睡眠 | 清醒 | REM | 核心 | 深度 | 评级 |
|------|--------|------|-----|------|------|------|
```

但落库后的 assistantContent 变成：

```text
assistantContent=好的！让我来帮您查看最近的睡眠情况。我先获取您的成员信息和最近一周的睡眠数据。睡眠概览|日期 |总睡眠 |清醒 | REM |核心 |深度 |评级 |
```

调试 JSON 中也同时存在两份内容：

```text
content: 睡眠概览|日期 |总睡眠 ...
content_text_from_events: 睡眠概览

| 日期 | 总睡眠 | 清醒 | REM | 核心 | 深度 | 评级 |
```

问题判断：

```text
1. `content_text_from_events` 更接近 DeepTutor-main 的 Markdown 渲染输入。
2. `content` / text block 在持久化或内容归一化时丢失了换行、标题空格、表格单元格空格。
3. UI 如果优先渲染 text block 的 `content`，就会出现回答卡片不一致：表格无法稳定识别，标题和正文粘连，Markdown 视觉降级。
4. 这也会反向放大 MarkdownTableHeightPreferenceKey 的测量问题，因为 Markdown AST 在流式中不断从“不是表格/半表格”变成“表格”。
```

当前需排查代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorMessageReducer.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Domain/DeepTutorStreamEvent.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorMessageCodec.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorLocalChatStore.swift
```

优化要求：

```text
1. 最终正文渲染源应优先使用 consolidated contentDelta 拼接出的 Markdown 原文。
2. 不得在 text block 持久化阶段做会破坏 Markdown 语义的空白折叠。
3. `content` 可作为搜索/preview 的 plain text，但 `text block payload.text` 必须保留 Markdown。
4. 会话列表 preview 可以单独生成 strippedPlainText，不能反向覆盖消息正文。
5. 增加日志对比 `contentLength`、`contentTextFromEventsLength`、`markdownPreserved=true/false`。
```

### 12.5 新增问题四：工具调用 start/result 的 callID 不稳定，trace 生命周期无法可靠配对

调试 JSON 中同一工具出现：

```text
toolCallStarted get_current_member call_id=legacy-tool-start-ECA14C23
toolResult get_current_member call_id=legacy-tool-result-081BD3EE
toolCallStarted fetch_sleep_details call_id=legacy-tool-start-3E11E6A5
toolResult fetch_sleep_details call_id=legacy-tool-result-F87B31C5
```

问题判断：

```text
1. 同一工具的一次调用，start 和 result 使用了不同 legacy callID。
2. trace row 如果按 callID 合并，会认为 start/result 是两次不同事件。
3. trace row 如果按 toolName 合并，又会在同名工具多轮调用时误合并。
4. DeepTutor-main 的 trace 展示依赖工具调用生命周期稳定：started -> result/error -> completed。
```

优化要求：

```text
1. toolCallStarted 和 toolResult 必须共享同一个 callID。
2. 如果 AI Runtime 没有返回 callID，需要 iOS 在 accumulator 层为同一轮工具调用生成稳定 ID。
3. fallback key 建议为 `assistantMessageID + toolName + invocationIndex`。
4. 不能分别用 `legacy-tool-start-*` 和 `legacy-tool-result-*` 随机生成。
5. trace 日志增加 `tool_lifecycle.paired` / `tool_lifecycle.unpaired`。
```

### 12.6 新增问题五：debug snapshot 中 allowedTools 与实际工具调用不一致

日志：

```text
debug.snapshot latestToolPolicyReason=chat_minimal_default
latestAllowedTools=ask_user_question
eventTypes=contentDelta=2,reasoningDelta=2,result=1,toolCallStarted=2,toolResult=2
实际工具：get_current_member, fetch_sleep_details
```

问题判断：

```text
1. 调试面板显示的 `latestAllowedTools` 不是本轮实际使用的 tool policy。
2. 可能取到了下一个默认状态、旧缓存、或 DeepTutorPromptBuilder 的默认工具策略。
3. 这会干扰问题排查：看起来只允许 ask_user_question，但实际已经调用健康工具。
```

优化要求：

```text
1. debug snapshot 需要区分 `configuredAllowedTools`、`resolvedAllowedToolsForCurrentTurn`、`actualToolCalls`。
2. 每个 assistant message 的 envelope 中保存本轮 resolved tool policy。
3. 调试面板按 messageID 展示工具策略，不使用全局 latest 覆盖当前消息。
4. 追加日志：deeptutor.debug.tool_policy_snapshot_mismatch。
```

### 12.7 新增问题六：流式完成后仍立即 reload 当前会话，普通回答也可能抖动

日志：

```text
DeepTutor AI 流式完成 ... finishReason=stop ... cost=107.016s
deeptutor.message.persist.completed ... status=已就绪
助手消息落库成功 ...
deeptutor.messages.reload.start conversation=F3DBD9AD lockBottom=false forceFullRediff=false
deeptutor.messages.load.start limit=50
deeptutor.messages.load.start limit=all
deeptutor.messages.reload.done ... durationMs=170
deeptutor.list.load.start source=send
```

问题判断：

```text
1. 即使没有 AskUser，send 完成后也会立即 page/all 双加载。
2. 如果最终 text block 与 events 文本不一致，reload 会把内存中正常 Markdown 替换成落库后的降级 Markdown。
3. 这会解释“回答卡片不一致、结束后突然变样、表格样式闪一下又坏掉”的现象。
```

优化要求：

```text
1. send 完成后的 reload 应只作为一致性校验，不应覆盖当前内存消息的 last-known-good render blocks。
2. 如果 reload 后检测到 Markdown 保真度降低，必须保留内存版本并记录 `reload.rejected_render_regression`。
3. page/all 双加载应拆分：当前 UI 只需 page，allMessagesCache 可后台延迟加载。
4. 会话列表 source=send 刷新只更新列表 preview，不触发当前消息二次 rediff。
```

## 13. 二次补充后的 P0 优化方案

### 13.1 建立三个独立节奏：UI 流式、持久化、数据库重载

当前链路混在一起：

```text
AI partial
  -> reducer
  -> update UI
  -> persist message
  -> database_change
  -> reload current conversation
  -> update UI again
```

目标链路：

```text
AI partial
  -> in-memory reducer
  -> UI smooth flush tick
  -> persistence debounce tick
  -> current conversation reload deferred
  -> terminal consistency check
```

要求：

```text
1. UI tick：80-150ms，适合用户看见文字增长。
2. Persist tick：500-1000ms，适合本地恢复和异常退出保护。
3. Reload tick：仅在非 streaming、非 resolvingAskUser、非 applyingStreamingUpdate 时执行。
4. Terminal check：流式完成后一次，不允许破坏当前 render blocks。
```

### 13.2 把 Markdown 渲染源和 preview/search 文本分离

目标字段语义：

```text
renderMarkdownText: 保留模型输出 Markdown 原文，用于消息正文。
plainPreviewText: 去 Markdown 后的列表预览。
searchableText: 可搜索纯文本。
contentTextFromEvents: 从 consolidated events 恢复出的原文，用于兼容和校验。
```

验收：

```text
1. renderMarkdownText 中表格前后换行必须保留。
2. 标题 `## 睡眠概览` 不得变成 `睡眠概览|日期`。
3. 表格单元格 `| 日期 | 总睡眠 |` 不得变成 `|日期 |总睡眠 |` 后再用于正文渲染。
4. 会话列表可以展示压缩 preview，但不能写回正文 block。
```

### 13.3 修复工具 trace 生命周期配对

目标：

```text
toolCallStarted(callID=A, toolName=get_current_member)
toolResult(callID=A, toolName=get_current_member)
trace row: 获取当前成员 -> 已完成
```

禁止：

```text
toolCallStarted(callID=legacy-tool-start-*)
toolResult(callID=legacy-tool-result-*)
```

验收：

```text
1. 同一工具调用只产生一行 trace。
2. 多个同名工具调用按 invocationIndex 区分。
3. Web 的 AssistantActivity/TracePanels 展示语义能在 iOS Trace 中复刻。
```

### 13.4 Markdown 表格流式渲染降噪

要求：

```text
1. streaming=true 时 Markdown 表格可以降低实时测量频率。
2. PreferenceKey 更新必须异步合并，不在同一 frame 内连续 setState。
3. 结束后再做一次最终表格布局测量。
4. 对长表格回答，滚动位置保持稳定，不因为表格高度变化反复跳动。
```

## 14. 二次补充后的新增日志需求

### 14.1 流式节奏日志

新增：

```text
deeptutor.stream.flush_decision
deeptutor.stream.ui_flush_applied
deeptutor.stream.persist_flush_applied
deeptutor.stream.flush_skipped_throttle
```

字段：

```text
conversation
assistant
reason
eventTypes
force
uiElapsedMs
persistElapsedMs
answerLen
reasoningLen
blockSummary
```

### 14.2 Markdown 保真日志

新增：

```text
deeptutor.markdown.preserve_check
deeptutor.markdown.render_source_selected
deeptutor.markdown.table_height_deferred
deeptutor.markdown.table_height_applied
```

字段：

```text
conversation
message
renderSource
contentLength
eventsTextLength
tableCount
headingCount
pipeLineCount
preserved
reason
```

### 14.3 工具生命周期日志

新增：

```text
deeptutor.tool_lifecycle.paired
deeptutor.tool_lifecycle.unpaired
deeptutor.tool_lifecycle.call_id_repaired
```

字段：

```text
conversation
message
toolName
callID
startEventIndex
resultEventIndex
invocationIndex
repairReason
```

### 14.4 reload 回归防护日志

新增：

```text
deeptutor.messages.reload.rejected_render_regression
deeptutor.messages.reload.render_source_changed
```

字段：

```text
conversation
message
oldRenderSource
newRenderSource
oldMarkdownLength
newMarkdownLength
oldTableCount
newTableCount
reason
```

## 15. 二次补充后的新增验收用例

### 15.1 睡眠分析长表格回答不抖动

步骤：

```text
1. 发送：我最近的睡眠情况怎么样
2. 等待调用 get_current_member 和 fetch_sleep_details
3. 观察流式生成完整睡眠表格
```

期望：

```text
1. 流式期间不会刷出大量 MarkdownTableHeightPreferenceKey 同帧警告。
2. 表格逐步出现但列表不明显跳动。
3. 最终回答卡片保持 DeepTutor-main 的 Markdown 层级：标题、表格、分隔线、列表都正确。
4. 流式完成后的 reload 不会把正常 Markdown 变成压缩文本。
5. trace 中每个工具只出现一条完整生命周期行。
```

### 15.2 content 与 contentTextFromEvents 一致性

期望：

```text
1. `content_text_from_events` 与最终 text block 的 Markdown 语义一致。
2. 如果 plain preview 需要压缩空白，只能存在会话列表 preview 字段。
3. debug JSON 中可直接看出 render source。
```

### 15.3 工具 callID 配对稳定

期望：

```text
1. get_current_member 的 started/result 使用同一个 callID。
2. fetch_sleep_details 的 started/result 使用同一个 callID。
3. 不再出现 `legacy-tool-start-*` 和 `legacy-tool-result-*` 分裂。
```

### 15.4 debug snapshot 工具策略可信

期望：

```text
1. debug snapshot 显示本轮 resolvedAllowedTools。
2. actualToolCalls 与 trace 工具一致。
3. 不再出现“latestAllowedTools=ask_user_question，但实际调用 sleep/member 工具”这种误导性调试信息。
```

## 16. 二次补充后的优先级调整

| 优先级 | 项 | 原因 |
| --- | --- | --- |
| P0 | 当前会话 streaming/reload 解耦 | 同时影响 AskUser、普通工具回答、滚动和卡片状态 |
| P0 | Markdown 原文保真 | 直接影响回答卡片是否对齐 DeepTutor-main |
| P0 | forceFlush 降级为结构性事件强刷 | 当前高频刷新是 UI 抖动的放大器 |
| P0 | AskUser / Tool callID 稳定 | 影响卡片去重、trace 配对、submit resume |
| P1 | Markdown 表格高度测量 debounce | 影响长回答性能和滚动稳定性 |
| P1 | debug snapshot 按 messageID 展示 | 影响排查效率，不应误导实现判断 |

## 17. 二次补充后的最终结论

本轮日志确认：

```text
1. DeepTutorChat 当前异常刷新不是单点 bug，而是“流式事件、持久化、数据库通知、SwiftUI 布局测量”四条链路未解耦。
2. AskUser 重复提问是同一类问题在交互卡片上的表现。
3. 普通工具回答卡片不一致，是同一类问题在 Markdown 正文和 Trace 上的表现。
4. 对齐 DeepTutor-main 的关键不是只改 UI 样式，而是先对齐事件 reducer、稳定 identity、render source 和刷新节奏。
```

因此，DEEPTUTORCHAT-000012 的实现拆分必须先做 P0 架构修正：

```text
1. current turn streaming state 以内存 reducer 为准。
2. 数据库只做持久化和恢复，不反向驱动当前 turn 每帧重载。
3. Markdown 正文使用保真原文渲染，preview/search 另行生成。
4. AskUser/tool trace 的 callID/identity 全链路稳定。
5. SwiftUI 表格测量做异步合并，避免同帧 preference 更新循环。
```

本工单只完成分析与需求创建，未修改 Swift 业务实现代码。
