# DEEPTUTORCHAT-000005 本地数据库会话列表、消息刷新与键盘收起工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | DEEPTUTORCHAT-000005 |
| 工单类型 | P0 缺陷修复 + DeepTutor Web 会话体验对齐 |
| 当前范围 | 只创建需求/技术工单，不直接修改 Swift 业务实现 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| iOS 功能目录 | `SparkClient/Projects/Features/DeepTutorChat` |
| Web 参考工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main` |
| 目标文档目录 | `需求文档/对话/DeepTutorChat` |
| 创建日期 | 2026-08-05 |
| AI 场景约束 | 继续使用项目通用 `.chat` 场景，不新增 `.deepTutor` 或 DeepTutor 专属场景 |
| 存储约束 | 当前版本必须走本地数据库和已有数据流程，不允许只停留在内存态 |
| UI 对齐约束 | 消息会话继续对齐 DeepTutor Web 的页面容器、状态、消息列表、单条气泡、内容渲染、工具/思考 trace 与输入区刷新体验 |

## 1. 本工单要解决的问题

### 1.1 新建对话后列表不可见

当前用户遇到的问题：

```text
创建新的对话没有在对话列表内看到，需要存储到本地数据库，对话列表可以加载出来。
```

必须达成的行为：

```text
Given 用户点击 DeepTutor 对话列表右上角新建按钮或空态新建按钮
When 新建对话成功
Then 新对话必须写入本地数据库 ChatThreadEntity
And 当前对话列表必须能立刻看到新对话
And App 重启后重新进入 DeepTutor 对话列表仍然能看到该对话
And 点击该对话可以打开对应会话页
```

### 1.2 发送新消息后消息列表不更新

当前用户遇到的问题：

```text
发送新的消息，消息列表会话没有更新。
```

必须达成的行为：

```text
Given 用户在已打开的 DeepTutor 对话输入一条新消息
When 点击发送
Then 用户消息气泡必须立即出现在消息列表底部
And 助手占位/思考/工具调用/正文区域必须进入可见更新状态
And 消息列表必须滚动到底部
And 本地数据库必须保存用户消息和后续助手消息
And 会话列表的 latestPreview 与 updatedAt 必须刷新
```

### 1.3 发送消息后键盘未收起

当前用户要求：

```text
发送消息之后需要收起键盘。
```

必须达成的行为：

```text
Given 输入框当前聚焦且系统键盘展开
When 用户点击发送按钮并且消息内容有效
Then iOS 键盘必须立即收起
And 输入框失去焦点
And 消息发送流程继续执行
And 空消息、禁用状态、停止生成按钮不应误触发收键盘逻辑
```

### 1.4 继续对齐 DeepTutor Web 消息会话

本工单不是单点修 bug，还要继续把 iOS 的会话刷新方式对齐 Web 的核心链路：

```text
state.messages
  -> ChatMessageList
  -> UserMessage / AssistantMessage
  -> AssistantActivity / AssistantResponse
  -> MarkdownRenderer / TracePanels / AskUserOptions
  -> Composer 发送后状态刷新
```

iOS 侧要落到：

```text
DeepTutorChatViewModel.state.messages
  -> DeepTutorMessageListRepresentable
  -> DeepTutorMessageListViewController diffable snapshot
  -> DeepTutorMessageRowView
  -> 用户气泡 / 助手气泡 / trace / markdown / ask_user / composer
  -> 本地数据库变更通知与刷新
```

## 2. 参考 DeepTutor Web 的关键事实

### 2.1 Web 会话页面入口

参考文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/app/(workspace)/home/[[...sessionId]]/page.tsx
```

核心事实：

```tsx
<ChatMessageList
  messages={state.messages}
  isStreaming={state.isStreaming}
  sessionId={state.sessionId}
  language={state.language}
  onCopyAssistantMessage={copyAssistantMessage}
  onRegenerateMessage={handleRegenerateMessage}
  onConfirmOutline={handleConfirmOutline}
  onPreviewAttachment={handlePreviewMessageAttachment}
  onDeleteTurn={deleteTurn}
  selectedBranches={state.selectedBranches}
  onEditMessage={editMessage}
  onSwitchBranch={switchBranch}
  onSubmitUserReply={submitUserReply}
/>
```

对 iOS 的要求：

| Web 职责 | iOS 对齐职责 |
| --- | --- |
| `state.messages` 是消息列表唯一渲染输入 | `DeepTutorChatViewModel.state.messages` 必须是当前会话 UI 的唯一事实源 |
| 页面壳层负责滚动、Composer、Turn 导航组合 | `DeepTutorChatPage` 负责消息列表、Composer、导航标题、底部避让与生命周期 |
| `ChatMessageList` 每次根据状态重新渲染 | `DeepTutorMessageListRepresentable.updateUIViewController` 每次接收 ViewModel 状态并 apply snapshot |
| Web 流式时自动滚底 | iOS 发送、流式、工具调用、最终完成都要触发底部锁定或滚底请求 |

### 2.2 Web 消息列表入口

参考文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ChatMessages.tsx
```

关键链路：

```text
ChatMessageList
  -> buildVisiblePath(messages, selectedBranches)
  -> deep_research 相邻轮次合并
  -> UserMessage
  -> AssistantMessage
```

对 iOS 的要求：

| Web 行为 | iOS 落地 |
| --- | --- |
| 消息列表来自 `messages` 数组 | 消息列表来自 `state.messages`，不得由 Cell 自己查库 |
| 分支可见路径控制展示 | iOS 当前可先不做多分支，但数据模型要保留 `parentMessageId` / `clientMessageID` / `turnID` 可扩展点 |
| 用户消息右对齐，助手消息左侧/全宽内容区 | iOS `DeepTutorMessageRowView` 必须按 role 分流，并保持最大宽度、圆角、背景、间距一致 |
| 工具 trace 先于助手正文展示 | iOS 助手消息必须先渲染 activity/trace，再渲染正文 markdown |
| ask_user 内联交互在消息中展示 | iOS 需要支持问题回答卡片，不应作为普通 markdown 文本吞掉 |

### 2.3 Web 输入区发送刷新语义

参考文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ChatComposer.tsx
/Users/hua/Documents/project/Reference/LookHealthClient/DeepTutor-main/web/components/chat/home/ComposerInput.tsx
```

Web 输入区关键语义：

| 语义 | Web 表现 | iOS 对齐要求 |
| --- | --- | --- |
| 文本有效性 | 空文本不可发送 | iOS 空白文本不得触发 send、不得收键盘、不得入库 |
| 发送按钮 | 发送与停止共用按钮，状态切换 | iOS `DeepTutorComposerToolbarView` 也应根据 `isStreaming` 切换发送/停止 |
| 输入高度 | 有消息时较紧凑，无消息时更高 | iOS `DeepTutorComposerCardView.minInputHeight` 已有 `hasMessages` 分支，需继续保持 |
| 发送后状态 | 草稿清空，消息区更新，滚到底部 | iOS 必须清空草稿、立即插入本地用户气泡、触发 diffable 刷新、滚底、收键盘 |
| 附件/引用 | composer 顶部有 reference band | iOS `DeepTutorComposerReferenceBandView` 必须与 Web context reference band 语义一致 |

## 3. iOS 当前关键代码位置与已发现偏差

### 3.1 会话列表页面

文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorChatPage.swift
```

已发现代码事实：

```swift
struct DeepTutorConversationListPage: View {
    @ObservedObject var viewModel: DeepTutorChatViewModel
    @State private var hasLoaded = false
    @State private var showsCreationError = false

    var body: some View {
        List {
            if viewModel.conversations.isEmpty {
                emptyState
            } else {
                ForEach(viewModel.conversations) { item in
                    Button {
                        viewModel.selectedConversationID = item.id
                    } label: {
                        conversationRow(item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationDestination(item: $viewModel.selectedConversationID) { conversationID in
            DeepTutorChatPage(conversationID: conversationID, viewModel: viewModel)
                .task(id: conversationID) {
                    await viewModel.openConversation(conversationID)
                }
        }
        .task {
            guard hasLoaded == false else { return }
            hasLoaded = true
            await viewModel.loadConversationsIfNeeded()
        }
        .refreshable {
            await viewModel.refreshConversations()
        }
    }
}
```

当前风险：

| 风险点 | 说明 | 影响 |
| --- | --- | --- |
| 新建后列表依赖本地查询是否命中 | 如果 `createConversation` 写库成功但 `loadConversationsUseCase` 查询条件不一致，列表会空 | 用户看不到新建对话 |
| 依赖 `selectedConversationID` 触发导航 | 如果列表没有刷新但导航打开成功，返回列表仍可能空 | 用户误以为对话未保存 |
| `DeepTutorChatPage` 与 `navigationDestination.task` 可能重复 open | 如果内部页面也 `.task(id:) openConversation`，需要防重复 | 可能出现多次 reload、状态闪烁 |
| 空态按钮与 toolbar 按钮共用新建流程 | 两处都必须写入数据库并刷新列表 | 任一入口不能成为例外 |

### 3.2 ViewModel 会话创建与列表刷新

文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorChatViewModel.swift
```

已发现代码事实：

```swift
func loadConversationsIfNeeded() async {
    conversations = await loadConversationsUseCase()
    logger.debug(
        "DeepTutor 会话列表已加载，count=\(conversations.count), scenario=\(DeepTutorScenarioConstants.scenario)",
        module: DeepTutorChatLog.module
    )
}
```

```swift
func refreshConversations(source: String = "manual", expectedCreatedID: UUID? = nil) async {
    let previous = conversations
    let loaded = await loadConversationsUseCase()

    if let expectedCreatedID {
        let containsCreated = loaded.contains { $0.id == expectedCreatedID }
        if containsCreated {
            conversations = loaded
        } else {
            logger.warning(
                "create_refresh_missing_created_conversation id=\(DeepTutorChatLog.shortID(expectedCreatedID)), refreshCount=\(loaded.count), scenario=\(DeepTutorScenarioConstants.scenario)",
                module: DeepTutorChatLog.module
            )
            if let optimistic = previous.first(where: { $0.id == expectedCreatedID }) {
                conversations = [optimistic] + loaded.filter { $0.id != expectedCreatedID }
            } else {
                conversations = loaded
            }
        }
    } else {
        conversations = loaded
    }
}
```

```swift
func createAndOpenConversation(source: String = "toolbar") async {
    do {
        let created = try await createConversation(title: "DeepTutor Chat", refreshList: false)
        optimisticallyInsertConversation(created)
        selectedConversationID = created.id
        await refreshConversations(source: "create", expectedCreatedID: created.id)
        await openConversation(created.id)
    } catch {
        conversationCreationError = error.localizedDescription
    }
}
```

必须补齐的工程要求：

| 要求 | 说明 |
| --- | --- |
| 新建对话必须先写库，再刷新列表 | 不能只修改 `conversations` 内存数组 |
| 乐观插入只能做临时体验兜底 | `optimisticallyInsertConversation` 不能掩盖数据库未命中的问题 |
| `expectedCreatedID` 缺失必须作为 P0 日志 | 如果刷新后查不到刚创建 ID，说明写库或查询过滤有偏差 |
| 列表查询必须使用同一账号和同一 scenario | `ownerAccountID`、`DeepTutorScenarioConstants.scenario` 必须创建和查询一致 |
| 创建完成后要支持冷启动恢复 | 退出页面或重启 App 后，`loadConversationsIfNeeded()` 必须能重新加载出来 |

### 3.3 本地数据库写入

文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorLocalChatStore.swift
```

已发现代码事实：

```swift
func createConversation(title: String) async throws -> DeepTutorConversation {
    guard let accountID = activeAccountID else {
        throw DeepTutorLocalChatStoreError.missingAccount
    }

    let conversation = DeepTutorConversation(
        title: title,
        createdAt: Date(),
        updatedAt: Date()
    )

    try kernel.writeWithoutNotification { context in
        let entity = ChatThreadEntity(context: context)
        entity.id = conversation.id
        entity.ownerAccountID = accountID
        entity.title = conversation.title
        entity.scenario = DeepTutorScenarioConstants.scenario
        entity.createdAt = conversation.createdAt
        entity.updatedAt = conversation.updatedAt
        entity.isSoftDeleted = false
        entity.isActive = false
        entity.isPinned = false
        entity.maxMessages = 20
        entity.topP = 1.0
    }

    return conversation
}
```

验收要点：

| 字段 | 必须值 | 验收方式 |
| --- | --- | --- |
| `id` | 新建 UUID | 创建日志与数据库查询一致 |
| `ownerAccountID` | 当前登录账号 ID | 切换账号后不串数据 |
| `scenario` | `DeepTutorScenarioConstants.scenario`，且底层 AI 消费继续用 `.chat` | 列表查询用相同 scenario |
| `title` | 默认 `DeepTutor Chat`，后续可由首条消息生成标题 | 列表 row 展示标题 |
| `createdAt` | 创建时间 | 列表排序可用 |
| `updatedAt` | 创建时间，后续消息发送后更新 | 发送消息后列表置顶 |
| `isSoftDeleted` | `false` | 列表不能过滤掉新建会话 |
| `latestPreview` | 初始可为空，发送后必须更新 | 发送后列表 preview 有内容 |

### 3.4 消息发送流程

文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorChatViewModel.swift
```

已发现代码事实：

```swift
func sendMessage() async {
    guard let conversationID = activeConversationID else {
        return
    }
    let text = state.draftText
    guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
        return
    }

    state.draftText = ""
    DeepTutorDraftStore.saveDraft("", for: conversationID)
    state.phase = .streaming
    state.isStreaming = true
    state.lockBottomViewport = true
    state.scrollToBottomRequestGeneration &+= 1
    isSendingMessage = true

    do {
        let result: (user: DeepTutorMessage, assistant: DeepTutorMessage)
        if DeepTutorDebugFlags.useLocalSimulator {
            result = try await localSendMessageUseCase(...)
        } else {
            result = try await sendMessageUseCase(...)
        }
        state.phase = .ready
        state.isStreaming = false
        state.lockBottomViewport = false
        await reloadMessages(for: conversationID)
        await refreshConversations(source: "send")
    } catch {
        state.phase = .error(message)
        state.isStreaming = false
        await reloadMessages(for: conversationID)
    }
}
```

当前偏差：

| 偏差 | 说明 | 用户感知 |
| --- | --- | --- |
| 发送后主要依赖最终 `reloadMessages` | 如果真实 AI 调用耗时较长，用户消息不会立即出现在列表 | 以为发送无效 |
| 缺少明确“本地用户消息先入库/先入 state”要求 | Web 是状态驱动立即渲染，iOS 不能等整个 use case 完成才刷新 | UI 卡住或滞后 |
| 助手占位、thinking、tool trace 更新链路需要冻结 | 如果流式事件未反推到 `state.messages`，trace 与正文不会动 | 工具调用、思考不可见 |
| 错误路径只 reload，不一定落失败气泡 | Web 通常能保留失败消息并提供重试 | 用户上下文断裂 |

必须补齐的目标流程：

```text
用户点击发送
  -> 校验非空
  -> 立即收起键盘
  -> 读取草稿 text
  -> 清空 draftText + 清空 DraftStore
  -> 构造本地 user message
  -> 写入 ChatMessageEntity
  -> state.messages 立即追加 user message
  -> 构造 assistant placeholder / thinking message
  -> state.messages 立即追加 assistant placeholder
  -> phase = .streaming, isStreaming = true
  -> scrollToBottomRequestGeneration += 1
  -> 调用真实 AI `.chat`
  -> 每个 streaming delta / tool event / thinking event 更新 assistant message
  -> 每次事件更新都触发 state.messages 变更 + diffable apply
  -> terminal success 写库并刷新 conversations
  -> terminal failure 保留失败 assistant message，可重试
```

### 3.5 消息列表 diffable 刷新

文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorMessageListView.swift
```

已发现代码事实：

```swift
func apply(conversationID: UUID, payload: DeepTutorListApplyPayload) {
    let messages = payload.messages
    let previousBottomGeneration = lastScrollToBottomGeneration
    let shouldForceScrollToBottom = payload.scrollToBottomRequestGeneration != previousBottomGeneration
    lastScrollToBottomGeneration = payload.scrollToBottomRequestGeneration

    bottomViewportLockActive = payload.lockBottomViewport && hasUserInteractedSinceOpen == false
    let plan = updateBuilder.plan(
        previous: currentMessages,
        next: messages,
        forceFullListRediff: payload.forceFullListRediff
    )

    let items = loadMoreItems + messages.map(\.clientMessageID)
    messageLookup = Dictionary(uniqueKeysWithValues: messages.map { ($0.clientMessageID, $0) })
    currentMessages = messages

    var snapshot = NSDiffableDataSourceSnapshot<Section, UUID>()
    snapshot.appendSections([.main])
    snapshot.appendItems(items, toSection: .main)
    snapshot.reloadItems(plan.reloadedItemIDs.filter { items.contains($0) })
    dataSource.apply(snapshot, animatingDifferences: hasAppliedInitialSnapshot)
}
```

刷新要求：

| 场景 | 必须触发的状态变化 | UI 结果 |
| --- | --- | --- |
| 打开会话 | `state.messages = 本地消息` | 渲染历史消息 |
| 点击发送 | `state.messages.append(user)` | 立即显示用户气泡 |
| 开始请求 AI | `state.messages.append(assistantPlaceholder)` | 立即显示助手占位/思考区域 |
| 收到 thinking | 替换对应 assistant message 的 thinking segments/events | activity 卡片刷新 |
| 收到 tool_call | 更新对应 assistant message events | 工具调用折叠区刷新 |
| 收到 answer delta | 更新 assistant content | markdown 正文流式刷新 |
| 完成 | assistant status -> completed，`isStreaming=false` | 停止 loading，保留最终文本 |
| 失败 | assistant status -> failed，错误内容可见 | 出现失败气泡与重试入口 |

特别注意：

```text
DiffableDataSource 通过 clientMessageID 识别 item。
如果发送后创建了消息但 clientMessageID 没有变化，或者 state.messages 没有发布新数组，UICollectionView 不会新增 Cell。
如果只是修改 message 内部引用但 plan 没识别内容变化，Cell 也可能不 reload。
```

因此实现时必须保证：

| 要求 | 说明 |
| --- | --- |
| 每条新消息有稳定且唯一的 `clientMessageID` | 用户消息和助手消息不能复用同一个 ID |
| 更新消息内容时触发 `state.messages` 重新赋值 | SwiftUI/Representable 才会调用 `updateUIViewController` |
| `DeepTutorConversationUpdateBuilder` 能识别 content/events/status 变化 | 否则 streaming 期间不会 reload |
| 强制滚底 generation 在发送时递增 | 对齐 Web 发送后贴底体验 |
| 用户主动上滑后不强行打断阅读 | 只有 bottom lock 或显式发送才自动滚底 |

## 4. 本地数据库与会话列表加载方案

### 4.1 创建对话的唯一正确链路

目标链路：

```text
DeepTutorConversationListPage.toolbar plus
  -> viewModel.createAndOpenConversation(source: "toolbar")
  -> createConversationUseCase(title)
  -> DeepTutorLocalChatStore.createConversation(title)
  -> ChatThreadEntity insert
  -> return DeepTutorConversation
  -> optimisticallyInsertConversation(created)
  -> selectedConversationID = created.id
  -> refreshConversations(source: "create", expectedCreatedID: created.id)
  -> openConversation(created.id)
```

必须禁止的错误链路：

```text
点击新建
  -> 只创建 DeepTutorConversation struct
  -> 只插入 viewModel.conversations
  -> 未写 ChatThreadEntity
  -> 页面上短暂出现
  -> refresh 或重启后丢失
```

### 4.2 列表查询必须与创建字段对齐

如果创建写入：

```text
ownerAccountID = activeAccountID
scenario = DeepTutorScenarioConstants.scenario
isSoftDeleted = false
```

则列表查询必须至少过滤：

```text
ownerAccountID == activeAccountID
scenario == DeepTutorScenarioConstants.scenario
isSoftDeleted == false
```

排序必须优先：

```text
updatedAt DESC
createdAt DESC
```

验收时必须检查以下偏差：

| 偏差 | 检查方式 |
| --- | --- |
| 创建用一个 scenario，查询用另一个 scenario | 打印 create/query scenario 完整值 |
| 创建时 activeAccountID 为空 | 日志出现 `missingAccount`，UI 弹出创建失败 |
| 写入在 private context 但未保存 | 创建后用同一 repository 立即按 ID 查询 |
| 查询误把 `isActive == true` 当必要条件 | 新建 entity 当前 `isActive = false`，如果列表要求 true 会查不到 |
| 查询被软删除过滤误伤 | 新建必须 `isSoftDeleted = false` |
| 列表只看有消息的 thread | 新建空对话也必须展示，不应要求 latest message 存在 |

### 4.3 新建空对话也必须展示

新建后即使还没有任何消息，列表也必须展示一条 row：

```text
标题：DeepTutor Chat
预览：可以为空、显示“暂无消息”或显示产品指定占位
时间：createdAt 或 updatedAt
位置：列表顶部
```

不能因为 `latestPreview == ""` 就过滤掉该对话。

### 4.4 会话列表 row 刷新规则

| 动作 | 列表应变更 |
| --- | --- |
| 新建对话 | 新 row 立刻插入顶部 |
| 发送用户消息 | row 置顶，preview 更新为用户问题或助手最终回答前的用户内容 |
| 助手生成中 | row 可显示生成中状态，至少不能消失 |
| 助手完成 | preview 更新为助手最终回答摘要，updatedAt 更新 |
| 失败 | preview 保留用户问题或显示失败状态，不删除 row |
| 返回列表 | 刷新列表，确认 latestPreview 和 updatedAt 已落库 |
| 重启 App | 重新从本地数据库加载所有未删除会话 |

### 4.5 数据库验收用例

```text
Case 1: 空态新建
Given 本地 DeepTutor 会话列表为空
When 点击空态“新建对话”
Then 列表不再为空
And 数据库 ChatThreadEntity 存在对应 id
And row title 为 DeepTutor Chat
```

```text
Case 2: toolbar 新建
Given 当前列表已有 N 条对话
When 点击右上角 plus.bubble
Then 列表变为 N+1
And 新对话位于第一行
And 进入详情页后返回列表仍然存在
```

```text
Case 3: 冷启动恢复
Given 已创建一条 DeepTutor 本地对话
When 结束 App 进程并重新打开 DeepTutor 列表
Then `loadConversationsIfNeeded()` 能加载该对话
And 列表不展示空态
```

```text
Case 4: 账号隔离
Given 账号 A 创建了 DeepTutor 对话
When 切换到账号 B
Then 账号 B 不应看到账号 A 的对话
When 切回账号 A
Then 账号 A 仍能看到该对话
```

## 5. 消息发送与消息列表更新方案

### 5.1 对齐 Web 的状态驱动模型

Web 的消息 UI 是：

```text
state.messages 改变
  -> ChatMessageList 重新计算可见消息
  -> UserMessage/AssistantMessage 重渲染
```

iOS 必须是：

```text
DeepTutorChatViewModel.state.messages 改变
  -> DeepTutorMessageListRepresentable.updateUIViewController
  -> DeepTutorMessageListViewController.apply
  -> NSDiffableDataSourceSnapshot 更新
```

核心原则：

```text
发送成功不是消息列表更新的起点。
点击发送那一刻就是消息列表更新的起点。
```

### 5.2 发送点击后的即时 UI 更新

目标时序：

```text
T+0ms 用户点击发送
T+0ms 校验 text 非空
T+1ms 收起键盘
T+1ms 清空输入框
T+5ms 本地追加用户消息气泡
T+8ms 本地追加助手占位气泡
T+10ms 消息列表滚动到底部
T+50ms 发起真实 AI `.chat` 请求
T+Nms streaming 事件持续刷新 assistant 气泡
T+Done 完成后保存最终 assistant 消息并刷新会话列表
```

视觉要求：

| 时间点 | 用户看到 |
| --- | --- |
| 点击发送瞬间 | 键盘收起，输入框清空，自己的问题以右侧气泡出现 |
| AI 请求中 | 助手区域出现“思考/活动/加载中”状态 |
| 工具调用中 | 工具使用卡片出现，可展开/折叠 |
| 回答生成中 | 助手正文流式增长 |
| 回答完成 | loading 消失，按钮恢复发送状态 |

### 5.3 本地入库顺序

发送消息时，至少应产生两条本地消息：

| 消息 | role | status | content | 入库时机 |
| --- | --- | --- | --- | --- |
| 用户消息 | `user` | `completed` | 用户输入全文 | 点击发送后立即 |
| 助手消息 | `assistant` | `streaming` 或 `pending` | 初始空文本或思考占位 | AI 请求开始前 |

推荐顺序：

```text
1. 创建 user DeepTutorMessage
2. repository.upsertMessage(user)
3. state.messages append user
4. 创建 assistant placeholder DeepTutorMessage
5. repository.upsertMessage(assistant)
6. state.messages append assistant
7. 开始真实 AI 请求
8. 事件 reducer 持续更新 assistant
9. terminal 后 repository.upsertMessage(assistantFinal)
10. refreshConversations(source: "send")
```

### 5.4 不能只依赖 use case 返回后 reload

当前 `sendMessage()` 的已发现行为是：

```text
真实 AI 或本地模拟完成
  -> await reloadMessages(for: conversationID)
  -> await refreshConversations(source: "send")
```

这只能保证“最终刷新”，不能保证“发送后立即更新”。因此需要补齐：

| 阶段 | 当前风险 | 修正要求 |
| --- | --- | --- |
| 发送开始 | 只有 phase/isStreaming 变化，没有明确 append user message | 必须立即 append 用户消息 |
| AI 请求中 | 如果 use case 内部不回调事件，UI 无法变化 | 必须通过事件 reducer 或 progress callback 更新 state |
| 工具调用中 | events 不更新则 trace 不展示 | tool event 必须落到 assistant.events |
| 完成后 | reload 可以兜底 | reload 仍保留，但不能作为唯一刷新机制 |
| 失败后 | 可能只显示 error，不显示失败消息 | 保留用户消息与失败助手消息 |

### 5.5 消息状态机

建议冻结以下状态：

| 状态 | 说明 | UI |
| --- | --- | --- |
| `drafting` | 用户输入中 | Composer 可编辑 |
| `sendingUser` | 用户消息本地写入中 | 可短暂禁用发送 |
| `waitingAssistant` | 助手占位已创建，等待首个事件 | 助手 loading/思考卡片 |
| `streamingThinking` | 正在输出 thinking 或 activity | trace 卡片刷新 |
| `streamingTool` | 正在工具调用 | 工具卡片刷新 |
| `streamingAnswer` | 正在输出正文 | markdown 流式刷新 |
| `completed` | 助手完成 | 固定最终气泡 |
| `failed` | 失败 | 失败状态 + 重试入口 |
| `cancelled` | 用户停止生成 | 保留已生成内容 + 状态标识 |

### 5.6 消息列表刷新验收

```text
Case 1: 立即显示用户消息
Given 已打开一条本地对话
When 输入“解释一下胰岛素抵抗”并点击发送
Then 右侧用户气泡必须在 300ms 内出现
And 不需要等待 AI 返回
```

```text
Case 2: 立即进入助手状态
Given 用户消息已出现在底部
When AI 请求尚未返回正文
Then 左侧助手区域必须出现 loading/thinking/activity 占位
And 发送按钮切换为停止按钮
```

```text
Case 3: 流式正文刷新
Given AI 正在返回内容
When 每次收到 delta
Then 同一条 assistant message 内容增长
And 不新增重复 assistant 气泡
And 消息列表保持贴底，除非用户主动上滑
```

```text
Case 4: 工具调用刷新
Given AI 触发 tool call
When 收到工具开始、参数、结果、完成事件
Then assistant 气泡正文上方出现工具/思考 trace
And trace 支持折叠/展开
And 工具完成后正文继续展示
```

```text
Case 5: 发送后列表 preview
Given 当前会话发送一条新消息并获得回答
When 返回会话列表
Then 该会话位于顶部
And latestPreview 显示最新用户问题或助手回答摘要
And updatedAt 为最新消息时间
```

## 6. 发送后键盘收起方案

### 6.1 当前输入区关键代码

文件：

```text
/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient/SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorComposerCardView.swift
```

已发现代码事实：

```swift
DeepTutorComposerTextView(
    text: $text,
    placeholder: "Message DeepTutor",
    minHeight: minInputHeight,
    maxHeight: DeepTutorPalette.composerMaxHeight,
    onSubmit: onSend
)
```

```swift
DeepTutorComposerToolbarView(
    capability: $capability,
    modelName: modelName,
    isStreaming: isStreaming,
    canSend: canSend,
    onSend: onSend,
    onStop: onStop
)
```

当前风险：

```text
onSend 只触发 ViewModel.sendMessage。
如果输入控件没有显式失焦，UITextView/SwiftUI TextEditor 会继续保持 first responder，键盘不会收起。
```

### 6.2 收键盘触发点

推荐触发点：

```text
DeepTutorComposerCardView / DeepTutorComposerTextView 所在 Presentation 层
```

不要把 UIKit 键盘收起逻辑塞进 AI UseCase 或 Repository。

原因：

| 层级 | 是否适合处理键盘 | 原因 |
| --- | --- | --- |
| Presentation | 是 | 键盘属于 UI 焦点状态 |
| ViewModel | 可接收“发送成功触发 UI intent”，但不直接依赖 UIKit 更好 | ViewModel 应尽量平台无关 |
| UseCase | 否 | 业务发送流程不应该知道键盘 |
| Repository | 否 | 数据存储不应该知道 UI |

### 6.3 推荐实现方式

方案 A：`@FocusState` 驱动 SwiftUI 输入失焦。

```swift
@FocusState private var isComposerFocused: Bool

DeepTutorComposerTextView(...)
    .focused($isComposerFocused)

private func sendAndDismissKeyboard() {
    guard canSend else { return }
    isComposerFocused = false
    onSend()
}
```

适用条件：

```text
如果 DeepTutorComposerTextView 能暴露 SwiftUI focus 绑定，优先使用。
```

方案 B：通过 UIKit resign first responder。

```swift
UIApplication.shared.sendAction(
    #selector(UIResponder.resignFirstResponder),
    to: nil,
    from: nil,
    for: nil
)
```

适用条件：

```text
如果 DeepTutorComposerTextView 是 UIViewRepresentable 包装 UITextView，且短期不方便接 FocusState，可先用此方案兜底。
```

方案 C：在 `DeepTutorComposerTextView` Coordinator 暴露 `resignFirstResponder()`。

```text
适用于需要更精确控制某一个 UITextView，而不是全局 resign。
```

### 6.4 收键盘验收边界

| 场景 | 是否收键盘 | 说明 |
| --- | --- | --- |
| 点击有效发送按钮 | 是 | 用户明确要求 |
| 键盘 return 触发发送 | 是 | 与点击发送一致 |
| 输入为空点击发送 | 否 | 因为没有真正发送 |
| 正在 streaming 点击停止 | 可不收 | 停止不是发送 |
| ask_user 提交选项 | 建议收 | 提交自由输入时与发送一致 |
| 上传附件/拖拽文件 | 否 | 不应打断输入 |
| 切换 capability | 否 | 不应打断输入 |

### 6.5 与 Web 的差异说明

Web 端 textarea 发送后可以继续保持焦点，方便连续输入。但 iOS 用户明确要求发送后收起键盘，并且移动端屏幕空间更紧张，因此本工单允许 iOS 在这个点做平台化差异：

```text
Web：发送后可继续 focus textarea。
iOS：发送后必须 dismiss keyboard。
```

这个差异不影响消息状态、消息列表、trace、markdown 与工具调用的 DeepTutor Web 对齐。

## 7. DeepTutor Web 消息卡片继续对齐要求

### 7.1 用户消息气泡

Web 参考：

```text
group flex justify-end
max-w-[75%]
rounded-2xl
bg-[var(--secondary)]
px-4 py-2.5
text-[14px]
leading-relaxed
whitespace-pre-wrap
```

iOS 要求：

| 设计项 | iOS 目标 |
| --- | --- |
| 对齐 | 用户消息右对齐 |
| 最大宽度 | 约屏幕宽度 75%，iPad 不无限拉宽 |
| 圆角 | 大圆角，连续曲线，类似 `rounded-2xl` |
| 内边距 | 水平约 16pt，垂直约 10pt |
| 字号 | 约 14-15pt，正文舒适可读 |
| 行高 | 比系统默认略松，支持多行 |
| 文本 | 保留换行与空格语义，等价 `whitespace-pre-wrap` |
| 操作 | 长按/hover 等价能力：复制、编辑、删除、分支后续扩展 |

### 7.2 助手消息气泡

Web 参考链路：

```text
AssistantMessage
  -> AssistantActivity
  -> outline / math / visualize / quiz / ask_user / AssistantResponse
```

iOS 要求：

| 区域 | 展示顺序 | 要求 |
| --- | --- | --- |
| Activity/Trace | 第一 | 思考、工具调用、已完成耗时在正文前 |
| 特殊能力卡片 | 第二 | Quiz/研究/可视化等后续能力按 capability 分流 |
| ask_user | 正文中间 | 问题回答卡片不能被普通 markdown 吞掉 |
| AssistantResponse | 最后 | markdown、数学、代码块、链接、列表等最终渲染 |
| 操作按钮 | 气泡下方/右侧 | 复制、重生成、删除等与 Web 语义一致 |

### 7.3 工具使用与思考 trace

Web 用户提供的 DOM 片段显示：

```text
已完成 · 1m 17s
写作搜索
分析思路
工具详情
工具参数
工具结果
最终答案
```

iOS 必须具备：

| 组件 | 要求 |
| --- | --- |
| Activity header | 显示状态、耗时、折叠箭头 |
| 左侧竖线 | 用于串联 thinking/tool steps |
| Tool row | 图标、名称、状态、耗时 |
| Tool details | 参数、结果、错误，支持展开 |
| Thinking row | 可折叠，支持长文本 |
| Completed state | 完成后显示“已完成 · xx s/min” |
| Streaming state | 进行中显示 spinner 或 breathing 状态 |
| Failed state | 显示失败原因与重试入口 |

### 7.4 Markdown 与回答效果

DeepTutor Web 最终回答由：

```text
AssistantResponse
  -> split think segment
  -> ModelThinkingCard
  -> MarkdownRenderer
```

iOS 要求：

| 内容类型 | iOS 展示 |
| --- | --- |
| 普通段落 | 清晰行距，正文宽度与助手气泡一致 |
| 标题 | 分级字号和上下间距 |
| 列表 | 缩进、项目符号/序号清楚 |
| 代码块 | 圆角浅底、等宽字体、可横向滚动或自动换行策略明确 |
| 引用 | 左侧线或浅色背景 |
| 数学 | 当前版本可先降级为文本，但必须记录为 P1 |
| Mermaid | 当前版本可先降级为文件/占位卡片，但必须记录为 P1 |
| thinking block | 不混入最终答案正文，单独卡片 |

## 8. 日志要求

### 8.1 本工单日志不要求脱敏

按用户最新约束：

```text
日志不需脱敏。
```

因此 DeepTutorChat 本地调试日志可以记录：

| 内容 | 是否允许 |
| --- | --- |
| 用户问题全文 | 允许 |
| 助手回答全文 | 允许 |
| conversationID | 允许 |
| messageID | 允许 |
| phase | 允许 |
| durationMs | 允许 |
| capability | 允许 |
| tool name | 允许 |
| tool input/output | 允许 |
| AI provider/model display name | 允许 |

仍然不得记录：

| 内容 | 原因 |
| --- | --- |
| API Key | 凭据 |
| Bearer Token | 凭据 |
| Cookie | 凭据 |
| refresh token | 凭据 |
| password | 凭据 |
| OTP/验证码 | 凭据 |
| Keychain 原始内容 | 凭据 |

### 8.2 必须新增/完善的日志点

| 日志点 | 级别 | 必须字段 |
| --- | --- | --- |
| 新建对话开始 | info | source、accountID、scenario |
| 新建对话写库成功 | info | conversationID、title、createdAt、scenario |
| 新建后按 ID 查库 | debug | conversationID、found |
| 新建后刷新列表 | debug/info | expectedCreatedID、containsCreated、listCount |
| 新建失败 | error | source、error、accountID、scenario |
| 列表加载开始 | debug | accountID、scenario |
| 列表加载完成 | info | count、firstID、scenario |
| 发送点击 | info | conversationID、text、capability |
| 键盘收起触发 | debug | trigger=sendButton/keyboardSubmit |
| 用户消息本地入库 | info | messageID、conversationID、content |
| 用户消息 append state | debug | messageID、messageCount |
| 助手占位创建 | info | messageID、conversationID、status |
| streaming delta | debug | messageID、delta、contentLength |
| tool event | debug/info | messageID、toolName、phase、payload |
| 发送完成 | info | userMessageID、assistantMessageID、durationMs、model |
| 发送失败 | error | conversationID、messageID、error、content |
| 会话列表 preview 刷新 | debug | conversationID、latestPreview、updatedAt |

## 9. 实施拆分

### 9.1 P0-1 修复新建对话列表不可见

任务：

```text
1. 审计 `DeepTutorCreateConversationUseCase` 是否真正调用 `DeepTutorLocalChatStore.createConversation`。
2. 审计 `DeepTutorLoadConversationsUseCase` 的查询谓词。
3. 确认 create 与 load 使用同一个 `activeAccountID`。
4. 确认 create 与 load 使用同一个 `DeepTutorScenarioConstants.scenario`。
5. 确认列表不要求 thread 必须有消息。
6. 创建后按 ID 立即查询数据库，查不到则记录 P0 error。
7. 新建后 `refreshConversations(expectedCreatedID:)` 必须 containsCreated=true。
8. App 重启后列表仍可加载。
```

验收：

```text
新建对话后立即可见。
返回列表仍可见。
重启 App 后仍可见。
日志中能看到写库成功和列表加载 count 增加。
```

### 9.2 P0-2 修复发送消息后列表不更新

任务：

```text
1. 发送按钮触发后立即构造 user message。
2. user message 立即写入本地数据库。
3. user message 立即 append 到 `state.messages`。
4. 立即构造 assistant placeholder。
5. assistant placeholder 立即 append 到 `state.messages`。
6. 开始真实 AI `.chat` 请求。
7. streaming event 持续更新同一条 assistant message。
8. 每次更新触发 `state.messages` 重新赋值。
9. diffable snapshot 能 reload 对应 `clientMessageID`。
10. terminal 后 reloadMessages 兜底校准。
11. 发送后 refreshConversations 更新列表 preview。
```

验收：

```text
点击发送 300ms 内用户气泡出现。
AI 未返回前也有助手状态。
流式返回时正文持续增长。
工具调用和思考卡片能刷新。
返回列表 preview 已更新。
```

### 9.3 P0-3 发送后收起键盘

任务：

```text
1. 在 Presentation 层给 Composer 增加 focus 管理或 resign first responder。
2. 点击有效发送按钮时先收键盘，再执行 onSend。
3. 键盘 return 提交时同样收键盘。
4. 空文本发送不收键盘。
5. 停止生成不强制收键盘。
6. ask_user 自由输入提交可复用同一收键盘策略。
```

验收：

```text
输入文本后点击发送，键盘立即收起。
消息正常发送。
输入框清空。
消息列表滚动到底部。
空文本点击发送不会收起键盘或触发请求。
```

### 9.4 P0-4 继续对齐 DeepTutor Web 会话 UI

任务：

```text
1. 用户气泡右对齐、宽度、圆角、背景、字号、行高继续对齐 Web。
2. 助手气泡按 trace -> special card -> markdown 顺序展示。
3. 工具调用卡片支持折叠、参数、结果、状态、耗时。
4. thinking 卡片与最终答案分离。
5. ask_user 问题回答卡片内联展示。
6. Composer card、reference band、send/stop 状态继续对齐 Web。
7. 滚动策略继续对齐 Web 自动滚底体验。
```

验收：

```text
使用同一段 DeepTutor Web 样例消息，在 iOS 上能看到相同信息层级。
工具/思考不丢失。
正文 markdown 可读。
发送/停止/输入区状态一致。
```

## 10. 回归测试矩阵

| 编号 | 场景 | 操作 | 预期 |
| --- | --- | --- | --- |
| T001 | 空列表新建 | 空态点击新建对话 | 新 row 出现并进入详情 |
| T002 | toolbar 新建 | 列表右上角点击 plus | 新 row 插入顶部 |
| T003 | 冷启动恢复 | 新建后重启 App | 列表加载该对话 |
| T004 | 新建后返回 | 新建进入详情后返回 | 列表仍显示该对话 |
| T005 | 发送文本 | 输入有效文本点击发送 | 用户气泡 300ms 内出现 |
| T006 | 发送后键盘 | 键盘展开时点击发送 | 键盘立即收起 |
| T007 | 空文本 | 输入空格点击发送 | 不发送、不收键盘、不入库 |
| T008 | 助手占位 | AI 未返回时观察列表 | 助手 loading/thinking 可见 |
| T009 | 流式回答 | AI 返回 delta | 同一助手气泡持续更新 |
| T010 | 工具调用 | AI 触发 tool call | trace 卡片展示工具状态 |
| T011 | 失败 | 模型请求失败 | 保留用户消息，助手失败可重试 |
| T012 | 停止 | streaming 中点击停止 | 生成停止，已生成内容保留 |
| T013 | 列表 preview | 发送完成后返回列表 | row 置顶且 preview 更新 |
| T014 | 主动上滑 | streaming 中用户上滑 | 不强制打断阅读 |
| T015 | 再次发送 | 第一轮完成后继续发送 | 第二轮按同样流程刷新 |

## 11. 关键代码落点

### 11.1 必查 iOS 文件

| 文件 | 检查重点 |
| --- | --- |
| `SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorChatPage.swift` | 列表加载、新建入口、导航、返回刷新 |
| `SparkClient/Projects/Features/DeepTutorChat/Application/DeepTutorChatViewModel.swift` | `createAndOpenConversation`、`refreshConversations`、`sendMessage`、`reloadMessages`、数据库变更通知 |
| `SparkClient/Projects/Features/DeepTutorChat/Infrastructure/DeepTutorLocalChatStore.swift` | `ChatThreadEntity` 写入、`ChatMessageEntity` 写入、change notification |
| `SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorMessageListView.swift` | diffable snapshot、reload item、滚底策略 |
| `SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorComposerView.swift` | Composer 容器、底部背景、安全区 |
| `SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorComposerCardView.swift` | 发送按钮、输入区、键盘收起触发点 |
| `SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorComposerTextView.swift` | UITextView/TextEditor focus、return submit、resign first responder |
| `SparkClient/Projects/Features/DeepTutorChat/Presentation/DeepTutorComposerToolbarView.swift` | send/stop 状态切换 |

### 11.2 必查 Web 文件

| 文件 | 对齐重点 |
| --- | --- |
| `DeepTutor-main/web/app/(workspace)/home/[[...sessionId]]/page.tsx` | 页面壳层、消息区、滚动、Composer |
| `DeepTutor-main/web/components/chat/home/ChatMessages.tsx` | 消息列表、用户气泡、助手气泡、能力分流 |
| `DeepTutor-main/web/components/chat/home/TracePanels.tsx` | 思考与工具调用 trace |
| `DeepTutor-main/web/components/chat/home/AskUserOptions.tsx` | 问题回答卡片 |
| `DeepTutor-main/web/components/chat/home/ChatComposer.tsx` | 输入区整体 UI |
| `DeepTutor-main/web/components/chat/home/ComposerInput.tsx` | 输入框高度、提交逻辑、组合输入保护 |
| `DeepTutor-main/web/components/common/AssistantResponse.tsx` | 助手正文最终落点 |
| `DeepTutor-main/web/components/common/MarkdownRenderer.tsx` | Markdown/数学/Mermaid 路由 |

## 12. 完成定义

本工单完成必须同时满足：

```text
1. 新建对话真实写入本地数据库。
2. 新建对话后列表立即显示。
3. App 重启后列表仍能加载新建对话。
4. 发送新消息后用户气泡立即显示。
5. 发送新消息后助手占位/思考/工具状态立即进入可见状态。
6. 流式事件能更新同一条助手消息。
7. 发送完成后会话列表 preview 与 updatedAt 刷新。
8. 发送有效消息后键盘立即收起。
9. 空消息不会触发发送、入库或收键盘。
10. 消息 UI、工具使用、思考、问题回答、Composer 继续对齐 DeepTutor Web。
11. 日志能完整定位 create、load、send、append、stream、refresh、keyboard dismiss 全链路。
12. AI 消费继续使用项目已有通用 `.chat` 场景，不新增 `.deepTutor`。
```

## 13. 风险与待确认项

| 风险 | 影响 | 处理 |
| --- | --- | --- |
| create 与 load 的 scenario 不一致 | 新建后列表查不到 | 统一 `DeepTutorScenarioConstants.scenario`，AI runtime 仍用 `.chat` |
| activeAccountID 为空 | 无法写库 | 创建前日志明确，UI 给出错误 |
| 列表查询只返回有消息会话 | 新建空对话不可见 | 查询必须包含空 thread |
| 发送流程等待 AI 完成才 reload | 用户认为消息没发送 | 点击发送立即本地 append |
| diffable 未识别 message 内容变化 | 流式 UI 不刷新 | 更新 `state.messages` 数组并 reload item |
| 键盘收起放错层级 | ViewModel/UseCase 污染 UI 逻辑 | 放在 Presentation 层 |
| 工具/思考事件只写日志不进 message events | UI 无 trace | event reducer 必须更新 assistant message |
| 失败路径吞掉用户消息 | 用户上下文丢失 | 保留用户消息与失败助手消息 |
| 乐观列表掩盖数据库失败 | 冷启动后对话丢失 | 创建后按 ID 查库，查不到报 P0 |

## 14. 给开发的最小执行顺序

```text
1. 先修新建对话本地数据库写入与列表查询一致性。
2. 再修发送点击后的 user message 即时 append。
3. 再补 assistant placeholder 与 streaming event reducer。
4. 再补发送后键盘收起。
5. 最后做 Web 消息卡片、trace、composer 的视觉细节复核。
```

不要反过来先做 UI 细节。当前用户遇到的是 P0 链路问题：

```text
没有列表
没有消息刷新
键盘不收
```

只有数据链路与刷新链路稳定后，DeepTutor Web UI 对齐才有可靠落点。
