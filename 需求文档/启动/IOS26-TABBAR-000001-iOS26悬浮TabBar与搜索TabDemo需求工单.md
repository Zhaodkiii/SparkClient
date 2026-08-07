# IOS26-TABBAR-000001：iOS 26 悬浮 TabBar 与搜索 Tab Demo 需求工单

> 创建日期：2026-08-07  
> 关联模块：启动态主协调、登录后主 Tab、iOS 26 Liquid Glass、搜索 Tab Demo  
> 关联代码：`SparkClient/Projects/App/Sources/App/AppCoordinatorView.swift:76-92`、`SparkClient/Projects/App/Sources/App/MainTabCoordinatorView.swift`  
> 状态：新需求/待实现

## 1. 背景

当前 `AppCoordinatorView` 在登录且账号准备完成后，对 iOS 26 及以上系统临时接入了一段 `TabView` demo：

```text
AppCoordinatorView.swift:76-92
if #available(iOS 26.0, *) {
    TabView {
        Tab("Numbers", systemImage: "number") { ... }
        Tab("Alerts", systemImage: "bell") { ... }
    }
    .tabBarMinimizeBehavior(.onScrollDown)
} else {
    MainTabCoordinatorView(...)
}
```

这段代码用于验证 iOS 26 新设计系统中的浮动 TabBar，但目前只有 `Numbers` 和 `Alerts` 两个临时页，缺少官方 WWDC25 推荐的“搜索作为专用 Tab”的 demo，也没有把官方文档入口沉淀到需求文档里，后续实现容易遗漏 Liquid Glass 的关键约束。

## 2. 目标

1. 在 iOS 26 demo TabView 底部增加一个 `搜索` Tab，用于验证多标签 App 中的专用搜索页模式。
2. 搜索 Tab 使用 SwiftUI iOS 26 官方 `Tab` API 的搜索角色能力，而不是自定义底部按钮伪装。
3. `TabView` 保留 `.tabBarMinimizeBehavior(.onScrollDown)`，验证 iPhone 上滚动下滑最小化、反向滚动展开的系统行为。
4.  demo 页面只承担系统能力验证，不替代现有 `MainTabCoordinatorView` 的正式业务结构。
5. 明确 Liquid Glass 约束：不得对系统 TabBar 设置自定义 `backgroundColor`、`backgroundImage`、自绘背景或遮挡式底栏。

## 3. 需求范围

### 3.1 本期包含

1. 在 `AppCoordinatorView.swift` 的 iOS 26 demo `TabView` 中新增 `搜索` Tab。
2. 搜索页内容使用轻量列表或建议项，确保可滚动并能触发底部 TabBar 行为变化。
3. 搜索入口使用 `.searchable`，搜索状态只在 demo 内本地过滤，不接入后端、不接入 AI 搜索工具。
4. iOS 26.0 分支中的首页/demo 代码必须单独创建新的 `.swift` 文件承载，`AppCoordinatorView.swift` 只负责条件分支和依赖装配。
5. 如 SDK 支持搜索 Tab role，则优先使用官方搜索角色：

```swift
Tab("搜索", systemImage: "magnifyingglass", role: .search) {
    IOS26SearchTabDemoView()
}
```

如果当前 Xcode 26 SDK 的 SwiftUI `Tab` 初始化签名有差异，以 Apple Developer Documentation 和本机编译结果为准。

### 3.2 本期不包含

1. 不改造正式 `MainTabCoordinatorView` 的业务 Tab 顺序。
2. 不新增真实全局搜索业务、不接入服务端搜索接口。
3. 不替换现有聊天列表、知识库、科普、设置页的局部搜索逻辑。
4. 不尝试移除系统选中胶囊指示器。
5. 不为 TabBar 自定义 Liquid Glass 背景或复刻 WWDC 视频里的 Figma 参数。

## 4. 产品与交互要求

### Q：搜索 Tab 应该是什么样？

A：搜索 Tab 是一个专门的 demo 页，用于验证 Apple 在 WWDC25 中说明的“多标签 App 中的搜索通常在专用搜索页面中完成”的模式。用户点击底部 `搜索` Tab 后，页面应展示搜索建议或示例内容，并由系统搜索栏承接输入。

建议内容：

```text
搜索
最近搜索
- 血压趋势
- 用药记录
- 检查报告

建议
- 查找家庭成员资料
- 搜索健康科普
- 搜索聊天记录
```

### Q：为什么要放在底部 Tab，而不是只加 toolbar 搜索按钮？

A：WWDC25 SwiftUI 视频同时介绍了两种搜索模式：

1. 工具栏搜索：搜索栏根据平台和尺寸自适应放置。
2. 专用搜索 Tab：多标签 App 可把搜索作为一个顶层页面，选择搜索 Tab 后由搜索栏替代或强化底部 Tab 区域。

本工单目标是验证第二种模式，因此应把搜索作为 TabView 中的一个 Tab，而不是单个页面里的 toolbar 按钮。

## 5. 技术方案

### 5.1 推荐文件结构

为了避免 `AppCoordinatorView` 继续膨胀，iOS 26.0 分支的首页/demo 代码必须单独创建新的 Swift 文件。`AppCoordinatorView.swift` 只保留入口判断和依赖传入，不在该文件内继续堆叠 `Numbers`、`Alerts`、`搜索` 等 demo 页面实现。

```text
SparkClient/Projects/App/Sources/App/AppCoordinatorView.swift
  - 仅保留 if #available(iOS 26.0, *) 分支
  - iOS 26 分支内调用 IOS26TabBarDemoView()

SparkClient/Projects/App/Sources/App/IOS26TabBarDemoView.swift
  - 新增 IOS26TabBarDemoView
  - 新增 IOS26NumbersTabDemoView
  - 新增 IOS26AlertsTabDemoView
  - 新增 IOS26SearchTabDemoView
```

如后续 demo 内容继续增长，再按页面拆分到更细文件：

```text
SparkClient/Projects/App/Sources/App/IOS26NumbersTabDemoView.swift
SparkClient/Projects/App/Sources/App/IOS26AlertsTabDemoView.swift
SparkClient/Projects/App/Sources/App/IOS26SearchTabDemoView.swift
```

### 5.2 示例实现草图

`AppCoordinatorView.swift` 中只保留：

```swift
if #available(iOS 26.0, *) {
    IOS26TabBarDemoView()
} else {
    MainTabCoordinatorView(...)
}
```

`IOS26TabBarDemoView.swift` 中承载 iOS 26 demo 首页：

```swift
@available(iOS 26.0, *)
struct IOS26TabBarDemoView: View {
    var body: some View {
        TabView {
            Tab("Numbers", systemImage: "number") {
                IOS26NumbersTabDemoView()
            }

            Tab("Alerts", systemImage: "bell") {
                IOS26AlertsTabDemoView()
            }

            Tab("搜索", systemImage: "magnifyingglass", role: .search) {
                IOS26SearchTabDemoView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
```

搜索页建议同样放在 `IOS26TabBarDemoView.swift`：

```swift
@available(iOS 26.0, *)
private struct IOS26SearchTabDemoView: View {
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List(filteredItems, id: \.self) { item in
                Text(item)
            }
            .navigationTitle("搜索")
            .searchable(text: $query, prompt: "搜索健康资料")
        }
    }
}
```

实际代码必须以本机 Xcode 26 SDK 编译结果为准；如果 `Tab(..., role: .search)` 语法不可用，应保留 `Tab("搜索", systemImage: "magnifyingglass")` 并在文档/代码注释中标记 SDK 差异。

## 6. Liquid Glass 约束

1. 不设置 `UITabBar.appearance().backgroundColor`。
2. 不设置 `UITabBar.appearance().backgroundImage` 或 `shadowImage` 来覆盖系统材质。
3. 不在 TabBar 背后额外添加固定色块、渐变、模糊遮罩或自绘胶囊。
4. 不使用自定义底栏替代系统 `TabView`。
5. 不通过私有 API 隐藏系统选中胶囊指示器。
6. 如果 demo 页面滚动内容延伸到底部，应让系统处理安全区和滚动边缘效果，不额外添加硬分割线。

## 7. 兼容性要求

1. `#available(iOS 26.0, *)` 分支必须只引用 iOS 26 可用 API。
2. iOS 25 及以下仍走现有 `MainTabCoordinatorView`，不得因为 demo 影响正式主导航。
3. `.tabBarMinimizeBehavior(.onScrollDown)` 重点验收 iPhone；iPad 上不要求最小化。
4. 新增 `IOS26TabBarDemoView.swift` 必须使用 `@available(iOS 26.0, *)` 标记，避免旧系统编译路径误引用 iOS 26 API。
5. 如需保留 demo，必须确保登录后 `launchIntentCoordinator.updateReadiness` 不被永久跳过。当前正式 `MainTabCoordinatorView` 的 readiness 更新在 iOS 26 demo 分支不会执行，实施时需要明确是否补齐 demo 分支的 readiness 标记，避免冷启动 intent 等待卡住。

## 8. 验收标准

1. iOS 26 模拟器或真机登录后底部 TabBar 展示 `Numbers`、`Alerts`、`搜索` 三个 Tab。
2. 点击 `搜索` Tab 后进入搜索 demo 页，搜索栏可以输入并过滤本地 demo 项。
3. 搜索页列表可滚动；在 iPhone 上向下滚动时 TabBar 可按系统行为最小化，反向滚动可恢复。
4. iOS 25 及以下系统仍进入现有 `MainTabCoordinatorView`，业务 Tab 不受影响。
5. 工程中没有新增破坏 Liquid Glass 的 TabBar 自定义背景代码。
6. iOS 26 demo 首页代码已从 `AppCoordinatorView.swift` 拆到新的 `IOS26TabBarDemoView.swift`，`AppCoordinatorView.swift` 不再内联 `Numbers`、`Alerts`、`搜索` 页面实现。
7. 通过 Xcode 编译；若 SDK 签名与示例草图不同，工单实现记录最终采用的 API 形态。

## 9. 风险与注意事项

1. 当前 demo 分支绕过正式 `MainTabCoordinatorView`，会导致正式首页、聊天、科普、设置等业务入口不可用。上线前必须删除 demo 分支或迁移为正式主导航能力。
2. iOS 26 API 依赖 Xcode 26 SDK，CI 或本地构建环境如果仍使用旧 SDK 会编译失败。
3. 官方未提供静态 HIG Figma 尺寸参数，不应按截图硬编码胶囊圆角、悬浮边距。
4. 系统选中胶囊指示器是原生行为，当前官方 API 未提供关闭开关。
5. 自定义 TabBar 外观会破坏 Liquid Glass 材质，应优先使用系统组件默认外观。

## 10. 官方说明文档

### SwiftUI API

1. `tabBarMinimizeBehavior(_:)` 修饰器  
   https://developer.apple.com/documentation/swiftui/view/tabbarminimizebehavior(_:)
2. `TabBarMinimizeBehavior` 枚举  
   https://developer.apple.com/documentation/swiftui/tabbarminimizebehavior
3. `tabViewBottomAccessory(content:)`  
   https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(content:)

### UIKit API

1. `UITabBarController`  
   https://developer.apple.com/documentation/uikit/uitabbarcontroller
2. iOS 26 新增属性：`tabBarMinimizeBehavior`，类型为 `UITabBarController.MinimizeBehavior`。

### Liquid Glass 总览

1. Adopting Liquid Glass  
   https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
2. 关键约束：不要给系统 TabBar 设置自定义背景、背景图或覆盖性材质，否则会破坏 Liquid Glass 默认效果。

### HIG 人机交互指南

1. Tab Bars  
   https://developer.apple.com/design/human-interface-guidelines/tab-bars
2. 注意：截至 2026-08，HIG 网页主要是文字规范，悬浮胶囊的精确视觉参数应以 WWDC 视频和系统默认组件为准。

### WWDC25 视频

1. SwiftUI：323 Build SwiftUI apps with the new design system  
   https://developer.apple.com/cn/videos/play/wwdc2025/323/  
   重点章节：`TabView`、floating tab bar、`tabBarMinimizeBehavior`、`tabViewBottomAccessory`、搜索。
2. UIKit：284 Build a UIKit app with the new design  
   https://developer.apple.com/videos/play/wwdc2025/284/  
   重点章节：`UITabBarController` 悬浮、滚动最小化、bottom accessory。

### Xcode 快速入口

1. 打开文档：`Shift + Command + 0`
2. 搜索关键词：
   - `tabBarMinimizeBehavior`
   - `UITabBarController.MinimizeBehavior`
   - `tabViewBottomAccessory`
   - `Adopting Liquid Glass`
