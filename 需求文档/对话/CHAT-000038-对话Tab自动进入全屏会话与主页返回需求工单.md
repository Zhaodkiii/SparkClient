# CHAT-000038 对话 Tab 自动进入全屏会话与主页返回需求工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | `CHAT-000038` |
| 工单类型 | P1 交互改造 / Chat / Tab 自动进入 / fullScreenCover / AppRouteStore |
| 当前阶段 | Swift 实现已落地；待真机/模拟器交互验收 |
| 目标工程 | `SparkClient` |
| 主入口 | 底部对话 Tab → `ChatConversationListPage` |
| 关联工单 | `CHAT-000029`、`CHAT-000030`、`CHAT-000035`、`CHAT-000037` |
| 重点文件 | `SignedInMainTabHostView.swift`、`HomePresentationSupport.swift`、`ChatConversationListPage.swift`、`ChatView.swift`、`AppRouteStore.swift`、`IOS26TabBarView.swift`、`MainTabCoordinatorView.swift` |
| 创建日期 | 2026-08-24 |

## 一、模块目标

将 `ChatConversationListPage` 打开 `ChatView` 的方式从当前 NavigationStack push 改为 App 根宿主统一管理的 `fullScreenCover`。列表页继续负责自动进入判断、会话选择与创建，但不在自身内部再声明第二个 Cover；它通过明确的 presentation request 请求 `SignedInMainTabHostView` 使用现有 `homeFullScreenCoverContent`/Chat 组装链路展示会话。

对话 Tab 首次进入时，保留现有自动决策：

1. 当前选中 Thread 有未发送文本草稿时，停留对话列表。
2. 否则优先打开最近 5 分钟内活跃的对话。
3. 没有最近活跃对话时，校验 Chat 模型，新建 Thread 并打开。

上述“由对话 Tab 自动进入”的 `ChatView` 左上角必须显示 `heart.fill` 主页按钮。用户点击后，先关闭当前 `fullScreenCover`，再通过 `AppRouteStore` 把底部 Tab 切换到 `.healthHome`，并落在健康首页根页面。

本工单同时要求区分“自动进入”与“用户在列表手动打开”：

- 自动进入：左上角是 `heart.fill` 主页按钮。
- 手动打开：继续使用 NavigationDestination 的系统返回，返回对话列表，不强制切首页。
- App 级 `.chatThread` 深链/程序化路由：本期不改变其现有导航语义。

### 1.1 用户价值

- 进入对话 Tab 后直接获得沉浸式全屏对话，不暴露中间 push 层级。
- 自动进入的用户不需先关闭到列表再切 Tab，可从头部一步返回健康首页。
- 手动查看历史会话仍保留“关闭回列表”的可预期行为。

### 1.2 范围与非目标

| 项目 | 本期结论 |
| --- | --- |
| `ChatConversationListPage` 打开 ChatView 统一改为根宿主 fullScreenCover | 必须 |
| 自动进入的 ChatView 左上角主页按钮 | 必须 |
| 主页按钮关闭 Cover 后切到 `.healthHome` | 必须 |
| 列表卡片点击、右上角新建、空态新建继续使用 NavigationDestination | 必须，属于手动来源 |
| 改变“5 分钟活跃会话”决策 | 不做 |
| 改变“文本草稿时跳过自动进入”决策 | 不做；附件/健康资源草稿扩展另立工单 |
| 改变 Thread 创建、首条 guide card、AI 生成流程 | 不做 |
| 改变 AppRoute `.chatThread` 外部路由 | 不做 |
| 改变对话消息 UI、Composer 与发送协议 | 不做 |

## 二、对话 Tab 全屏会话模块结构

### 2.1 结构职责表

| 层级 | 当前职责 | 已确认关键代码 |
| --- | --- | --- |
| 对话 Tab 列表 | 列表展示、自动进入决策、新建、编辑、删除、模型设置引导 | `Projects/Features/Chat/Presentation/ChatConversationListPage.swift` |
| 对话详情 | 消息、Composer、Thread 内切换、Toolbar、全屏关闭确认 | `Projects/Features/Chat/Presentation/ChatView.swift` |
| 会话列表 VM | 加载/刷新/搜索/创建 Thread、更新列表读模型 | `Projects/Features/Chat/Presentation/ChatListViewModel.swift` |
| 会话详情 VM | 模型校验、消息加载、发送与取消生成 | `Projects/Features/Chat/Presentation/ChatDetailViewModel.swift` |
| 会话状态 | Thread 列表、selectedThreadID、消息缓存、草稿、发送状态 | `Projects/Features/Chat/Presentation/ChatStateStore.swift` |
| App 路由 | RootTab、每个 Tab 的 route stack、Tab 选中持久化 | `Projects/App/Sources/App/AppRouteStore.swift` |
| App 全屏呈现宿主 | 统一持有 active cover、组装 ChatView、处理 dismiss 后动作 | `Projects/App/Sources/App/SignedInMainTabHostView.swift` |
| 全屏呈现值模型 | 当前 `HomeFullScreenCover`；本期需扩展为含来源的 App 级语义 | `Projects/Features/Home/Presentation/HomePresentationSupport.swift` |
| iOS 26 Tab 宿主 | 系统 `TabView`、对话容器与路由注入 | `Projects/App/Sources/App/IOS26TabBarView.swift` |
| 经典 Tab 宿主 | 兼容 TabView、对话页与路由注入 | `Projects/App/Sources/App/MainTabCoordinatorView.swift` |
| 正常 App 路由目标 | 处理 `.chatThread(UUID)` 等程序化 push 目标 | `Projects/App/Sources/App/MainTabRouteDestinationBuilder.swift` |
| 测试 | `AppRouteStore` Tab 持久化和可见 Tab 回退 | `Tests/App/AppRouteStoreSelectedTabPersistenceTests.swift` |

### 2.2 当前已确认目录结构

```text
SparkClient/
├── Projects/App/Sources/App/
│   ├── AppRouteStore.swift
│   ├── SignedInMainTabHostView.swift
│   ├── IOS26TabBarView.swift
│   ├── MainTabCoordinatorView.swift
│   └── MainTabRouteDestinationBuilder.swift
├── Projects/Features/Chat/Presentation/
│   ├── ChatConversationListPage.swift
│   ├── ChatView.swift
│   ├── ChatListViewModel.swift
│   ├── ChatDetailViewModel.swift
│   └── ChatStateStore.swift
└── Tests/App/
    └── AppRouteStoreSelectedTabPersistenceTests.swift
```

### 2.3 目录职责与依赖方向

```text
IOS26TabBarView / MainTabCoordinatorView
  → 向 ChatConversationListPage 注入 onPresentChat action 与其现有业务依赖

ChatConversationListPage
  → 决定要打开哪个 threadID
  → 标记 presentationSource（automatic/manual）
  → 选中 Thread 并预加载消息
  → 发出 presentChat(threadID, source) 请求

SignedInMainTabHostView
  → 持有唯一 active full-screen presentation
  → 复用现有 homeFullScreenCoverContent / chatFullScreenCover 组装 ChatView
  → 根据 source 注入 leading action 与 dismiss 后动作

ChatView
  → 消费 threadID 和头部 leading action 语义
  → 不直接持有 AppRouteStore
  → 点击后仅回调根呈现宿主

SignedInMainTabHostView fullScreenCover onDismiss
  → 普通关闭：清理展示状态，留在对话列表
  → 主页返回：AppRouteStore.route(to: .home, replaceStack: true)
```

当前模块是 SwiftUI 列表页 + ObservableObject ViewModel/Store + App 级路由宿主的混合形态；本功能不引入新的 Repository 或服务端 API。

### 2.4 方案对比与架构决策

| 比较项 | 复用 `SignedInMainTabHostView` 根 Cover | `ChatConversationListPage` 内新建 Cover |
| --- | --- | --- |
| 跨 Tab 生命周期 | 根宿主在 Tab 切换时仍稳定存在，适合“dismiss 后回首页” | 列表页属于 Chat Tab；切 Tab 时 presenter 生命周期更脆弱 |
| ChatView 依赖组装 | 复用现有 `chatFullScreenCover`，依赖、预加载、关闭策略只有一处 | 需复制完整 ChatView 初始化，后续新增依赖容易漏传 |
| 全屏互斥 | 与医疗上传、相机、成员详情、健康资源 Chat 共用一个 active cover，自然互斥 | 形成根 Cover + 列表 Cover 两套状态，可能出现竞争或叠层 |
| 需求语义 | 本需求包含跨 Feature、跨 Tab 的返回首页动作，属于 App 级呈现 | 更适合只在列表内部打开、关闭后永远回列表的局部弹层 |
| 双 Tab 宿主 | `IOS26TabBarView` 与经典宿主已共享根 binding | 两个宿主都要重复注入 Chat 构建依赖与路由能力 |
| 后续扩展 | 医疗详情、体检、处方、药箱及对话 Tab 可共用一个 Chat presenter | 每个入口可能继续创建自己的 Cover，重复造轮子 |
| 代价 | 需把 `HomeFullScreenCover` 的命名/值模型提升为 App 级语义 | 初期改动看似集中在列表页，但长期维护成本更高 |

**架构结论：推荐复用 `SignedInMainTabHostView` 的根级 `fullScreenCover`。**

推荐采用“决策归列表，呈现归根宿主”的职责拆分：

1. `ChatConversationListPage` 保留自动恢复、自动新建、手动选择、模型检查等业务决策，只输出 `threadID + source`。
2. `SignedInMainTabHostView` 负责唯一 Cover、ChatView 依赖组装、展示互斥和 dismiss 后跨 Tab 路由。
3. 不让 Chat Feature 直接依赖 `HomeFullScreenCover`；由两个 Tab 宿主向列表页注入 `onPresentChat` 闭包或等价 presenter 协议。
4. 当前 `HomeFullScreenCover` 名称已经不能准确覆盖“对话 Tab 全屏会话”。本期建议重命名为 `MainFullScreenCover` 或 `SignedInFullScreenCover`；若为控制改动暂不重命名，至少将其视为待偿还的架构债并禁止新增第二套 Cover。
5. `.chat(threadID:)` 需要扩展为能够携带 `source`/`presentationContext`，不能只传 UUID；否则无法稳定决定 `heart.fill`、xmark 和关闭后的目标。

### 2.5 当前代码证据

- `SignedInMainTabHostView.swift:26-28` 已在登录后根宿主声明 `.fullScreenCover(item:)`，其生命周期高于任一 Tab 内容页。
- `SignedInMainTabHostView.swift:233-234` 已将 `.chat(threadID:)` 分派到统一 `chatFullScreenCover`。
- `SignedInMainTabHostView.swift:239-260` 已集中构造 `ChatView`、传入 Chat/Knowledge/Task/Home/AI/自动小任务依赖，并执行 Thread 选中与消息预加载。
- `HomePresentationSupport.swift:31-46` 显示当前 `HomeFullScreenCover.chat` 只有 threadID，缺少入口 source；这正是需要扩展而不是另建 Cover 的部分。

因此，本次需求应复用用户指出的 `SignedInMainTabHostView` 根链路。唯一需要修正的是它现在带有 `Home` 命名且 Chat case 信息不足，而不是它的宿主层级不合适。

## 三、根宿主统一 fullScreenCover 呈现模型

### 需求说明

只有自动进入来源的 ChatView 通过 presentation request 交给 `SignedInMainTabHostView` 的唯一 `.fullScreenCover(item:onDismiss:content:)` 展示。列表卡片和手动新建保留 `MainNavigationLink`/`pendingThreadNavigation + navigationDestination`，不新增局部 `.fullScreenCover`。

### 基础要求与业务规则

1. 在 App 呈现层建立稳定的展示值模型，至少包含 `threadID` 与 `source`；不使用两个互相独立的 `@State UUID?` + `@State Bool`。
2. `source` 只用于自动进入来源：自动恢复最近会话、自动新建会话；手动列表行/右上角新建/空态新建保留普通 NavigationDestination。
3. 自动来源在 UI 层归并为 `automatic`，并在日志/测试中保留 recent/new 细分；手动来源不进入根 Cover。
4. presentation `id` 不能只使用一个常量；应至少包含 threadID，防止不同 Thread 被 SwiftUI 视为同一张 Cover。
5. 列表行继续使用 `MainNavigationLink` 进入 ChatView，必须保留整行点击区、长按菜单、左右滑操作、无障碍和视觉样式。
6. 右上角新建和空态新建复用同一 `createThreadIfAvailable(source:)`，不各写一套新建/模型检查。
7. 用户点击列表行时不需检查“是否可新建模型”；打开历史对话应允许查看，发送时仍由 ChatView 现有逻辑校验可用模型。
8. 根 `fullScreenCover` 继续使用 `CompatibleNavigationContainer` 包裹 ChatView，保证 Toolbar 与 Chat 内部 `navigationDestination` 正常工作。
9. 展示前继续执行现有的 `selectThread(threadID)` 和 `loadMessagesIfNeeded(for:lockBottomViewport:)`；不得因呈现方式改造而删除预加载。
10. ChatView 自身 `.task(id: currentThreadID)` 仍作为幂等第二层保证，负责模型选择、图片传递模式、消息、guide card 和自动小任务初始化。
11. `chatAutoSmallTaskCoordinator` 等完整依赖继续由 `SignedInMainTabHostView.chatFullScreenCover` 统一传递；列表页不承担 ChatView 构造责任，禁止在改造中丢失自动小任务。
12. fullScreenCover 关闭后由根宿主将 active presentation 归零，不清理 Thread、消息缓存或 Composer 草稿。
13. `ChatConversationListPage` 只接收 `onPresentChat(request)`；不得直接持有或修改根宿主的 `@State`，也不得依赖 Home Feature 的具体枚举。

### 验收标准

- [ ] 只有自动恢复、自动新建使用根宿主 fullScreenCover。
- [ ] 列表卡片、右上角新建、空态新建继续通过 `pendingThreadNavigation`/`navigationDestination` 进入 ChatView。
- [ ] `ChatConversationListPage` 内不存在第二个 Chat fullScreenCover。
- [ ] 列表行的长按、滑动、编辑、置顶与删除行为不回归。
- [ ] 全屏 Chat 显示时底部 TabBar 不可见，关闭后正常恢复。
- [ ] 新建 Thread 首条 guide card、模型选择、草稿与消息缓存行为不变。

### 技术细节与设计代码位置

- 根呈现主改造文件：`SparkClient/Projects/App/Sources/App/SignedInMainTabHostView.swift` 与 `SparkClient/Projects/Features/Home/Presentation/HomePresentationSupport.swift`；列表入口改造文件为 `ChatConversationListPage.swift`。
- 当前程序化 push：`pendingThreadNavigation`、`.navigationDestination(isPresented:)`、`navigateToThread(_:)`。
- 当前手动 push：`threadRow(_:)` 中的 `MainNavigationLink`。
- presentation request 应放在 App/Chat 可共同访问但不反向依赖 Home UI 的位置；根 active cover 值模型属于 App 呈现层，不作为 `ChatConversationListPage` 私有类型。

## 四、自动进入决策保留与来源标记

### 需求说明

保留 `handleInitialAutoNavigationIfNeeded()` 现有决策与一次性语义，只把最后一步从“设置 NavigationStack destination”改为“向根宿主发送 fullScreenCover presentation request”，并正确标记 automatic 来源。

### 基础要求与业务规则

1. `.task` 仍按“先 `loadForListIfNeeded()`，后 `handleInitialAutoNavigationIfNeeded()`”执行。
2. `hasLoaded` 与 `hasHandledInitialAutoNavigation` 继续保证同一列表 View 生命周期仅处理一次自动进入。
3. `shouldSkipInitialAutoNavigation` 当前仅检查 `stateStore.draft(for:)` 的非空文本，本工单保持该现状，不扩大为附件/健康资源引用。
4. 命中最近 5 分钟活跃 Thread 时，使用 `.automaticRecentThread` 来源。
5. 无活跃 Thread 并成功新建时，使用 `.automaticNewThread` 来源。
6. 无可用 Chat 模型时继续在列表页显示现有 alert 和 API Key Sheet，不创建 Thread，不打开 Cover。
7. 本工单不改变 API Key Sheet 关闭后是否自动重试的产品行为；按当前实现，关闭后留在列表，用户可再次新建。
8. 用户点主页按钮回到首页后，再次切换到同一对话 Tab View 时，不重复执行本生命周期已处理的自动进入；页面被销毁并重建时可按现有规则重新执行。
9. 自动决策完成后需记录 source、thread 短 ID、是否新建，不记录用户消息或草稿内容。

### 验收标准

- [ ] 有未发文本草稿时仍停留列表，不显示 Cover。
- [ ] 有 5 分钟内活跃会话时，自动全屏打开该 Thread，来源为 automatic recent。
- [ ] 无活跃会话时仅新建 1 个 Thread，再全屏打开，来源为 automatic new。
- [ ] 同一列表 View 生命周期内，主页返回后再点对话 Tab 不立即重复自动弹 Cover。
- [ ] 无模型时不会先显示空白 ChatView。

### 技术细节与设计代码位置

- 首次加载：`ChatConversationListPage.swift` 的 `.task`。
- 自动决策：`handleInitialAutoNavigationIfNeeded()`。
- 跳过判定：`shouldSkipInitialAutoNavigation`。
- 最近会话：`mostRecentActiveThreadID(within:)`。
- 新建并检查模型：`createThreadIfAvailable()` 与 `ChatDetailViewModel.hasAvailableChatModel()`。

## 五、ChatView 左上角主页/关闭操作

### 需求说明

扩展 `ChatView` 已有的全屏 leading action 能力，使其可按展示来源在左上角显示关闭或主页按钮。`ChatView` 只渲染语义与回调，不直接修改 `AppRouteStore`。

### 基础要求与业务规则

1. 自动来源：`ToolbarItem(placement: .topBarLeading)` 显示 `Image(systemName: "heart.fill")`。
2. 主页按钮 accessibility label 为“返回首页”，hint 为“关闭当前对话并切换到健康首页”，文案进入简体中文、繁体中文和英文本地化。
3. 主页按钮的颜色使用 `Color.accentColor`/项目统一导航颜色，可点区不小于 44×44 pt，不使用非系统的乱序心形资源。
4. 普通 NavigationStack push 场景（列表卡片、手动新建）：不显示额外 heart/xmark，继续使用系统返回。
5. 只有 automatic source 的根 fullScreenCover 显示 `heart.fill`。
6. 不建议增加 `showHomeButton` + `showCloseButton` + `isFullScreen` 三个布尔参数；应使用互斥枚举/展示上下文，保证同一时间最多一个 leading action。
7. 右上角现有“新建对话”和设置 Menu 保持不变，不把主页按钮放到 trailing 与其们竞争。
8. ChatView 内部点击右上角“新建对话”后，即使 `activeThreadID` 已切换，头部来源语义仍保留：最初是自动入口则继续显示主页按钮。
9. 若 `stateStore.isSending == true`，点击主页按钮复用已有“停止并关闭”确认，但相关文案应根据目标语义显示“停止并返回首页”，不得只写“关闭”造成含糊。
10. 全屏 Chat 生成中必须禁止交互式下滑 dismiss，避免绕过取消生成与消息收尾。未发送/非生成状态可交互关闭，交互关闭只回列表，不触发主页跳转。

### 验收标准

- [ ] 自动恢复和自动新建的 ChatView 左上角都显示 `heart.fill`。
- [ ] 手动列表行/手动新建显示 `xmark.circle.fill`，不显示 heart。
- [ ] 普通 AppRoute `.chatThread` push 不出现额外按钮。
- [ ] VoiceOver 正确播报“返回首页”而不是“心形填充”。
- [ ] 生成中点主页会先确认、停止生成，不留悬挂的 assistant message。

### 技术细节与设计代码位置

- 当前 leading close 位置：`SparkClient/Projects/Features/Chat/Presentation/ChatView.swift` 的 `.toolbar` 中 `if let onClose` 分支。
- 当前生成中关闭确认：同文件 `showCloseChatConfirmation` alert。
- 建议将 `onClose` 扩展为可表达 `.close` / `.home` 的单一 leading action 语义，或保留回调同时增加互斥样式枚举。
- ChatView 不引入 `AppRouteStore`，避免对话 Feature 直接控制 App 根路由。

## 六、关闭 Cover 后切换健康首页

### 需求说明

主页按钮的终态不是“显示对话列表”，而是“关闭全屏 Chat，切换底部 Tab 到健康首页根页面”。该跨 Feature 操作由 `SignedInMainTabHostView` 与 `AppRouteStore` 协作完成；`ChatConversationListPage` 不直接控制根路由。

### 基础要求与业务规则

1. 点击主页按钮时，由根宿主先记录一个一次性 post-dismiss intent（例如 `goHome`），再将 active presentation 设为 nil。
2. 不在 Cover 仍处于 presented 状态时立即修改 `selectedTab`；虽然根宿主不会随 Tab 切换销毁，仍应保持“先 dismiss、后 route”的确定时序。
3. 在 `SignedInMainTabHostView.fullScreenCover(..., onDismiss:)` 的 `onDismiss` 中消费一次性 intent，执行 `routeStore.route(to: .home, replaceStack: true)`。
4. 使用 `.home` 根 route 而不是手工写 magic raw value `0`。`.home.rootTab` 已映射到 `AppRouteStore.RootTab.healthHome`；`replaceStack: true` 保证落在首页根层，不恢复健康 Tab 中之前 push 的医疗详情。
5. 路由操作会同步更新 `selectedTab` 并通过 `RootTabPreferenceStore` 持久化 `.healthHome`，这是现有 `AppRouteStore.selectedTab.didSet` 的既有语义。
6. 普通 xmark 关闭、交互下滑、系统 dismiss 不设置 `goHome` intent，`onDismiss` 后继续留在 Chat Tab 列表。
7. `goHome` intent 必须在消费后立即清理；不得影响下一次手动关闭的全屏会话。
8. 账号切换、根宿主销毁或准备任务取消时清理 active presentation 与 post-dismiss intent，不在新账号误切首页；列表页销毁不应破坏已呈现 Cover 的关闭收尾。

### 验收标准

- [ ] 点击 heart 后先看到 Cover 正常关闭，再切换到健康首页。
- [ ] 健康首页没有残留医疗详情 NavigationStack。
- [ ] 手动打开的会话点 xmark 后回对话列表，不切首页。
- [ ] 交互下滑关闭不切首页。
- [ ] 连续执行“自动进入 → heart 回首页 → 手动打开 → xmark”时，第二次关闭不会被上一次的 goHome intent 污染。

### 技术细节与设计代码位置

- Tab 枚举与持久化：`SparkClient/Projects/App/Sources/App/AppRouteStore.swift`。
- `.home` 映射：`AppRoute.rootTab` 中 `.home → .healthHome`。
- 根路由 API：`AppRouteStore.route(to:replaceStack:)`。
- 呈现请求注入点：`IOS26TabBarView.chatContainer`、`MainTabCoordinatorView.chatTab`；Cover 与路由执行点：`SignedInMainTabHostView`。

## 七、两种 Tab 宿主与现有全屏 Chat 的协作

### 需求说明

同时支持 `IOS26TabBarView` 和 `MainTabCoordinatorView` 两条真实宿主路径，不得只在其中一个 Tab 容器有效。复用 `CHAT-000037` 已建立的 App 级健康资源全屏 Chat 宿主与依赖组装，但通过 presentation source 保持不同入口的返回语义。

### 基础要求与业务规则

1. 两个 Tab 宿主都向 `ChatConversationListPage` 注入同一个 `onPresentChat` action；该 action 最终写入 `SignedInMainTabHostView` 的 App 级 active cover。
2. 对话列表不自建 Cover，复用 `SignedInMainTabHostView.activeHomeFullScreenCover` 所在的唯一呈现通道。建议同步将该状态和 `homeFullScreenCoverContent` 重命名为 App 级名称，避免继续误认为仅服务首页。
3. `CHAT-000037` 的病历/体检/处方等详情入口继续使用同一个 App 宿主 Chat case；其 source 为健康资源详情，左上角关闭回原详情，不显示本工单的自动入口 heart。
4. 由 `AppRouteStore.route(to: .chatThread(...))` 打开的程序化 Chat 仍走 `MainTabRouteDestinationBuilder`，不被本工单的根 Cover 流程拦截。
5. 根宿主同一时间只允许一个 active full-screen cover。若健康资源请求、上传或外部 App route 在 Chat Cover 显示时到达，应由统一 presenter 拒绝、排队或先关闭后消费，不重叠呈现。
6. 根 Cover 消失不应修改 `routeStacks[.chat]`，因为该展示不是 Chat Tab NavigationStack 的一层。

### 验收标准

- [ ] iOS 26 Tab 和经典 Tab 都能自动全屏打开对话。
- [ ] 两个宿主点 heart 都切到各自的健康首页 Tab。
- [ ] 病历详情全屏 Chat 仍可关闭回病历详情，不被修改为回首页。
- [ ] AppRoute `.chatThread` 路由仍可 push 并使用系统返回。
- [ ] 不出现根 Cover 与列表 Cover 两套实现、两层 ChatView、两个键盘或两个工具 Sheet。

### 技术细节与设计代码位置

- iOS 26 对话容器：`SparkClient/Projects/App/Sources/App/IOS26TabBarView.swift` 的 `chatContainer`。
- 经典对话 Tab：`SparkClient/Projects/App/Sources/App/MainTabCoordinatorView.swift` 的 `chatTab`。
- App 级对话 route：`SparkClient/Projects/App/Sources/App/MainTabRouteDestinationBuilder.swift`。
- 统一全屏宿主：`SparkClient/Projects/App/Sources/App/SignedInMainTabHostView.swift`。

## 八、整体业务流程

```text
用户进入对话 Tab
  ↓
ChatConversationListPage.task（本 View 生命周期仅一次）
  ↓
ChatListViewModel.loadForListIfNeeded()
  ↓
handleInitialAutoNavigationIfNeeded()
  ├── 当前选中 Thread 有非空文本草稿
  │     → 停留对话列表
  ├── 存在 5 分钟内活跃 Thread
  │     → presentThread(threadID, source: automaticRecentThread)
  └── 无活跃 Thread
        → hasAvailableChatModel()
        ├── 不可用 → alert / API Key Sheet / 留在列表
        └── 可用 → createThread()
              → presentThread(threadID, source: automaticNewThread)

presentThread
  ↓
listViewModel.selectThread(threadID)
  ↓
detailViewModel.loadMessagesIfNeeded(lockBottomViewport: true)
  ↓
onPresentChat(threadID, source)
  ↓
SignedInMainTabHostView.activeFullScreenCover = chat(threadID, source)
  ↓
SignedInMainTabHostView.fullScreenCover
  ↓
CompatibleNavigationContainer → ChatView
  └── automatic source → 左上角 heart.fill

用户点 heart.fill
  ↓
若正在生成，先确认并停止生成
  ↓
根宿主 postDismissIntent = goHome
  ↓
根宿主 active presentation = nil
  ↓
根宿主 fullScreenCover.onDismiss
  ↓
routeStore.route(to: .home, replaceStack: true)
  ↓
selectedTab = .healthHome，健康首页根栈
```

### 8.1 手动打开路径

```text
列表行 / 右上角新建 / 空态新建
  ↓
presentThread(threadID, source: manual...)
  ↓
NavigationDestination → ChatView（系统返回）
  ↓
系统返回
  ↓
退出当前 ChatView，不设置 goHome
  ↓
回到对话列表
```

### 8.2 失败、重试与恢复

- 列表加载失败：保留现有 empty/syncing/error 语义，不展示 Cover。
- 无模型：保留 alert/API Key Sheet，不建 Thread。
- Thread 创建失败：停留列表，不展示空 ChatView。
- 历史 Thread 在预加载期间被删除：取消展示并刷新列表，不打开错误 Thread。
- Cover 呈现失败/被系统取消：根宿主清理 presentation 与 post-dismiss intent，留在当前 Tab。

### 8.3 取消、并发和幂等

- 展示准备中连点：列表页同一时间只发出一个 request；根宿主同一时间只接受一个 active presentation。
- Cover 已显示时点其他列表行在 UI 上不可达，不会重入。
- ChatView 内新建 Thread 继续原地切换，不建第二层 Cover。
- heart 点击只设置一次 goHome，`onDismiss` 只消费一次。

## 九、状态模型

| 状态 | 进入条件 | 用户可见结果 | 退出条件 |
| --- | --- | --- | --- |
| `listIdle` | 列表可见，无准备/展示 | 对话列表 | 自动决策或用户点击 |
| `loadingList` | 首次加载/刷新 | syncing/列表状态 | 加载完成/失败 |
| `checkingModel` | 自动/手动新建 | 列表保持可见 | 可用/不可用 |
| `creatingThread` | 模型可用 | 新建入口 loading/禁用 | 创建成功/失败 |
| `preparingThread` | 已有 threadID，选中/预加载 | 列表仍可见但入口禁用 | presentation 就绪/失败 |
| `presentingAutomaticChat` | automatic presentation 非空 | 全屏 Chat + heart | heart/xmark 确认/系统关闭 |
| `presentingManualChat` | NavigationDestination 已 push | ChatView + 系统返回 | 系统返回 |
| `confirmingStop` | 生成中点 leading action | 停止确认 alert | 继续/停止 |
| `dismissingForHome` | goHome intent 已设置 | Cover 正在消失 | onDismiss |
| `switchingHomeTab` | Cover 已消失 | 健康首页 | route 完成后回 idle |
| `failed` | 创建/准备/路由异常 | 列表错误提示 | 确认/重试 |

必须维持下列互斥约束：

- 根宿主 active Chat presentation 非空时不得同时展示 API Key Sheet 或会话外观编辑 Sheet。
- `goHome` 只能与 automatic presentation 的显式 heart 操作关联。
- `pendingThreadNavigation` 仅用于手动新建的 NavigationDestination；自动进入不使用它。

## 十、数据与持久化

| 数据 | 所有者 | 存储位置 | 生命周期 | 清理时机 |
| --- | --- | --- | --- | --- |
| Thread 列表/当前 Thread | `ChatStateStore` + Chat Repository | 现有内存读模型/Core Data | 账号会话周期 | 删除 Thread/账号清理 |
| 消息缓存 | `ChatStateStore` | 按 threadID 的运行时缓存 + Repository | 会话周期 | 清空、删除、账号切换 |
| Composer 草稿 | `ChatStateStore` | 当前运行期按 threadID 存储 | App 运行期 | 清草稿/账号切换 |
| active presentation | `SignedInMainTabHostView` | SwiftUI `@State` | 单次 Cover | dismiss/根宿主销毁/账号切换 |
| presentation source | active presentation 值 | 不持久化 | 单次 Cover | 随 presentation 清理 |
| post-dismiss intent | `SignedInMainTabHostView` | SwiftUI 瞬时状态 | 从按钮点击到 onDismiss | 消费、取消、账号切换 |
| 根 Tab 选中态 | `AppRouteStore` | `RootTabPreferenceStore`/UserDefaults | 设备级 | selectedTab 下次变更 |
| Chat Tab route stack | `AppRouteStore` | 内存 routeStacks | 账号路由周期 | `resetRouteGraph`/显式替换 |

本工单只改变页面呈现状态，不改变 Thread、消息或草稿持久化协议。presentation source 不写入 Thread 或消息数据库。

## 十一、错误模型

| 错误类别 | 触发条件 | 是否重试 | 用户反馈 | 清理动作 |
| --- | --- | --- | --- | --- |
| 列表加载失败 | 本地/远程加载失败 | 是 | 保留列表失败/空态 | 不创建 presentation |
| 无可用模型 | 新建前 chat models 为空 | 配置后手动重试 | 现有 alert/API Key Sheet | 不建 Thread、不弹 Cover |
| Thread 创建失败 | 本地 Repository/用例失败 | 是 | 新建失败提示 | 清准备状态 |
| Thread 已删除 | 点击后预加载找不到 | 刷新后可 | 该对话已不存在 | 清 presentation，刷新列表 |
| Cover 冲突 | API Key/外观 Sheet 正在显示 | 关闭后可 | 保持当前 Sheet | 不重叠呈现 |
| 生成中交互 dismiss | 下滑尝试绕过确认 | 否 | 拒绝 dismiss，使用头部按钮 | 不改状态 |
| 主页路由时序错误 | Cover 未 dismiss 就切 Tab | 是 | 应不可见 | 依赖 onDismiss 消费 intent |
| 残留 goHome | intent 未清理污染下次 dismiss | 否 | 应不可见 | onDismiss 原子读取并清空 |
| 账号切换 | Cover 显示期间 accountID 改变 | 否 | 关闭会话并进入新账号 | 清 presentation/intent/任务 |

## 十二、与其他模块的接口边界

### 12.1 本模块负责

- 对话列表负责手动/自动入口决策并发出 Chat presentation request。
- `SignedInMainTabHostView` 负责唯一 fullScreenCover、ChatView 组装、展示互斥与 dismiss 收尾。
- 展示来源标记和左上角 leading action 选择。
- 先 dismiss 再切健康首页的跨 Tab 时序。
- 两种 Tab 宿主的依赖注入与行为一致性。

### 12.2 本模块不负责

- 不改变会话列表数据、搜索、排序、置顶、删除和外观编辑业务。
- 不改变模型/API Key 可用性规则。
- 不改变 ChatView Thread 内新建和 `activeThreadID` 切换。
- 不改变健康资源全屏 Chat 返回原详情的行为。
- 不替换 `AppRouteStore` 的 Tab 持久化方案。

### 12.3 上游调用方

- `IOS26TabBarView.chatContainer`。
- `MainTabCoordinatorView.chatTab`。

### 12.4 下游依赖

- `ChatListViewModel`、`ChatDetailViewModel`、`ChatStateStore`。
- `ChatView`、`CompatibleNavigationContainer`。
- `AppRouteStore`、`RootTabPreferenceStore`。

### 12.5 输入和输出契约

| 方向 | 契约 |
| --- | --- |
| 呈现输入 | threadID + presentation source |
| 手动关闭输出 | dismiss Cover，留在 Chat Tab |
| 主页按钮输出 | dismiss Cover → `.home` root route → `.healthHome` Tab |
| 失败输出 | 不展示 Cover，在列表页提示/保留现有空态 |

## 十三、关键代码对应关系

| 能力 | 入口/UI | 编排/状态 | Domain/Repository | 基础设施 | 测试 |
| --- | --- | --- | --- | --- | --- |
| 列表请求全屏呈现 | `ChatConversationListPage.swift` | present request（threadID/source） | 当前未单独分层 | 注入 action/protocol | 当前无专项测试 |
| App 级全屏呈现 | `SignedInMainTabHostView.swift` | active presentation/source/post-dismiss intent | 当前 `HomeFullScreenCover.chat` | SwiftUI `fullScreenCover` | 当前无专项测试 |
| 自动进入 | 列表 `.task` | `handleInitialAutoNavigationIfNeeded` | `ChatStateStore.threadItems` | 无新 API | 当前无专项测试 |
| 新建对话 | 右上/空态/自动 | `createThreadIfAvailable` | `CreateChatThreadUseCase`/Chat Repository | Core Data + 现有同步 | 现有 guide/thread 测试，缺呈现来源测试 |
| 全屏 leading action | `ChatView.swift` Toolbar | presentation context | 当前未单独分层 | SwiftUI Toolbar/alert | 当前无专项测试 |
| 切换首页 | heart 按钮 | post-dismiss intent | `AppRoute`/`AppRouteStore` | `RootTabPreferenceStore` | `AppRouteStoreSelectedTabPersistenceTests.swift` |
| 两种 Tab 宿主 | `IOS26TabBarView` / `MainTabCoordinatorView` | 依赖注入 | `MainTabDependencies` | TabView/Navigation container | 当前无集成测试 |

## 十四、测试策略

### 14.1 已有测试

- `SparkClient/Tests/App/AppRouteStoreSelectedTabPersistenceTests.swift` 覆盖默认 Tab、`.healthHome` 持久化、非法 Tab 回退和样式可见集合。
- `SparkClient/Tests/Chat/` 已有新建 Thread、guide card、成员绑定、并发和架构门禁测试，可用于确认呈现改造未破坏 Chat 业务链。

### 14.2 当前测试缺口

1. `ChatConversationListPage` 自动决策的独立可测试结果。
2. automatic/manual source 到 heart/xmark 的映射。
3. 根宿主 fullScreenCover dismiss 后才路由首页的时序。
4. goHome intent 一次性消费和污染防护。
5. 生成中禁止交互 dismiss、停止并回首页收尾。
6. iOS 26 与经典 Tab 的一致性。
7. 列表行从 Link 改 Button 后的 context menu/swipe/accessibility 回归。

### 14.3 建议补充测试

| 类型 | 建议用例 |
| --- | --- |
| 自动决策单元测试 | 草稿跳过、5 分钟临界、最近 Thread、无 Thread 新建、无模型 |
| presentation 映射测试 | automatic recent/new → home；manual row/new/empty → close |
| 根 presenter 测试 | 同时只接受一个 active cover；Chat request 正确携带 thread/source；与健康资源 Cover 互斥 |
| dismiss coordinator 测试 | heart → dismiss → home；xmark/swipe → dismiss only；intent 消费一次 |
| AppRouteStore 测试 | `.home, replaceStack: true` 选中 healthHome 并清空健康栈 |
| ChatView Toolbar 测试 | 三种上下文：home/close/system back；同时仅一个 leading action |
| UI 测试 | 入 Chat Tab 自动全屏、heart 回首页、手动会话 xmark 回列表、TabBar 恢复 |
| 回归测试 | 列表长按/滑动、Chat 内新建、guide card、草稿、工具 Sheet |

### 14.4 验收矩阵

| 入口场景 | 呈现 | 左上角 | 退出结果 |
| --- | --- | --- | --- |
| Tab 首次进入 + 5 分钟内活跃 Thread | fullScreenCover | `heart.fill` | 健康首页根层 |
| Tab 首次进入 + 无活跃 Thread + 模型可用 | 新建后 fullScreenCover | `heart.fill` | 健康首页根层 |
| Tab 首次进入 + 有文本草稿 | 不展示 | 无 | 留对话列表 |
| Tab 首次进入 + 无可用模型 | 不展示 | 无 | alert/API Key Sheet |
| 点击历史会话行 | NavigationDestination | 系统返回 | 对话列表 |
| 右上角手动新建 | NavigationDestination | 系统返回 | 对话列表 |
| 空态手动新建 | NavigationDestination | 系统返回 | 对话列表 |
| AppRoute `.chatThread` | NavigationStack push | 系统返回 | 上一层 App route |
| 医疗详情快捷对话 | App 级 fullScreenCover | `xmark.circle.fill` | 原医疗详情 |

## 十五、当前实现、缺口与演进

### 15.1 当前实现

- `ChatConversationListPage` 已实现会话列表、搜索、新建、无模型引导、会话管理和首次自动进入决策。
- 自动进入已使用两个一次性状态防止同一 View 生命周期重复执行。
- 自动路径已在设置 destination 前选中 Thread 并预加载消息。
- `ChatView` 已有可选 `onClose`、左上角 xmark 和生成中关闭确认（来自 `CHAT-000037` 的当前工作区实现）。
- `SignedInMainTabHostView` 已持有 `activeHomeFullScreenCover`，并通过 `homeFullScreenCoverContent` / `chatFullScreenCover` 统一组装全屏 ChatView、注入完整依赖和预加载消息；这是本工单推荐复用的基础。
- `AppRouteStore` 已实现 `.home → .healthHome`、route stack 替换和 selectedTab 持久化。
- `IOS26TabBarView` 与 `MainTabCoordinatorView` 都由同一账号级 `routeStore` 管理 Tab 选中。

### 15.2 当前缺口

1. 自动进入已改为根宿主 fullScreenCover。
2. 列表行继续使用 `MainNavigationLink` push `ChatView`；手动新建使用 `pendingThreadNavigation`。
3. `ChatConversationListPage` 已输出带 source 的 App 级 Chat presentation request，仅自动来源消费该 request。
4. 根 `HomeFullScreenCover.chat` 当前只携带 threadID，无法表达 automatic/manual/health-resource 来源；命名也仍局限于 Home。
5. `ChatView` 已有 close 语义，但尚无 home leading action 语义和 `heart.fill`。
6. 根宿主尚无“Cover 完全 dismiss 后再切 Tab”的一次性时序状态。
7. 尚无 automatic/manual 来源映射与专项测试。
8. 生成中交互 dismiss 的禁用行为尚未在根 fullScreenCover 场景定义。

### 15.3 建议演进

1. 将自动决策输出与 SwiftUI 展示解耦：列表只输出 threadID/source，App 根宿主决定 Cover。
2. 将 ChatView leading action 收口为一个互斥模型，便于后续扩展“回列表”、“回首页”、“回业务详情”而不增加布尔参数。
3. 本期直接复用根宿主已有 `chatFullScreenCover` 组装点；长期再将普通 AppRoute Chat 与根 Cover 的 ChatView 依赖组装抽成单一 builder，降低新依赖漏传风险。
4. 将 `HomeFullScreenCover` 演进为 App 级命名和值模型，为后续体检报告、医疗报告、处方、用药、药箱等快捷入口保留统一 source/context 扩展位。

### 15.4 建议实施顺序

1. 定义中立的 Chat presentation request/source，并将 `HomeFullScreenCover` 提升/重命名为 App 级 active cover 值模型。
2. 为两个 Tab 宿主注入 `onPresentChat` action，仅自动进入消费该 action；手动列表行/新建保留 NavigationDestination。
3. 扩展根 `chatFullScreenCover` 读取 source，继续复用现有 ChatView 完整依赖组装与预加载。
4. 扩展 ChatView leading action，实现 heart/xmark/system back 互斥。
5. 在根宿主接入 fullScreenCover dismiss 后通过 `AppRouteStore` 返回首页的链路。
6. 保留手动 Chat push 入口，同步本地化、日志和测试。

## 十六、整体验收标准

### 16.1 主流程验收

- [ ] 进入对话 Tab 后，自动恢复或自动新建的 ChatView 使用 fullScreenCover，不 push。
- [ ] 自动打开的 ChatView 左上角显示 `heart.fill`。
- [ ] 点击 heart 先关闭 Cover，再切到 `.healthHome` 根页面。
- [ ] 自动进入现有草稿跳过、5 分钟恢复、无活跃新建规则不变。

### 16.2 手动入口验收

- [ ] 列表卡片、右上角新建、空态新建通过 NavigationDestination 进入 ChatView。
- [ ] 手动入口使用系统返回，不显示本工单的自动入口 heart。
- [ ] 手动关闭不会意外切到健康首页。
- [ ] 列表行保留 MainNavigationLink 后，长按、左右滑、置顶、编辑、删除不回归。

### 16.3 状态与稳定性验收

- [ ] 同一时间只有一个 ChatView，不叠加 Cover/Navigation destination。
- [ ] `ChatConversationListPage` 不声明第二个 Chat fullScreenCover，根 active cover 是唯一事实源。
- [ ] 不会因 body 重算、连点、Cover 关闭或 Thread 内新建而重复弹窗。
- [ ] 生成中不能通过交互下滑绕过停止确认。
- [ ] 主页 post-dismiss intent 仅消费一次，不污染下一次会话关闭。
- [ ] 账号切换会取消呈现并清理瞬时状态。

### 16.4 兼容性验收

- [ ] `IOS26TabBarView` 与 `MainTabCoordinatorView` 行为一致。
- [ ] AppRoute `.chatThread` 仍走现有程序化 push，使用系统返回。
- [ ] `CHAT-000037` 医疗资源 full-screen Chat 仍关闭回原详情，不显示主页 heart。
- [ ] `HomeFullScreenCover` 已重命名为 App 级名称，或建立明确的兼容迁移说明且不新增局部 Cover。
- [ ] Chat 内新建 Thread、guide card、模型选择、自动小任务、工具 Sheet、Composer 和消息列表不回归。

## 十七、实施前确认清单

- [ ] 产品确认主页按钮使用 `heart.fill`，不增加“首页”文字标签。
- [ ] 产品确认主页返回会清空健康 Tab 已有导航栈，使用 `.home, replaceStack: true`。
- [ ] 开发确认 fullScreenCover 生成中使用 `.interactiveDismissDisabled(true)` 或等价动态策略。
- [ ] 开发确认采用“列表决策、根宿主呈现”，不在 `ChatConversationListPage` 内新增 fullScreenCover。
- [ ] 开发确认对话列表实例在 Tab 切换后的实际存活行为，并按“同 View 生命周期仅自动一次”验收。
- [ ] QA 准备至少一个有最近会话、一个无会话、一个无模型、一个有未发文本草稿的账号场景。
