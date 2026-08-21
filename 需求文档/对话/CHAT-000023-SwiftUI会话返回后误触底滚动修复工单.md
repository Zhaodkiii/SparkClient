# CHAT-000023 SwiftUI 会话返回后误触底滚动修复工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | CHAT-000023 |
| 工单类型 | P1 体验缺陷 / SwiftUI 会话滚动状态 / 导航返回位置保持 |
| 当前范围 | 创建问题分析与修复方案工单，不修改 Swift 实现代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 目标模块 | `SparkClient/Projects/Features/Chat/Presentation` |
| 重点文件 | `ChatView.swift`、`SwiftUIConversation/ChatSwiftUIConversationView.swift`、`SwiftUIConversation/ChatSwiftUIScrollAnchorPolicy.swift`、`ChatStateStore.swift`、`ChatDetailViewModel.swift` |
| 创建日期 | 2026-08-21 |
| 触发问题 | 初始进入会话时自动滚动到底部正常；在会话内点击消息卡片进入其他页面后，返回会话页面又会自动滚动到底部 |
| 预期行为 | 导航返回会话时保持离开前的滚动位置，不应重新执行初始进入滚动到底部 |
| 优先级 | P1，影响阅读上下文连续性 |

## 1. 一句话目标

把“首次打开会话需要滚到底部”和“从消息卡片详情页返回会话需要保持当前位置”拆成两个明确场景，避免 SwiftUI 会话视图在导航返回时把 `onAppear` 当作首次进入，从而误触底部滚动。

---

## 2. 问题现象

### 2.1 当前表现

1. 从对话列表点击进入某个会话。
2. 会话初始加载后自动滚动到底部，展示最新消息。该行为符合预期。
3. 用户向上滚动到某条历史消息，或当前视口停留在非底部位置。
4. 点击消息内卡片，进入任务详情、健康卡片详情、天气设置或工具授权详情等页面。
5. 从详情页返回会话。
6. 会话列表又自动滚动到底部，导致用户丢失刚才阅读的上下文。

### 2.2 预期表现

1. 首次进入会话：自动滚动到底部。
2. 用户主动发送消息、明确点击“滚动到底部”或系统有显式触底请求：可以滚动到底部。
3. 从会话内卡片详情页返回：保持返回前滚动位置，不自动滚动到底部。
4. 如果返回期间有新消息到达，应遵循现有用户滚动策略：用户不在底部时不抢位置，用户在底部或显式跟随时才触底。

---

## 3. 关联代码现状

### 3.1 初始加载入口

`ChatView.swift` 中会话初始任务只在 `hasLoaded == false` 时执行：

```swift
.task {
    guard hasLoaded == false else { return }
    hasLoaded = true
    listViewModel.selectThread(threadID)
    await detailViewModel.loadMessagesIfNeeded(for: threadID, lockBottomViewport: true)
}
```

该逻辑本身已经避免导航返回时重复加载消息。

### 3.2 SwiftUI 会话视图每次 appear 都 reset

`ChatSwiftUIConversationView.swift` 当前在 `onAppear` 中执行：

```swift
.onAppear {
    apply(input: input, reset: true)
}
```

`reset: true` 会重置：

```swift
streamBuffer.reset()
scrollPolicy.reset()
frameScheduler.reset()
```

这里是本问题的关键触发点。SwiftUI 的 `onAppear` 不只代表“首次进入会话”，从子页面 pop 回来、Tab/NavigationStack 重建局部视图、架构切换造成视图重新挂载时也可能触发。

### 3.3 滚动策略把返回误判成打开初始态

`ChatSwiftUIScrollAnchorPolicy.swift` 当前状态：

```swift
@Published private(set) var hasUserInteractedSinceOpen = false
private var hasScrolledToBottomSinceOpen = false
```

`reset()` 后这两个状态恢复为“刚打开且未交互”。随后 `shouldScrollToBottom` 中：

```swift
if frame.scrollToBottomRequestGeneration != lastScrollRequestGeneration {
    hasScrolledToBottomSinceOpen = true
    return true
}

if frame.lockBottomViewport && hasUserInteractedSinceOpen == false {
    hasScrolledToBottomSinceOpen = true
    return true
}
```

由于 `lastScrollRequestGeneration` 被 reset 为 `0`，而 `ChatStateStore` 中该会话历史的 `scrollToBottomRequestGeneration` 很可能已经大于 `0`，返回页面后会被判断为新的显式触底请求。

即使 generation 没有变化，只要 `lockBottomViewport` 仍在短时间内为 true，`hasUserInteractedSinceOpen == false` 也会促成触底。

### 3.4 全量加载会无条件增加触底请求

`ChatDetailViewModel.satisfyLoadRequest(.openOrReloadNewest)` 当前在加载最新消息后执行：

```swift
stateStore.requestScrollToBottom(for: threadID)
```

这对首次进入会话是合理的，但从语义上看，`scrollToBottomRequestGeneration` 是“显式触底请求”。如果后续视图的本地策略被 reset，它会把历史 generation 当成“新请求”再次消费。

---

## 4. 根因判断

根因不是消息高度计算错误，也不是卡片导航本身触发了新的数据加载；核心是滚动状态生命周期放在 `ChatSwiftUIConversationView` 内部，随 SwiftUI 视图 appear/reset 被清空，无法区分：

1. 第一次打开 thread。
2. 同一个 thread 内 push 详情页后 pop 返回。
3. 同一个 thread 的消息内容真实变化。
4. 用户显式请求滚动到底部。

因此返回时出现了这条误触发链路：

```text
卡片详情页返回
  -> ChatSwiftUIConversationView.onAppear
  -> apply(reset: true)
  -> scrollPolicy.reset()
  -> lastScrollRequestGeneration = 0
  -> 当前 frame.scrollToBottomRequestGeneration 仍为历史值 N
  -> shouldScrollToBottom 判定 generation 变化
  -> proxy.scrollTo(bottomAnchor, anchor: .bottom)
  -> 返回后被强制滚到最新消息
```

---

## 5. 修复原则

1. 初始打开会话的触底滚动只能消费一次。
2. 导航返回不能等价于初始打开。
3. 滚动策略应以 thread 生命周期为边界，而不是以 SwiftUI View 的 appear 次数为边界。
4. 用户已经离开底部阅读历史消息后，除非有明确触底请求，不应抢滚动位置。
5. 修复不能破坏此前“工具收起后等待布局稳定再滚到底部”的问题修复。

---

## 6. 推荐修复方案

### 6.1 首选方案：引入会话级滚动会话状态

在 `ChatSwiftUIConversationView` 内新增轻量状态，记录当前 SwiftUI 列表是否已经为当前 `threadID` 完成首次初始化，而不是每次 `onAppear` 都 reset。

建议语义：

```swift
@State private var initializedThreadID: UUID?
```

处理规则：

1. `onAppear`：
   - 如果 `initializedThreadID != threadID`，说明是首次进入该会话或切换了会话，执行 `apply(reset: true)`。
   - 如果 `initializedThreadID == threadID`，说明是同一会话返回，不 reset，只执行必要的 `apply(reset: false)` 或不处理。
2. `onChange(of: threadID)`：
   - 设置 `initializedThreadID = newThreadID` 前后执行 thread 切换 reset。
   - 保持现有首次进入新会话自动滚到底部。
3. 不改变 `layoutGeneration` 稳定后滚动机制，确保工具折叠后的底部校正仍然有效。

该方案改动最小，直接切断“导航返回 -> reset -> 历史 generation 被重新消费”的链路。

### 6.2 配套方案：滚动策略 reset 时同步当前 generation

进一步增强 `ChatSwiftUIScrollAnchorPolicy`，让 reset 支持以当前 frame 作为基线：

```swift
func reset(to frame: ChatSwiftUIConversationFrame, layoutGeneration: UInt64)
```

重置时将：

1. `lastScrollRequestGeneration = frame.scrollToBottomRequestGeneration`
2. `lastContentGeneration = frame.generation`
3. `lastLayoutGeneration = layoutGeneration`

然后通过额外参数控制是否需要初始触底：

```swift
enum ChatSwiftUIScrollOpenReason {
    case firstOpen
    case threadChanged
    case navigationReturn
}
```

对于 `navigationReturn`，reset 后不应将历史 generation 当作新请求。对于 `firstOpen` 和 `threadChanged`，仍允许首次触底。

该方案比 6.1 更完整，但改动面略大。可作为二阶段治理或与 6.1 合并实现。

### 6.3 状态源方案：在 ChatStateStore 记录已消费的打开触底请求

如果希望 UIKit 与 SwiftUI 两套会话 UI 语义完全统一，可在 `ChatStateStore` 里新增会话级状态：

```swift
private var consumedInitialBottomScrollThreadIDs: Set<UUID>
```

语义：

1. `loadMessagesIfNeeded(lockBottomViewport: true)` 可以标记本次加载期望首次触底。
2. UI 成功执行初始触底后，调用 store 标记已消费。
3. 返回页面时即使视图重建，也不会再次消费。

该方案对跨架构最干净，但需要让 UI 回写 Store，涉及职责边界调整；本问题建议先采用 6.1，后续再评估是否抽到 Store 层。

---

## 7. 建议实施步骤

### 7.1 第一步：修复 SwiftUI 返回误触底

目标文件：

```text
SparkClient/Projects/Features/Chat/Presentation/SwiftUIConversation/ChatSwiftUIConversationView.swift
```

建议修改点：

1. 增加 `initializedThreadID` 状态。
2. `onAppear` 只在当前 thread 尚未初始化时 reset。
3. 同一 thread 返回时不调用 `scrollPolicy.reset()` 和 `frameScheduler.reset()`。
4. `onChange(of: threadID)` 保留 reset，但要明确这是会话切换，不是导航返回。

### 7.2 第二步：修正滚动策略的 generation 基线

目标文件：

```text
SparkClient/Projects/Features/Chat/Presentation/SwiftUIConversation/ChatSwiftUIScrollAnchorPolicy.swift
```

建议修改点：

1. 避免 reset 后默认把 `lastScrollRequestGeneration` 置为 0 导致历史请求被重复消费。
2. 初始打开需要滚底时，使用单独的 `shouldPerformInitialBottomScroll` 或 open reason 表达，而不是依赖 generation 差异。
3. 保留用户交互后的保护：`hasUserInteractedSinceOpen == true` 时，不因 layout/content 变化自动触底。

### 7.3 第三步：补充最小回归验证

建议增加人工验收用例，若项目已有 UI 自动化基础，可再补自动化：

1. 初始进入长会话，落到最新消息。
2. 上滑到历史消息，点击任务卡片进入详情，返回后仍停留在历史消息附近。
3. 上滑到历史消息，点击结构化健康卡片进入详情，返回后仍停留在历史消息附近。
4. 停留底部，发送新消息，仍能跟随到底部。
5. 停留底部，工具调用完成并收起，仍能在布局稳定后看到最新消息，不出现底部空白。
6. 用户手动拖动后，后续普通消息高度变化不抢滚动位置。
7. 切换到另一个 thread，首次进入仍自动滚到底部。

---

## 8. 验收标准

1. 首次从会话列表进入会话，仍自动滚动到最新消息。
2. 在会话内点击消息卡片进入任意详情页后返回，不自动滚动到底部。
3. 返回时不出现底部空白、不闪跳、不把用户从历史消息位置拉走。
4. 用户主动发送消息或触发显式滚动到底部请求时，仍能滚到最新消息。
5. 工具过程完成并自动收起后，底部布局校正仍然生效。
6. SwiftUI 架构下通过验证；UIKit 架构不出现行为回退。

---

## 9. 风险与注意事项

1. 不能简单删除 `onAppear` 的 `apply(reset: true)`，否则首次进入会话可能不构建 frame 或不触底。
2. 不能简单移除 `stateStore.requestScrollToBottom(for:)`，否则发送消息、重新加载最新窗口等链路可能失去显式触底能力。
3. 不能用固定延迟规避返回滚动；该问题是状态生命周期误判，不是布局稳定时间不足。
4. 修复时要保留 `layoutGeneration` 驱动的工具折叠后再滚动策略。
5. 如果未来支持会话内多层 push、sheet、全屏图片预览，需要统一把这些都归为“同 thread 导航返回”，不应触发初始滚底。

---

## 10. 推荐结论

本问题的最佳修复方向是：把滚动策略从“View 每次 appear 都重新初始化”改为“按 thread 首次初始化”。初始进入会话仍可以滚到底部，但同一会话内的卡片详情返回只恢复原列表状态，不重新消费历史 `scrollToBottomRequestGeneration`。

短期优先落地 `ChatSwiftUIConversationView` 的 `initializedThreadID` 防护，成本低、收益直接；随后再考虑让 `ChatSwiftUIScrollAnchorPolicy.reset` 支持以当前 frame 作为基线，彻底消除历史 generation 被重复消费的隐患。
