# iOS 15 导航兼容修复方案

> 范围说明：本文聚焦 SparkClient 当前主 Tab 内 typed route 导航在 iOS 15 上不可用的问题，给出根因分析、实现选型、推荐方案、改造步骤与验收口径。目标是在不破坏 iOS 16+ `NavigationStack(path:)` 现有能力的前提下，补齐 iOS 15 的兼容导航能力。

## 1. 现象

### Q：当前 iOS 15 上的异常表现是什么？

A：在首页点击医疗卡片，例如“服药计划”，日志会连续打印：

```text
首页医疗卡片跳转 kind=medicationPlans selectedMemberID=509
```

但页面没有稳定进入目标列表页，用户体感表现为：

1. 点击有反馈但不跳转
2. 连续点多次只重复打印日志
3. 高版本系统正常，iOS 15 异常

### Q：这是不是接口或数据问题？

A：不是。

从日志看，点击事件已经被正确触发，业务层也已调用路由：

- `HomeView` 已记录“首页医疗卡片跳转”
- `routeStore.route(to: .homeMedicalList(...))` 已执行

说明问题不在首页医疗数据、成员选择、网络请求或 `medicationPlans` 数据本身，而在 **路由容器对 iOS 15 的消费能力缺失**。

## 2. 根因

### Q：问题的根因在哪里？

A：主因是 `CompatibleRouteNavigationContainer` 在 iOS 15 分支只保留了 `NavigationView` 外壳，但没有把 typed route 的 `path` 真正桥接成可执行导航。

关键代码：

```swift
if #available(iOS 16.0, *) {
    NavigationStack(path: $path) {
        content()
            .navigationDestination(for: Route.self) { route in
                destination(route)
            }
    }
} else {
    NavigationView {
        content()
    }
}
```

这意味着：

1. iOS 16+ 使用 `NavigationStack(path:)`，`path` 被系统真正消费
2. iOS 15 虽然也维护 `path`，但 fallback 的 `NavigationView` 根本不认识 typed path
3. 结果就是路由状态变了，但 UI 没有 push

### Q：为什么首页点击会反复打印日志？

A：因为点击代码是正常执行的：

```swift
viewModel.logMedicalListNavigation(kind: card.id)
dependencies.routeStore.route(to: .homeMedicalList(card.id.homeMedicalListRoute, nil))
```

日志只说明“事件发出去了”，不代表“导航已经落地”。  
在 iOS 15 上，事件发出后没有导航消费层，因此会出现“点一次记一次日志，但页面不进”的现象。

## 3. 当前架构约束

### Q：修复时要遵守哪些现有约束？

A：当前工程导航架构有几个明显约束：

1. iOS 16+ 已经基于 typed route + `NavigationStack(path:)`
2. `AppRouteStore` 已经是主导航单一事实源
3. 主 Tab 下的 Home / Chat / Settings 都依赖统一 route stack
4. 不能为了兼容 iOS 15 把 iOS 16+ 路由体系推倒重做

因此修复原则应是：

- **保留 iOS 16+ 现状**
- **仅补齐 iOS 15 的 fallback 消费层**
- **尽量复用 `AppRouteStore` 和现有 destination 构造**

## 4. 方案选型

### 方案 A：iOS 15 下完全放弃 typed path，页面内各自维护 `NavigationLink(isActive:)`

#### 做法

每个页面自己新增：

- `selectedRoute`
- `isMedicalListPresented`
- 隐藏 `NavigationLink`
- 手动同步 `routeStore`

#### 优点

1. 实现简单
2. 某个页面能很快止血

#### 缺点

1. 路由状态分散
2. Home / Chat / Settings 各自维护一套兼容逻辑
3. 容易和现有 `AppRouteStore` 脱节
4. 后续 push 场景越多越难维护

#### 结论

不推荐作为统一方案，只适合非常临时的局部止血。

---

### 方案 B：在 `CompatibleRouteNavigationContainer` 内补一个 iOS 15 专用的 route bridge

#### 做法

保留 iOS 16+ 的：

```swift
NavigationStack(path: $path)
```

给 iOS 15 增加一个桥接层：

1. 观察 `path.last`
2. 将最后一个 route 映射到一个 `selection` / `isActive`
3. 用隐藏 `NavigationLink(tag:selection:)` 或 `NavigationLink(isActive:)`
4. push 时展示 `destination(route)`
5. pop 时把 `path` 回写为空或按层级回退

#### 优点

1. 保持 `AppRouteStore` 为统一路由源
2. iOS 16+ 无需改动现有 typed navigation
3. iOS 15 兼容逻辑集中在一个容器里
4. Home / Chat / Settings 都能复用

#### 缺点

1. iOS 15 无法完整等价模拟多层 typed path
2. 需要限制 fallback 行为，通常先支持“单层 push”
3. 需要认真处理 pop 回写

#### 结论

**推荐方案。**

---

### 方案 C：为 iOS 15 单独实现 UIKit `UINavigationController` 宿主

#### 做法

为低版本单独做一个 UIKit bridge：

1. SwiftUI 页面嵌进 `UIHostingController`
2. 路由变化时手动 push / pop `UIHostingController`
3. route store 与 UIKit 栈同步

#### 优点

1. 导航控制最强
2. 能更接近真实栈行为

#### 缺点

1. 实现成本高
2. 容易引入新的生命周期问题
3. 与当前 SwiftUI 架构差异过大

#### 结论

不适合作为当前问题的首选修复。

## 5. 推荐统一方案

### Q：最终推荐采用哪种方案？

A：推荐采用 **方案 B：在 `CompatibleRouteNavigationContainer` 内补 iOS 15 route bridge**。

一句话概括：

**iOS 16+ 继续使用 `NavigationStack(path:)`；iOS 15 用隐藏 `NavigationLink` 桥接 `path.last`，把 typed route 的最后一层 push 出来。**

## 6. 推荐实现设计

### 6.1 设计目标

1. 保持 `CompatibleRouteNavigationContainer` 仍然是跨版本统一入口
2. iOS 16+ 行为不变
3. iOS 15 至少支持主导航常见的一层 push
4. pop 返回时能正确回写 `path`

### 6.2 iOS 15 fallback 的行为边界

第一阶段建议明确边界：

1. 先支持 `path.last` 对应的一层详情页
2. 不要求完整模拟任意深度 typed stack
3. 对 Home / Chat / Settings 这类“列表 -> 详情”场景足够

这样可以先把当前核心问题修好，再看是否需要扩展多层。

### 6.3 容器内部推荐状态

建议在 iOS 15 fallback bridge 内维护：

```swift
@State private var legacyPresentedRoute: Route?
@State private var legacyIsActive = false
```

同步逻辑：

1. 当 `path.last` 变为某个 route：
   - `legacyPresentedRoute = route`
   - `legacyIsActive = true`
2. 当用户返回：
   - `legacyIsActive = false`
   - 同步把 `path` 修正
3. 当外部将 `path` 清空：
   - 关闭 legacy push

### 6.4 推荐桥接模板

示意模板：

```swift
struct CompatibleRouteNavigationContainer<Route: Hashable, Content: View, Destination: View>: View {
    @Binding private var path: [Route]
    @State private var legacyPresentedRoute: Route?
    @State private var legacyIsActive = false

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack(path: $path) {
                content()
                    .navigationDestination(for: Route.self) { route in
                        destination(route)
                    }
            }
        } else {
            NavigationView {
                ZStack {
                    content()

                    NavigationLink(
                        isActive: Binding(
                            get: { legacyIsActive && legacyPresentedRoute != nil },
                            set: { isActive in
                                legacyIsActive = isActive
                                if !isActive {
                                    legacyPresentedRoute = nil
                                    path = []
                                }
                            }
                        )
                    ) {
                        if let route = legacyPresentedRoute {
                            destination(route)
                        } else {
                            EmptyView()
                        }
                    } label: {
                        EmptyView()
                    }
                    .hidden()
                }
            }
            .onChange(of: path) { newValue in
                let next = newValue.last
                if let next {
                    legacyPresentedRoute = next
                    legacyIsActive = true
                } else {
                    legacyIsActive = false
                    legacyPresentedRoute = nil
                }
            }
        }
    }
}
```

### 6.5 为什么推荐只消费 `path.last`

A：因为 iOS 15 的 `NavigationView` 没有 typed path 栈能力，强行完整模拟成本高且容易错。  
当前项目的主流路由大多是：

1. 首页列表 -> 详情
2. 会话列表 -> 会话页
3. 设置列表 -> 设置子页

先消费 `path.last` 已能覆盖绝大部分实际场景。

## 7. 与现有代码的结合点

### Q：这次最关键要改哪些位置？

A：核心改造点只有一处主入口，若需要再补少量调用侧。

#### 主改造入口

- `SparkClient/SparkClient/Projects/Core/UI/Navigation/CompatibleNavigationContainer.swift`

这里补齐 `CompatibleRouteNavigationContainer` 的 iOS 15 fallback bridge。

#### 验证重点调用方

1. `MainTabCoordinatorView`
2. `HomeView` -> `.homeMedicalList(...)`
3. `ChatConversationListPage` -> 会话 push
4. `SettingsView` 的子页 push

### Q：`HomeView` 需要改吗？

A：理论上不需要先改。

`HomeView` 现在触发路由的方式没有问题：

```swift
dependencies.routeStore.route(to: .homeMedicalList(...))
```

主问题是下游容器没消费。  
只有当 fallback bridge 接上后，若发现某些页面还依赖 iOS 16 专属行为，再做调用侧补充。

## 8. 推荐分阶段落地

### 第一阶段：止血

目标：

1. 修复 iOS 15 首页医疗卡片无法进入
2. 修复 iOS 15 会话页基础 push
3. 保证主导航单层 push 可用

改动范围：

1. 仅改 `CompatibleRouteNavigationContainer`
2. 不调整 `AppRouteStore` 对外接口
3. 不改业务页面路由写法

### 第二阶段：扩展

若后续发现 iOS 15 上仍有多级 push 需求，再扩展：

1. 从 `path.last` 扩展为有限深度桥接
2. 明确哪些 Route 支持多层
3. 对复杂场景单独提供 legacy route adapter

## 9. 风险与注意点

### 风险 1：pop 回写不一致

表现：

1. 页面已返回，但 `path` 还保留旧 route
2. 再次点击不生效或 push 状态异常

对策：

1. 在 `isActive` setter 中回写 `path`
2. 明确 iOS 15 fallback 默认只保留单层 route

### 风险 2：某些 destination 依赖 typed stack 深度

表现：

1. 首页能进去，但子页面再 push 异常
2. 某些深链路径在 iOS 15 行为不一致

对策：

1. 第一阶段只承诺单层
2. 多层场景单独列清单

### 风险 3：页面生命周期差异

`NavigationView` + 隐藏 `NavigationLink` 在 iOS 15 的生命周期与 `NavigationStack` 不完全一致，可能出现：

1. `onAppear` 多次触发
2. 返回时状态刷新次数不同

对策：

1. 关键页面避免把“只能执行一次”的逻辑裸写在 `onAppear`
2. 已有 `hasLoaded` / `task(id:)` 守卫要保留

## 10. 验收口径

### 功能验收

1. iOS 15 首页点击“服药计划”可进入 `MedicationExecutionCenterPage`
2. iOS 15 首页点击其他医疗卡片可进入对应列表页
3. iOS 15 会话列表点击会话可进入会话页
4. iOS 15 设置页子项 push 正常
5. iOS 16+ 行为与现状保持一致

### 状态验收

1. 进入详情页时 `path` 与 UI 保持一致
2. 从详情页返回时 `path` 能正确清空或回退
3. 不出现“页面已经返回但路由残留”的情况

### 日志验收

建议补充以下日志：

1. `legacy_route_push route=...`
2. `legacy_route_pop route=...`
3. `legacy_route_sync pathCount=... last=...`

便于区分：

1. 点击未触发
2. 路由已触发但未 bridge
3. bridge 已触发但 pop 回写异常

## 11. 最终结论

当前 iOS 15 问题的本质不是业务数据错误，而是：

**typed route 导航容器在低版本只有外壳，没有真正的导航桥接。**

最稳妥、改动面最小、最符合现有架构的修复方案是：

**在 `CompatibleRouteNavigationContainer` 内补齐 iOS 15 fallback，把 `path.last` 桥接成隐藏 `NavigationLink` 导航，同时处理 pop 回写。**

这会是当前项目最合适的通用修复方向。

## 12. 实现记录（2026-06-16）

### 已完成（第一阶段）

**改动文件：** `SparkClient/Projects/Core/UI/Navigation/CompatibleNavigationContainer.swift`

1. 新增 `LegacyRouteNavigationBridge`（iOS 15 专用）
   - 观察 `path` / `path.last`，同步 `legacyPresentedRoute` + `legacyIsActive`
   - 用隐藏 `NavigationLink(isActive:)` push `destination(route)`
   - pop 时在 `isActive` setter 回写 `path = []`
   - 强制 `.navigationViewStyle(.stack)`，保证 Tab 内 push 行为一致
2. iOS 16+ `NavigationStack(path:)` 分支**未改动**
3. `AppRouteStore` / `HomeView` 路由写法**未改动**（符合 §8 第一阶段范围）

### 诊断日志

iOS 15 fallback 已输出：

- `legacy_route_sync pathCount=... last=...`（debug）
- `legacy_route_push route=...`（info）
- `legacy_route_pop route=...`（info）

### 待 iOS 15 真机/模拟器验收

1. 首页医疗卡片（服药计划等）可进入目标页
2. 返回后 `path` 清空，再次点击可正常 push
3. iOS 16+ 行为与改前一致

### 已知边界（与 §6.2 / §9 一致）

1. 仅桥接 `path.last` 单层 push；多层 typed stack 不在第一阶段承诺范围
2. Chat 列表、Settings 子页本身使用 `NavigationLink` / `MainNavigationLink`，不依赖 typed path，iOS 15 原本可用
3. 通过 `routeStore.route(to: .chatThread)` / `.aiSettings` 的 push 会走同一 bridge

