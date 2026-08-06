# DEEPTUTORCHAT-000016 Diffable 队列内 Hosting Cell 自尺寸测量崩溃优化工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000016 |
| 工单类型 | P0 崩溃修复 + 消息列表结构/内容刷新分层 + DeepTutor-main 对齐 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| iOS 功能目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| Web 参考工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main` |
| 崩溃附件 | `/Users/hua/.codex/attachments/5e38882b-af89-4057-a2f7-bdfb34d58344/pasted-text.txt` |
| 创建日期 | 2026-08-06 |
| 关联工单 | `DEEPTUTORCHAT-000014`、`DEEPTUTORCHAT-000015` |

## 1. 本工单目标

继续修复 DeepTutorChat 消息列表崩溃。

本次崩溃发生在：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorMessageListView.swift
line 135-136
```

对应代码：

```swift
dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
    guard let self else { return }
```

崩溃堆栈显示当前已经不是 `DiffableDataSource` 快照重入断言，也不完全是 row 直接订阅 ViewModel 的问题。当前更具体的问题是：

```text
UICollectionViewDiffableDataSource 正在 serial diffing queue 内执行 apply，
UICollectionView 为 UIHostingConfiguration cell 做自尺寸测量，
SwiftUI VStackLayout.sizeThatFits 复制/retain StackLayout.Child 时崩溃。
```

本工单目标是把 iOS 消息列表刷新继续对齐 DeepTutor-main：

```text
1. 结构变更和内容变更分离。
2. 流式 token/trace 不再频繁走 snapshot.reloadItems。
3. Diffable apply 只负责插入/删除/顺序变化。
4. 单条消息内容更新走轻量 reconfigure 或 cell 内局部 store。
5. 避免在 dataSource.apply completion 内同步 layoutIfNeeded 和滚动。
6. 降低 UIHostingConfiguration + estimated self-sizing 在 diffing 队列中的崩溃风险。
```

## 2. 崩溃日志结论

### 2.1 当前崩溃堆栈

附件核心堆栈：

```text
Thread 1 Queue : com.apple.uikit.datasource.diffing (serial)
#0  swift_retain
#1  initializeWithCopy value witness for SwiftUI.StackLayout.Child
#2  swift_arrayInitWithCopy
#3  Swift._ArrayBuffer._consumeAndCreateNew
#4  SwiftUI.VStackLayout.sizeThatFits
...
#37 systemLayoutSizeFitting
#39 UICollectionViewCell systemLayoutSizeFittingSize
#40 UICollectionReusableView preferredLayoutAttributesFittingAttributes
#42 UICollectionView _checkForPreferredAttributesInView
#44 UICollectionView _createPreparedCellForItemAtIndexPath
...
#63 __UIDiffableDataSource _applyDifferencesFromSnapshot
#65 DeepTutorMessageListViewController.performApply(...) at DeepTutorMessageListView.swift:135
#67 DeepTutorMessageListRepresentable.updateUIViewController(...) at DeepTutorMessageListView.swift:297
```

结论：

```text
Diffable apply 仍是入口。
崩溃点已经深入到 SwiftUI VStackLayout.sizeThatFits 的布局测量和 StackLayout.Child copy/retain。
也就是说，UICollectionView 正在准备 cell、计算 preferred layout attributes、自尺寸测量 UIHostingConfiguration 内容时，SwiftUI layout graph 出现不稳定。
```

### 2.2 与上一张工单的关系

`DEEPTUTORCHAT-000015` 已推动当前代码出现以下改动：

```text
1. DeepTutorMessageRowView 已改为 value model + actions。
2. DeepTutorMessageRowView 不再直接 @ObservedObject DeepTutorChatViewModel。
3. DeepTutorListApplyPayload 已包含 rowModels。
4. DeepTutorMessageListViewController 已包含 renderObserver。
5. ViewModel 已加入 DeepTutorRenderScheduler。
```

当前代码证据：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorMessageRowView.swift
line 3: struct DeepTutorMessageRowView: View
line 4: let model: DeepTutorMessageRowModel
line 5: let actions: DeepTutorMessageRowActions
```

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorMessageListView.swift
line 124: rowModelLookup = Dictionary(uniqueKeysWithValues: payload.rowModels.map { ($0.id, $0) })
line 132: snapshot.reloadItems(reloadable)
line 135: dataSource.apply(snapshot, animatingDifferences: false)
line 137: self.collectionView.layoutIfNeeded()
line 213: cell.contentConfiguration = UIHostingConfiguration { DeepTutorMessageRowView(...) }
```

说明：

```text
上一张工单的方向是对的，但还没有完全解决 diffable apply 队列内的 SwiftUI Hosting 自尺寸测量问题。
当前需要继续把“消息内容刷新”从“列表结构快照 apply”中拆出去。
```

## 3. 当前关键风险点

### 3.1 `snapshot.reloadItems` 仍会重建/重测 UIHostingConfiguration cell

当前代码：

```swift
let reloadable = plan.reloadedItemIDs.filter { snapshot.indexOfItem($0) != nil }
if reloadable.isEmpty == false {
    snapshot.reloadItems(reloadable)
}
```

风险：

```text
只要 message 内容、trace、thinking、ask_user、blocks 或状态变化，
DeepTutorConversationUpdateBuilder 会把该 clientMessageID 放入 reloadedItemIDs。
随后 snapshot.reloadItems 会让 UICollectionView 在 diffable apply 中重载 cell。
对于 UIHostingConfiguration，这通常意味着重新配置 SwiftUI view，并触发 systemLayoutSizeFitting / preferredLayoutAttributesFitting。
```

在 DeepTutorChat 里，助手消息非常复杂：

```text
1. trace 折叠区。
2. thinking 文本。
3. tool call 状态。
4. ask_user 卡片。
5. markdown 正文。
6. quiz / visualize / generated files 等扩展卡片。
7. 流式 reasoning 和 answer token。
```

这些内容如果都通过 `reloadItems` 进入 diffable apply，就会让 diffing 队列承担过多 SwiftUI 布局测量。

### 3.2 `renderSignature` 仍把高频内容变化纳入列表快照签名

当前代码：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Domain/DeepTutorMessageRowModel.swift
```

关键逻辑：

```swift
hasher.combine(message.status.rawValue)
hasher.combine(message.content)
...
for block in message.blocks {
    hasher.combine(block.kind.rawValue)
    hasher.combine(blockSignature(block))
}
```

其中 block 签名：

```swift
case .trace(let payload):
    let detailLen = payload.rows.map { ($0.argsDetail ?? "") + ($0.resultDetail ?? "") }.joined().count
    return "trace|\(payload.isFinalAnswerPhase)|\(payload.rows.count)|\(detailLen)|\(payload.isExpanded)"
case .text(let text):
    return "text|\(text.count)"
case .thinking(let text):
    return "thinking|\(text.count)"
```

风险：

```text
流式阶段每一小段 thinking/text/trace detail 长度变化都可能改变 renderSignature。
renderSignature 改变后，ListApplySignature 改变。
ListApplySignature 改变后，updateUIViewController 会继续调用 apply。
apply 中 reloadedItemIDs 会进入 snapshot.reloadItems。
最终，流式内容变化仍然频繁驱动 Diffable + Hosting cell 自尺寸测量。
```

### 3.3 CompositionalLayout 使用 estimated 高度，强依赖 cell 自尺寸

当前代码：

```swift
let item = NSCollectionLayoutItem(
    layoutSize: NSCollectionLayoutSize(
        widthDimension: .fractionalWidth(1),
        heightDimension: .estimated(120)
    )
)
let group = NSCollectionLayoutGroup.vertical(
    layoutSize: NSCollectionLayoutSize(
        widthDimension: .fractionalWidth(1),
        heightDimension: .estimated(120)
    ),
    subitems: [item]
)
```

风险：

```text
estimated height 会让 UICollectionView 高频调用 preferredLayoutAttributesFitting / systemLayoutSizeFitting。
UIHostingConfiguration 又会在 sizeThatFits 中驱动 SwiftUI layout graph。
如果同一时间还在 diffable apply、reloadItems、layoutIfNeeded、scrollToBottom，SwiftUI 布局图压力会非常大。
```

### 3.4 apply completion 中同步 `layoutIfNeeded` 和滚动

当前代码：

```swift
dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
    guard let self else { return }
    self.collectionView.layoutIfNeeded()
    if shouldForceScroll {
        self.scrollToBottom(force: true)
    } else if self.bottomViewportLockActive {
        self.scrollToBottom(force: true)
    } ...
}
```

风险：

```text
dataSource.apply completion 并不意味着 UICollectionView/SwiftUI Hosting 的所有自尺寸测量都已经完全稳定。
在 completion 内立刻 layoutIfNeeded，会强制同步触发布局。
随后 scrollToBottom 又可能触发可见 cell 创建和测量。
这会把 diffable apply、cell creation、SwiftUI sizeThatFits、scroll layout 压到同一个事务附近。
```

### 3.5 updateUIViewController 仍直接把所有 rowModels 投入 apply

当前代码：

```swift
let payload = DeepTutorListApplyPayload(
    rowModels: viewModel.makeMessageRowModels(),
    hasMoreMessages: viewModel.state.hasMoreMessages,
    ...
)
uiViewController.apply(conversationID: conversationID, payload: payload)
```

风险：

```text
即使 row 去掉了 ViewModel 订阅，只要每次 state.messages 改变都会生成新的 rowModels，
并通过 ListApplySignature 触发 apply，SwiftUI Hosting cell 仍会被 diffable 频繁参与重测。
```

## 4. 根因链路

```text
AI 流式输出 reasoning / answer / trace
  -> DeepTutorChatViewModel.applyStreamingMessage
  -> DeepTutorRenderScheduler 合帧后 commit state.messages
  -> SwiftUI updateUIViewController
  -> makeMessageRowModels 生成新的 renderSignature
  -> DeepTutorListApplySignature 变化
  -> DeepTutorMessageListViewController.apply
  -> DeepTutorConversationUpdateBuilder 发现 message != old message
  -> snapshot.reloadItems(reloadable)
  -> dataSource.apply(snapshot)
  -> UICollectionView diffing queue 创建/重载 cell
  -> UIHostingConfiguration 进入 systemLayoutSizeFitting
  -> SwiftUI VStackLayout.sizeThatFits 复制 StackLayout.Child
  -> 高复杂度消息内容 + 自尺寸测量 + 同步 layoutIfNeeded/scroll
  -> swift_retain / StackLayout.Child copy 崩溃
```

## 5. DeepTutor-main 对齐基线

### 5.1 Web 端列表结构和消息内容天然分层

参考位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ChatMessages.tsx
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/common/AssistantResponse.tsx
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/TracePanels.tsx
```

Web 端渲染特点：

```text
1. ChatMessageList 根据 messages 渲染列表结构。
2. 单条 AssistantMessage 内部再分发 trace、ask_user、markdown、quiz、visualize。
3. 流式正文主要更新 AssistantResponse / MarkdownRenderer 的内容。
4. trace 展开/折叠主要影响 AssistantActivity 局部。
5. 不会因为正文每个 token 变化就重建整个消息列表结构。
```

Web 可以概括为：

```text
列表结构：message IDs / branch visible path / turn order
消息内容：trace / thinking / answer / ask_user / markdown / cards
滚动策略：useChatAutoScroll 独立处理
```

### 5.2 iOS 当前仍把内容变化塞进结构快照

当前 iOS 可概括为：

```text
message.content 或 block detailLen 变化
  -> renderSignature 变化
  -> ListApplySignature 变化
  -> Diffable snapshot apply
  -> reloadItems
  -> Hosting cell 重新测量
```

与 DeepTutor-main 的主要偏差：

| 维度 | DeepTutor-main Web | 当前 iOS | 需要对齐 |
| --- | --- | --- | --- |
| 列表结构 | message key / order 变化才影响列表结构 | 内容变化也触发 snapshot apply | 结构与内容拆分 |
| 内容流式 | AssistantResponse 局部更新 | reloadItems 重载整条 cell | 局部 store / reconfigure |
| trace 更新 | AssistantActivity 局部更新 | trace detailLen 进入 renderSignature | trace 独立刷新 |
| 滚动 | useChatAutoScroll 独立调度 | apply completion 内 layoutIfNeeded + scroll | 滚动延后一帧 |
| 自尺寸 | 浏览器布局增量处理 | UIHostingConfiguration 自尺寸测量压在 diffing queue | 高度缓存与降频 |

## 6. iOS 修复方案

### 6.1 P0：拆分结构签名和内容签名

当前 `renderSignature` 同时承担：

```text
1. 列表结构是否需要 apply。
2. cell 内容是否需要刷新。
3. cell 高度是否可能变化。
```

建议拆成三类签名：

```swift
struct DeepTutorMessageRowModel {
    let identitySignature: Int
    let contentSignature: Int
    let layoutSignature: Int
}
```

含义：

| 签名 | 触发条件 | 更新方式 |
| --- | --- | --- |
| `identitySignature` | id、role、parent、turn、branch 变化 | diffable apply |
| `contentSignature` | text、thinking、trace 文案、tool 状态变化 | reconfigure 或 cell 内局部更新 |
| `layoutSignature` | 会明显改变高度的卡片增删、ask_user 出现/消失、附件数量变化 | 延迟 layout invalidation |

要求：

```text
1. ListApplySignature 只包含 identitySignature、message ids、hasMore、forceFullListRediff。
2. text.count / thinking.count / trace detailLen 不得进入列表结构签名。
3. 流式 token 不得触发 snapshot.reloadItems。
```

### 6.2 P0：Diffable apply 只处理结构变化

结构变化包括：

```text
1. 首次加载。
2. 新增用户消息。
3. 新增助手消息。
4. 历史消息 prepend。
5. 删除 turn。
6. 分支切换导致 visible path 变化。
7. load more row 出现/消失。
```

非结构变化包括：

```text
1. assistant.content 增长。
2. reasoning/thinking 增长。
3. trace row detail 增长。
4. cost/token/duration 更新。
5. streaming 状态从 streaming 到 completed。
6. trace 展开/折叠。
```

对非结构变化：

```text
不要调用 dataSource.apply(snapshot)。
不要调用 snapshot.reloadItems。
优先走 visible cell 局部 update 或 dataSource.reconfigureItems。
```

### 6.3 P0：用 `reconfigureItems` 替代 `reloadItems`

对于同一个 itemID 已存在，只是内容变化：

```swift
snapshot.reconfigureItems(contentChangedItemIDs)
```

而不是：

```swift
snapshot.reloadItems(reloadable)
```

差异：

```text
reloadItems 更接近删除/重建 cell，会带来更重的 cell 生命周期和布局测量。
reconfigureItems 适合 item identity 不变时刷新内容，理论上更符合消息流式更新。
```

注意：

```text
如果使用 reconfigureItems 仍触发 UIHostingConfiguration 大量 sizeThatFits，
则继续升级到 6.4 的 cell 内局部 store 方案。
```

### 6.4 P0：为流式助手消息引入 cell 内局部内容 Store

DeepTutor-main 的核心体验是：

```text
消息列表结构稳定，助手消息内容自己流动。
```

iOS 建议为 assistant streaming row 引入局部 store：

```swift
@MainActor
final class DeepTutorMessageCellStore: ObservableObject {
    @Published private(set) var content: DeepTutorMessageContentState
    func updateContent(_ next: DeepTutorMessageContentState)
}
```

使用方式：

```text
1. Diffable snapshot 只创建 cell 和绑定 messageID。
2. cell 内持有/获取对应 messageID 的 store。
3. 流式 token、trace、thinking 更新只更新 store。
4. store 更新只影响该 cell 内 AssistantBubble / AssistantResponse / TracePanel。
5. 不触发列表 snapshot apply。
```

约束：

```text
1. store 必须按 conversationID + messageID 管理生命周期。
2. cell reuse 时必须取消旧订阅，绑定新 store。
3. 非可见 cell 的 store 可以只缓存最新状态，不必持续渲染。
4. 消息完成或会话关闭时清理 store。
```

这是最接近 DeepTutor-main 的 iOS 实现：

```text
ChatMessageList 负责 message identity。
AssistantMessage 内部组件负责内容渲染。
```

### 6.5 P0：移除 apply completion 内同步 `layoutIfNeeded`

当前 completion 内立刻：

```swift
self.collectionView.layoutIfNeeded()
self.scrollToBottom(...)
```

建议改为：

```text
1. apply completion 只标记 apply 结束、记录日志、处理 pending。
2. 滚动请求进入独立 ScrollScheduler。
3. ScrollScheduler 在下一 runloop 或下一帧执行。
4. 执行前判断 collectionView.window != nil、numberOfItems > 0、目标 indexPath 可用。
5. 不在 diffable apply completion 内强制 layoutIfNeeded。
```

伪代码：

```swift
dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
    guard let self else { return }
    self.finishApply(...)
    self.scrollScheduler.enqueue(reason: scrollReason)
}

scrollScheduler.enqueue {
    await Task.yield()
    collectionView.performBatchUpdates(nil)
    scrollToBottomIfNeeded()
}
```

更保守方案：

```text
使用 DispatchQueue.main.async 或 Task { @MainActor in await Task.yield() }
将滚动和 layout 推迟到当前 diffable/layout 事务之后。
```

### 6.6 P1：增加高度缓存，降低 estimated self-sizing 压力

当前所有 item/group 都是：

```text
heightDimension: .estimated(120)
```

建议：

```text
1. 记录每个 messageID 的最近稳定高度。
2. layout estimated height 使用更接近真实高度的缓存值。
3. 用户消息、短助手消息、trace/ask_user/markdown 长消息使用不同默认估算。
4. 内容流式增长时，不每个 token invalidate layout。
5. 高度明显变化时，合帧后统一 invalidate。
```

估算策略：

| 消息类型 | 默认估算 |
| --- | --- |
| 用户短文本 | 64 |
| 用户长文本 | 96-140 |
| 助手纯短文本 | 120 |
| 助手含 trace | 180 |
| 助手含 ask_user | 260 |
| 助手含 markdown 长文 | 320+ |

注意：

```text
高度缓存不是最终布局，只是减少 self-sizing 反复震荡。
```

### 6.7 P1：复杂消息卡片分层，减少单个 VStack 子节点 churn

本次崩溃在：

```text
SwiftUI.VStackLayout.sizeThatFits
initializeWithCopy value witness for SwiftUI.StackLayout.Child
```

说明复杂 `VStack` 子节点复制/测量压力很高。

建议：

```text
1. DeepTutorAssistantBubble 内部拆成稳定容器。
2. TracePanel、AskUserCard、AssistantResponse、GeneratedFileCards 使用明确子组件边界。
3. 对经常变化的文本组件使用固定身份。
4. 避免流式期间频繁增删 VStack 子节点，优先保留节点，仅更新内部内容。
5. 正式回答出现后 thinking 折叠，不要删除整块节点；可以隐藏/折叠到稳定容器。
```

示例：

```swift
VStack(alignment: .leading, spacing: 12) {
    TraceSlotView(...)
        .id("trace-slot")
    AskUserSlotView(...)
        .id("ask-user-slot")
    AssistantResponseSlotView(...)
        .id("response-slot")
    ActionBarSlotView(...)
        .id("actions-slot")
}
```

目标：

```text
减少 VStack child 数组频繁 replace/copy。
降低 StackLayout.Child retain/copy 崩溃概率。
```

### 6.8 P1：评估自定义 Hosting Cell 替代 UIHostingConfiguration

如果完成结构/内容分离后仍崩溃，建议升级：

```text
DeepTutorHostingMessageCell: UICollectionViewCell
```

职责：

```text
1. 内部持有 UIHostingController。
2. prepareForReuse 时显式解绑 messageID/store。
3. setModel 时只在 messageID 变化时重建 rootView。
4. 内容变化时更新 store，不替换 rootView。
5. 高度变化时通过 delegate/requestLayoutUpdate 合帧通知 collectionView。
```

这样可以避免 `UIHostingConfiguration` 在 diffable reconfigure/reload 中反复创建闭包内容和 hosting view。

## 7. 推荐改造顺序

### 阶段一：止住 diffable 内容刷新

```text
1. 拆分 identitySignature / contentSignature / layoutSignature。
2. ListApplySignature 只包含结构签名。
3. 删除流式内容对 snapshot.reloadItems 的触发。
4. 将 reloadItems 改为 reconfigureItems，且只用于非流式、低频内容变化。
```

验收：

```text
assistant token 增长时，日志不出现 list.snapshot.apply_start。
只有新消息插入、删除、分支切换、load more 时才出现 snapshot apply。
```

### 阶段二：滚动调度独立

```text
1. 移除 apply completion 内同步 layoutIfNeeded。
2. 新增 ScrollScheduler。
3. 滚动到底部和恢复 topAnchor 均延后一帧。
4. 滚动前检查目标 item 是否存在。
```

验收：

```text
崩溃堆栈不再出现 apply completion 内同步 layoutIfNeeded 触发的 cell measurement。
```

### 阶段三：cell 内局部内容 Store

```text
1. 为可见 assistant row 建立 DeepTutorMessageCellStore。
2. 流式 reasoning/answer/trace 更新 store，不 apply snapshot。
3. ask_user 出现这类高度明显变化事件，通过 layoutSignature 合帧请求 layout update。
```

验收：

```text
长文本流式 500 次 partial 更新，列表结构 apply 次数 <= 3。
可见助手气泡内容正常流动。
滚动不卡顿，不崩溃。
```

### 阶段四：Hosting cell 稳定性升级

```text
1. 如果 UIHostingConfiguration 仍崩溃，替换为 DeepTutorHostingMessageCell。
2. 显式管理 UIHostingController 生命周期。
3. 固化 slot 子组件身份。
4. 高度缓存与 layout invalidation 合帧。
```

## 8. 日志补充

### 8.1 区分结构 apply 与内容更新

新增：

```text
deeptutor.list.structure.apply_start conversation={id} itemCount={n} reason={initial|append|prepend|delete|branch|load_more}
deeptutor.list.structure.apply_done conversation={id} durationMs={ms} pending={true|false}
deeptutor.message.content.update conversation={id} message={id} contentSignature={hash} path={cell_store|reconfigure|reload}
deeptutor.message.layout.update_requested conversation={id} message={id} layoutSignature={hash} reason={ask_user|trace_expand|markdown_growth}
```

验收：

```text
流式 token 期间主要出现 message.content.update path=cell_store。
不应持续出现 list.structure.apply_start。
```

### 8.2 监控 reload/reconfigure 使用

新增：

```text
deeptutor.list.items.reload count={n} reason={reason}
deeptutor.list.items.reconfigure count={n} reason={reason}
deeptutor.list.items.reload_blocked count={n} reason=streaming_content
```

规则：

```text
streaming_content 场景不允许 reloadItems。
```

### 8.3 自尺寸测量监控

新增：

```text
deeptutor.cell.measure.start message={id} estimatedHeight={h}
deeptutor.cell.measure.done message={id} measuredHeight={h} durationMs={ms}
deeptutor.cell.height.cache_hit message={id} height={h}
deeptutor.cell.height.cache_miss message={id} fallback={h}
```

用途：

```text
排查是否仍在 diffable apply 中出现大量 self-sizing。
```

### 8.4 滚动调度日志

新增：

```text
deeptutor.scroll.schedule reason={force_bottom|bottom_lock|prepend_anchor|stream_follow} delay={next_runloop|next_frame}
deeptutor.scroll.execute reason={reason} target={messageID|-} visibleCount={n}
deeptutor.scroll.skip reason={not_pinned|target_missing|collection_not_ready|user_dragging}
```

## 9. 验收标准

### 9.1 不再复现本次崩溃堆栈

```text
Given 使用同一条崩溃复现路径
When 打开会话并触发流式 reasoning / answer / trace 更新
Then App 不崩溃
And 崩溃堆栈不再出现：
SwiftUI.VStackLayout.sizeThatFits
initializeWithCopy value witness for SwiftUI.StackLayout.Child
UICollectionReusableView preferredLayoutAttributesFittingAttributes
DeepTutorMessageListViewController.performApply line 135
```

### 9.2 流式内容不触发结构快照

```text
Given assistant 正在持续输出 token
When message.content / thinking / trace detailLen 增长
Then 不触发 dataSource.apply(snapshot)
And 不触发 snapshot.reloadItems
And UI 内容仍正常流式展示
```

### 9.3 结构变化仍正常

```text
Given 用户发送新消息
When 插入 user message 和 assistant message
Then Diffable apply 正常执行
And 自动滚动到底部
And 消息顺序正确
```

### 9.4 ask_user 高度变化正常

```text
Given assistant 流式过程中出现 ask_user 卡片
When ask_user block 从无到有
Then 卡片展示出来
And 只触发布局级合帧更新
And 不发生频繁 reloadItems
```

### 9.5 trace 展开/折叠不崩溃

```text
Given assistant 消息包含 trace
When 用户快速展开/折叠 trace 20 次
Then 不崩溃
And 不出现 AttributeGraph cycle
And 列表滚动位置稳定
```

### 9.6 长会话加载稳定

```text
Given 本地数据库存在 100+ 会话
And 单个会话包含 50+ 消息
And 多条助手消息包含 trace、ask_user、markdown、工具调用
When 连续打开 20 个会话
Then 不崩溃
And 不出现 com.apple.uikit.datasource.diffing 队列内 SwiftUI layout 崩溃
```

## 10. 风险与注意事项

### 10.1 不要把所有内容变化继续塞进 renderSignature

原因：

```text
如果 text.count、thinking.count、trace detailLen 继续影响列表 apply signature，
那么流式内容仍会频繁进入 diffable apply。
这会复现本次 Hosting cell 自尺寸测量崩溃。
```

### 10.2 不要简单把 estimated height 改成 absolute height

原因：

```text
DeepTutor 消息高度差异极大。
absolute height 会造成内容截断或大量空白。
正确方向是高度缓存 + 合帧 invalidation，而不是固定高度。
```

### 10.3 不要在 apply completion 内继续强制同步布局

原因：

```text
completion 内 layoutIfNeeded 会把 UICollectionView cell 创建、SwiftUI sizeThatFits、滚动计算压进同一事务。
本次崩溃堆栈正发生在 cell 自尺寸测量链路上。
```

### 10.4 `reconfigureItems` 不是最终保险

原因：

```text
reconfigureItems 比 reloadItems 轻，但 UIHostingConfiguration 仍可能触发内容重新配置和测量。
如果流式高频更新仍不稳定，必须升级到 cell 内局部 store 或自定义 Hosting cell。
```

## 11. 最小修复闭环

本工单最小修复闭环：

```text
1. 流式 token/trace/thinking 不再触发 dataSource.apply。
2. snapshot.reloadItems 不再用于 streaming_content。
3. dataSource.apply completion 不再同步 layoutIfNeeded。
4. 滚动进入下一 runloop/下一帧调度。
5. 高度变化合帧处理。
6. 日志能证明结构 apply 和内容 update 已分离。
```

达到以上闭环后，DeepTutorChat iOS 消息列表才算从“Diffable 驱动一切变化”转向 “DeepTutor-main 式的结构列表 + 单条消息内容局部渲染”。

## 12. 后续可选架构目标

如果 P0 修复后仍有 SwiftUI Hosting 稳定性问题，建议启动下一张架构工单：

```text
DEEPTUTORCHAT-000017 自定义 DeepTutorHostingMessageCell 与消息内容 Store 架构改造
```

目标：

```text
1. UICollectionViewDiffableDataSource 只管理 messageID。
2. DeepTutorHostingMessageCell 绑定 messageID + content store。
3. UIHostingController rootView 不随 token 重建。
4. AssistantResponse/TracePanel/AskUserCard 按 slot 局部更新。
5. 高度测量与滚动调度完全可控。
```
