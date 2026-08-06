# DEEPTUTORCHAT-000015 消息 Cell 渲染期间发布状态导致 AttributeGraph 崩溃优化工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000015 |
| 工单类型 | P0 崩溃修复 + SwiftUI/UICollectionView 混合渲染架构优化 + DeepTutor-main 对齐 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| iOS 功能目录 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat` |
| Web 参考工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main` |
| 崩溃堆栈附件 | `/Users/hua/.codex/attachments/e7c00f44-65c0-4e17-880f-12d9a12b88c2/pasted-text.txt` |
| 运行日志附件 | `/Users/hua/.codex/attachments/cb0c1d4e-e94a-48cb-9dac-7e99d17622ba/pasted-text.txt` |
| 创建日期 | 2026-08-06 |
| 关联工单 | `DEEPTUTORCHAT-000014`、`DEEPTUTORCHAT-000012`、`DEEPTUTORCHAT-000013` |

## 1. 本工单目标

解决 `DEEPTUTORCHAT-000014` 之后仍然出现的消息列表崩溃问题。

当前日志说明 `DiffableDataSource` 快照重入已经被初步拦截，但列表仍会在 `UICollectionView` 创建/布局 `UIHostingConfiguration` cell 时触发 SwiftUI `AttributeGraph` 循环，并最终在 SwiftUI 栈布局缓存释放阶段崩溃。

用户可见问题：

```text
1. 打开或流式刷新 DeepTutor 会话时仍可能崩溃。
2. 崩溃前出现大量：
   Publishing changes from within view updates is not allowed, this will cause undefined behavior.
3. 崩溃前出现大量：
   === AttributeGraph: cycle detected through attribute ... ===
4. 崩溃堆栈落在 DeepTutorMessageListViewController.performApply line 130，
   但直接触发点已经不是 Diffable reentrant assertion，而是 SwiftUI cell 布局期间的状态发布/视图图循环。
```

本工单只做原因分析、对齐方案、实现拆解和验收标准，不修改 Swift 代码。

## 2. 关键结论

### 2.1 这次不是上一张工单里的同类崩溃

`DEEPTUTORCHAT-000014` 聚焦的问题是：

```text
dataSource.apply(snapshot) 正在执行时再次 apply snapshot，
触发 UIKit 的 reentrant snapshot 断言。
```

本次日志中已经出现：

```text
deeptutor.list.snapshot.apply_done conversation=C22B6A2A pending=false durationMs=71
```

这说明当前代码已经存在某种 `isApplyingSnapshot` / `pendingApply` / `same_signature` 级别的保护，至少没有直接落到 `NSInternalInconsistencyException` 那条路径。

但新崩溃堆栈显示：

```text
#0  swift_release
#1  swift_arrayDestroy
#2  Swift._ArrayBufferProtocol.replaceSubrange
#4  SwiftUI.HVStack.updateCache
...
#45 UICollectionView _createPreparedCellForItemAtIndexPath
...
#64 __UIDiffableDataSource _applyDifferencesFromSnapshot
#66 DeepTutorMessageListViewController.performApply(...) at DeepTutorMessageListView.swift:130
#68 DeepTutorMessageListRepresentable.updateUIViewController(...) at DeepTutorMessageListView.swift:278
```

结论：

```text
Diffable apply 仍在堆栈中，但它更像是触发 cell 创建/布局的入口。
真正危险点是 SwiftUI 的 HStack/VStack 布局图正在更新，
同时外部又发布了 ObservableObject 状态，导致 AttributeGraph 循环和布局缓存异常释放。
```

### 2.2 日志已经明确提示状态发布时机错误

运行日志连续出现：

```text
Publishing changes from within view updates is not allowed, this will cause undefined behavior.
```

随后出现：

```text
=== AttributeGraph: cycle detected through attribute 1301672 ===
=== AttributeGraph: cycle detected through attribute 1302592 ===
=== AttributeGraph: cycle detected through attribute 1322704 ===
...
```

结论：

```text
当前 ViewModel 或 UI 回调正在 SwiftUI view update / UIKit cell layout 事务期间发布 @Published 状态。
这类问题不一定每次立刻崩溃，但属于 SwiftUI 明确标记的 undefined behavior。
本次 swift_release / swift_arrayDestroy 崩溃就是该 undefined behavior 的一种结果。
```

### 2.3 行视图订阅整个 ViewModel 是核心放大器

iOS 代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorMessageRowView.swift
```

当前关键结构：

```swift
struct DeepTutorMessageRowView: View {
    @ObservedObject var viewModel: DeepTutorChatViewModel
    let message: DeepTutorMessage

    var body: some View {
        HStack {
            if message.role == .user {
                DeepTutorUserBubble(
                    message: message,
                    branchInfo: viewModel.branchInfo(for: message.id),
                    ...
                )
            } else {
                DeepTutorAssistantBubble(message: message, ...)
            }
        }
    }
}
```

问题：

```text
每一个 UICollectionView cell 里的 SwiftUI row 都 @ObservedObject 订阅 DeepTutorChatViewModel。
只要 ViewModel 任意 @Published 字段变化，所有可见 row 都可能重新计算 body 和 layout。
这些变化包括 messages、conversation、conversations、selectedConversationID、phase、streaming、toast 等。

结果是：
UICollectionView 正在 dataSource.apply -> 创建 cell -> UIHostingConfiguration 布局 row，
此时 ViewModel 又发布状态 -> row body 再次失效 -> AttributeGraph 尝试重入更新布局图。
```

### 2.4 rowBuilder 捕获 ViewModel，导致 cell 不是纯数据渲染

iOS 代码位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorMessageListView.swift
```

当前关键结构：

```swift
controller.rowBuilder = { message in
    AnyView(
        DeepTutorMessageRowView(
            viewModel: viewModel,
            message: message,
            onCopy: { onCopy(message) },
            onRetry: { onRetry(message) },
            onSubmitAskUser: { toolCallID, answers in
                onSubmitAskUser(message, toolCallID, answers)
            }
        )
    )
}
```

问题：

```text
UICollectionView cell 本应该使用 itemID -> immutable row model 渲染。
但当前 rowBuilder 捕获了 live ViewModel，并把 ViewModel 放进每个 cell。
这会让 cell 生命周期、SwiftUI body 生命周期、ViewModel 发布生命周期纠缠在一起。
```

### 2.5 UIKit 滚动回调中也会直接触发 ViewModel 状态变更

当前关键结构：

```swift
controller.onUserInteraction = {
    viewModel.releaseBottomLockAfterUserInteraction()
    if let lastID = viewModel.state.messages.last?.id {
        viewModel.rememberScrollAnchor(messageID: lastID)
    }
}
```

问题：

```text
scrollViewWillBeginDragging 可能发生在 UICollectionView 更新可见 cell / SwiftUI hosting layout 的附近。
如果 onUserInteraction 内部直接修改 @Published state，也可能触发：
Publishing changes from within view updates is not allowed
```

### 2.6 会话列表 database_change 刷新与消息列表渲染互相干扰

运行日志：

```text
DeepTutor 仓储：loadConversations count=109, ownerAccountID=265, scenario=deepTutor
Publishing changes from within view updates is not allowed, this will cause undefined behavior.
...
DeepTutor 会话列表已刷新，count=109, source=database_change, scenario=deepTutor
deeptutor.list.load.done count=109 source=database_change
```

结论：

```text
数据库变化触发了会话列表刷新，刷新后发布 conversations。
该发布发生在消息列表 apply/layout 附近。
虽然 conversations 不直接属于当前消息 cell 的渲染数据，
但由于 cell row 订阅了整个 DeepTutorChatViewModel，
conversations 更新也会让所有 row 失效。
```

### 2.7 reasoning-only 流式 trace 更新频率过高

运行日志：

```text
deeptutor.stream.partial.mapped conversation=C22B6A2A assistant=EF0C586D tool=- call=- answerLen=0 reasoningLen=238 events=reasoning(2) forceFlush=false blocks=envelope=1,trace=1
deeptutor.stream.partial.mapped conversation=C22B6A2A assistant=EF0C586D tool=- call=- answerLen=0 reasoningLen=239 events=reasoning(1) forceFlush=false blocks=envelope=1,trace=1
deeptutor.stream.partial.mapped conversation=C22B6A2A assistant=EF0C586D tool=- call=- answerLen=0 reasoningLen=242 events=reasoning(2) forceFlush=false blocks=envelope=1,trace=1
...
```

问题：

```text
正式 answerLen 仍为 0，但 reasoningLen 高频增长。
如果每次 reasoning delta 都进入 message block 更新、state.messages 更新和 list snapshot reload，
就会在 cell layout 期间制造大量 row body invalidation。
```

DeepTutor-main 的 Web 端可以承受较高频流式更新，是因为 React 渲染链路里消息 row 更接近 props 派生渲染，且 trace、正文、滚动都有独立组件与 hook 管控。iOS 当前把这些更新压到同一个 ObservableObject 和同一个 UICollectionView hosting cell 树里，风险更高。

## 3. 当前根因链路

```text
用户打开 DeepTutor 会话 / AI 正在流式 reasoning
  -> DeepTutorChatViewModel 接收数据库变化或 stream partial
  -> 发布 @Published state / conversations / conversation
  -> SwiftUI 调用 DeepTutorMessageListRepresentable.updateUIViewController
  -> DeepTutorMessageListViewController.performApply
  -> UICollectionViewDiffableDataSource.apply(snapshot)
  -> UICollectionView 创建/更新可见 cell
  -> UIHostingConfiguration 创建 SwiftUI row
  -> DeepTutorMessageRowView body 读取 @ObservedObject viewModel
  -> row 订阅整个 ViewModel
  -> 同一时间 database_change / stream partial / scroll callback 再次发布 ViewModel
  -> SwiftUI 在 view update/layout 事务期间收到 objectWillChange
  -> Publishing changes from within view updates warning
  -> AttributeGraph cycle detected
  -> SwiftUI.HVStack.updateCache / ArrayBuffer.replaceSubrange 崩溃
```

## 4. 与 DeepTutor-main 的架构差异

### 4.1 Web 参考链路

参考位置：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/app/(workspace)/home/[[...sessionId]]/page.tsx
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ChatMessages.tsx
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/common/AssistantResponse.tsx
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/TracePanels.tsx
```

Web 会话链路：

```text
UnifiedChatContext
  -> state.messages
  -> ChatMessageList props
  -> UserMessage / AssistantMessage props
  -> AssistantActivity / AssistantResponse / AskUserOptions props
```

核心特点：

```text
1. ChatMessageList 接收 messages、isStreaming、sessionId、language 等显式 props。
2. UserMessage / AssistantMessage 主要基于单条 message props 渲染。
3. trace、ask_user、markdown、generated files 都是从 message.events / message.content 派生。
4. 行组件不是在渲染期间反向订阅整个 UnifiedChatContext 并读取所有全局状态。
5. 流式更新由上下文 reducer 聚合成 messages，再向下分发 props。
```

### 4.2 iOS 当前差异

当前 iOS 链路：

```text
DeepTutorChatViewModel
  -> @Published state / conversation / conversations / selectedConversationID
  -> DeepTutorMessageListRepresentable.updateUIViewController
  -> DeepTutorMessageListViewController.apply
  -> UIHostingConfiguration
  -> DeepTutorMessageRowView(@ObservedObject viewModel)
```

主要偏差：

| 项目 | DeepTutor-main Web | 当前 iOS | 风险 |
| --- | --- | --- | --- |
| 消息 row 数据来源 | 显式 props | `message + @ObservedObject viewModel` | row 被所有 ViewModel 发布牵连 |
| branchInfo | 列表层按 message 派生后传入 | row body 内调用 `viewModel.branchInfo` | body 期间读取可变全局状态 |
| 流式 trace | reducer 聚合后组件渲染 | 高频 partial 可能直接刷新 row | layout thrash |
| 会话列表刷新 | 与消息 row 渲染边界清楚 | `conversations` 与 row 共享同一 ViewModel 订阅源 | database_change 影响消息 cell |
| 列表更新 | React reconciliation | Diffable + UIHostingConfiguration | 更怕 view update 期间发布 |

## 5. iOS 落地方案

### 5.1 P0：消息 Row 去 ViewModel 订阅化

目标：

```text
DeepTutorMessageRowView 不再 @ObservedObject DeepTutorChatViewModel。
row 必须成为纯输入渲染组件，只接收 immutable row model 和 action closures。
```

建议新增行模型：

```swift
struct DeepTutorMessageRowModel: Equatable, Identifiable {
    let id: UUID
    let conversationID: UUID
    let message: DeepTutorMessage
    let branchInfo: DeepTutorMessageBranchInfo?
    let isStreamingTail: Bool
    let renderSignature: Int
}
```

目标结构：

```swift
struct DeepTutorMessageRowView: View {
    let model: DeepTutorMessageRowModel
    let actions: DeepTutorMessageRowActions

    var body: some View {
        HStack {
            if model.message.role == .user {
                DeepTutorUserBubble(
                    message: model.message,
                    branchInfo: model.branchInfo,
                    onCopy: { actions.copy(model.message.id) },
                    onEdit: { actions.edit(model.message.id, $0) },
                    onSelectPreviousBranch: { actions.selectBranch(model.message.id, -1) },
                    onSelectNextBranch: { actions.selectBranch(model.message.id, 1) }
                )
            } else {
                DeepTutorAssistantBubble(
                    message: model.message,
                    onCopy: { actions.copy(model.message.id) },
                    onRetry: { actions.retry(model.message.id) },
                    onSubmitAskUser: { toolCallID, answers in
                        actions.submitAskUser(model.message.id, toolCallID, answers)
                    }
                )
            }
        }
    }
}
```

实现要求：

```text
1. 删除 DeepTutorMessageRowView 内的 @ObservedObject viewModel。
2. 删除 row body 内所有 viewModel.branchInfo(for:) 读取。
3. 删除 row body 内所有 Task { await viewModel.xxx }。
4. 所有行为改为 action closure，由列表外层统一调度。
5. row body 必须只读 model，不读 ViewModel，不写 ViewModel。
```

### 5.2 P0：列表 payload 从 messages 扩展为 rowModels

当前：

```swift
DeepTutorListApplyPayload(
    messages: viewModel.state.messages,
    hasMoreMessages: viewModel.state.hasMoreMessages,
    ...
)
```

建议：

```swift
DeepTutorListApplyPayload(
    rowModels: viewModel.makeMessageRowModels(),
    hasMoreMessages: viewModel.state.hasMoreMessages,
    ...
)
```

`makeMessageRowModels()` 负责一次性计算：

```text
1. message 本体。
2. branchInfo。
3. 当前消息是否是流式尾消息。
4. trace/ask_user/markdown/附件变化签名。
5. reload/reconfigure 所需 renderSignature。
```

收益：

```text
UICollectionView cell 获取的是稳定的 value model。
cell 不再因为 conversations、phase、toast、selectedConversationID 变化而重绘。
只有 rowModels 中某条消息签名变化时才 reload/reconfigure 对应 cell。
```

### 5.3 P0：ViewModel 发布统一进入渲染调度器

新增一个消息列表渲染调度层，职责是把高频状态变化合并到安全时间点发布。

建议命名：

```text
DeepTutorRenderScheduler
DeepTutorMessageRenderCommitter
DeepTutorViewModelPublishGate
```

核心规则：

```text
1. ViewModel 不在 UIKit/SwiftUI view update 事务期间直接发布 @Published。
2. stream partial、database_change、scroll callback 产生的是 pending mutation。
3. pending mutation 统一在下一个 MainActor turn 或 display frame 提交。
4. 如果消息列表正在 apply snapshot，则延后到 apply completion 后提交。
5. 多个 reasoning-only delta 合并成一次 UI commit。
```

伪代码：

```swift
@MainActor
final class DeepTutorRenderScheduler {
    private var pending: DeepTutorRenderMutation?
    private var isMessageListApplying = false
    private var scheduled = false

    func enqueue(_ mutation: DeepTutorRenderMutation) {
        pending = pending?.merged(with: mutation) ?? mutation
        scheduleCommitIfNeeded()
    }

    func setMessageListApplying(_ applying: Bool) {
        isMessageListApplying = applying
        if applying == false {
            scheduleCommitIfNeeded()
        }
    }

    private func scheduleCommitIfNeeded() {
        guard scheduled == false else { return }
        scheduled = true
        Task { @MainActor in
            await Task.yield()
            scheduled = false
            guard isMessageListApplying == false else {
                scheduleCommitIfNeeded()
                return
            }
            commitPendingMutation()
        }
    }
}
```

注意：

```text
这里不是为了延迟用户可见响应，而是为了避开 SwiftUI view update transaction。
一次 Task.yield 或 RunLoop.main.async 往往就能把发布移到当前渲染事务之后。
对于流式 reasoning，还应叠加 100ms 到 150ms 的合帧节流。
```

### 5.4 P0：Diffable apply 生命周期反向通知 ViewModel/调度器

当前 `DeepTutorMessageListViewController` 内已有：

```swift
private var isApplyingSnapshot = false
private var pendingApply: ...
```

但这个状态只在 ViewController 内部使用，ViewModel 并不知道列表正在 apply/layout。

建议补充协议：

```swift
protocol DeepTutorMessageListRenderStateObserving: AnyObject {
    func messageListWillApplySnapshot(conversationID: UUID)
    func messageListDidApplySnapshot(conversationID: UUID, durationMs: Int)
}
```

在 `performApply`：

```swift
renderObserver?.messageListWillApplySnapshot(conversationID: conversationID)
dataSource.apply(snapshot, animatingDifferences: false) {
    ...
    renderObserver?.messageListDidApplySnapshot(conversationID: conversationID, durationMs: durationMs)
}
```

ViewModel 或 RenderScheduler 收到后：

```text
1. apply 期间不直接 commit pending state。
2. apply completion 后再提交合并后的最新 state。
3. 如果 completion 后仍有 pending snapshot，继续排队，但不允许 ViewModel 同步发布打断当前 cell layout。
```

### 5.5 P0：database_change 会话列表刷新与消息列表刷新隔离

当前日志说明 database_change 刷新会话列表时机危险：

```text
DeepTutor 仓储：loadConversations count=109
Publishing changes from within view updates is not allowed
DeepTutor 会话列表已刷新，count=109, source=database_change
```

优化要求：

```text
1. database_change 不应立即发布 conversations。
2. 对 affectsConversationList 的事件做 200ms 到 300ms debounce。
3. 如果当前正在消息列表 apply/layout，则延后到 apply completion 后。
4. 如果只是当前 active conversation 的 title/updatedAt 变化，优先更新会话列表缓存，不触发消息 row 订阅刷新。
5. conversations 最好拆到独立 `DeepTutorConversationListViewModel`，不要和消息 row 共用同一个 ObservableObject 发布源。
```

短期可接受方案：

```text
DeepTutorChatViewModel 仍保留 conversations，
但 row 去 ViewModel 订阅后，conversations 发布不会再让每个 cell row 失效。
```

长期推荐方案：

```text
拆分：
DeepTutorConversationListViewModel
DeepTutorChatSessionViewModel
DeepTutorMessageRenderStore

让会话列表、会话详情、消息 cell 渲染各自拥有最小观察范围。
```

### 5.6 P0：reasoning-only trace 更新合帧

当前日志中 answerLen 为 0，但 reasoningLen 连续变化：

```text
answerLen=0 reasoningLen=238 forceFlush=false
answerLen=0 reasoningLen=239 forceFlush=false
answerLen=0 reasoningLen=242 forceFlush=false
```

优化策略：

```text
1. `forceFlush=false` 的 reasoning-only delta 不应每次都触发 message list snapshot reload。
2. 正在展开 trace 时，reasoning 文案最多 100ms 到 150ms 刷新一次。
3. trace 已折叠时，只更新状态、耗时、调用数量等轻量字段，不刷新完整 reasoning text。
4. 正式 answerLen 从 0 变为 >0 时，自动折叠思考区，并强制提交一次最终 answer phase。
5. 工具调用状态变化、ask_user 卡片出现、final answer 出现属于高优先级 UI commit，可以立即或下一 runloop commit。
```

建议分级：

| 事件类型 | UI 刷新优先级 | 建议策略 |
| --- | --- | --- |
| final answer 首 token | P0 | 立即进入 answer phase，自动折叠 thinking |
| ask_user 卡片创建 | P0 | 下一 MainActor turn 提交，不等待节流窗口 |
| tool_call started/completed | P1 | 可 50ms 合并 |
| reasoning text delta | P2 | 100ms 到 150ms 合帧 |
| token/cost/duration | P3 | 250ms 到 500ms 合帧或完成时刷新 |

### 5.7 P1：UIHostingConfiguration 使用稳定身份和轻量内容

当前：

```swift
cell.contentConfiguration = UIHostingConfiguration { content }
```

其中 `content` 是 `AnyView(DeepTutorMessageRowView(viewModel: viewModel, ...))`。

优化要求：

```text
1. 避免 cell content 持有大 ObservableObject。
2. 避免不必要的 AnyView 包装导致 SwiftUI diff 信息丢失。
3. 使用稳定 row model 和 renderSignature。
4. 对内容变化优先使用 reconfigureItems，而不是大范围 reloadItems。
5. 如果 UIHostingConfiguration 在高频流式场景仍不稳定，评估自定义 UICollectionViewCell + UIHostingController 复用池。
```

可选方案：

```text
方案 A：继续使用 UIHostingConfiguration，但 row 是纯 value model。
方案 B：实现 DeepTutorHostingMessageCell，内部持有 UIHostingController，显式 prepareForReuse 和 setModel。
方案 C：关键高频区域如 trace/reasoning 改为 UIKit/TextKit 渲染，降低 SwiftUI layout graph 压力。
```

推荐先执行方案 A；只有崩溃仍存在时再升级到方案 B。

### 5.8 P1：禁止在 SwiftUI body / updateUIViewController 内触发业务写操作

需要审计：

```text
1. DeepTutorMessageRowView.body 内是否间接触发 ViewModel 写操作。
2. updateUIViewController 是否每次都 wire closures，导致回调身份变化和潜在副作用。
3. scrollViewWillBeginDragging 中 onUserInteraction 是否会立即发布 state。
4. UIRefreshControl 回调是否可能和 apply snapshot 同时触发 reload。
```

规则：

```text
1. SwiftUI body 只能读 value model，不发起 Task，不读写 ViewModel。
2. updateUIViewController 只能提交渲染 payload，不做业务 side effect。
3. UIKit delegate 回调产生的 mutation 进入 RenderScheduler，不直接写 @Published。
4. ViewModel 对外暴露 action 方法，但 action 内部也要通过发布门控提交 state。
```

## 6. 关键代码位置

### 6.1 崩溃入口

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorMessageListView.swift
```

重点位置：

```text
DeepTutorMessageListViewController.performApply
  line 130: dataSource.apply(snapshot, animatingDifferences: false)

DeepTutorMessageListRepresentable.updateUIViewController
  line 278: uiViewController.apply(conversationID: conversationID, payload: payload)

configureDataSource
  line 204: UIHostingConfiguration { content }

wire
  line 298: controller.rowBuilder = { message in ... }
```

### 6.2 行视图订阅点

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorMessageRowView.swift
```

重点位置：

```text
line 4:  @ObservedObject var viewModel: DeepTutorChatViewModel
line 20: branchInfo: viewModel.branchInfo(for: message.id)
line 23: Task { await viewModel.editUserMessage(...) }
line 49: guard let info = viewModel.branchInfo(for: message.id)
line 52: viewModel.selectBranch(...)
```

### 6.3 ViewModel 状态发布点

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorChatViewModel.swift
```

重点审计：

```text
1. reloadMessages
2. applyStreamingMessage
3. handleDatabaseChange
4. refreshConversations(source: "database_change")
5. releaseBottomLockAfterUserInteraction
6. rememberScrollAnchor
7. selectBranch
8. editUserMessage
9. submitAskUserAnswer / continueTurn
```

目标：

```text
这些方法可以改变业务状态，但不能在 SwiftUI view update / UICollectionView apply/layout 事务期间同步发布 @Published。
```

### 6.4 Trace / Thinking / AskUser 相关渲染

需要联动审计：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorAssistantBubble.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorTracePanelView.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorAskUserCardView.swift
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorMessageReducer.swift
```

关注点：

```text
1. reasoning-only delta 是否每次都改 message.blocks。
2. trace 折叠状态是否存储在全局 ViewModel，并导致全列表刷新。
3. ask_user block 出现时是否稳定保留 toolCallID。
4. final answer phase 出现时是否自动折叠 thinking。
```

## 7. 日志补充方案

### 7.1 渲染事务日志

新增：

```text
deeptutor.render.transaction.begin conversation={id} source={swiftui_update|diffable_apply|hosting_cell}
deeptutor.render.transaction.end conversation={id} durationMs={ms}
deeptutor.render.publish_deferred conversation={id} reason={view_update|snapshot_applying|reasoning_coalesce}
deeptutor.render.publish_commit conversation={id} mutations={messages|conversation|conversations|phase} durationMs={ms}
```

用途：

```text
判断 @Published 是否在 view update / snapshot apply 期间发生。
```

### 7.2 Row 渲染日志

新增：

```text
deeptutor.message_row.model_built conversation={id} message={id} role={user|assistant} signature={hash} branch={index/count}
deeptutor.message_row.configure_cell conversation={id} message={id} signature={hash}
deeptutor.message_row.render_isolated message={id} observedViewModel=false
```

验收要求：

```text
observedViewModel 必须为 false。
如果仍为 true，说明 row 还没有完成去 ViewModel 订阅化。
```

### 7.3 状态发布防线日志

新增：

```text
deeptutor.publish.guard.blocked mutation={state|conversation|conversations} reason=view_update
deeptutor.publish.guard.blocked mutation={state|conversation|conversations} reason=snapshot_applying
deeptutor.publish.guard.allowed mutation={state|conversation|conversations} source={stream|database_change|user_action}
```

### 7.4 Stream 合帧日志

新增：

```text
deeptutor.stream.reasoning.coalesced conversation={id} assistant={id} pendingChars={n} intervalMs={ms}
deeptutor.stream.reasoning.commit conversation={id} assistant={id} reasoningLen={n} answerLen={n} collapsed={true|false}
deeptutor.stream.answer.phase_enter conversation={id} assistant={id} answerLen={n} thinkingAutoCollapsed=true
```

### 7.5 database_change 延迟日志

新增：

```text
deeptutor.database_change.received conversation={id} affectsList={true|false} affectsMessages={true|false}
deeptutor.database_change.deferred conversation={id} reason={snapshot_applying|view_update|debounce}
deeptutor.database_change.commit conversation={id} source=database_change delayMs={ms}
```

## 8. 分阶段实施计划

### 8.1 阶段一：止血

目标：

```text
消除消息 row 对整个 DeepTutorChatViewModel 的订阅。
```

任务：

```text
1. 新增 DeepTutorMessageRowModel。
2. DeepTutorListApplyPayload 改为承载 rowModels。
3. DeepTutorMessageRowView 删除 @ObservedObject viewModel。
4. branchInfo 在 ViewModel 构建 rowModels 时预计算。
5. row 操作全部改为 action closure。
6. row body 内禁止 Task 和 ViewModel 调用。
```

预期效果：

```text
conversations、phase、selectedConversationID 等非当前 row 数据变化，不再触发所有 visible cell 重绘。
```

### 8.2 阶段二：发布调度

目标：

```text
消除 Publishing changes from within view updates warning。
```

任务：

```text
1. 新增 RenderScheduler / PublishGate。
2. DeepTutorMessageListViewController 在 apply 前后通知 scheduler。
3. database_change 刷新进入 debounce + scheduler。
4. scroll callback 状态修改进入 scheduler。
5. stream partial 状态修改进入 scheduler。
```

预期效果：

```text
SwiftUI view update / UICollectionView apply/layout 期间不再直接发布 @Published。
```

### 8.3 阶段三：流式 trace 合帧

目标：

```text
降低 reasoning-only 更新对列表布局的压力，并对齐 DeepTutor-main 的思考/工具/正式回答展示体验。
```

任务：

```text
1. reasoning-only delta 100ms 到 150ms 合帧。
2. final answer 首 token 出现时自动折叠 thinking。
3. ask_user block 创建提升为高优先级 commit。
4. trace 折叠状态从全局 ViewModel 中拆出或局部化。
5. 对 collapsed trace 只刷新 summary，不刷新完整 reasoning text。
```

### 8.4 阶段四：Hosting cell 稳定性

目标：

```text
确保 UIHostingConfiguration 在长会话、高频流式、快速切换场景下稳定。
```

任务：

```text
1. 用 rowModel.renderSignature 控制 reload/reconfigure。
2. 避免 AnyView 过度擦除。
3. 如果仍存在 AttributeGraph cycle，切换到自定义 DeepTutorHostingMessageCell。
4. 对超长 Markdown / trace 文本评估局部 UIKit/TextKit 渲染。
```

## 9. 验收标准

### 9.1 打开历史会话不崩溃

```text
Given 本地数据库存在 100+ DeepTutor 会话
And 当前会话包含 trace、ask_user、tool_call、reasoning、final answer 等 blocks
When 连续打开 20 个不同会话
Then App 不崩溃
And 日志不出现 Diffable reentrant assertion
And 日志不出现 AttributeGraph cycle detected
And 日志不出现 Publishing changes from within view updates
```

### 9.2 流式 reasoning 不触发布局风暴

```text
Given AI 正在输出大量 reasoning-only delta
When answerLen=0 且 reasoningLen 高频增长
Then iOS 每 100ms 到 150ms 最多提交一次 trace 文案 UI 更新
And forceFlush=false 的 partial 不应每次触发 snapshot reload
And 滚动、点击、下拉时不崩溃
```

### 9.3 正式回答出现后自动折叠思考

```text
Given assistant 消息正在展示 thinking/trace
When final answer 首 token 出现
Then thinking/trace 自动折叠
And 正文进入正式回答区域
And 消息卡片视觉效果对齐 DeepTutor-main
```

### 9.4 database_change 不干扰消息 cell 渲染

```text
Given 当前消息列表正在 apply snapshot 或创建 hosting cell
When 本地数据库触发 affectsConversationList 的变更
Then 会话列表刷新被延后或合并
And 不在 view update 事务内发布 conversations
And 当前消息 row 不因 conversations 变化而重绘
```

### 9.5 Row 组件完成渲染隔离

```text
Given 任意 DeepTutorMessageRowView
When 检查代码
Then Row 内不存在 @ObservedObject DeepTutorChatViewModel
And Row body 内不调用 viewModel.branchInfo
And Row body 内不创建 Task 写 ViewModel
And Row 只依赖 DeepTutorMessageRowModel 和 actions
```

### 9.6 崩溃堆栈不再复现

```text
Given 使用同一条崩溃复现路径
When 打开会话 C22B6A2A 并触发 reasoning stream
Then 不再崩溃于：
DeepTutorMessageListViewController.performApply line 130
And 不再出现：
SwiftUI.HVStack.updateCache
Swift._ArrayBufferProtocol.replaceSubrange
swift_arrayDestroy
swift_release
```

## 10. 风险与注意事项

### 10.1 不要只继续加强 Diffable apply guard

原因：

```text
本次日志已显示 apply_done pending=false。
如果只继续在 dataSource.apply 外面加锁，无法解决 SwiftUI row 订阅 ViewModel 和渲染期间发布状态的问题。
```

### 10.2 不要把所有状态拆分都压到一个巨大 ObservableObject

原因：

```text
即使 state.messages 被优化，只要 cell row 仍 @ObservedObject 整个 ViewModel，
conversation list、toast、phase、selectedConversationID 等变化仍可能使 cell 失效。
```

### 10.3 不要在 body 中计算依赖全局可变状态的复杂派生数据

原因：

```text
SwiftUI body 可能在布局、测量、cell prepare、diffable update 中被多次调用。
body 内访问全局可变状态越多，越容易产生 AttributeGraph 依赖环。
```

### 10.4 trace 合帧不能影响 ask_user 卡片出现

要求：

```text
reasoning-only 可以节流。
ask_user、tool_call 状态切换、final answer 首 token 不能被长时间节流。
否则会再次出现用户提问卡片不展示、工具卡片延迟、正式回答阶段识别不及时的问题。
```

## 11. 推荐优先级

| 优先级 | 任务 | 必须先做原因 |
| --- | --- | --- |
| P0 | Row 去 ViewModel 订阅化 | 这是 AttributeGraph 循环的最大放大器 |
| P0 | 发布调度器 / PublishGate | 直接解决 view update 期间发布 |
| P0 | database_change debounce | 日志已证明会话列表刷新触发 warning |
| P0 | reasoning-only 合帧 | 降低流式 trace 对布局压力 |
| P1 | Hosting cell 稳定化 | 在 Row 隔离后进一步降低 SwiftUI/UICollectionView 混用风险 |
| P1 | ViewModel 拆分 | 长期架构治理，降低未来功能互相牵连 |

## 12. 最小修复闭环

本工单的最小闭环不是“让这一次不崩”，而是达到：

```text
1. Message row 是纯 value model 渲染。
2. ViewModel 发布不会发生在 SwiftUI view update / Diffable apply / cell layout 事务内。
3. reasoning-only 流式更新被合帧。
4. database_change 会话列表刷新不再牵连消息 cell。
5. 日志能明确证明每次 publish 是 allowed 还是 deferred。
```

达到以上 5 点后，DeepTutorChat 的 iOS 消息列表刷新方式才算真正接近 `DeepTutor-main` 的稳定渲染链路。
