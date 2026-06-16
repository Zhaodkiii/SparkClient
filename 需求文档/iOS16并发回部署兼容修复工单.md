# iOS 16 并发回部署兼容修复工单

> 范围说明：本文按工单管理 SparkClient 在 iOS 16.x 回部署场景下，由 Swift 新并发元数据、`@MainActor` 默认隔离、`ObservableObject` / `View` 反射、`async closure` 存储属性组合引发的启动期与页面构建期闪退问题。本文优先给出统一治理策略、改造优先级、标准模板与验收口径，便于后续横向治理。

## 工单索引

| 工单号 | 工单名 | 状态 | 范围 |
| --- | --- | --- | --- |
| `IOS-COMPAT-000001` | iOS 16 并发回部署兼容统一修复 | 已实现 | `ObservableObject`、SwiftUI `View` / `Representable`、存储型 `async closure`、actor 引用封装、构建配置与横向扫描治理 |
| `IOS-COMPAT-000002` | iOS 15 Push 场景隐藏主 TabBar 兼容方案 | 已实现 | 为 `View+MainTabBarVisibility`、`MainNavigationLink`、`CompatibleRouteNavigationContainer` 补齐 iOS 15 的 push 隐藏 TabBar 能力；统一采用 UIKit `hidesBottomBarWhenPushed` 方案，不使用全局 `UITabBar.appearance()` 或页面级硬隐藏 |

## 工单 `IOS-COMPAT-000001`：iOS 16 并发回部署兼容统一修复

## 1. 背景

### Q：当前线上/测试环境出现了什么问题？

A：在 iOS 16.6 上，应用在以下场景出现主线程闪退：

1. 冷启动进入未登录页时闪退。
2. 点击进入对话页时闪退。

两类栈的共同特征：

- 栈顶接近 `0x0000000000000000`
- 中间出现 `type metadata accessor for nonisolated(nonsending)`
- 一类崩在 `Combine.ObservableObject.objectWillChange.getter`
- 一类崩在 SwiftUI `View._makeView(...)` / `UIViewControllerRepresentable` 构建阶段

这说明问题不在业务接口本身，而在 **SwiftUI / Combine 对类型字段做反射或构建时，老系统运行时无法正确处理新并发元数据**。

### Q：为什么新系统正常，iOS 16 会闪退？

A：工程已启用如下编译特性：

```text
SWIFT_APPROACHABLE_CONCURRENCY = YES
SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
```

当类型中再叠加以下写法时：

- `@MainActor` 的 `ObservableObject`
- SwiftUI `View` / `Representable`
- 存储型 `() async -> Void` 或类似 `async` 函数类型属性
- 需要被 SwiftUI / Combine 反射扫描到的 actor 相关字段

编译器会生成新的并发元数据。较新的系统运行时可以处理这些元数据；iOS 16.x 的运行时在部分路径上无法正确回部署处理，因此在页面首屏构建、`objectWillChange` 访问、`Representable` 建树时崩溃。

## 2. 已命中的确认案例

### Q：目前已经确认的崩点有哪些？

A：当前至少有两处已命中。

#### 2.1 登录页崩溃

- 触发入口：`AppCoordinatorView` 进入 `.signedOut`
- 视图持有：`AuthCoordinatorView` / `LoginView`
- 高概率根因：
  - `SparkClient/SparkClient/Projects/Features/Auth/Presentation/LoginViewModel.swift`
  - 存储属性：

```swift
private let onBeginAccountSwitch: () async -> Void
private let onEndAccountSwitch: (_ commit: Bool) async -> Void
```

#### 2.2 对话页崩溃

- 触发入口：`ChatConversationListPage` 点击会话后 push `ChatView`
- 直接崩点：`ConversationMessageListRepresentable` 构建
- 高概率根因：
  - `SparkClient/SparkClient/Projects/Features/Chat/Presentation/ConversationList/ConversationMessageListRepresentable.swift`
  - 存储属性：

```swift
var onRefresh: () async -> Void
```

同时同类字段也需一并纳入治理：

```swift
var onLoadMore: () -> Void
var onCaptureOpenFiles: () -> Void
```

虽然同步 closure 风险低于 `async closure`，但统一模板建议整组一起改，避免后续继续在 `View` / `Representable` 上累积函数类型字段。

## 3. 问题根因归纳

### Q：什么写法最容易触发 iOS 16 崩溃？

A：按风险从高到低排序如下。

1. `@MainActor` / 默认 `MainActor` 隔离的 `ObservableObject`，内部持有存储型 `async closure`
2. SwiftUI `View` / `UIViewControllerRepresentable` / `UIViewRepresentable` 持有存储型 `async closure`
3. 需要被 SwiftUI / Combine 反射到的类型，持有复杂并发函数类型或 actor 相关状态
4. 在 `body` 内频繁创建带并发字段的对象，放大反射与生命周期问题

### Q：本次治理的核心原则是什么？

A：**禁止在会被 SwiftUI / Combine 直接持有、扫描、反射的类型上，存储 `async closure`。**

具体包括：

- `ObservableObject`
- `View`
- `UIViewRepresentable`
- `UIViewControllerRepresentable`
- 其他直接作为 SwiftUI 状态树节点参与构建的桥接类型

最终治理原则：

**按工单把所有 SwiftUI / `ObservableObject` / `Representable` 上的这类写法统一清掉。**

## 4. 修复优先级清单

### P0：立即修复，阻塞 iOS 16 可用性

以下问题必须优先处理，处理后才允许继续做新增需求：

1. 所有已知闪退路径中的存储型 `async closure`
2. 所有 `ObservableObject` 中的存储型 `async closure`
3. 所有 `UIViewRepresentable` / `UIViewControllerRepresentable` 中的存储型 `async closure`
4. 所有首屏、登录、会话页、主导航路径上的同类问题

当前明确落点：

- `SparkClient/SparkClient/Projects/Features/Auth/Presentation/LoginViewModel.swift`
- `SparkClient/SparkClient/Projects/Features/Chat/Presentation/ConversationList/ConversationMessageListRepresentable.swift`

---

## 工单 `IOS-COMPAT-000002`：iOS 15 Push 场景隐藏主 TabBar 兼容方案

## 1. 背景

当前项目已经有统一入口：

```swift
@ViewBuilder
func hidesMainTabBarWhenPushed() -> some View {
    if #available(iOS 16.0, *) {
        self.toolbar(.hidden, for: .tabBar)
    } else {
        self
    }
}
```

现状问题：

1. iOS 16 及以上可以用 SwiftUI 官方 API 隐藏 TabBar。
2. iOS 15 没有 `toolbar(.hidden, for: .tabBar)`。
3. 当前 iOS 15 分支直接 `self` 返回，导致 push 二级页时底部主 TabBar 仍然显示。
4. 项目里已经有多个页面依赖这个统一入口：
   `MainNavigationLink`
   `CompatibleRouteNavigationContainer`
   `ChatConversationListPage`
   `KnowledgeLibraryView`
   `NutritionRecipeCreateView`

这意味着问题不是单页样式，而是导航基础设施兼容不完整。

## 2. 目标

### 2.1 目标

1. iOS 16+ 继续保持当前 `.toolbar(.hidden, for: .tabBar)` 写法。
2. iOS 15 在 push 到详情页时，也能稳定隐藏根 `TabView` 对应的底部 TabBar。
3. 方案要统一挂在导航基础设施层，不允许每个页面各写一套。
4. push 返回后 TabBar 自动恢复显示。
5. 不影响当前 `CompatibleRouteNavigationContainer` 的 typed route 结构。

### 2.2 非目标

1. 不改为 sheet / fullScreenCover 替代 push。
2. 不通过页面内容遮挡方式“伪隐藏” TabBar。
3. 不使用全局 `UITabBar.appearance().isHidden`。
4. 不在每个页面手动找 `tabBarController` 做临时开关。

## 3. 推荐方案

### 3.1 结论

**最通用、最成熟、和 UIKit 语义最一致的方案，是在 iOS 15 的 push 链路上回到 `UIViewController.hidesBottomBarWhenPushed`。**

原因：

1. 这是 UIKit 官方原生能力，语义就是“当前页面被 push 时隐藏底部栏”。
2. 行为和 iOS 16 的 `.toolbar(.hidden, for: .tabBar)` 目标一致，都是“详情页期间隐藏，返回后恢复”。
3. 比全局 `appearance` 稳定。
4. 比直接操作 `tabBar.isHidden` 更不容易出现返回态错乱、转场闪烁、safe area 错位。

参考：

1. Apple `UIViewController.hidesBottomBarWhenPushed`
   https://developer.apple.com/documentation/uikit/uiviewcontroller/hidesbottombarwhenpushed
2. Apple SwiftUI `toolbarVisibility(_:for:)` / `toolbar(_:for:)`
   https://developer.apple.com/documentation/swiftui/view/toolbarvisibility%28_%3Afor%3A%29

### 3.2 不推荐方案

以下方案明确不选：

1. `UITabBar.appearance().isHidden = true`
   问题：全局污染，容易影响整个应用，不区分当前 push 栈。
2. `tabBarController?.tabBar.isHidden = true/false`
   问题：需要手动恢复，转场、返回、多层 push 时容易错乱。
3. 用额外 `safeAreaInset` / 遮罩盖住底部
   问题：只是视觉遮挡，不是真正隐藏，点击区域和 safe area 会出问题。
4. 每个页面单独包装 UIKit bridge
   问题：重复实现，后续维护成本高。

## 4. 实现设计

### 4.1 总体思路

iOS 15 不在 SwiftUI `View` 层硬隐藏 TabBar，而是在“被 push 的 HostingController”上设置：

```swift
hidesBottomBarWhenPushed = true
```

统一挂载位置建议：

```text
SparkClient/SparkClient/Projects/Core/UI/Navigation
```

### 4.2 建议实现层级

建议新增一个 iOS 15 专用桥接组件，例如：

```text
LegacyTabBarHiddenHostingBridge.swift
```

职责：

1. 作为 destination 的背景桥接视图注入到 SwiftUI 页面中。
2. 在拿到所属 `UIViewController` 后，向上找到当前被 push 的 HostingController。
3. 仅在 iOS 15 生效，把当前 HostingController 的 `hidesBottomBarWhenPushed` 置为 `true`。
4. 不直接操作 `tabBar.isHidden`。

实现方式建议：

1. `UIViewControllerRepresentable`
2. 内部创建一个空的 `UIViewController`
3. 在 `viewWillAppear` / `didMove(toParent:)` 后拿到父级 HostingController
4. 设置父级 `hidesBottomBarWhenPushed = true`

### 4.3 为什么不直接在 `NavigationLink` 前设置

SwiftUI 的 `NavigationLink` 在 iOS 15 下并不直接暴露“即将 push 的 UIKit VC 实例”。

所以更稳的做法不是在 link 点击前猜测，而是等 destination 真正挂到 HostingController 后，再给那个 controller 设置：

```text
hidesBottomBarWhenPushed = true
```

这和 UIKit 里的“push 前配置目标 VC”目标一致，只是桥接时机略后移到 HostingController 建立完成之后。

### 4.4 与现有接口的结合

当前入口：

```text
View+MainTabBarVisibility.swift
MainNavigationLink.swift
CompatibleNavigationContainer.swift
```

建议统一为：

```swift
@ViewBuilder
func hidesMainTabBarWhenPushed() -> some View {
    if #available(iOS 16.0, *) {
        self.toolbar(.hidden, for: .tabBar)
    } else {
        self.background(LegacyTabBarHiddenHostingBridge())
    }
}
```

这样现有所有调用点不用改。

## 5. 涉及文件

### 5.1 核心改动

| 文件 | 改动 |
| --- | --- |
| `SparkClient/SparkClient/Projects/Core/UI/Navigation/View+MainTabBarVisibility.swift` | iOS 15 分支改为挂桥接组件 |
| 新增 `SparkClient/SparkClient/Projects/Core/UI/Navigation/LegacyTabBarHiddenHostingBridge.swift` | iOS 15 UIKit 桥接，设置 `hidesBottomBarWhenPushed` |
| `SparkClient/SparkClient/Projects/Core/UI/Navigation/MainNavigationLink.swift` | 原则上无行为改动，只继续走统一 modifier |
| `SparkClient/SparkClient/Projects/Core/UI/Navigation/CompatibleNavigationContainer.swift` | 原则上无行为改动，只继续走统一 modifier |

### 5.2 受影响调用点

| 文件 | 说明 |
| --- | --- |
| `ChatConversationListPage.swift` | 会话 push 详情 |
| `KnowledgeLibraryView.swift` | 知识库 push 详情 |
| `NutritionRecipeCreateView.swift` | 营养相关 push 详情 |
| `NutritionMealFoodEditListView.swift` | 营养编辑页面 push |

## 6. 验收标准

1. iOS 16+ push 详情页时继续正常隐藏主 TabBar。
2. iOS 15 push 详情页时主 TabBar 也能隐藏。
3. pop 返回上一层后，主 TabBar 自动恢复。
4. 多层 push 时，中间层和末级层都不出现底部 TabBar 闪现。
5. 交互返回、代码 `path = []` 返回、系统返回按钮三种方式都能恢复正常。
6. 不引入全局 `UITabBar.appearance()` 隐藏逻辑。
7. 不直接写 `tabBarController?.tabBar.isHidden = ...` 这种需要手动恢复的逻辑。
8. safe area、底部滚动 inset、键盘弹起布局不异常。

## 7. 风险点

1. iOS 15 下 SwiftUI 的 HostingController 层级可能因容器不同而有差异，桥接组件要尽量只依赖通用父链，不写死具体类名。
2. 如果桥接时机太晚，首次 push 动画中可能会短暂闪一下 TabBar，需要在 `viewWillAppear` 前后验证。
3. `CompatibleRouteNavigationContainer` 的 legacy push 是隐藏 `NavigationLink` 驱动，必须重点回归这个路径。

## 8. 实施顺序建议

1. 先补 `LegacyTabBarHiddenHostingBridge` 原型。
2. 接到 `View+MainTabBarVisibility.swift` 的 iOS 15 分支。
3. 回归 `MainNavigationLink` 路径。
4. 回归 `CompatibleRouteNavigationContainer` 的 iOS 15 legacy path 路径。
5. 验证会话页、营养页、知识库页三个真实页面。

### P1：本轮顺手修复，避免后续继续出现随机崩溃

1. 所有普通 SwiftUI `View` 中的存储型 closure 字段，评估是否可改为事件枚举、委托或环境注入
2. 所有桥接 UIKit 的 SwiftUI 类型，清理函数类型字段
3. 所有在 `body` 中直接 `makeViewModel()` 的登录态/导航关键路径，改为上层 `@StateObject` 或容器缓存

### P2：工程治理与防回归

1. 补充脚本扫描 `() async ->`、`async -> Void`、`UIViewControllerRepresentable`、`ObservableObject`
2. 增加 iOS 16.6 真机/模拟器回归用例
3. 在 code review 清单中新增“禁止在 SwiftUI 反射类型上存储 async closure”
4. 评估是否需要下调或细化相关 Swift 并发编译特性

## 5. 统一改法模板

### Q：推荐的通用实现方式是什么？

A：统一采用 **“同步事件入口 + 容器/拥有者内部起 `Task`”** 的方式，不再把 `async` 作为存储属性暴露给 SwiftUI 反射类型。

---

### 模板 A：`ObservableObject` 去掉存储型 `async closure`

#### 反例

```swift
@MainActor
final class LoginViewModel: ObservableObject {
    private let onBeginAccountSwitch: () async -> Void
    private let onEndAccountSwitch: (_ commit: Bool) async -> Void
}
```

#### 推荐改法 1：改为协议依赖

```swift
@MainActor
protocol AccountSwitchCoordinating: AnyObject {
    func beginAccountSwitch() async
    func endAccountSwitch(commit: Bool) async
}

@MainActor
final class LoginViewModel: ObservableObject {
    private let accountSwitchCoordinator: any AccountSwitchCoordinating

    init(accountSwitchCoordinator: any AccountSwitchCoordinating, ...) {
        self.accountSwitchCoordinator = accountSwitchCoordinator
    }

    private func prepareAccountSwitchIfNeeded() async {
        await accountSwitchCoordinator.beginAccountSwitch()
    }

    private func finishAccountSwitch(commit: Bool) async {
        await accountSwitchCoordinator.endAccountSwitch(commit: commit)
    }
}
```

#### 推荐改法 2：改为拥有者对象方法引用，不存 closure

```swift
@MainActor
final class LoginViewModel: ObservableObject {
    private weak var container: AppContainer?

    init(container: AppContainer, ...) {
        self.container = container
    }

    private func prepareAccountSwitchIfNeeded() async {
        await container?.beginAccountSwitchForLogin()
    }
}
```

适用原则：

- 有清晰职责边界时优先协议
- 只有单一上层拥有者时可用容器方法
- 不再存储 `() async -> Void`

---

### 模板 B：`Representable` 去掉存储型 `async closure`

#### 反例

```swift
struct ConversationMessageListRepresentable: UIViewControllerRepresentable {
    var onLoadMore: () -> Void
    var onRefresh: () async -> Void
    var onCaptureOpenFiles: () -> Void
}
```

#### 推荐改法 1：改为同步事件闭包

```swift
struct ConversationMessageListRepresentable: UIViewControllerRepresentable {
    var onLoadMore: () -> Void
    var onRefreshRequested: () -> Void
    var onCaptureOpenFiles: () -> Void
}
```

调用方内部自己起 `Task`：

```swift
ConversationMessageListRepresentable(
    ...,
    onLoadMore: {
        Task { await detailViewModel.loadMoreMessages(for: threadID) }
    },
    onRefreshRequested: {
        Task {
            await detailViewModel.loadMessagesIfNeeded(for: threadID)
            await MainActor.run {
                conversationListLayoutNonce += 1
            }
        }
    },
    onCaptureOpenFiles: {
        showCaptureFileImporter = true
    }
)
```

#### 推荐改法 2：改为命令枚举 + 单一事件分发

```swift
enum ConversationListCommand {
    case loadMore
    case refresh
    case captureOpenFiles
}

struct ConversationMessageListRepresentable: UIViewControllerRepresentable {
    let onCommand: (ConversationListCommand) -> Void
}
```

适用原则：

- 事件少、简单时：多个同步 closure 即可
- 事件较多、后续还会扩展时：统一命令枚举更稳

---

### 模板 C：普通 SwiftUI `View` 去掉并发函数类型字段

#### 反例

```swift
struct SomePage: View {
    let onSubmit: () async -> Void
}
```

#### 推荐改法

```swift
struct SomePage: View {
    let onSubmit: () -> Void
}
```

按钮点击时由上层起任务：

```swift
SomePage(
    onSubmit: {
        Task {
            await viewModel.submit()
        }
    }
)
```

核心原则：

- `View` 只接同步事件
- 异步工作由拥有者、ViewModel 或容器内部执行

---

### 模板 D：actor 不直接作为 SwiftUI 反射类型的复杂字段扩散

#### 问题

actor 本身不一定直接导致崩溃，但若与其他并发函数类型、默认隔离、桥接 View 混用，老系统兼容成本更高。

#### 推荐改法

1. actor 保留在纯业务层/状态层
2. SwiftUI `View` / `Representable` 尽量只持有轻量同步接口
3. 若必须与桥接层交互，优先通过 ViewModel 暴露同步入口而不是直接扩散 actor 引用

## 6. 本工单推荐的最佳通用实现

### Q：如果要选一个“最通用、最好落地”的方案，建议是什么？

A：建议统一采用下面这套模式。

#### 6.1 事件全部同步化

- `View`
- `Representable`
- `ObservableObject` 构造注入

以上三个层面都不再持有 `async closure`。

#### 6.2 异步行为只留在三类位置

1. `ViewModel` 的实例方法
2. 容器/协调器/UseCase 的实例方法
3. 事件触发点内部显式 `Task { ... }`

#### 6.3 SwiftUI 树只看到“同步命令”

例如：

```swift
enum LoginCommand {
    case startAppleLogin
    case beginAccountSwitch
    case endAccountSwitch(commit: Bool)
}
```

或：

```swift
let onRefreshRequested: () -> Void
```

这样 SwiftUI 反射到的只是普通同步函数类型或普通值，避免把 `async` 元数据暴露到老系统运行时。

#### 6.4 容器层负责把同步事件桥接到异步实现

```swift
onRefreshRequested: {
    Task {
        await detailViewModel.loadMessagesIfNeeded(for: threadID)
    }
}
```

这是本工单建议的默认标准写法。

## 7. 改造步骤

### Step 1：先修崩溃路径

1. `LoginViewModel` 去掉存储型 `async closure`
2. `ConversationMessageListRepresentable` 去掉存储型 `async closure`
3. 验证 iOS 16.6 登录页、对话页可正常进入

### Step 2：横向扫描

建议使用关键字扫描：

```text
async -> Void
() async ->
UIViewControllerRepresentable
UIViewRepresentable
ObservableObject
```

重点查看：

1. 类型字段
2. init 参数是否被直接存成属性
3. 是否属于 SwiftUI 状态树直接持有类型

### Step 3：统一替换

替换策略：

1. `async closure` -> 同步 closure
2. `async closure` -> 协议方法
3. `async closure` -> 命令枚举
4. `body` 内构造关键 ViewModel -> `@StateObject` / 容器缓存

## 8. 验收口径

### 功能验收

1. iOS 16.6 冷启动进入未登录页不闪退
2. iOS 16.6 登录成功后切换主页面不闪退
3. iOS 16.6 点击进入会话页不闪退
4. 会话页下拉刷新、加载更多、附件导入均行为正常
5. iOS 17/18 行为与现状保持一致，无功能回退

### 工程验收

1. SwiftUI `View` / `Representable` 中不再出现存储型 `async closure`
2. `ObservableObject` 中不再出现存储型 `async closure`
3. 关键路径对象不在 `body` 中重复构建
4. 代码评审清单新增“iOS 16 并发回部署兼容检查”

### 日志与回归

1. 关键入口增加页面进入日志，便于确认不再崩在首帧
2. 补录 iOS 16.6 真机或模拟器回归结果
3. 若仍有崩溃，优先检查是否还有漏网的 `async closure` 字段

## 9. 涉及文件

首批改造文件建议如下：

- `SparkClient/SparkClient/Projects/Features/Auth/Presentation/LoginViewModel.swift`
- `SparkClient/SparkClient/Projects/App/Sources/App/AppCoordinatorView.swift`
- `SparkClient/SparkClient/Projects/Features/Chat/Presentation/ChatView.swift`
- `SparkClient/SparkClient/Projects/Features/Chat/Presentation/ConversationList/ConversationMessageListRepresentable.swift`

后续横向扫描范围：

- `SparkClient/SparkClient/Projects/**`
- 所有 `ObservableObject`
- 所有 `UIViewRepresentable` / `UIViewControllerRepresentable`
- 所有 SwiftUI 页面类型

## 10. 备注

### Q：是否要立刻关闭 `SWIFT_APPROACHABLE_CONCURRENCY`？

A：不建议把“关闭新特性”作为唯一修复方案。优先策略应是先把 **危险代码形态** 收敛掉，保留当前工程并发模型的一致性。只有在短期必须止血且代码面太大时，才评估是否临时调整编译开关。

### Q：本工单完成后是否能完全杜绝同类问题？

A：可以显著降低风险，但前提是后续新增代码继续遵守本工单的模板与 review 约束。真正要稳定，需要同时做到：

1. 存量治理
2. 新增约束
3. iOS 16 回归验证

## 11. 实现记录（2026-06-16）

### 已完成的存量治理

1. **P0 崩溃路径**
   - `LoginViewModel`：`LoginAccountSwitchHandling` 协议替代存储型 async closure
   - `AppCoordinatorView`：`SignedOutAuthCoordinatorView` 缓存 `LoginViewModel`
   - `ConversationMessageListRepresentable`：`ConversationMessageListRefreshHandling` + `ConversationListCommand` 命令枚举
   - `HanlinChatComposerView` / 问报告链路：`MemberCompleteDataFetching` 协议

2. **P1 横向扫描修复**
   - `AISettingsPromptToolingProviding` 替代 `AISettingsPromptTooling` struct（含 `AISettingsViewModel` 及下游 View）
   - `PendingMemberInvitesView`：`MainActorAsyncAction` / `MainActorAsyncVoidAction`
   - `PromptRepoSettingsView`：同步 `onPersistRequested`
   - `ChatThreadSettingsSheet`：同步 `onUpdateRequested`
   - 8 个医疗表单 View：`MainActorThrowingAction<Draft>` 包装提交回调
   - `ChatMessageActionStateHandle` 包装 actor，Representable 不再直接持有 actor

3. **P2 工程治理**
   - 扫描脚本：`scripts/ios16-compat/scan-async-closures.sh`
   - 通用包装类：`Projects/Core/Concurrency/IOS16CompatAsyncActions.swift`

### 新增代码约定

- SwiftUI `View` / `Representable` / `ObservableObject` **禁止**存储 `() async -> Void` 或 `async throws ->` 类型属性
- 异步注入优先：协议 + `AnyObject`、或 `MainActorThrowingAction` 等包装 class
- 事件面优先：同步 closure / 命令枚举，调用方 `Task { await ... }`

### 待 iOS 16.6 真机/模拟器回归

- [ ] 冷启动 → 未登录页
- [ ] 登录 → 主界面
- [ ] 聊天列表 → 会话页 → Composer 渲染
- [ ] 下拉刷新 / 加载更多 / 附件导入
- [ ] 医疗表单创建/编辑提交
- [ ] 待处理成员邀请 Sheet

## 12. 工单 `IOS-COMPAT-000002` 实现记录（2026-06-16）

### 已完成

1. **新增** `Projects/Core/UI/Navigation/LegacyTabBarHiddenHostingBridge.swift`
   - `UIViewControllerRepresentable` 注入透明子 VC
   - 在 `didMove(toParent:)` / `viewWillAppear` / `updateUIViewController` 中向上查找当前 push 栈顶 VC
   - 对其设置 `hidesBottomBarWhenPushed = true`（不操作 `tabBar.isHidden` / `appearance`）

2. **更新** `View+MainTabBarVisibility.swift`
   - iOS 16+：保持 `.toolbar(.hidden, for: .tabBar)`
   - iOS 15：`.background(LegacyTabBarHiddenHostingBridge())`

3. **无需改动的调用点**（自动继承统一 modifier）
   - `MainNavigationLink`
   - `CompatibleRouteNavigationContainer`（含 iOS 15 `LegacyRouteNavigationBridge` destination）
   - `ChatConversationListPage` / `KnowledgeLibraryView` / 营养相关 push 页

### 待 iOS 15 真机/模拟器回归

- [ ] push 详情页时主 TabBar 隐藏
- [ ] pop 返回后 TabBar 自动恢复
- [ ] 首页医疗卡片 typed route push（legacy bridge 路径）
- [ ] 会话列表 push 会话页
- [ ] Settings 子页 push
- [ ] 交互返回 / 系统返回 / `path = []` 代码返回三种 pop 方式
