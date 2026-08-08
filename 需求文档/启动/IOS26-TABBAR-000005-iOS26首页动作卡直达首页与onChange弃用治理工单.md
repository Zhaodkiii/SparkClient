# IOS26-TABBAR-000005：iOS 26 首页动作卡直达首页与 `onChange` 弃用治理工单

> 创建日期：2026-08-07  
> 关联模块：`IOS26HomeView`、`IOS26HomeDashboardView`、`IOS26TabBarView`、`HomeView`  
> 关联代码：`SparkClient/Projects/Features/Home/Presentation/IOS26HomeView.swift:1-290`、`SparkClient/Projects/Features/Home/Presentation/IOS26HomeDashboardView.swift:76-279`、`SparkClient/Projects/App/Sources/App/IOS26TabBarView.swift:81-93`、`SparkClient/Projects/Features/Home/Presentation/HomeView.swift:113-173`  
> 状态：已实现  
> 优先级：P1，体验与编译告警治理

## 1. 一句话目标

将 iOS 26 首页中的「制定体检计划」与「报告解读」动作从 DeepTutor 直接建会话改为直达首页根容器，同时把首页链路中所有旧式 `.onChange(of:perform:)` 迁移到 iOS 17+ 推荐写法，消除弃用告警并统一交互语义。

## 2. 背景

当前 iOS 26 首页已经完成独立 root 拆分，但动作入口和状态监听仍保留了旧的会话创建导向与弃用 API：

1. `IOS26HomeDashboardView` 里的动作卡在点击后会走 `actionHandler.handle(item.id)`，并且对 `checkupPlan` / `reportInterpretation` 设置 `loadingAction`，依赖 `deepTutorChatViewModel.isCreatingConversation` 来结束 loading。
2. `IOS26HomeView` 和 `HomeView` 内部仍大量使用 `.onChange(of:perform:)`，编译时会持续报 iOS 17 弃用告警。

这会让首页主入口的语义变得混乱：

1. 用户点击「制定体检计划」或「报告解读」时，界面先进入 loading，再切到 DeepTutor 创建会话态。
2. 视觉上像是一个首页入口，实际却在执行会话创建流程。
3. 旧式 `onChange` 告警会持续污染编译输出，后续也不利于 SwiftUI 升级。

## 3. 现状问题

### 3.1 动作卡仍然绑定 DeepTutor 创建会话

当前实现位于：

`SparkClient/Projects/Features/Home/Presentation/IOS26HomeDashboardView.swift:269-279`

现有逻辑：

```swift
@ViewBuilder
private func actionCard(for item: IOS26HomeActionItem) -> some View {
    IOS26HomeActionCard(
        item: item,
        isLoading: loadingAction == item.id && deepTutorChatViewModel.isCreatingConversation,
        action: {
            guard item.isEnabled else { return }
            triggerHaptic(style: .light)
            if item.id == .checkupPlan || item.id == .reportInterpretation {
                loadingAction = item.id
            }
            actionHandler.handle(item.id)
        }
    )
}
```

问题点：

1. `loadingAction` 只对 DeepTutor 快速建会话有意义。
2. `deepTutorChatViewModel.isCreatingConversation` 把首页动作卡和会话创建状态强耦合。
3. 这与当前「iOS 26 首页独立 root」的方向不一致，入口应该首先服务首页语义，而不是先切到会话创建态。

### 3.2 首页链路仍有旧式 `onChange`

当前告警主要出现在：

`SparkClient/Projects/Features/Home/Presentation/IOS26HomeView.swift:81-133`

`SparkClient/Projects/Features/Home/Presentation/HomeView.swift:113-173`

这些位置仍使用：

```swift
.onChange(of: value) { newValue in ... }
```

在 iOS 17 之后需要迁移为：

```swift
.onChange(of: value) { oldValue, newValue in ... }
```

或者在不需要参数时使用零参数闭包。

### 3.3 首页 root 已经独立，但入口语义还没收口

`IOS26TabBarView` 的首页容器已经直接承载 `IOS26HomeView`：

`SparkClient/Projects/App/Sources/App/IOS26TabBarView.swift:81-93`

这意味着首页入口的最佳归宿已经明确：**先回到首页根容器，再由首页承接各类业务入口**。  
当前动作卡再去驱动 DeepTutor 创建会话，会让主导航和业务入口之间再生一层分叉。

## 4. 目标

1. 「制定体检计划」与「报告解读」点击后不再进入 DeepTutor 创建会话 loading。
2. 动作卡语义改为「直达首页」或「切回首页根容器」，不再把首页入口包装成会话创建动作。
3. `IOS26HomeView.swift` 与 `HomeView.swift` 中所有旧式 `.onChange(of:perform:)` 迁移为新写法。
4. 首页编译告警清零，保持 iOS 26 首页和旧首页的行为边界清晰。

## 5. 非目标

1. 本工单不重做首页视觉稿。
2. 本工单不新增 DeepTutor 快速建会话逻辑。
3. 本工单不改 `IOS26TabBarView` 的 tab 结构。
4. 本工单不改旧首页的业务数据模型。
5. 本工单不处理仓库内所有页面的 `onChange` 告警，只收口首页相关链路；全局清理可另开工单。

## 6. 需求 A：动作卡直达首页

### 6.1 目标行为

用户点击 iOS 26 首页的：

1. 制定体检计划
2. 报告解读

之后，应当：

1. 直接回到首页根容器。
2. 不再展示 DeepTutor 创建会话 loading。
3. 不再依赖 `deepTutorChatViewModel.isCreatingConversation` 作为按钮状态源。
4. 不再把首页动作卡设计成“先建会话，再进入内容”的中转站。

### 6.2 业务流程

建议流程如下：

1. 用户停留在 `IOS26HomeView`。
2. 点击首页动作卡。
3. 动作只负责触发首页级导航或 Tab 切换。
4. 页面回到 `IOS26TabBarView.homeContainer` 所承载的首页根容器。
5. 后续如需进入 DeepTutor 的独立流程，再由新的业务入口单独设计，不混在当前首页动作卡里。

### 6.3 关键代码示例

当前代码不应继续依赖 DeepTutor 创建会话状态：

```swift
@ViewBuilder
private func actionCard(for item: IOS26HomeActionItem) -> some View {
    IOS26HomeActionCard(
        item: item,
        isLoading: false,
        action: {
            guard item.isEnabled else { return }
            triggerHaptic(style: .light)
            // 直达首页 root，不再进入 DeepTutor quick-start loading。
            routeToHomeRoot()
        }
    )
}
```

说明：

1. `isLoading` 不再绑定 `deepTutorChatViewModel.isCreatingConversation`。
2. `checkupPlan` 和 `reportInterpretation` 不再触发会话创建 loading。
3. 具体的 `routeToHomeRoot()` 实现由路由层或 Tab 层承接，工单只约束结果，不限定具体导航 API 名称。

### 6.4 落地细节

1. 保留首页动作卡视觉样式。
2. 保留轻触反馈。
3. 去掉只服务会话创建态的 loading 语义。
4. 如果后续还要保留 DeepTutor 快速建会话，需要单独设计一层明确的入口，不要继续复用这两个首页动作卡。

## 7. 需求 B：`onChange` 弃用治理

### 7.1 目标范围

本工单优先处理首页相关文件中的旧式写法：

1. `IOS26HomeView.swift`
2. `HomeView.swift`

### 7.2 当前问题点

`IOS26HomeView.swift` 当前包含多处旧式监听：

1. `launchIntentCoordinator.readiness.canConsume`
2. `viewModel.activeSheet?.id`
3. `viewModel.pendingMemberDetailMemberID`
4. `activeFullScreenCover`
5. `medicalDocumentUploadViewModel.isUploadPresented`
6. `medicalDocumentUploadViewModel.stage`
7. `externalMedicalDocumentImportCoordinator.errorMessage`
8. `medicalDocumentUploadViewModel.saveSucceededRevision`

`HomeView.swift` 也保留同类写法。

### 7.3 迁移规则

1. 如果闭包需要旧值和新值，改成双参数闭包。
2. 如果只关心新值，改成双参数但忽略旧值。
3. 如果根本不需要参数，改成零参数闭包。
4. 保留原有副作用顺序，不改变首页生命周期。

### 7.4 关键代码示例

旧写法：

```swift
.onChange(of: medicalDocumentUploadViewModel.saveSucceededRevision) { _ in
    Task {
        await viewModel.refresh()
    }
}
```

推荐新写法：

```swift
.onChange(of: medicalDocumentUploadViewModel.saveSucceededRevision) { _, _ in
    Task {
        await viewModel.refresh()
    }
}
```

如果只想用一个新值：

```swift
.onChange(of: viewModel.pendingMemberDetailMemberID) { _, memberID in
    guard let memberID else { return }
    activeFullScreenCover = .memberDetail(memberID: memberID)
    viewModel.pendingMemberDetailMemberID = nil
}
```

### 7.5 落地细节

1. 先改首页根链路，确保编译告警立即下降。
2. 迁移后保持行为完全一致，尤其是上传、成员详情、Launch Intent drain、sheet/cover 同步。
3. 旧式 `onChange(of:perform:)` 不要留在首页文件里反复堆积。

## 8. 影响文件

### 8.1 需要修改的文件

1. `SparkClient/Projects/Features/Home/Presentation/IOS26HomeDashboardView.swift`
2. `SparkClient/Projects/Features/Home/Presentation/IOS26HomeView.swift`
3. `SparkClient/Projects/Features/Home/Presentation/HomeView.swift`

### 8.2 可能联动的文件

1. `SparkClient/Projects/App/Sources/App/IOS26TabBarView.swift`
2. `SparkClient/Projects/Features/Home/Presentation/IOS26HomeDashboardActionHandler.swift`

## 9. 验收标准

### 9.1 功能验收

1. 点击「制定体检计划」不再进入 DeepTutor 创建会话 loading。
2. 点击「报告解读」不再进入 DeepTutor 创建会话 loading。
3. 动作点击后页面回到首页根容器或等价首页入口。
4. 首页动作卡保持可点击、可反馈。

### 9.2 编译验收

1. `IOS26HomeView.swift` 不再出现旧式 `.onChange(of:perform:)`。
2. `HomeView.swift` 不再出现旧式 `.onChange(of:perform:)`。
3. 首页相关告警不再持续刷屏。

### 9.3 回归验收

1. iOS 26 首页原有上传、成员详情、任务和 Launch Intent 流程不受影响。
2. 旧首页行为不受影响。
3. tab 切换和首页生命周期保持稳定。

## 10. 风险与规避

| 风险 | 影响 | 规避 |
| --- | --- | --- |
| 动作卡从会话创建改成直达首页后，用户短期找不到 DeepTutor 入口 | 入口语义变化 | 如需保留 DeepTutor，另开独立入口，不复用首页动作卡 |
| `onChange` 迁移时漏掉某个副作用 | 首页刷新或宿主同步异常 | 逐个对照迁移，保持原始逻辑和调用顺序 |
| 仅改首页文件但遗漏联动层 | 告警未清零 | 改动前后跑一次 grep 验证 |

## 11. 禁止事项

1. 禁止继续在动作卡里依赖 `deepTutorChatViewModel.isCreatingConversation` 作为 loading 来源。
2. 禁止把首页动作再次包装成会话创建流程。
3. 禁止用旧式 `.onChange(of:perform:)` 继续往首页文件里加新代码。
4. 禁止为了消除告警而改坏首页现有副作用。

## 12. 实施顺序

1. 先改 `IOS26HomeDashboardView` 的动作卡语义。
2. 再迁移 `IOS26HomeView` 的 `onChange`。
3. 再迁移 `HomeView` 的 `onChange`。
4. 最后补充一次编译与行为回归。
