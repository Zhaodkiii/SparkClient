# CHAT-000030 对话详情页右上角新建对话按钮与内部 Thread 切换工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | CHAT-000030 |
| 工单类型 | P1 Chat / 对话详情页 / 新建对话 / Thread 切换 / 消息缓存切换 |
| 当前范围 | 创建需求与技术方案工单；本工单不直接修改现有 Swift 代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 关联工单 | `CHAT-000028`、`CHAT-000029` |
| 目标模块 | `SparkClient/Projects/Features/Chat/Presentation` |
| 重点文件 | `ChatView.swift`、`ChatListViewModel.swift`、`ChatDetailViewModel.swift`、`ChatStateStore.swift`、`ChatConversationListPage.swift` |
| 创建日期 | 2026-08-22 |
| 明确非目标 | 不改消息卡片样式；不改变输入框发送逻辑；不新增服务端接口；不通过 Navigation push 跳到新页面 |

## 1. 模块目标

在对话详情页右上角增加“新建对话”按钮，位置参考用户截图中的右上角入口，对应 `ChatView.swift` 当前预留位置：

```swift
.toolbar {
    ToolbarItem(placement: .topBarTrailing) {
        // 增加 新建对话按钮
    }
    ToolbarItem(placement: .navigationBarTrailing) {
        Menu { ... }
    }
}
```

点击后要求：

1. 不发生任何页面跳转。
2. 不 push 新的 `ChatView`。
3. 不 pop 回会话列表。
4. 直接在当前对话详情容器内部创建新 thread。
5. 完成当前 `threadID` 切换。
6. 完成对话消息缓存切换。
7. 按 `CHAT-000029` 新建对话流程插入首条 system guide card，并后台生成科普问题。

目标交互：

```text
用户在 ChatView 右上角点击新建对话
  ↓
按钮进入 loading/disabled
  ↓
本地创建新 thread
  ↓
stateStore.selectedThreadID 切换为新 threadID
  ↓
当前详情页消息区切到新 thread 的消息缓存
  ↓
不做 Navigation push/pop
  ↓
新 thread 首条 guide card 展示
  ↓
后台科普问题生成
```

## 2. 当前实现事实

### 2.1 ChatView 当前右上角位置

文件：`SparkClient/Projects/Features/Chat/Presentation/ChatView.swift`

当前 toolbar 已有预留：

```swift
.toolbar {
    ToolbarItem(placement: .topBarTrailing) {
        // 增加 新建对话按钮
    }
    ToolbarItem(placement: .navigationBarTrailing) {
        Menu {
            ...
        }
    }
}
```

当前右侧另有设置菜单。新增按钮需要与设置菜单共存，避免两个 trailing item 排列混乱。

### 2.2 当前新建对话能力

文件：`SparkClient/Projects/Features/Chat/Presentation/ChatListViewModel.swift`

当前已有普通新建：

```swift
func createThread() async {
    let title = L10n.text("chat.default_thread_title")
    let thread = await createThreadUseCase.execute(
        memberID: memberContextStore.context.selectedMemberID,
        title: title
    )
    await reloadThreads(selectFirstIfNeeded: false)
    stateStore.markThreadAsNewlyCreated(thread.id)
    stateStore.setSelectedThreadID(thread.id)
}
```

当前列表页新建后会设置 `selectedThreadID`。但列表页入口通常再通过导航进入 `ChatView`，与本工单“不跳转、当前详情内部切换”不同。

### 2.3 当前 ChatView 的 threadID 输入风险

文件：`SparkClient/Projects/Features/Chat/Presentation/ChatView.swift`

当前 `ChatView` 初始化参数里有固定：

```swift
let threadID: UUID
```

并且多个派生状态依赖该 `threadID`：

```swift
private var hasMoreMessages: Bool {
    stateStore.hasMoreMessages(for: threadID)
}

private var isLoadingMoreMessages: Bool {
    stateStore.isLoadingMoreMessages(for: threadID)
}
```

生命周期任务也绑定：

```swift
.task(id: threadID) {
    ...
}
```

因此，如果只在按钮点击后调用：

```swift
stateStore.setSelectedThreadID(newThreadID)
```

但当前 `ChatView.threadID` 仍是旧值，则当前详情页内部可能继续读取旧 thread 的消息缓存、分页状态、草稿和生命周期任务。

本工单需要明确解决“详情页内部 threadID 状态源”问题。

### 2.4 当前消息缓存能力

文件：`SparkClient/Projects/Features/Chat/Presentation/ChatStateStore.swift`

当前已有：

```swift
func setSelectedThreadID(_ threadID: UUID?)
func setMessages(_ messages: [ChatMessage], for threadID: UUID, hasMore: Bool?)
```

说明 stateStore 已支持按 threadID 维护消息缓存，但 `ChatView` 是否切换读取新缓存，取决于当前 View 使用的是固定初始化 `threadID`，还是跟随 `stateStore.selectedThreadID`。

### 2.5 当前列表页导航事实

文件：`SparkClient/Projects/Features/Chat/Presentation/ChatConversationListPage.swift`

当前列表页存在 `navigationDestination` 和 `MainNavigationLink` 创建新的 `ChatView(threadID:)`。本工单要求详情页按钮不使用该导航路径。

## 3. 需求范围

### 3.1 右上角新建对话按钮

#### 需求说明

在 `ChatView` 右上角增加新建对话按钮，点击后创建新会话并在当前详情页切换。

#### 基础要求与业务规则

1. 按钮位置在右上角 toolbar。
2. 图标建议使用 `plus.bubble` 或 `square.and.pencil`，与列表页新建入口语义一致。
3. 需要 accessibility label：`新建对话`。
4. 点击期间按钮置灰，防止重复点击创建多个 thread。
5. 创建失败时轻量提示，不切换当前会话。
6. 创建成功后不跳转，只更新当前详情页状态。

#### 主流程

```text
用户点击右上角新建对话
  ↓
isCreatingThreadInDetail = true
  ↓
调用详情页内部新建对话用例
  ↓
创建成功返回 newThreadID
  ↓
切换当前详情 threadID
  ↓
加载/展示新 thread 消息缓存
  ↓
isCreatingThreadInDetail = false
```

#### 技术细节与设计代码位置

建议在 `ChatView.swift` 的预留 `ToolbarItem(placement: .topBarTrailing)` 中实现：

```swift
Button {
    Task {
        await createThreadInsideCurrentChat()
    }
} label: {
    Image(systemName: "plus.bubble")
}
.disabled(isCreatingThreadInDetail)
.accessibilityLabel(L10n.text("chat.thread.new", fallback: "新建对话"))
```

如果右上角已有设置菜单，建议使用 `ToolbarItemGroup(placement: .topBarTrailing)` 合并按钮与菜单，避免 `.topBarTrailing` 和 `.navigationBarTrailing` 在不同 iOS 版本排列不稳定。

#### 验收标准

1. 对话详情页右上角可见新建对话按钮。
2. 点击按钮不会 push 新页面。
3. 点击按钮不会返回会话列表。
4. 连续快速点击不会创建多个 thread。
5. VoiceOver 能读出“新建对话”。

### 3.2 当前详情内部创建 thread

#### 需求说明

详情页按钮复用现有新建对话能力，但返回新 threadID 给当前详情容器，而不是触发导航。

#### 基础要求与业务规则

1. 普通新建默认标题仍使用 `chat.default_thread_title`。
2. 默认绑定成员规则沿用 `CHAT-000029`：创建 thread 本地完成时写入初始 memberID。
3. 创建后标记 `stateStore.markThreadAsNewlyCreated(newThreadID)`。
4. 创建后刷新 thread 列表缓存。
5. 创建失败时保留旧 thread。

#### 推荐接口

当前 `ChatListViewModel.createThread()` 没有返回值。建议新增一个可复用方法：

```swift
@discardableResult
func createThreadAndSelect() async -> UUID?
```

或调整现有方法返回：

```swift
@discardableResult
func createThread() async -> UUID?
```

该方法内部仍做：

```text
createThreadUseCase.execute
reloadThreads
markThreadAsNewlyCreated
setSelectedThreadID
return thread.id
```

#### 技术细节与设计代码位置

涉及：

```text
SparkClient/Projects/Features/Chat/Presentation/ChatListViewModel.swift
SparkClient/Projects/Features/Chat/Presentation/ChatView.swift
SparkClient/Projects/Features/Chat/Presentation/ChatStateStore.swift
```

如果不希望 `ChatView` 直接依赖列表 ViewModel 的创建方法，也可新增 `ChatThreadCreationCoordinator`，但本期建议优先复用 `ChatListViewModel`，减少范围。

#### 验收标准

1. 详情页点击新建后，仓储中新增 thread。
2. thread 列表缓存包含新 thread。
3. `stateStore.selectedThreadID == newThreadID`。
4. 新 thread 带有 newlyCreated marker。

### 3.3 当前详情内部切换 threadID

#### 需求说明

点击新建后，当前详情页必须从旧 thread 切换到新 thread，不依赖导航栈重新创建 `ChatView`。

#### 核心问题

当前 `ChatView` 使用 `let threadID: UUID` 固定参数。若不改造，按钮内部只改 `stateStore.selectedThreadID`，当前 View 很可能仍用旧 `threadID`。

#### 推荐方案 A：ChatView 使用动态 effectiveThreadID

在 `ChatView` 内部增加：

```swift
private var effectiveThreadID: UUID {
    stateStore.selectedThreadID ?? threadID
}
```

然后将以下读取从 `threadID` 改为 `effectiveThreadID`：

1. `reasoningRefreshId`
2. `visibleMessages` 对应的 selectedMessages 来源。
3. `hasMoreMessages`
4. `isLoadingMoreMessages`
5. `.task(id:)`
6. `composerDraft(for:)`
7. `messageList` 传参。
8. `trySendAutoSmallTaskIfReady` 相关 thread。
9. guide card 生成/修复入口。

风险：

1. 改动面较大，需要逐一检查 `threadID` 的语义。
2. 如果多个 ChatView 在导航栈中同时存在，共享 `selectedThreadID` 可能影响旧页面。

#### 推荐方案 B：引入详情页局部 activeThreadID

在 `ChatView` 内部维护：

```swift
@State private var activeThreadID: UUID
```

初始化为传入 `threadID`。点击右上角新建成功后：

```swift
activeThreadID = newThreadID
stateStore.setSelectedThreadID(newThreadID)
```

然后当前详情页所有业务使用 `activeThreadID`。

优点：

1. 只影响当前 ChatView 实例。
2. 不会让导航栈里其他 ChatView 被全局 selectedThreadID 意外带动。
3. 更符合“不跳转，只在当前详情内部切换”的需求。

本工单推荐方案 B。

#### 主流程

```text
ChatView 初始化
  ↓
activeThreadID = threadID
  ↓
点击新建对话
  ↓
newThreadID = await listViewModel.createThreadAndSelect()
  ↓
activeThreadID = newThreadID
  ↓
.task(id: activeThreadID) 重新执行
  ↓
加载新 thread 消息缓存
  ↓
新建 guide card / 科普问题链路启动
```

#### 验收标准

1. 点击新建后当前页面标题变为新 thread 标题。
2. 当前消息列表切换为新 thread 消息。
3. 输入框草稿切换为新 thread 草稿。
4. 旧 thread 消息缓存不丢失。
5. 返回列表后选中项为新 thread。

### 3.4 对话消息缓存切换

#### 需求说明

切换 threadID 后，当前详情页必须展示新 thread 的消息缓存，不能继续显示旧消息。

#### 基础要求与业务规则

1. 新建成功后，应立即把当前 visible messages 切换到新 thread。
2. 如果新 thread 尚无消息，先展示空态或 guide card loading。
3. 插入首条 guide card 后，消息列表展示该 system message。
4. 旧 thread 的 messages、hasMore、loadingMore 状态保留在 stateStore 中。
5. 新 thread 的 composer draft 与旧 thread 隔离。

#### 技术细节与设计代码位置

需要检查并改造这些依赖固定 `threadID` 的位置：

```text
SparkClient/Projects/Features/Chat/Presentation/ChatView.swift
SparkClient/Projects/Features/Chat/Presentation/ChatDetailViewModel.swift
SparkClient/Projects/Features/Chat/Presentation/ChatStateStore.swift
```

建议新增日志：

```text
chat.detail.new_thread_button.tap current=<old>
chat.detail.new_thread_button.created old=<old> new=<new>
chat.detail.thread_switch.begin old=<old> new=<new>
chat.detail.thread_switch.messages_loaded new=<new> count=<n>
```

#### 验收标准

1. 点击新建后旧消息不再显示。
2. 新 thread guide card 或空态立即显示。
3. 再切回旧 thread 时旧消息仍存在。
4. 新旧 thread 草稿互不覆盖。

### 3.5 与引导卡片新建链路衔接

#### 需求说明

详情页内部新建对话后，仍必须遵循 `CHAT-000029` 新建对话流程。

#### 基础要求与业务规则

1. 新 thread 创建时完成默认绑定。
2. 进入当前详情内部新 thread 后插入首条 system guide card。
3. guide card 插入后后台启动科普问题生成。
4. AI 成功/失败后本地回写 guide block 并刷新 UI。
5. block_updates 后台同步服务端。

#### 主流程

```text
详情页右上角新建
  ↓
createThreadAndSelect
  ↓
activeThreadID = newThreadID
  ↓
ChatView .task(id: activeThreadID)
  ↓
ensure guide card inserted
  ↓
startGuideQuestionGenerationForNewlyCreatedThread
  ↓
generated/fallback
```

#### 验收标准

1. 右上角新建的新 thread 也会出现首条 guide card。
2. 有绑定成员时也会后台生成科普问题。
3. 重新进入该 thread 不重复生成。

### 3.6 详细落地拆分

#### 需求说明

本节把右上角新建对话拆成可执行开发步骤，避免只新增按钮但没有真正完成“当前详情内部 thread 切换”。

推荐拆分顺序：

| 步骤 | 目标 | 主要文件 |
| --- | --- | --- |
| 1 | 让 `ChatListViewModel` 新建方法返回 `UUID?` | `ChatListViewModel.swift` |
| 2 | 在 `ChatView` 引入局部 `activeThreadID` | `ChatView.swift` |
| 3 | 将当前详情页业务读取从固定 `threadID` 切到 `activeThreadID` | `ChatView.swift` |
| 4 | 新增右上角按钮和防重入状态 | `ChatView.swift` |
| 5 | 新建成功后切换 selectedThreadID + activeThreadID | `ChatView.swift`、`ChatStateStore.swift` |
| 6 | 确保新 thread 消息缓存加载、guide card 插入和科普问题生成 | `ChatDetailViewModel.swift` |
| 7 | 补日志和测试 | Tests |

#### 第 1 步：ChatListViewModel 返回新 threadID

当前 `createThread()` 返回 `Void`。详情页内部切换需要拿到新 `threadID`，建议改为：

```swift
@discardableResult
func createThread() async -> UUID? {
    let title = L10n.text("chat.default_thread_title")
    let thread = await createThreadUseCase.execute(
        memberID: memberContextStore.context.selectedMemberID,
        title: title
    )
    await reloadThreads(selectFirstIfNeeded: false)
    stateStore.markThreadAsNewlyCreated(thread.id)
    stateStore.setSelectedThreadID(thread.id)
    return thread.id
}
```

如果担心影响现有调用方，也可以新增：

```swift
@discardableResult
func createThreadAndSelect() async -> UUID?
```

现有列表页按钮可继续：

```swift
await listViewModel.createThread()
```

忽略返回值即可。

快捷入口 `createQuickStartThread(mode:source:)` 当前已经返回 `UUID?`，该模式可作为普通新建返回值的参考。

#### 第 2 步：ChatView 引入 activeThreadID

由于 `@State` 需要初始化，建议在 `ChatView` 增加：

```swift
@State private var activeThreadID: UUID
@State private var isCreatingThreadInDetail = false
@State private var detailThreadCreationError: String?
```

在 init 内初始化：

```swift
_activeThreadID = State(initialValue: threadID)
```

保留原始 `let threadID: UUID` 的用途：

1. 仅作为 ChatView 初始 thread。
2. 仅用于 `activeThreadID` 初始值。
3. 不再作为当前详情页运行时业务 thread。

建议新增辅助属性：

```swift
private var currentThreadID: UUID {
    activeThreadID
}
```

开发时统一搜索 `threadID`，逐个判断是否应替换为 `currentThreadID`。

#### 第 3 步：ChatView 中必须替换为 currentThreadID 的位置

根据当前代码搜索，以下位置属于“当前详情运行时 thread”，应改为 `currentThreadID`：

| 当前位置/能力 | 当前代码特征 | 改造要求 |
| --- | --- | --- |
| 模型刷新 key | `reasoningRefreshId` 使用 `threadID` | 改用 `currentThreadID` |
| composer draft | `stateStore.composerDraft(for: threadID)` | 改用 `currentThreadID` |
| 消息分页 | `hasMoreMessages(for: threadID)` | 改用 `currentThreadID` |
| loadingMore | `isLoadingMoreMessages(for: threadID)` | 改用 `currentThreadID` |
| Signal/Hanlin composer | `threadID: threadID` | 改用 `currentThreadID` |
| 附件加入/删除 | `enqueueComposerAttachments(... for: threadID)` | 改用 `currentThreadID` |
| 成员绑定 | `updateThreadMemberBinding(... for: threadID)` | 改用 `currentThreadID` |
| Ask report picker | `presentAskReportPicker(for: threadID, ...)` | 改用 `currentThreadID` |
| 模型切换 | `updateThreadModel(... for: threadID)` | 改用 `currentThreadID` |
| 生命周期 task | `.task(id: threadID)` | 改用 `.task(id: currentThreadID)` |
| 列表选中 | `listViewModel.selectThread(threadID)` | 改用 `currentThreadID` |
| 消息加载 | `loadMessagesIfNeeded(for: threadID)` | 改用 `currentThreadID` |
| 自动小任务 | `trySendAutoSmallTaskIfReady` 内部 thread | 改用 `currentThreadID` |
| UIKit 消息列表容器 | `threadID: threadID` | 改用 `currentThreadID` |
| SwiftUI 消息列表容器 | `threadID: threadID` | 改用 `currentThreadID` |
| 视口锁定 | `isBottomViewportLocked(for: threadID)` | 改用 `currentThreadID` |
| 滚动请求 | `scrollToBottomRequestGeneration(for: threadID)` | 改用 `currentThreadID` |
| 卡片 action snapshot key | `threadID.uuidString` | 改用 `currentThreadID.uuidString` |
| 参数设置保存 | `updateThreadGenerationSettings(... for: threadID)` | 改用 `currentThreadID` |
| 清空消息 | `clearMessages(for: threadID)` | 改用 `currentThreadID` |
| 诊断导出 | `"thread_id": threadID.uuidString` | 改用 `currentThreadID` |

这些位置如果漏改，会出现典型问题：

```text
标题切到新会话，但消息列表还是旧会话
输入框草稿写到旧会话
模型选择更新到旧会话
成员绑定更新到旧会话
guide card 生成写到旧会话
自动小任务发到旧会话
```

#### 第 4 步：哪些 threadID 不应替换

以下用途可以保留原始 `threadID` 或需要单独判断：

1. `init(threadID:)` 参数本身。
2. `_activeThreadID = State(initialValue: threadID)`。
3. 与历史导航来源相关的只读调试日志，可以保留但建议标明 `initialThreadID`。
4. 子视图结构体的入参名可以仍叫 `threadID`，但传入值应是 `currentThreadID`。

建议重命名原始字段，降低误用：

```swift
let initialThreadID: UUID
```

如果改名影响较大，也至少在注释中标明：

```swift
/// 初始进入该 ChatView 时的 threadID；运行时当前会话请使用 currentThreadID。
let threadID: UUID
```

#### 第 5 步：右上角按钮实现细节

建议新增私有方法：

```swift
@MainActor
private func createThreadInsideCurrentChat() async {
    guard isCreatingThreadInDetail == false else { return }
    let oldThreadID = currentThreadID
    isCreatingThreadInDetail = true
    detailThreadCreationError = nil
    defer { isCreatingThreadInDetail = false }

    logger.info(
        "chat.detail.new_thread_button.tap current=\(shortID(oldThreadID))",
        module: .general
    )

    guard let newThreadID = await listViewModel.createThreadAndSelect() else {
        detailThreadCreationError = L10n.text(
            "chat.thread.create_failed",
            fallback: "新建对话失败"
        )
        logger.warning(
            "chat.detail.new_thread_button.failed current=\(shortID(oldThreadID))",
            module: .general
        )
        return
    }

    switchDetailThread(from: oldThreadID, to: newThreadID)
}
```

切换方法：

```swift
@MainActor
private func switchDetailThread(from oldThreadID: UUID, to newThreadID: UUID) {
    guard oldThreadID != newThreadID else { return }
    logger.info(
        "chat.detail.thread_switch.begin old=\(shortID(oldThreadID)) new=\(shortID(newThreadID))",
        module: .general
    )
    activeThreadID = newThreadID
    stateStore.setSelectedThreadID(newThreadID)
    persistCardActionSnapshot()
    restoreCardActionSnapshot(for: newThreadID)
}
```

如果 `persistCardActionSnapshot()` 当前内部直接使用 `threadID`，需要先改为使用 `currentThreadID`，否则切换前后会把旧会话卡片动作状态写错 key。

Toolbar 建议：

```swift
ToolbarItemGroup(placement: .topBarTrailing) {
    Button {
        Task { await createThreadInsideCurrentChat() }
    } label: {
        if isCreatingThreadInDetail {
            ProgressView()
        } else {
            Image(systemName: "plus.bubble")
        }
    }
    .disabled(isCreatingThreadInDetail)
    .accessibilityLabel(L10n.text("chat.thread.new", fallback: "新建对话"))

    settingsMenu
}
```

如果 `ProgressView` 在 toolbar 内尺寸不稳定，可保持图标不变，只 disabled，并在按钮上加轻量 opacity。

#### 第 6 步：生命周期 task 改造

当前 `.task(id: threadID)` 是详情页切换的核心触发器。改为：

```swift
.task(id: currentThreadID) {
    let id = currentThreadID
    if let initialModel = await detailViewModel.refreshChatModelPicker(for: id) {
        if stateStore.composerDraft(for: id).runtimeFlags.selectedChatModelName == nil {
            stateStore.setSelectedChatModelName(initialModel, for: id)
        }
    }
    await detailViewModel.refreshThreadImageDeliveryMode(for: id)
    await detailViewModel.loadMessagesIfNeeded(for: id, lockBottomViewport: true)

    if stateStore.isThreadMarkedAsNewlyCreated(id) {
        await detailViewModel.ensureGuideMessageForNewlyCreatedThread()
        await detailViewModel.startGuideQuestionGenerationForNewlyCreatedThread()
        stateStore.clearThreadWasJustCreatedMarker(id)
    } else {
        await detailViewModel.repairGuideQuestionsForReenteredThreadIfNeeded()
    }

    await trySendAutoSmallTaskIfReady(for: id)
}
```

注意事项：

1. task 内第一行用 `let id = currentThreadID` 固定本轮 ID，避免 await 期间用户又点新建导致后续步骤串到新 thread。
2. `trySendAutoSmallTaskIfReady` 建议改为显式传入 threadID。
3. `repairGuideQuestionsForReenteredThreadIfNeeded` 如果内部读取 `stateStore.selectedThreadID`，应改为接收 threadID 参数，避免局部 `activeThreadID` 与全局 selectedThreadID 不一致时误修复。

推荐改造 ViewModel 方法：

```swift
func startGuideQuestionGenerationForNewlyCreatedThread(threadID: UUID) async
func repairGuideQuestionsForReenteredThreadIfNeeded(threadID: UUID) async
func ensureGuideMessageForNewlyCreatedThread(threadID: UUID) async
```

不要让这些方法只读 `stateStore.selectedThreadID`。

#### 第 7 步：消息缓存切换与首屏空态

点击按钮后，新 thread 可能有三个阶段：

```text
activeThreadID 已切换
  ↓
messagesByThread[newThreadID] 还为空
  ↓
loadMessagesIfNeeded 读取本地
  ↓
ensure guide card inserted 后 updateMessages/setMessages
```

UI 策略：

1. 切换后立即不再展示旧 thread 消息。
2. `visibleMessages` 必须来自 `stateStore.conversationListItems(for: currentThreadID)`，不能来自 `stateStore.selectedMessages`，因为 selectedMessages 依赖全局 selectedThreadID。
3. 如果新 thread 暂无消息，显示空消息列表或轻量 loading。
4. guide card 插入后再展示首条 system message。

建议改：

```swift
private var visibleMessages: [ChatMessage] {
    stateStore
        .conversationListItems(for: currentThreadID)
        .filter { uiStateStore.isDeleted($0.id) == false }
}
```

不要继续用：

```swift
stateStore.selectedMessages
```

否则一旦全局 selectedThreadID 与局部 activeThreadID 短暂不同步，消息列表会错。

#### 第 8 步：composer 与附件隔离

所有 composer 操作必须使用 `currentThreadID`：

```text
composerDraft(for:)
setDraft
setSelectedChatModelName
enqueueComposerAttachments
removeComposerAttachment
appendAskReportRefs
startSendingCurrentDraft / sendCurrentDraft
```

特别注意：

1. 用户在旧 thread 输入了未发送草稿，点击新建后不应带到新 thread。
2. 新 thread 输入内容后，再回旧 thread，旧草稿应还在。
3. 附件准备状态如果是全局按附件 ID 管理，要确认 composer draft 中附件归属按 thread 隔离。
4. 如果点击新建时旧 thread 正在发送，应禁止新建或允许切换但旧发送继续归旧 thread。推荐本期先禁止：

```text
stateStore.isSending == true -> 禁用新建按钮
```

#### 第 9 步：成员绑定与模型设置隔离

右上角新建后，以下操作必须作用于新 thread：

1. 成员选择/切换。
2. 当前模型选择。
3. temperature / topP / maxTokens / maxMessages。
4. imageDeliveryMode。
5. rolePrompt / system prompt。

建议 `ChatView` 所有设置面板打开时读取 `currentThreadID` 的最新 thread，而不是打开前缓存旧 thread。

如果设置菜单在旧 thread 打开期间用户又点击新建，应关闭设置弹层：

```swift
activeParameterCard = nil
```

避免弹层保存到旧 thread 或新 thread 混乱。

#### 第 10 步：导航栈与返回行为

本工单“不跳转”的含义：

1. 不设置 `pendingThreadNavigation`。
2. 不触发 `NavigationLink`。
3. 不创建新的 `ChatView` 实例。
4. 不 pop 当前详情。

返回按钮行为：

1. 如果当前 ChatView 是从列表 push 进来的，点击右上角新建后仍处于同一个 pushed 页面。
2. 用户点系统返回，回到会话列表。
3. 会话列表当前选中项应是新 thread。
4. 旧 thread 仍在列表中，用户可重新进入。

注意：如果当前路由栈路径里记录的是旧 threadID，这不应影响当前页面内部显示；但返回再点旧路由时仍应按列表项进入对应 thread。

#### 第 11 步：与 CHAT-000029 的关系

右上角新建按钮必须复用 `CHAT-000029` 的新建流程口径：

```text
本地 thread 创建时确定默认绑定 memberID
  ↓
thread-push 后台同步
  ↓
当前详情内部切到新 thread
  ↓
进入/切换后确保 guide card 本地插入
  ↓
后台生成科普问题
  ↓
本地回写，UI 立即刷新
  ↓
block_updates 后台同步
```

不能因为按钮在详情页里，就重新走旧的页面进入补绑逻辑。

#### 第 12 步：临时日志与排查点

建议新增日志：

```text
chat.detail.new_thread_button.tap current=<old> isSending=<bool> isCreating=<bool>
chat.detail.new_thread_button.create_start current=<old>
chat.detail.new_thread_button.create_success old=<old> new=<new> member=<id?>
chat.detail.new_thread_button.create_failed old=<old> error=<category>
chat.detail.thread_switch.begin old=<old> new=<new>
chat.detail.thread_switch.active_set old=<old> new=<new> selected=<selected>
chat.detail.thread_switch.task_start thread=<new> marker=<bool>
chat.detail.thread_switch.messages_loaded thread=<new> count=<n>
chat.detail.thread_switch.guide_ensured thread=<new> inserted=<bool>
chat.detail.thread_switch.ready thread=<new> messages=<n>
```

日志排查规则：

| 现象 | 重点看 |
| --- | --- |
| 点击后没反应 | 是否有 `tap`、按钮是否 disabled |
| 创建了多个 thread | `isCreatingThreadInDetail` 是否防重入 |
| 页面仍显示旧消息 | `active_set` 后 `visibleMessages` 是否仍读 selectedMessages |
| 新 thread 没 guide card | `guide_ensured` 是否执行 |
| guide card 生成写到旧 thread | ViewModel 方法是否仍读 `stateStore.selectedThreadID` 或旧 `threadID` |
| 草稿串会话 | composer 是否仍用旧 `threadID` |

### 3.7 文件级改造清单

#### `ChatView.swift`

必须处理：

1. 增加 `@State activeThreadID`。
2. 增加 `@State isCreatingThreadInDetail`。
3. 初始化 `activeThreadID`。
4. 增加 `currentThreadID`。
5. 新增右上角按钮。
6. 新增 `createThreadInsideCurrentChat()`。
7. 新增 `switchDetailThread(from:to:)`。
8. `.task(id: threadID)` 改为 `.task(id: currentThreadID)`。
9. `visibleMessages` 改为按 `currentThreadID` 读取。
10. 所有运行时 thread 操作改用 `currentThreadID`。
11. 切换 thread 时关闭参数弹层、清理临时 UI 状态。

不建议在本期处理：

1. 大规模重构 ChatView 子组件结构。
2. 改变消息渲染架构。
3. 改变 ChatList 路由方式。

#### `ChatListViewModel.swift`

必须处理：

1. `createThread()` 返回 `UUID?`，或新增 `createThreadAndSelect()`。
2. 创建失败时提供错误状态或返回 nil。
3. 防止内部已有创建中状态与详情页按钮状态冲突。

建议：

```swift
@Published private(set) var isCreatingThread = false
```

如果已有创建中状态，应复用，不重复增加。

#### `ChatDetailViewModel.swift`

必须处理：

1. 新建 guide card、科普问题生成、重新进入修复方法改为显式 threadID 参数。
2. 不再依赖 `stateStore.selectedThreadID` 作为唯一来源。
3. 发送消息/附件/成员绑定等方法确认入参 threadID 正确。

推荐签名：

```swift
func ensureGuideMessageForNewlyCreatedThread(threadID: UUID) async
func startGuideQuestionGenerationForNewlyCreatedThread(threadID: UUID) async
func repairGuideQuestionsForReenteredThreadIfNeeded(threadID: UUID) async
```

#### `ChatStateStore.swift`

当前已支持按 threadID 缓存消息。建议补充：

```swift
func messages(for threadID: UUID) -> [ChatMessage] {
    conversationListItems(for: threadID)
}
```

这只是语义增强，可选。

如果需要更强的 UI 切换信号，可增加：

```swift
@Published private(set) var detailActiveThreadIDs: [UUID: UUID]
```

但本期推荐保持简单，由 `ChatView.activeThreadID` 负责。

### 3.8 交互细节

按钮形态：

```text
图标：plus.bubble 或 square.and.pencil
位置：topBarTrailing，设置菜单左侧
点击态：disabled + opacity
loading：可选，不强制
```

按钮禁用条件：

1. `isCreatingThreadInDetail == true`
2. `listViewModel.isCreatingThread == true`（如果有）
3. `stateStore.isSending == true`（本期建议）
4. 当前无可用 Chat 模型时不禁用，但创建后发送仍按现有模型检查

错误提示：

1. 创建失败使用 alert/toast 均可，遵循项目现有提示风格。
2. 不要把底层 CoreData 或网络错误直接展示给用户。
3. 错误后保留旧 thread，按钮恢复可点。

### 3.9 并发与边界

必须覆盖：

| 场景 | 处理 |
| --- | --- |
| 用户连续点击新建 | 第一次进入 creating，后续点击 no-op |
| 旧 thread 正在发送 | 本期按钮禁用，避免上下文切换 |
| 旧 thread 正在 AI 回复 | 本期按钮禁用或允许后台继续；推荐先禁用 |
| 新建完成但消息加载慢 | 立即切空缓存/轻 loading，不显示旧消息 |
| 新建完成后 guide card 插入失败 | 停留新 thread，可显示空态 |
| 新建后立即返回列表 | 新 thread 已在列表，后台生成继续 |
| 新建后立刻再次点新建 | 第一轮 ready 后才允许第二次 |
| App 进入后台 | 已创建 thread 保留；未完成后台同步继续按现有机制 |

### 3.10 伪代码总览

```swift
struct ChatView: View {
    let threadID: UUID
    @State private var activeThreadID: UUID
    @State private var isCreatingThreadInDetail = false

    private var currentThreadID: UUID { activeThreadID }

    init(threadID: UUID, ...) {
        self.threadID = threadID
        _activeThreadID = State(initialValue: threadID)
        ...
    }

    private var visibleMessages: [ChatMessage] {
        stateStore.conversationListItems(for: currentThreadID)
            .filter { uiStateStore.isDeleted($0.id) == false }
    }

    private var lifecycleLayout: some View {
        statePersistenceLayout
            .task(id: currentThreadID) {
                let id = currentThreadID
                listViewModel.selectThread(id)
                await detailViewModel.loadMessagesIfNeeded(for: id, lockBottomViewport: true)
                if stateStore.isThreadMarkedAsNewlyCreated(id) {
                    await detailViewModel.ensureGuideMessageForNewlyCreatedThread(threadID: id)
                    await detailViewModel.startGuideQuestionGenerationForNewlyCreatedThread(threadID: id)
                    stateStore.clearThreadWasJustCreatedMarker(id)
                } else {
                    await detailViewModel.repairGuideQuestionsForReenteredThreadIfNeeded(threadID: id)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task { await createThreadInsideCurrentChat() }
                    } label: {
                        Image(systemName: "plus.bubble")
                    }
                    .disabled(isCreatingThreadInDetail || stateStore.isSending)

                    settingsMenu
                }
            }
    }

    @MainActor
    private func createThreadInsideCurrentChat() async {
        guard isCreatingThreadInDetail == false else { return }
        let old = currentThreadID
        isCreatingThreadInDetail = true
        defer { isCreatingThreadInDetail = false }
        guard let new = await listViewModel.createThreadAndSelect() else { return }
        activeParameterCard = nil
        activeThreadID = new
        stateStore.setSelectedThreadID(new)
        logger.info("chat.detail.thread_switch.begin old=\(old) new=\(new)", module: .general)
    }
}
```

### 3.11 验收用例矩阵

| 编号 | 场景 | 预期 |
| --- | --- | --- |
| A1 | 旧 thread 有 10 条消息，点击右上角新建 | 当前页面不跳转，消息列表变为新 thread |
| A2 | 新建过程中连点 3 次 | 只创建 1 个 thread |
| A3 | 旧 thread 有草稿，点击新建 | 新 thread 草稿为空，旧 thread 草稿保留 |
| A4 | 新 thread guide card 插入成功 | 当前页面显示 guide card |
| A5 | 新 thread 有绑定成员 | 后台生成科普问题 |
| A6 | 新 thread 未绑定成员 | guide card 直接固定问题 |
| A7 | 创建失败 | 留在旧 thread，旧消息不变 |
| A8 | 点击新建后返回列表 | 新 thread 在列表中，选中态为新 thread |
| A9 | 再进入旧 thread | 旧消息、草稿、分页状态仍正确 |
| A10 | 设置弹层打开时点击新建 | 弹层关闭，避免保存串 thread |

## 4. 整体业务流程

```text
用户在对话详情页点击右上角新建对话
  ↓
ChatView 设置创建中
  ↓
ChatListViewModel.createThreadAndSelect()
  ↓
CreateThreadUseCase 创建本地 thread
  ↓
ChatStateStore 标记 newlyCreatedThread
  ↓
ChatStateStore selectedThreadID = newThreadID
  ↓
ChatView activeThreadID = newThreadID
  ↓
当前详情页内部重载新 thread 消息缓存
  ↓
插入/展示首条 guide card
  ↓
后台生成科普问题
```

## 5. 状态模型

| 状态 | 含义 | UI |
| --- | --- | --- |
| idle | 当前无创建任务 | 按钮可点 |
| creating | 正在创建新 thread | 按钮置灰或显示 ProgressView |
| switching | 已创建，正在切换缓存 | 消息区可显示轻量 loading |
| ready | 新 thread 消息缓存就绪 | 显示新 thread |
| failed | 创建失败 | 保持旧 thread，提示失败 |

## 6. 数据与持久化

本地数据：

1. 新 thread 写入 CoreData。
2. `stateStore.threadItems` 刷新或插入新项。
3. `stateStore.selectedThreadID` 更新为新 thread。
4. `ChatView.activeThreadID` 更新为新 thread。
5. 新 thread messages 缓存单独维护。
6. 新 thread composer draft 单独维护。

服务端同步：

1. thread 元数据后台同步。
2. guide system message 走 outbox。
3. guide block generated/fallback 走 block_updates。
4. 所有同步不阻塞当前页面切换。

## 7. 错误模型

| 错误 | 处理 |
| --- | --- |
| createThread 失败 | 保持旧会话，提示失败 |
| reloadThreads 失败 | 仍可切换到本地新 thread，后续刷新列表 |
| activeThreadID 切换后消息加载失败 | 显示空态/错误态，可重试 |
| guide card 插入失败 | 不影响 thread 切换，记录日志 |
| AI 科普问题生成失败 | 固定问题 fallback |
| 服务端同步失败 | 不回滚 UI，后台重试 |
| 用户连续点击 | 创建中禁用，防重复 thread |

## 8. 与其他模块的接口边界

本模块负责：

1. 在 ChatView 右上角提供新建对话入口。
2. 在当前详情页内部创建并切换 thread。
3. 切换消息缓存、草稿和分页状态。
4. 衔接新 thread 的 guide card 和科普问题生成链路。

本模块不负责：

1. 对话列表页的导航样式。
2. 服务端接口改造。
3. AI 科普问题 prompt 生成质量。
4. 健康数据滑块展示。

上游调用方：

```text
ChatView toolbar button
```

下游依赖：

```text
ChatListViewModel
CreateThreadUseCase
ChatStateStore
ChatDetailViewModel
ChatGuideQuestionGenerationCoordinator
```

## 9. 关键代码对应关系

| 能力 | 代码位置 |
| --- | --- |
| 右上角 toolbar | `SparkClient/Projects/Features/Chat/Presentation/ChatView.swift` |
| 新建 thread | `SparkClient/Projects/Features/Chat/Presentation/ChatListViewModel.swift` |
| thread 创建用例 | `SparkClient/Projects/Features/Chat/Application/CreateThreadUseCase.swift` |
| 当前选中 thread | `SparkClient/Projects/Features/Chat/Presentation/ChatStateStore.swift` |
| 消息加载与 guide 生成 | `SparkClient/Projects/Features/Chat/Presentation/ChatDetailViewModel.swift` |
| 列表页现有导航 | `SparkClient/Projects/Features/Chat/Presentation/ChatConversationListPage.swift` |

## 10. 测试策略

建议新增或调整测试：

| 测试 | 覆盖点 |
| --- | --- |
| `ChatDetailNewThreadButtonTests` | 点击详情页按钮创建新 thread |
| `ChatDetailThreadSwitchTests` | 不跳转情况下 activeThreadID 切换 |
| `ChatDetailMessageCacheSwitchTests` | 新旧 thread 消息缓存隔离 |
| `ChatDetailDraftIsolationTests` | 新旧 thread 草稿隔离 |
| `ChatDetailNewThreadGuideCardTests` | 内部新建后 guide card 插入与生成 |
| `ChatDetailNewThreadDebounceTests` | 连续点击不重复创建 |
| `ChatDetailActiveThreadIDMigrationTests` | ChatView 运行时操作全部使用 active/current threadID |
| `ChatDetailComposerThreadIsolationTests` | 附件、模型、成员绑定、参数设置不串到旧 thread |
| `ChatDetailToolbarStateTests` | 创建中按钮禁用，发送中按钮禁用 |
| `ChatDetailThreadSwitchLoggingTests` | 关键切换日志完整出现 |

手动验收：

1. 进入任意对话，点击右上角新建按钮。
2. 页面不 push、不 pop。
3. 当前详情页标题、消息、输入框切换到新 thread。
4. 新 thread 出现 guide card。
5. 返回会话列表，新 thread 已在列表中。
6. 再进入旧 thread，旧消息仍存在。
7. 旧 thread 输入草稿后点击新建，新 thread 草稿为空；返回旧 thread 草稿仍存在。
8. 打开参数设置弹层后点击新建，弹层关闭且不会保存到错误 thread。
9. 新 thread 生成 guide card 后，科普问题生成日志 threadID 与当前 activeThreadID 一致。
10. 快速连续点击新建按钮，仓储只新增一个 thread。

## 11. 当前实现、缺口与演进

当前实现：

1. `ChatView.swift` 已有右上角 toolbar 预留注释。
2. `ChatListViewModel.createThread()` 已能创建 thread、标记新建、切换 selectedThreadID。
3. `ChatStateStore` 已按 threadID 维护 selectedThread 和消息缓存。
4. `ChatDetailViewModel` 已有新建 thread guide card / 科普问题链路。

当前缺口：

1. `ChatView` 还没有右上角新建对话按钮。
2. `ChatListViewModel.createThread()` 当前不返回新 threadID。
3. `ChatView` 使用固定 `let threadID`，不适合当前实例内部切换。
4. 点击详情页新建后如何切换消息缓存尚未实现。
5. 缺少不跳转内部切换的测试。

建议演进：

1. 优先实现 `activeThreadID` 方案，避免全局 selectedThreadID 影响导航栈其他 ChatView。
2. 后续可把“创建并切换 thread”抽成 `ChatDetailThreadSwitchCoordinator`，减少 ChatView 状态复杂度。
3. 如果未来支持多窗口或 iPad 多列同时打开多个对话，必须避免单一全局 selectedThreadID 作为详情页唯一状态源。

## 12. 整体验收标准

1. ChatView 右上角新增新建对话按钮。
2. 点击按钮不发生任何导航跳转。
3. 点击按钮后当前详情页内部切换到新 threadID。
4. 消息缓存切换到新 thread，不显示旧消息。
5. 新 thread 正常插入首条 system guide card。
6. 新 thread 后台启动科普问题生成。
7. 新旧 thread 的消息、草稿、分页状态互不污染。
8. 连续点击只创建一个新 thread。
9. 创建失败时留在旧 thread。
10. 返回列表后新 thread 出现在会话列表中。
11. ChatView 内所有运行时业务使用 `currentThreadID/activeThreadID`，不再误用初始 `threadID`。
12. 右上角新建后，成员绑定、模型设置、附件、自动小任务、清空消息、参数面板都作用于新 thread。
13. 切换过程中不闪回旧消息。
14. 新建后 `.task(id: activeThreadID)` 会重新执行新 thread 初始化链路。
15. 日志可以完整串起 tap、create_success、active_set、messages_loaded、guide_ensured、ready。
