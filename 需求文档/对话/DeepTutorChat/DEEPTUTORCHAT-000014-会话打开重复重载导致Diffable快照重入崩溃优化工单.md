# DEEPTUTORCHAT-000014 会话打开重复重载导致 Diffable 快照重入崩溃优化工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000014 |
| 工单类型 | P0 崩溃修复 + 消息列表刷新架构优化 + DeepTutor-main 对齐 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| iOS 功能目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| Web 参考工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main` |
| 日志附件 1 | `/Users/hua/.codex/attachments/824aa8a1-1fb4-4ef4-8c42-d44027544433/pasted-text.txt` |
| 日志附件 2 | `/Users/hua/.codex/attachments/5218f4ea-956c-431c-b3a0-cd622d93252c/pasted-text.txt` |
| 创建日期 | 2026-08-05 |
| 关联工单 | `DEEPTUTORCHAT-000008`、`DEEPTUTORCHAT-000009`、`DEEPTUTORCHAT-000012`、`DEEPTUTORCHAT-000013` |

## 1. 本工单目标

解决打开 DeepTutor 会话时出现的 `UICollectionViewDiffableDataSource` 快照重入崩溃，并把 iOS 消息列表刷新方式向 `DeepTutor-main` 的稳定渲染链路对齐。

当前用户可见问题：

```text
1. 打开已有 DeepTutor 会话后 App 直接崩溃。
2. 崩溃前同一个 conversation 出现重复 open 和重复 reload。
3. 日志显示 ask_user block 可以恢复，但 UI 列表在恢复渲染期间触发 AttributeGraph cycle。
4. UIKit 抛出 DiffableDataSource 快照重入断言。
```

本工单只做原因分析、优化方案和验收标准，不修改 Swift 代码。

## 2. 崩溃日志结论

### 2.1 直接崩溃原因

日志中的终止原因：

```text
NSInternalInconsistencyException
Deadlock detected: attempted to apply a snapshot to diffable data source while it was already applying a snapshot.
BUG_IN_CLIENT_OF_DIFFABLE_DATA_SOURCE__APPLYING_SNAPSHOTS_REENTRANTLY_OR_ON_MAIN_AND_BACKGROUND_THREADS
View updated by this diffable data source: UICollectionViewDiffableDataSource<Int, UUID>
```

结论：

```text
崩溃不是消息解码异常直接导致，也不是 ask_user payload 无法创建卡片导致。
直接原因是 DeepTutorMessageListViewController 正在 dataSource.apply(snapshot) 时，又被 SwiftUI updateUIViewController 触发第二次 apply。
```

### 2.2 崩溃前出现重复打开

日志：

```text
deeptutor.conversation.open.start conversation=85D0B84C
deeptutor.conversation.open.start conversation=85D0B84C
deeptutor.messages.reload.start conversation=85D0B84C lockBottom=false forceFullRediff=false source=manual
deeptutor.messages.reload.start conversation=85D0B84C lockBottom=false forceFullRediff=false source=manual
deeptutor.messages.load.start conversation=85D0B84C limit=50 before=-
deeptutor.messages.load.start conversation=85D0B84C limit=50 before=-
```

iOS 代码证据：

```text
DeepTutorChatPage.body:
  .task(id: conversationID) {
      await viewModel.openConversation(conversationID)
  }

DeepTutorConversationListPage.navigationDestination:
  DeepTutorChatPage(...)
      .task(id: conversationID) {
          await viewModel.openConversation(conversationID)
      }
```

文件位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorChatPage.swift
```

结论：

```text
同一个页面进入时存在两处 `.task(id: conversationID)` 同时调用 `openConversation`。
`shouldSkipOpen` 依赖 activeConversationID/conversation/state.phase，但两个 Task 几乎同时启动时，第二个可能在第一个完整写入 state 前进入，因此不能稳定拦截。
```

### 2.3 reloadMessages 一次调用内会多次发布状态

iOS 代码证据：

```text
reloadMessages:
  state.messages = visible
  state.hasMoreMessages = totalCount > visible.count
  state.isStreaming = visible.last?.status == .streaming
  if lockBottom {
      state.lockBottomViewport = true
      state.scrollToBottomRequestGeneration &+= 1
  }
  if forceFullRediff {
      objectWillChange.send()
  }
```

文件位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorChatViewModel.swift
```

结论：

```text
一次 reload 会连续触发多个 `@Published state` 更新。
SwiftUI 每次更新都可能调用 `updateUIViewController`。
`updateUIViewController` 每次都会调用 `uiViewController.apply(...)`。
如果上一次 diffable snapshot apply 尚未完成，就会触发 UIKit 的 reentrant apply 断言。
```

### 2.4 MessageList 当前没有 apply 串行保护

iOS 代码证据：

```text
DeepTutorMessageListViewController.apply:
  dataSource.apply(snapshot, animatingDifferences: false) { ... }

DeepTutorMessageListRepresentable.updateUIViewController:
  uiViewController.apply(conversationID: conversationID, payload: payload)
```

文件位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorMessageListView.swift
```

结论：

```text
当前 `apply` 没有 `isApplyingSnapshot` 标记、pending payload 合并、snapshot identity 去重或 MainActor 串行队列。
只要 SwiftUI 在 diffable apply completion 前再次调用 update，就可能重入崩溃。
```

### 2.5 ask_user 恢复不是本次崩溃直接原因，但放大了刷新压力

日志显示 ask_user block 可以恢复：

```text
deeptutor.ask_user.payload_validated message=24B5F5C7 ...
deeptutor.message_reducer.ask_user_block_created message=24B5F5C7 ...
deeptutor.ask_user.payload_validated message=484E06B4 ...
deeptutor.message_reducer.ask_user_block_created message=484E06B4 ...
```

但同一次打开中反复出现不同 legacy toolCallID：

```text
legacy-ask-user-294FEBA8
legacy-ask-user-A77F28CA
legacy-ask-user-76DC99FC
```

结论：

```text
ask_user 兼容恢复会增加 block 重建和 row 更新次数。
这些更新本身不应崩溃，但在当前没有 reload 单飞和 diffable apply 串行保护的前提下，会放大 reentrant apply 的概率。
```

## 3. 根因判断

### 3.1 根因链路

```text
用户点击会话
  -> selectedConversationID 改变
  -> navigationDestination 创建 DeepTutorChatPage
  -> 外层 navigationDestination.task 调用 openConversation
  -> DeepTutorChatPage 内层 .task 调用 openConversation
  -> 两个 openConversation 并发/近并发执行
  -> 两个 reloadMessages 并发/近并发执行
  -> state.messages / hasMore / isStreaming / phase 连续发布
  -> SwiftUI 多次 updateUIViewController
  -> DeepTutorMessageListViewController 多次 dataSource.apply(snapshot)
  -> 上一次 apply 未结束又进入下一次 apply
  -> UIKit 抛出 NSInternalInconsistencyException
```

### 3.2 优先级排序

| 优先级 | 问题 | 影响 | 证据 |
| --- | --- | --- | --- |
| P0 | `openConversation` 被两处 `.task` 重复触发 | 直接制造重复 reload | 日志双 `open.start`；`DeepTutorChatPage.swift` 两处 `.task` |
| P0 | Diffable apply 无串行保护 | 直接触发崩溃 | UIKit reentrant snapshot 断言；`DeepTutorMessageListView.swift` |
| P0 | `reloadMessages` 连续发布多个 state 字段 | 放大 apply 次数 | `DeepTutorChatViewModel.reloadMessages` |
| P1 | reload 缺少同 conversation 单飞/取消旧任务 | 快速切换、数据库通知时继续重载 | `handleDatabaseChange`、`reloadMessages` |
| P1 | ask_user legacy id 恢复仍不稳定 | 卡片身份波动，增加更新次数 | 日志多个 `legacy-ask-user-*` |

## 4. DeepTutor-main 对齐基线

### 4.1 Web 消息列表是 React 状态渲染，不直接持有 diffable 快照

参考位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/app/(workspace)/home/[[...sessionId]]/page.tsx
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ChatMessages.tsx
```

Web 链路：

```text
state.messages
  -> ChatMessageList
  -> useMemo(buildVisiblePath)
  -> message.map render
```

关键行为：

```text
1. 页面只把 `state.messages` 作为单一消息输入传给 ChatMessageList。
2. ChatMessageList 内部用 memo/useMemo 派生 visible path 和 deep_research merge。
3. 滚动由 `useChatAutoScroll` 读取 messageCount、lastMessageContent、lastEventCount 后统一处理。
4. Web 没有“正在 apply snapshot 时又 apply snapshot”的 UIKit 类状态。
```

### 4.2 iOS 对齐含义

iOS 不需要照搬 React，但要对齐以下架构原则：

```text
1. 消息列表应有单一、稳定的渲染 payload。
2. 一次 reload 的多字段变化应合并成一次列表渲染。
3. UIKit diffable apply 必须串行化。
4. 同一 conversation 打开和 reload 应单飞，后到请求复用或取消前一个请求。
5. 流式/AskUser 期间优先增量更新内存态，不因数据库通知反复全量 reload 当前消息。
```

## 5. 优化方案

### 5.1 P0 去掉重复 open 入口

目标：

```text
同一个 conversation 页面只保留一个 `openConversation` 触发点。
```

建议：

```text
1. 保留 `DeepTutorChatPage` 内部 `.task(id: conversationID)`，移除 navigationDestination 外层重复 `.task`。
2. 或者保留外层 `.task`，移除页面内部 `.task`。
3. 推荐保留页面内部 `.task`，因为页面自身拥有 conversationID 和加载生命周期，更利于后续单页预览/深链复用。
```

验收日志：

```text
点击同一个会话后，只出现一次：
deeptutor.conversation.open.start conversation=...

只出现一次初始：
deeptutor.messages.reload.start conversation=... source=open
```

### 5.2 P0 为 open/reload 增加单飞与版本号

目标：

```text
同一 conversation 同一时刻最多一个 open/reload 生效。
```

建议新增 ViewModel 内部状态：

```text
activeOpenTaskByConversationID / currentOpenGeneration
activeReloadTaskByConversationID / currentReloadGeneration
```

建议行为：

```text
1. openConversation 开始时生成 `openGeneration`。
2. reloadMessages 返回前检查 generation 是否仍是最新。
3. 旧 generation 返回时只打日志，不写 state。
4. 同一 conversation 已在打开中时，新 open 直接 join 或 skip。
5. 不同 conversation 切换时，旧 conversation reload 返回不得写入新 conversation state。
```

需要新增日志：

```text
deeptutor.conversation.open.join conversation=... generation=...
deeptutor.conversation.open.stale_drop conversation=... generation=...
deeptutor.messages.reload.join conversation=... source=...
deeptutor.messages.reload.stale_drop conversation=... source=...
```

### 5.3 P0 为 Diffable snapshot apply 增加串行队列

目标：

```text
DeepTutorMessageListViewController 永远不会 reentrant 调用 dataSource.apply。
```

建议在 `DeepTutorMessageListViewController` 内增加：

```text
isApplyingSnapshot: Bool
pendingPayload: DeepTutorListApplyPayload?
lastAppliedSignature: DeepTutorListApplySignature?
```

建议流程：

```text
apply(payload):
  1. 计算 signature：conversationID + message ids + block fingerprints + hasMore + lockBottom + scroll generation + layoutNonce。
  2. 如果 signature 与 lastAppliedSignature 相同，直接跳过。
  3. 如果 isApplyingSnapshot=true，只缓存 latest pendingPayload，不立即 apply。
  4. 当前 apply completion 结束后，检查 pendingPayload。
  5. 如果存在 pendingPayload，再启动下一轮 apply。
```

需要新增日志：

```text
deeptutor.list.snapshot.apply_start conversation=... items=... signature=...
deeptutor.list.snapshot.apply_queued conversation=... reason=reentrant_guard
deeptutor.list.snapshot.apply_done conversation=... pending=true durationMs=...
deeptutor.list.snapshot.apply_skipped conversation=... reason=same_signature
```

### 5.4 P0 合并 reloadMessages 的 state 更新

目标：

```text
一次 reload 只产生一次可观察的列表状态更新。
```

建议：

```text
1. 构造 nextState 或局部 copy。
2. 先完成 count/load/merge/visible 计算。
3. 最后一次性赋值给 `state`。
4. 避免 `state.messages`、`state.hasMoreMessages`、`state.isStreaming` 连续触发多次 objectWillChange。
5. `forceFullRediff` 不再直接 `objectWillChange.send()`，改为更新明确的 `listLayoutNonce` 字段或交给 RefreshCoordinator 单向触发。
```

风险说明：

```text
当前 `state` 是 struct，但 `@Published private(set) var state` 下直接改 `state.messages` 仍会触发发布。
需要改为局部 var next = state，修改 next 后 `state = next`。
```

### 5.5 P1 数据库通知与当前会话 reload 节流

目标：

```text
数据库变更不应在 UI snapshot apply、open reload、streaming/ask_user resolving 期间立即全量 reload 当前消息。
```

建议：

```text
1. 当前已通过 `shouldDeferMessageReload` 避免 streaming 期间 reload，应继续覆盖 open/loadingLocal/applySnapshotInProgress。
2. 数据库变更先刷新会话列表，不立即刷新当前消息列表。
3. 当前会话消息在 terminal consistency、手动下拉、返回页面时统一补一次。
4. 对 300ms 内多次 database_change 做 debounce，只保留最后一次。
```

### 5.6 P1 稳定 ask_user legacy 恢复身份

目标：

```text
历史数据恢复时，同一 message/block 的 ask_user toolCallID 不应每次 reload 都变。
```

建议：

```text
1. legacy toolCallID 由 messageID + blockID + prompt hash 派生稳定值。
2. 不使用随机后缀。
3. reload 中恢复出的 askUser block 要保持同一个 blockID 和 toolCallID。
4. submit/resolved 匹配优先使用稳定 identity key。
```

## 6. 实施拆分

| 阶段 | 内容 | 目标 |
| --- | --- | --- |
| P0-1 | 移除重复 open 入口 | 消除双 `open.start` |
| P0-2 | open/reload generation guard | 旧请求不覆盖新状态 |
| P0-3 | Diffable apply 串行化 + pending payload 合并 | 消除 reentrant snapshot 崩溃 |
| P0-4 | reloadMessages 一次性提交 state | 降低 SwiftUI update 次数 |
| P1-1 | database_change debounce/defer | 降低流式与打开期间重载压力 |
| P1-2 | ask_user legacy identity 稳定化 | 降低卡片身份波动 |
| P1-3 | 对齐 Web 的 list/render 日志 | 建立后续问题定位能力 |

## 7. 验收标准

### 7.1 崩溃验收

```text
Given 本地已有 100+ DeepTutor 会话
When 连续快速点击同一个会话 10 次
Then App 不崩溃
And 日志不出现 Diffable reentrant snapshot 断言
And 同一个 conversation 不出现并发双 open.start
```

```text
Given 会话内包含 ask_user 历史卡片
When 打开该会话
Then ask_user 卡片正常展示
And 不出现 AttributeGraph cycle 连续刷屏
And 不出现 UIKit diffable deadlock
```

### 7.2 日志验收

```text
Given 打开 conversation=85D0B84C
When 页面进入完成
Then 至少看到：
deeptutor.conversation.open.start
deeptutor.messages.reload.start source=open
deeptutor.list.snapshot.apply_start
deeptutor.list.snapshot.apply_done
deeptutor.conversation.open.done
```

```text
And 不应看到：
同一 conversation 同一 generation 的重复 open.start
snapshot apply 未完成时直接第二次 apply
forceFullRediff 直接 objectWillChange.send 导致隐式刷新
```

### 7.3 DeepTutor-main 对齐验收

```text
Given 同一批 messages
When 进行分支切换、ask_user 展示、历史 reload
Then iOS 与 Web 一样以当前内存消息列表为主状态源
And reload 只作为 hydration/一致性补偿
And UI 渲染层不承担业务数据恢复职责
```

## 8. 风险与待确认项

```text
1. Diffable apply 串行化必须保留滚动锚点恢复能力，尤其是 load more prepend 场景。
2. 合并 state 更新后，要确认 composer、navigationTitle、message list 都能收到必要更新。
3. 移除重复 .task 后，要确认 deep link、创建后打开、返回再进入都能正常加载。
4. database_change 延迟 reload 后，要确认会话列表 preview 仍及时刷新。
5. ask_user legacy identity 稳定化需要和 DEEPTUTORCHAT-000012 的提交恢复链路一起验收。
```

## 9. 本次分析结论

本次崩溃的最高置信原因是：

```text
重复 openConversation + reloadMessages 连续发布 state + DiffableDataSource apply 无重入保护
```

优先修复顺序：

```text
1. 去掉重复 `.task(id: conversationID)`。
2. 给 open/reload 加 generation guard。
3. 给 diffable snapshot apply 加串行队列和 pending payload 合并。
4. 把 reloadMessages 改成一次性 state commit。
5. 再继续收敛 ask_user legacy identity 和 database_change 节流。
```

本工单未修改 Swift 业务代码，仅新增需求与技术分析文档。
