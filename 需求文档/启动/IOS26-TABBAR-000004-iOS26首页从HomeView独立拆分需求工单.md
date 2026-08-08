# IOS26-TABBAR-000004：iOS 26 首页从 HomeView 独立拆分需求工单

> 创建日期：2026-08-07  
> 关联模块：iOS26TabBarView、HomeView、IOS26HomeDashboardView、IOS26HomeTaskSummaryView、LaunchIntent、HomeSheet、HomeFullScreenCover  
> 关联代码：`SparkClient/Projects/Features/Home/Presentation/HomeView.swift:1-1051`、`SparkClient/Projects/App/Sources/App/IOS26TabBarView.swift`、`SparkClient/Projects/Features/Home/Presentation/IOS26HomeDashboardView.swift`、`SparkClient/Projects/Features/Home/Presentation/IOS26HomeTaskSummaryView.swift`  
> 状态：已实现  
> 优先级：P0，结构纠偏

## 1. 一句话目标

将 iOS 26 首页从当前 `HomeView.swift` 中彻底独立出来，新增单独的 iOS 26 首页根视图文件，不再把 iOS 26 首页逻辑融入现有 `HomeView`。`HomeView` 继续作为旧版首页/兼容首页，`IOS26TabBarView` 的首页 Tab 直接承载新的 iOS 26 首页。

## 2. 背景

当前 `HomeView.swift` 已经开始混入 iOS 26 首页逻辑：

```swift
var ios26DashboardActionHandler: IOS26HomeDashboardActionHandler?
var deepTutorChatViewModel: DeepTutorChatViewModel?

@ViewBuilder
private var homeScrollBody: some View {
    if #available(iOS 26.0, *),
       let actionHandler = ios26DashboardActionHandler,
       let deepTutorChatViewModel {
        IOS26HomeDashboardView(...)
    } else {
        legacyHomeScrollBody
    }
}
```

这会导致 `HomeView` 同时承担两套首页：

1. 旧版首页：医疗信息、营养、模块维护、成员选择、上传、启动意图消费。
2. iOS 26 首页：工作台、DeepTutor 快捷入口、代办任务摘要、iOS 26 视觉层。

这种混合会让文件越来越重，也会让后续维护者不清楚 `HomeView` 到底是旧首页还是 iOS 26 首页的宿主。

## 3. 现状问题

### 3.1 HomeView 职责膨胀

当前 `HomeView.swift:1-1051` 已经包含：

1. 首页生命周期。
2. Launch Intent 消费。
3. Sheet / fullScreenCover 管理。
4. 旧首页滚动内容。
5. 成员选择栏。
6. 医疗信息板块。
7. 营养信息板块。
8. 模块维护板块。
9. iOS 26 首页条件分支。
10. iOS 26 首页 action handler 注入。
11. DeepTutorChatViewModel 注入。
12. TaskManager 同步逻辑。

继续把 iOS 26 首页塞在 `HomeView` 内，会让这个文件变成双首页中控。

### 3.2 iOS 26 首页和旧首页生命周期不同

iOS 26 首页需要：

1. 首页工作台布局。
2. 代办任务模块。
3. DeepTutor 快捷建会话。
4. 三 Tab 导航下的首页语义。
5. iOS 26 Liquid Glass 滚动边缘适配。

旧 `HomeView` 主要服务：

1. 旧主 Tab 下的首页。
2. 既有医疗卡片与模块维护。
3. 旧版顶部成员选择栏。

两者可以复用依赖和页面能力，但不应该共用同一个 root View。

### 3.3 依赖方向不干净

`HomeView` 当前已经为了 iOS 26 引入：

```swift
IOS26HomeDashboardActionHandler?
DeepTutorChatViewModel?
TaskManager
```

旧首页本不应该关心 DeepTutor 快捷入口，也不应该知道 iOS 26 dashboard action handler。

## 4. 目标

1. 新增独立 iOS 26 首页根视图文件。
2. `IOS26TabBarView` 的首页 Tab 直接使用新 iOS 26 首页。
3. `HomeView.swift` 移除 iOS 26 条件分支。
4. `HomeView.swift` 移除 `ios26DashboardActionHandler`、`deepTutorChatViewModel` 等 iOS 26 专属注入。
5. `HomeView.swift` 不再引用 `IOS26HomeDashboardView`。
6. 旧首页行为保持不变。
7. iOS 26 首页仍保留必要的 sheet、cover、Launch Intent、上传、成员详情能力，但由 iOS 26 首页自己的 root 承担或通过共享组件承接。

## 5. 非目标

1. 本工单不重做 iOS 26 首页 UI。
2. 本工单不删除 `IOS26HomeDashboardView`。
3. 本工单不删除 `IOS26HomeTaskSummaryView`。
4. 本工单不改 DeepTutor 快捷会话业务。
5. 本工单不改任务中心业务。
6. 本工单不改旧首页的医疗/营养/模块维护逻辑。

## 6. 推荐文件结构

### 6.1 新增 iOS 26 首页根视图

新增文件：

```text
SparkClient/Projects/Features/Home/Presentation/IOS26HomeView.swift
```

职责：

1. iOS 26 首页 root。
2. 承载 `IOS26HomeDashboardView`。
3. 管理 iOS 26 首页需要的 sheet / fullScreenCover。
4. 管理 iOS 26 首页需要的 Launch Intent host readiness。
5. 处理外部医疗文档导入、上传成功刷新、成员详情打开。
6. 管理任务摘要刷新。

### 6.2 保留 iOS 26 首页内容组件

保留已有文件：

```text
SparkClient/Projects/Features/Home/Presentation/IOS26HomeDashboardView.swift
SparkClient/Projects/Features/Home/Presentation/IOS26HomeDashboardActionHandler.swift
SparkClient/Projects/Features/Home/Presentation/IOS26HomeTaskSummary.swift
SparkClient/Projects/Features/Home/Presentation/IOS26HomeTaskSummaryView.swift
```

这些文件属于 iOS 26 首页内部模块，不再被 `HomeView` 直接引用。

### 6.3 HomeView 回归旧首页

`HomeView.swift` 只保留旧首页职责：

```text
HomeView.swift
├── legacy home root
├── legacyHomeScrollBody
├── medicalInfoSection
├── nutritionInfoSection
├── moduleMaintenanceSection
├── HomeSheet
├── HomeFullScreenCover
└── LaunchIntent lifecycle for legacy home
```

不要再出现：

```text
IOS26HomeDashboardView
IOS26HomeDashboardActionHandler
deepTutorChatViewModel
if #available(iOS 26.0, *)
```

## 7. 关键改造范围

### 7.1 HomeView.swift 必须移除的内容

从 `SparkClient/Projects/Features/Home/Presentation/HomeView.swift:1-1051` 中移除以下 iOS 26 融入内容：

```swift
var ios26DashboardActionHandler: IOS26HomeDashboardActionHandler?
var deepTutorChatViewModel: DeepTutorChatViewModel?
```

从 init 中移除：

```swift
ios26DashboardActionHandler: IOS26HomeDashboardActionHandler? = nil
deepTutorChatViewModel: DeepTutorChatViewModel? = nil
```

从 init body 中移除：

```swift
self.ios26DashboardActionHandler = ios26DashboardActionHandler
self.deepTutorChatViewModel = deepTutorChatViewModel
```

移除当前 `homeScrollBody` 中的 iOS 26 分支：

```swift
if #available(iOS 26.0, *),
   let actionHandler = ios26DashboardActionHandler,
   let deepTutorChatViewModel {
    IOS26HomeDashboardView(...)
} else {
    legacyHomeScrollBody
}
```

回退为：

```swift
private var homeScrollBody: some View {
    legacyHomeScrollBody
}
```

或直接把 `legacyHomeScrollBody` 改回 `homeScrollBody`。

### 7.2 IOS26TabBarView 必须调整的内容

当前 `IOS26TabBarView.homeContainer` 不应再承载 `HomeView(...)`。

改造前：

```swift
private var homeContainer: some View {
    CompatibleRouteNavigationContainer(path: routePath(.home)) {
        HomeView(
            dependencies: homeDependencies,
            viewModel: homeViewModel,
            medicalDocumentUploadViewModel: medicalDocumentUploadViewModel,
            externalMedicalDocumentImportCoordinator: externalMedicalDocumentImportCoordinator,
            launchIntentCoordinator: launchIntentCoordinator,
            session: session,
            ios26DashboardActionHandler: homeDashboardActionHandler,
            deepTutorChatViewModel: deepTutorChatViewModel
        )
    } destination: { route in
        destinationBuilder.destination(route)
    }
}
```

改造后：

```swift
private var homeContainer: some View {
    CompatibleRouteNavigationContainer(path: routePath(.home)) {
        IOS26HomeView(
            dependencies: homeDependencies,
            viewModel: homeViewModel,
            taskManager: taskManager,
            medicalDocumentUploadViewModel: medicalDocumentUploadViewModel,
            externalMedicalDocumentImportCoordinator: externalMedicalDocumentImportCoordinator,
            launchIntentCoordinator: launchIntentCoordinator,
            session: session,
            actionHandler: homeDashboardActionHandler,
            deepTutorChatViewModel: deepTutorChatViewModel
        )
    } destination: { route in
        destinationBuilder.destination(route)
    }
}
```

### 7.3 新 IOS26HomeView 必须承接的能力

`IOS26HomeView` 不能只是一个 UI 包装层。它要承接原先 `HomeView` 为首页宿主承担的必要能力：

1. `launchIntentConsumer.setHomeHostReady(true/false)`。
2. `requestLaunchIntentDrain(reason:)`。
3. `syncLaunchIntentHostState()`。
4. `viewModel.loadInitialIfNeeded(syncRemote: true)`。
5. `viewModel.consumePendingShareTicketIfNeeded()`。
6. `viewModel.consumePendingInviteIfNeeded()`。
7. `medicalDocumentUploadViewModel` 展示态与 fullScreenCover 同步。
8. `externalMedicalDocumentImportCoordinator.errorMessage` 弹窗。
9. `medicalDocumentUploadViewModel.saveSucceededRevision` 后刷新首页。
10. `pendingMemberDetailMemberID` 打开成员详情。
11. `taskManager.loadInitial(memberID:)` 和 `taskManager.syncIncremental(memberID:)`。

如果这些能力不迁移，iOS 26 首页虽然视觉独立，但冷启动、外部导入、上传刷新、成员详情、任务同步都会出现断点。

## 8. IOS26HomeView 设计草图

### 8.1 根视图结构

```swift
@available(iOS 26.0, *)
struct IOS26HomeView: View {
    let dependencies: HomeFeatureDependencies
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject var taskManager: TaskManager
    @ObservedObject var medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel
    @ObservedObject var externalMedicalDocumentImportCoordinator: ExternalMedicalDocumentImportCoordinator
    @ObservedObject var launchIntentCoordinator: LaunchIntentCoordinator
    let session: UserSession
    let actionHandler: IOS26HomeDashboardActionHandler
    @ObservedObject var deepTutorChatViewModel: DeepTutorChatViewModel

    @State private var hasLoaded = false
    @State private var activeFullScreenCover: HomeFullScreenCover?
    @State private var showExternalImportErrorAlert = false
    @State private var addMemberNearbyTransport = NearbyShareTransport()

    var body: some View {
        content
    }
}
```

### 8.2 内容层

```swift
@available(iOS 26.0, *)
private extension IOS26HomeView {
    var dashboardContent: some View {
        IOS26HomeDashboardView(
            viewModel: viewModel,
            taskManager: taskManager,
            session: session,
            actionHandler: actionHandler,
            deepTutorChatViewModel: deepTutorChatViewModel
        )
        .refreshable {
            await viewModel.refresh()
            await taskManager.syncIncremental(memberID: viewModel.selectedMemberID)
        }
        .navigationBarHidden(true)
    }
}
```

### 8.3 Presentation 层

```swift
@available(iOS 26.0, *)
private extension IOS26HomeView {
    var content: some View {
        dashboardContent
            .sheet(item: $viewModel.activeSheet) { sheet in
                homeSheetContent(sheet)
            }
            .fullScreenCover(item: $activeFullScreenCover) { cover in
                homeFullScreenCoverContent(cover)
            }
            .onAppear {
                launchIntentConsumer.setHomeHostReady(true)
                syncLaunchIntentHostState()
                requestLaunchIntentDrain(reason: "ios26_home_appear")
            }
            .onDisappear {
                launchIntentConsumer.setHomeHostReady(false)
            }
    }
}
```

说明：

1. 示例代码只说明结构，不要求逐字照抄。
2. `homeSheetContent` 和 `homeFullScreenCoverContent` 可以先从 `HomeView` 复制一份，再在后续工单中抽公共 builder。
3. 不要为了复用 sheet 逻辑又把 `IOS26HomeView` 包回 `HomeView`。

## 9. 可选抽象：HomePresentationBuilder

为了减少复制，后续可以抽出共享 presentation builder：

```text
SparkClient/Projects/Features/Home/Presentation/HomePresentationBuilder.swift
```

职责：

1. 构建 `HomeSheet` 内容。
2. 构建 `HomeFullScreenCover` 内容。
3. 复用成员详情、上传、任务中心、新增成员流程。

但本工单不强制先抽。优先级是先完成拆分，让边界清楚。

推荐策略：

```text
Phase 1：允许 IOS26HomeView 暂时复制 presentation 构建逻辑
Phase 2：抽 HomePresentationBuilder 去重
```

## 10. 业务流程

### 10.1 iOS 26 首页进入

```text
AppCoordinatorView
  -> IOS26TabBarView
  -> homeContainer
  -> CompatibleRouteNavigationContainer(path: routePath(.home))
  -> IOS26HomeView
  -> IOS26HomeDashboardView
```

### 10.2 旧首页进入

```text
AppCoordinatorView
  -> MainTabCoordinatorView
  -> home tab
  -> CompatibleRouteNavigationContainer(path: routePath(.home))
  -> HomeView
```

### 10.3 关键原则

```text
iOS 26 首页和旧首页都可以复用 HomeViewModel / HomeFeatureDependencies
但不能共用同一个 HomeView root
```

## 11. 文件改动清单

| 文件 | 动作 | 要求 |
| --- | --- | --- |
| `HomeView.swift` | 修改 | 移除 iOS 26 分支与 iOS 26 专属依赖 |
| `IOS26HomeView.swift` | 新增 | iOS 26 首页独立 root |
| `IOS26TabBarView.swift` | 修改 | homeContainer 改为承载 `IOS26HomeView` |
| `IOS26HomeDashboardView.swift` | 保留 | 继续作为 iOS 26 首页内容组件 |
| `IOS26HomeDashboardActionHandler.swift` | 保留 | 继续处理 iOS 26 首页动作 |
| `IOS26HomeTaskSummaryView.swift` | 保留 | 继续作为代办任务模块 |
| `HomePresentationBuilder.swift` | 可选新增 | 后续抽共享 presentation 构建逻辑 |

## 12. 验收标准

### 12.1 结构验收

1. 存在新文件 `SparkClient/Projects/Features/Home/Presentation/IOS26HomeView.swift`。
2. `IOS26TabBarView.homeContainer` 直接使用 `IOS26HomeView`。
3. `HomeView.swift` 不再引用 `IOS26HomeDashboardView`。
4. `HomeView.swift` 不再包含 `ios26DashboardActionHandler`。
5. `HomeView.swift` 不再包含 `deepTutorChatViewModel`。
6. `HomeView.swift` 不再有 `if #available(iOS 26.0, *)` 用来切换首页内容。

### 12.2 行为验收

1. iOS 26 进入首页时展示 iOS 26 首页工作台。
2. iOS 25 及以下仍展示旧首页。
3. iOS 26 首页能打开新增成员、成员详情、任务中心、医疗文档上传。
4. iOS 26 首页能消费外部导入 PDF 的 Launch Intent。
5. iOS 26 首页上传保存成功后能刷新首页数据。
6. iOS 26 首页代办任务模块能加载和刷新任务。
7. DeepTutor 快捷入口仍能一步创建并进入会话。

### 12.3 回归验收

1. 旧首页医疗卡片点击仍能进入对应列表。
2. 旧首页家庭药箱入口仍可用。
3. 旧首页成员邀请、成员分享、成员模块维护仍可用。
4. 冷启动目标页面队列不丢失。
5. iOS 26 和旧首页切换不会互相污染状态。

## 13. 实施步骤

### Phase 1：创建独立 IOS26HomeView

1. 新增 `IOS26HomeView.swift`。
2. 把 iOS 26 首页 root 所需依赖迁移到 `IOS26HomeView`。
3. 在 `IOS26HomeView` 中承载 `IOS26HomeDashboardView`。
4. 迁移任务刷新逻辑。

### Phase 2：迁移 presentation 能力

1. 迁移 `HomeSheet` 构建能力。
2. 迁移 `HomeFullScreenCover` 构建能力。
3. 迁移外部导入错误提示。
4. 迁移上传保存成功刷新。
5. 迁移 pending member detail 处理。

### Phase 3：清理 HomeView

1. 移除 iOS 26 init 参数。
2. 移除 iOS 26 分支。
3. 移除 `IOS26HomeDashboardView` 引用。
4. 恢复旧首页 `homeScrollBody` 结构。

### Phase 4：接入 IOS26TabBarView

1. `IOS26TabBarView.homeContainer` 改为 `IOS26HomeView`。
2. 保持 `CompatibleRouteNavigationContainer(path: routePath(.home))` 不变。
3. 保持 `destinationBuilder.destination(route)` 不变。

### Phase 5：验证

1. 编译 iOS 26。
2. 编译 iOS 25 或旧系统目标。
3. 手工验证首页入口。
4. 手工验证冷启动 intent。
5. 手工验证任务模块、DeepTutor 快捷入口、上传流程。

## 14. 风险与规避

| 风险 | 影响 | 规避 |
| --- | --- | --- |
| 直接复制 HomeView presentation 逻辑 | 短期重复代码 | 先拆边界，后续抽 `HomePresentationBuilder` |
| 未迁移 Launch Intent host 状态 | 冷启动目标页不打开 | `IOS26HomeView` 必须调用 `launchIntentConsumer` |
| 未迁移上传同步 | 外部 PDF 导入断链 | 保留 `medicalDocumentUploadViewModel` 的展示态同步 |
| 未迁移成员详情 pending action | 家庭档案入口失效 | 迁移 `pendingMemberDetailMemberID` 监听 |
| HomeView 仍引用 iOS 26 类型 | 边界不清 | 验收中 grep 检查 `IOS26` / `deepTutorChatViewModel` |

## 15. 禁止事项

1. 禁止继续在 `HomeView.swift` 中新增 iOS 26 UI。
2. 禁止让 `IOS26HomeView` 再包一层 `HomeView`。
3. 禁止为了复用旧逻辑而把 DeepTutor 依赖继续塞进 `HomeView`。
4. 禁止删除旧首页能力。
5. 禁止改动任务、DeepTutor、上传的业务协议来完成视图拆分。

